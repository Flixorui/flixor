//
//  StremioStreamFacts.swift
//  FlixorMac
//
//  Reads the things that matter for choosing a source (resolution, HDR, codec,
//  audio, size, languages, provider) out of the free text addons send in
//  name / title / description and the file name. Anything not found is nil.
//

import Foundation

struct StremioStreamFacts {
    let resolution: String?
    let hdr: String?
    let codec: String?
    let audio: String?
    let sizeBytes: Int64?
    let languages: [String]
    /// "Torrentio via TorBox", "DDLBase · Server 1", or the addon name.
    let provider: String
    let filename: String?
    let cached: Bool
    let subtitleCount: Int

    var sizeText: String? {
        sizeBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
    }

    /// File name and size: the same file served from several servers.
    var fileKey: String? {
        guard let filename, !filename.isEmpty else { return nil }
        return "\(filename.lowercased())|\(sizeBytes.map { $0 / 1_000_000 } ?? -1)"
    }

    init(_ stream: StremioPlayableStream, addonName: String) {
        let parts = [stream.name, stream.title, stream.description, stream.behaviorHints?.filename, stream.quality].compactMap { $0 }
        let text = parts.joined(separator: "\n")
        let lower = text.lowercased()

        // Resolution
        switch StremioSourceRanking.resolutionBucket(stream) {
        case 2160: resolution = "4K"
        case 1080: resolution = "1080p"
        case 720: resolution = "720p"
        case 480: resolution = "480p"
        default: resolution = nil
        }

        // HDR
        if Self.has(lower, ["dolby vision", "dovi", "\\bdv\\b"]) {
            hdr = Self.has(lower, ["hdr10\\+", "hdr10plus"]) ? "DV · HDR10+" : (Self.has(lower, ["\\bhdr"]) ? "DV · HDR" : "DV")
        } else if Self.has(lower, ["hdr10\\+", "hdr10plus"]) {
            hdr = "HDR10+"
        } else if Self.has(lower, ["\\bhdr10\\b", "\\bhdr\\b"]) {
            hdr = "HDR"
        } else {
            hdr = nil
        }

        // Codec
        if Self.has(lower, ["\\bav1\\b"]) { codec = "AV1" }
        else if Self.has(lower, ["hevc", "x265", "h\\.?265"]) { codec = "HEVC" }
        else if Self.has(lower, ["\\bavc\\b", "x264", "h\\.?264"]) { codec = "H.264" }
        else { codec = nil }

        // Audio: format, then channels
        var audioParts: [String] = []
        if Self.has(lower, ["atmos"]) { audioParts.append("Atmos") }
        if Self.has(lower, ["truehd"]) { audioParts.append("TrueHD") }
        else if Self.has(lower, ["dts-?hd", "dts-?x"]) { audioParts.append("DTS-HD") }
        else if Self.has(lower, ["\\bdts\\b"]) { audioParts.append("DTS") }
        else if Self.has(lower, ["dd\\+", "\\bddp", "e-?ac-?3", "eac3"]) { audioParts.append("DD+") }
        else if Self.has(lower, ["\\bdd\\b", "\\bac-?3\\b", "dolby digital"]) { audioParts.append("DD") }
        else if Self.has(lower, ["\\baac\\b"]) { audioParts.append("AAC") }
        if let channels = Self.firstMatch(lower, "\\b([2-7])[ .]([01])\\b").map({ "\($0[0]).\($0[1])" }) {
            audioParts.append(channels)
        }
        audio = audioParts.isEmpty ? nil : audioParts.joined(separator: " ")

        // Size: the field, the hint, or "1.1 GB" / "1 006.2 MiB" in the text
        if let size = stream.size, size > 0 { sizeBytes = Int64(size) }
        else if let size = stream.behaviorHints?.videoSize, size > 0 { sizeBytes = Int64(size) }
        else { sizeBytes = Self.parsedSize(text) }

        // Languages: two-letter codes on a line marked with a flag, plus "Multi"
        var langs: [String] = []
        for line in text.split(separator: "\n") where line.contains("🌐") || line.contains("⚐") || line.contains("🗣") || line.lowercased().contains("lang") {
            for token in line.split(whereSeparator: { !$0.isLetter }) where token.count == 2 && token.uppercased() == token {
                langs.append(String(token))
            }
        }
        for (pattern, code) in [("\\bmulti\\b", "Multi"), ("\\bdual\\b", "Dual")] where Self.has(lower, [pattern]) {
            langs.append(code)
        }
        var seen = Set<String>()
        languages = langs.filter { seen.insert($0).inserted }

        // Provider: "[TB] Torrentio" → "Torrentio via TorBox"; "Server 2" for DDL addons.
        let debrid: [String: String] = ["TB": "TorBox", "RD": "Real-Debrid", "AD": "AllDebrid", "PM": "Premiumize",
                                        "DL": "Debrid-Link", "ED": "EasyDebrid", "OC": "Offcloud", "PKP": "PikPak"]
        if let match = Self.firstMatch(text, "\\[(TB|RD|AD|PM|DL|ED|OC|PKP)\\+?\\]\\s*([A-Za-z][A-Za-z0-9 .\\-]{1,30})") {
            let source = match[1].trimmingCharacters(in: .whitespaces)
            provider = "\(source) via \(debrid[match[0]] ?? match[0])"
        } else if let server = Self.firstMatch(text, "(?i)\\bserver\\s*([0-9]+)") {
            provider = "\(addonName) · Server \(server[0])"
        } else {
            provider = addonName
        }

        // File name: the hint, else a line that looks like one.
        if let hinted = stream.behaviorHints?.filename, !hinted.isEmpty {
            filename = hinted
        } else {
            filename = parts.flatMap { $0.split(separator: "\n") }
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { $0.range(of: "\\.(mkv|mp4|avi|m4v|ts|webm)$", options: [.regularExpression, .caseInsensitive]) != nil }
                .map { $0.replacingOccurrences(of: "^[^A-Za-z0-9]+", with: "", options: .regularExpression) }
        }

        cached = stream.behaviorHints?.cached == true
        subtitleCount = stream.subtitles?.count ?? 0
    }

    private static func has(_ text: String, _ patterns: [String]) -> Bool {
        patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    /// Capture groups of the first match.
    private static func firstMatch(_ text: String, _ pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
    }

    private static func parsedSize(_ text: String) -> Int64? {
        guard let match = firstMatch(text, "([0-9][0-9 ]*(?:[.,][0-9]+)?)\\s*(TB|TiB|GB|GiB|MB|MiB)") else { return nil }
        let number = Double(match[0].replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".")) ?? 0
        let unit = match[1].lowercased()
        let factor: Double
        switch unit {
        case "tb": factor = 1e12
        case "tib": factor = 1_099_511_627_776
        case "gb": factor = 1e9
        case "gib": factor = 1_073_741_824
        case "mib": factor = 1_048_576
        default: factor = 1e6
        }
        return number > 0 ? Int64(number * factor) : nil
    }
}
