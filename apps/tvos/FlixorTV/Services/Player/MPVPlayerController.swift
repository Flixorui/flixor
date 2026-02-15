import Foundation

@MainActor
final class MPVPlayerController: ObservableObject, PlayerController {
    let coordinator: MPVPlayerView.Coordinator

    @Published private(set) var state: PlayerState = .uninitialized
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isPaused: Bool = true
    @Published private(set) var volume: Double = 100
    @Published private(set) var hdrMode: HDRMode = .sdr

    var onPropertyChange: ((String, Any?) -> Void)?
    var onEvent: ((String) -> Void)?
    var onHDRDetected: ((Bool, String?, String?) -> Void)?

    private var streamingManager: PlexStreamingManager?
    private var sessionId: String?
    private var plexBaseUrl: String?
    private var plexToken: String?

    init(coordinator: MPVPlayerView.Coordinator) {
        self.coordinator = coordinator
        bindCoordinator()
        state = .ready
    }

    convenience init() {
        self.init(coordinator: MPVPlayerView.Coordinator())
    }

    private func bindCoordinator() {
        coordinator.onPropertyChange = { [weak self] _, property, data in
            guard let self else { return }
            handlePropertyChange(property: property, value: data)
        }

        coordinator.onMediaLoaded = { [weak self] in
            guard let self else { return }
            state = isPaused ? .paused : .playing
            onEvent?("file-loaded")
        }

        coordinator.onPlaybackEnded = { [weak self] in
            guard let self else { return }
            state = .stopped
            onEvent?("file-ended")
        }
    }

    private func handlePropertyChange(property: PlayerProperty, value: Any?) {
        switch property {
        case .pause:
            let paused = (value as? Bool) ?? true
            isPaused = paused
            state = paused ? .paused : .playing
            onEvent?(paused ? "pause" : "playback-restart")

        case .pausedForCache:
            if let buffering = value as? Bool {
                state = buffering ? .buffering : (isPaused ? .paused : .playing)
                onEvent?(buffering ? "buffering" : "buffering-ended")
            }

        case .timePos:
            if let time = value as? Double {
                currentTime = time
            }

        case .duration:
            if let total = value as? Double {
                duration = total
            }

        case .demuxerCacheDuration:
            break

        case .videoParamsSigPeak:
            let sigPeak = (value as? Double) ?? 1.0
            let isHDR = sigPeak > 1.0
            hdrMode = isHDR ? .hdr : .sdr
            onHDRDetected?(isHDR, nil, nil)
        }

        onPropertyChange?(property.rawValue, value)
    }

