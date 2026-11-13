//
//  YouTubeStreamExtractor.swift
//  FlixorMac
//
//  Turns a YouTube video key into direct stream URLs that AVPlayer can play,
//  so trailers play natively instead of in the YouTube web embed.
//
//  How (same approach as Nuvio's InAppYouTubeExtractor):
//  1. Load the watch page once and read INNERTUBE_API_KEY and VISITOR_DATA.
//  2. POST /youtubei/v1/player as YouTube's own apps (visionOS, then Android,
//     then iOS). App clients get plain googlevideo URLs, so there is no
//     signature cipher or player JS to run.
//  3. Prefer the HLS master playlist (visionOS returns one, H.264 up to 1080p
//     with separate audio renditions). AVPlayer starts on the first variant in
//     the master, which is 240p, and stays there for a long time, so the master
//     is rewritten with the best H.264 variant (up to `maxHeight`) first and the
//     VP9 variants dropped. The player serves that text through a resource
//     loader (TrailerAVPlayer).
//  4. Otherwise use the best progressive (video+audio in one file) format,
//     usually 360p, after checking that googlevideo actually serves it.
//
//  Nil means "use the YouTube embed instead". Results are cached for 10 minutes
//  (stream URLs expire after a few hours) and concurrent lookups share a fetch.
//  The client versions below are what YouTube accepts today; when it stops
//  accepting one the next client is tried, and eventually the embed fallback.
//

import Foundation

struct YouTubeTrailerStream: Sendable {
    enum Source: Sendable {
        /// Rewritten HLS master playlist (best H.264 variant first). Variant and
        /// rendition URLs inside are absolute googlevideo URLs.
        case hls(master: String, originalURL: URL, height: Int)
        /// One file with video and audio together.
        case progressive(url: URL, height: Int)
    }

    let videoKey: String
    let source: Source
    /// Which InnerTube client produced it (for logs).
    let client: String

    var height: Int {
        switch source {
        case .hls(_, _, let height), .progressive(_, let height): return height
        }
    }

    var kindLabel: String {
        switch source {
        case .hls: return "hls"
        case .progressive: return "progressive"
        }
    }
}