    func loadFile(_ url: String) {
        state = .loading
        onEvent?("file-started")

        if url.hasPrefix("plex:") || url.contains("/library/metadata/") {
            loadPlexContent(url)
            return
        }

        guard let playURL = URL(string: url) else {
            state = .error(NSError(domain: "MPV", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
            return
        }

        coordinator.setPendingURL(playURL)
        coordinator.play(playURL)
    }

    private func loadPlexContent(_ metadataURL: String) {
        guard let ratingKey = parsePlexRatingKey(metadataURL) else {
            state = .error(NSError(domain: "MPV", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Plex metadata URL"]))
            return
        }

        Task {
            do {
                let api = APIClient.shared
                let servers = try await api.getPlexServers()
                guard let activeServer = servers.first(where: { $0.isActive == true }) else {
                    throw NSError(domain: "MPV", code: -1, userInfo: [NSLocalizedDescriptionKey: "No active Plex server configured"])
                }

                let connectionsResponse = try await api.getPlexConnections(serverId: activeServer.id)
                guard let selectedConnection = connectionsResponse.connections.first(where: { $0.local == true }) ?? connectionsResponse.connections.first else {
                    throw NSError(domain: "MPV", code: -1, userInfo: [NSLocalizedDescriptionKey: "No Plex server connection available"])
                }

                let baseUrl = selectedConnection.uri.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

                let authServers = try await api.getPlexAuthServers()
                guard let serverWithToken = authServers.first(where: {
                    $0.clientIdentifier == activeServer.id ||
                    $0.clientIdentifier == activeServer.machineIdentifier
                }), let token = serverWithToken.token as String? else {
                    throw NSError(domain: "MPV", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not get Plex access token"])
                }

                plexBaseUrl = baseUrl
                plexToken = token
                streamingManager = PlexStreamingManager(baseUrl: baseUrl, token: token)

                let decision = try await streamingManager!.getStreamingDecision(
                    ratingKey: ratingKey,
                    options: PlexStreamingManager.StreamingOptions(
                        streamingProtocol: "hls",
                        directPlay: true,
                        directStream: true,
                        maxVideoBitrate: nil,
                        videoResolution: nil,
                        autoAdjustQuality: true
                    )
                )

                try await loadDecision(decision)
            } catch {
                state = .error(error)
            }
        }
    }

    private func loadDecision(_ decision: PlexStreamingManager.StreamingDecision) async throws {
        sessionId = decision.sessionId

        var finalURLString: String
        switch decision.method {
        case .directPlay(let url):
            finalURLString = url

        case .directStream(let url), .transcode(let url):
            if url.contains("start.m3u8") {
                finalURLString = try await startStreamSession(url: url, sessionId: decision.sessionId)
            } else {
                finalURLString = url
            }
        }

        guard let finalURL = URL(string: finalURLString) else {
            throw NSError(domain: "MPV", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid MPV stream URL"])
        }

        coordinator.setPendingURL(finalURL)
        coordinator.play(finalURL)
    }

    private func startStreamSession(url: String, sessionId: String) async throws -> String {
        guard let startURL = URL(string: url) else {
            throw NSError(domain: "MPV", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid start URL"])
        }

        let (data, response) = try await URLSession.shared.data(from: startURL)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let message = String(data: data, encoding: .utf8) ?? "start session failed"
            throw NSError(domain: "MPV", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }

        try await Task.sleep(nanoseconds: 2_000_000_000)

        guard let urlComponents = URLComponents(string: url),
              let baseUrlString = url.components(separatedBy: "/video/").first else {
            throw NSError(domain: "MPV", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not parse base URL"])
        }

        let token = urlComponents.queryItems?.first(where: { $0.name == "X-Plex-Token" })?.value
        var sessionURL = "\(baseUrlString)/video/:/transcode/universal/session/\(sessionId)/base/index.m3u8"
        if let token {
            sessionURL += "?X-Plex-Token=\(token)"
        }
        return sessionURL
    }

    func play() {
        coordinator.resume()
        isPaused = false
        state = .playing
    }

    func pause() {
        coordinator.pause()
        isPaused = true
        state = .paused
    }

    func seek(to seconds: Double) {
        coordinator.seek(to: seconds)
    }

    func setVolume(_ volume: Double) {
        self.volume = min(max(volume, 0), 100)
        coordinator.setVolume(self.volume)
    }

    func shutdown() {
        Task {
            await stopTranscodeSession()
        }

        coordinator.destruct()
        state = .uninitialized
    }

    private func stopTranscodeSession() async {
        guard let sessionId, let baseUrl = plexBaseUrl, let token = plexToken else {
            return
        }

        guard let stopURL = URL(string: "\(baseUrl)/video/:/transcode/universal/stop?session=\(sessionId)&X-Plex-Token=\(token)") else {
            return
        }

        _ = try? await URLSession.shared.data(from: stopURL)
    }

    private func parsePlexRatingKey(_ url: String) -> String? {
        if url.hasPrefix("plex:") {
            let key = String(url.dropFirst("plex:".count))
            return key.isEmpty ? nil : key
        }

        guard let urlComponents = URLComponents(string: url) else {
            return nil
        }

        let pathComponents = urlComponents.path.split(separator: "/")
        guard let metadataIndex = pathComponents.firstIndex(of: "metadata"),
              metadataIndex + 1 < pathComponents.count else {
            return nil
        }

        return String(pathComponents[metadataIndex + 1])
    }
}