actor YouTubeStreamExtractor {
    static let shared = YouTubeStreamExtractor()

    /// Highest variant put first in the HLS master. Larger variants stay in the
    /// playlist, so AVPlayer can still switch up on a big window.
    static let defaultMaxHeight = 1080

    private struct CacheEntry {
        let stream: YouTubeTrailerStream
        let storedAt: Date
    }

    private static let cacheTTL: TimeInterval = 10 * 60
    private static let requestTimeout: TimeInterval = 15
    private static let overallTimeout: TimeInterval = 25

    private var cache: [String: CacheEntry] = [:]
    /// Keys that failed recently, so a title without a usable stream doesn't
    /// re-run the whole lookup on every hover.
    private var failures: [String: Date] = [:]
    private var inFlight: [String: Task<YouTubeTrailerStream?, Never>] = [:]

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = YouTubeStreamExtractor.requestTimeout
        config.timeoutIntervalForResource = YouTubeStreamExtractor.overallTimeout
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    // MARK: - Public API

    /// Direct stream for a YouTube key (or watch/youtu.be/embed URL), or nil when
    /// none could be found and the caller should fall back to the embed.
    func stream(for videoKeyOrURL: String, maxHeight: Int = YouTubeStreamExtractor.defaultMaxHeight) async -> YouTubeTrailerStream? {
        guard let videoId = Self.videoId(from: videoKeyOrURL) else { return nil }
        let key = "\(videoId)@\(maxHeight)"

        if let entry = cache[key] {
            if Date().timeIntervalSince(entry.storedAt) < Self.cacheTTL { return entry.stream }
            cache[key] = nil
        }
        if let failedAt = failures[key], Date().timeIntervalSince(failedAt) < Self.cacheTTL {
            return nil
        }

        let task: Task<YouTubeTrailerStream?, Never>
        if let existing = inFlight[key] {
            task = existing
        } else {
            let session = self.session
            task = Task.detached(priority: .userInitiated) {
                await Self.extract(videoId: videoId, maxHeight: maxHeight, session: session)
            }
            inFlight[key] = task
        }

        let result = await task.value
        inFlight[key] = nil
        if let result {
            cache[key] = CacheEntry(stream: result, storedAt: Date())
            failures[key] = nil
        } else {
            failures[key] = Date()
        }
        return result
    }

    /// Starts a lookup ahead of time (e.g. while the hero's idle timer runs).
    /// Skipped when native trailer playback is switched off.
    nonisolated func prefetch(_ videoKey: String, maxHeight: Int = YouTubeStreamExtractor.defaultMaxHeight) {
        guard !UserDefaults.standard.bool(forKey: "trailerNativePlaybackDisabled") else { return }
        Task { _ = await stream(for: videoKey, maxHeight: maxHeight) }
    }

    func clearCache() {
        cache.removeAll()
        failures.removeAll()
    }

    // MARK: - Clients

    private struct Client {
        let key: String
        let id: String
        let version: String
        let userAgent: String
        let context: [String: Any]
    }

    private static let clients: [Client] = [
        Client(
            key: "visionos",
            id: "101",
            version: "1.02",
            userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15",
            context: [
                "clientName": "VISIONOS", "clientVersion": "1.02",
                "deviceMake": "Apple", "deviceModel": "RealityDevice17,1",
                "osName": "visionOS", "osVersion": "26.5.23O471",
                "hl": "en", "gl": "US",
            ]
        ),
        Client(
            key: "android",
            id: "3",
            version: "20.10.35",
            userAgent: "com.google.android.youtube/20.10.35 (Linux; U; Android 14; en_US) gzip",
            context: [
                "clientName": "ANDROID", "clientVersion": "20.10.35",
                "osName": "Android", "osVersion": "14", "platform": "MOBILE",
                "androidSdkVersion": 34, "hl": "en", "gl": "US",
            ]
        ),
        Client(
            key: "ios",
            id: "5",
            version: "20.10.1",
            userAgent: "com.google.ios.youtube/20.10.1 (iPhone16,2; U; CPU iOS 17_4 like Mac OS X)",
            context: [
                "clientName": "IOS", "clientVersion": "20.10.1",
                "deviceModel": "iPhone16,2", "osName": "iPhone",
                "osVersion": "17.4.0.21E219", "platform": "MOBILE",
                "hl": "en", "gl": "US",
            ]
        ),
    ]

    private static let browserUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36"

    // MARK: - Extraction

    private struct Progressive {
        let url: URL
        let height: Int
        let fps: Int
        let bitrate: Int
        let isMP4: Bool
        let client: String
        let clientIndex: Int
    }

    private static func extract(videoId: String, maxHeight: Int, session: URLSession) async -> YouTubeTrailerStream? {
        let started = Date()
        do {
            let (apiKey, visitorData) = try await watchConfig(videoId: videoId, session: session)

            var progressive: [Progressive] = []
            for (index, client) in clients.enumerated() {
                if Task.isCancelled { return nil }
                let streamingData: [String: Any]
                do {
                    streamingData = try await playerResponse(
                        videoId: videoId, apiKey: apiKey, visitorData: visitorData,
                        client: client, session: session
                    )
                } catch {
                    AppLogger.shared.debug("[YouTubeExtractor] client failed", data: [
                        "videoId": videoId, "client": client.key, "error": error.localizedDescription,
                    ])
                    continue
                }

                if let manifest = streamingData["hlsManifestUrl"] as? String,
                   let manifestURL = URL(string: manifest),
                   let (master, height) = try? await rewrittenMaster(manifestURL, maxHeight: maxHeight, session: session) {
                    log(videoId: videoId, kind: "hls", client: client.key, height: height, started: started)
                    return YouTubeTrailerStream(
                        videoKey: videoId,
                        source: .hls(master: master, originalURL: manifestURL, height: height),
                        client: client.key
                    )
                }

                for format in (streamingData["formats"] as? [[String: Any]]) ?? [] {
                    guard let raw = format["url"] as? String, let url = URL(string: raw) else { continue }
                    let mime = (format["mimeType"] as? String) ?? ""
                    guard mime.isEmpty || mime.hasPrefix("video/") else { continue }
                    progressive.append(Progressive(
                        url: url,
                        height: intValue(format["height"]) ?? qualityLabelHeight(format["qualityLabel"] as? String) ?? 0,
                        fps: intValue(format["fps"]) ?? 0,
                        bitrate: intValue(format["bitrate"]) ?? intValue(format["averageBitrate"]) ?? 0,
                        isMP4: !mime.contains("webm"),
                        client: client.key,
                        clientIndex: index
                    ))
                }
            }

            // AVPlayer only plays the MP4 progressive formats.
            let ranked = progressive.filter(\.isMP4).sorted { a, b in
                if a.height != b.height { return a.height > b.height }
                if a.fps != b.fps { return a.fps > b.fps }
                if a.bitrate != b.bitrate { return a.bitrate > b.bitrate }
                return a.clientIndex < b.clientIndex
            }
            for candidate in ranked.prefix(3) {
                if Task.isCancelled { return nil }
                if await isReachable(candidate.url, session: session) {
                    log(videoId: videoId, kind: "progressive", client: candidate.client, height: candidate.height, started: started)
                    return YouTubeTrailerStream(
                        videoKey: videoId,
                        source: .progressive(url: candidate.url, height: candidate.height),
                        client: candidate.client
                    )
                }
            }

            AppLogger.shared.warn("[YouTubeExtractor] no playable stream, using embed", data: [
                "videoId": videoId, "progressiveCandidates": ranked.count,
            ])
            return nil
        } catch {
            AppLogger.shared.warn("[YouTubeExtractor] extraction failed, using embed", data: [
                "videoId": videoId, "error": error.localizedDescription,
            ])
            return nil
        }
    }

    private static func log(videoId: String, kind: String, client: String, height: Int, started: Date) {
        AppLogger.shared.info("[YouTubeExtractor] resolved", data: [
            "videoId": videoId, "kind": kind, "client": client, "height": height,
            "ms": Int(Date().timeIntervalSince(started) * 1000),
        ])
    }

    private enum ExtractError: LocalizedError {
        case http(Int, String)
        case missingAPIKey
        case notPlayable(String)
        case noStreamingData

        var errorDescription: String? {
            switch self {
            case .http(let status, let what): return "\(what) returned HTTP \(status)"
            case .missingAPIKey: return "INNERTUBE_API_KEY not found on the watch page"
            case .notPlayable(let reason): return "not playable: \(reason)"
            case .noStreamingData: return "no streamingData"
            }
        }
    }

    private static func watchConfig(videoId: String, session: URLSession) async throws -> (apiKey: String, visitorData: String?) {
        var request = URLRequest(url: URL(string: "https://www.youtube.com/watch?v=\(videoId)&hl=en")!)
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw ExtractError.http(status, "watch page") }
        let html = String(decoding: data, as: UTF8.self)
        guard let apiKey = firstMatch(#""INNERTUBE_API_KEY":"([^"]+)""#, in: html) else { throw ExtractError.missingAPIKey }
        return (apiKey, firstMatch(#""VISITOR_DATA":"([^"]+)""#, in: html))
    }

    private static func playerResponse(
        videoId: String, apiKey: String, visitorData: String?,
        client: Client, session: URLSession
    ) async throws -> [String: Any] {
        var components = URLComponents(string: "https://www.youtube.com/youtubei/v1/player")!
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(client.id, forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(client.version, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue(client.userAgent, forHTTPHeaderField: "User-Agent")
        if let visitorData, !visitorData.isEmpty {
            request.setValue(visitorData, forHTTPHeaderField: "X-Goog-Visitor-Id")
        }
        let payload: [String: Any] = [
            "videoId": videoId,
            "contentCheckOk": true,
            "racyCheckOk": true,
            "context": ["client": client.context],
            "playbackContext": ["contentPlaybackContext": ["html5Preference": "HTML5_PREF_WANTS"]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw ExtractError.http(status, "player API (\(client.key))") }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ExtractError.noStreamingData }

        if let playability = json["playabilityStatus"] as? [String: Any],
           let state = playability["status"] as? String, state != "OK" {
            throw ExtractError.notPlayable((playability["reason"] as? String) ?? state)
        }
        guard let streamingData = json["streamingData"] as? [String: Any] else { throw ExtractError.noStreamingData }
        return streamingData
    }

    // MARK: - HLS

    /// Downloads the master playlist and rewrites it so AVPlayer starts on the
    /// best H.264 variant at or below `maxHeight`. Returns nil when it has no
    /// H.264 variant AVPlayer can play.
    private static func rewrittenMaster(_ url: URL, maxHeight: Int, session: URLSession) async throws -> (String, Int)? {
        var request = URLRequest(url: url)
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw ExtractError.http(status, "HLS manifest") }
        return rewriteMaster(String(decoding: data, as: UTF8.self), baseURL: url, maxHeight: maxHeight)
    }

    /// Pure rewrite (no network), split out so it is easy to reason about:
    /// keeps every non-variant tag (EXT-X-MEDIA audio renditions etc.), drops
    /// non-H.264 variants, and orders the rest so the preferred one is first.
    static func rewriteMaster(_ text: String, baseURL: URL, maxHeight: Int) -> (String, Int)? {
        struct Variant {
            let lines: [String]
            let height: Int
            let bandwidth: Int
        }

        let lines = text.components(separatedBy: .newlines)
        var header: [String] = []
        var variants: [Variant] = []
        var index = 0
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                // The URI is the next non-empty, non-tag line.
                var next = index + 1
                while next < lines.count, lines[next].trimmingCharacters(in: .whitespaces).isEmpty { next += 1 }
                guard next < lines.count else { break }
                let uri = lines[next].trimmingCharacters(in: .whitespaces)
                index = next + 1
                guard !uri.hasPrefix("#") else { continue }
                let attrs = hlsAttributes(line)
                let codecs = attrs["CODECS"] ?? ""
                guard codecs.isEmpty || codecs.contains("avc1") else { continue }
                let height = attrs["RESOLUTION"].flatMap { Int($0.split(separator: "x").last ?? "") } ?? 0
                let absolute = URL(string: uri, relativeTo: baseURL)?.absoluteString ?? uri
                variants.append(Variant(
                    lines: [line, absolute],
                    height: height,
                    bandwidth: Int(attrs["BANDWIDTH"] ?? "") ?? 0
                ))
                continue
            }
            if !line.isEmpty { header.append(absolutizeURIAttribute(in: line, baseURL: baseURL)) }
            index += 1
        }

        guard !variants.isEmpty else { return nil }
        let sorted = variants.sorted { ($0.height, $0.bandwidth) > ($1.height, $1.bandwidth) }
        let preferred = sorted.first { $0.height > 0 && $0.height <= maxHeight } ?? sorted.last!
        let ordered = [preferred] + sorted.filter { $0.lines != preferred.lines }
        let output = (header + ordered.flatMap(\.lines)).joined(separator: "\n") + "\n"
        return (output, preferred.height)
    }

    private static func hlsAttributes(_ line: String) -> [String: String] {
        guard let colon = line.firstIndex(of: ":") else { return [:] }
        var result: [String: String] = [:]
        var key = ""
        var value = ""
        var inKey = true
        var inQuote = false
        for ch in line[line.index(after: colon)...] {
            if inKey {
                if ch == "=" { inKey = false } else { key.append(ch) }
                continue
            }
            if ch == "\"" { inQuote.toggle(); continue }
            if ch == ",", !inQuote {
                result[key.trimmingCharacters(in: .whitespaces)] = value
                key = ""; value = ""; inKey = true
                continue
            }
            value.append(ch)
        }
        if !key.isEmpty { result[key.trimmingCharacters(in: .whitespaces)] = value }
        return result
    }

    /// The master is served from a custom scheme, so relative URI="..." values
    /// in tags like EXT-X-MEDIA must be made absolute. YouTube's are already
    /// absolute; this only guards against a change.
    private static func absolutizeURIAttribute(in line: String, baseURL: URL) -> String {
        guard line.hasPrefix("#"), let range = line.range(of: #"URI="([^"]+)""#, options: .regularExpression) else { return line }
        let uri = String(line[range].dropFirst(5).dropLast())
        guard !uri.hasPrefix("http://"), !uri.hasPrefix("https://"),
              let absolute = URL(string: uri, relativeTo: baseURL)?.absoluteString else { return line }
        return line.replacingCharacters(in: range, with: "URI=\"\(absolute)\"")
    }

    // MARK: - Helpers

    /// googlevideo sometimes hands out URLs that return 403; check with a tiny
    /// range request before committing to one.
    private static func isReachable(_ url: URL, session: URLSession) async -> Bool {
        var request = URLRequest(url: url, timeoutInterval: 4)
        request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        guard let (_, response) = try? await session.data(for: request) else { return false }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return status == 206 || status == 200
    }

    static func videoId(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if isVideoId(trimmed) { return trimmed }
        let normalized = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: normalized), let host = components.host?.lowercased() else { return nil }
        let segments = components.path.split(separator: "/").map(String.init)
        if host.hasSuffix("youtu.be"), let first = segments.first, isVideoId(first) { return first }
        if let v = components.queryItems?.first(where: { $0.name == "v" })?.value, isVideoId(v) { return v }
        if segments.count >= 2, ["embed", "shorts", "live", "v"].contains(segments[0]), isVideoId(segments[1]) {
            return segments[1]
        }
        return nil
    }

    private static func isVideoId(_ value: String) -> Bool {
        value.count == 11 && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let int as Int: return int
        case let double as Double: return Int(double)
        case let string as String: return Int(string)
        case let number as NSNumber: return number.intValue
        default: return nil
        }
    }

    private static func qualityLabelHeight(_ label: String?) -> Int? {
        guard let label, let match = firstMatch(#"(\d{3,4})p"#, in: label) else { return nil }
        return Int(match)
    }
}
