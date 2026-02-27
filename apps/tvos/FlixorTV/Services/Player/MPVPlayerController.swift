import Foundation
import FlixorKit

@MainActor
final class MPVPlayerController: ObservableObject, PlayerController {
    let coordinator: MPVPlayerView.Coordinator

    @Published private(set) var state: PlayerState = .uninitialized
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isPaused: Bool = true
    @Published private(set) var volume: Double = 100
    @Published private(set) var hdrMode: HDRMode = .sdr

    @Published private(set) var selectedQuality: PlaybackQuality = .original
    @Published private(set) var sessionMode: MPVSessionMode = .directPlay
    @Published private(set) var sourceWidth: Int?
    @Published private(set) var mergedAudioOptions: [PlayerAudioOption] = []
    @Published private(set) var mergedSubtitleOptions: [PlayerSubtitleOption] = []
    @Published private(set) var markers: [PlexMarker] = []
    @Published private(set) var currentMarker: PlexMarker?

    var onPropertyChange: ((String, Any?) -> Void)?
    var onEvent: ((String) -> Void)?
    var onHDRDetected: ((Bool, String?, String?) -> Void)?
    var onPlaybackCompleted: ((String?, TimeInterval, TimeInterval) -> Void)?

    private var streamingManager: PlexStreamingManager?
    private var sessionId: String?
    private var plexBaseUrl: String?
    private var plexToken: String?
    private var currentRatingKey: String?

    private var activeOverride = PlaybackOverride()
    private var currentMetadata: FlixorKit.PlexMediaItem?
    private var loadTask: Task<Void, Never>?
    private var activeLoadToken = UUID()
    private var pendingRestoreState: PendingRestoreState?
    private var isShuttingDown = false
    private var isRebuilding = false
    private var hasAppliedTrackPreferencesForCurrentLoad = false
    private var cachedLoadGuardTask: Task<Void, Never>?

    private let profileSettings = TVProfileSettings.shared
    private let markerCoordinator = TVPlaybackMarkerCoordinator(profileSettings: .shared)
    private let trackPreferenceService = TVTrackPreferenceService.shared
    private let streamSessionCache = TVStreamSessionCache.shared

    private struct PendingRestoreState {
        let position: TimeInterval
        let wasPaused: Bool
    }

    init(coordinator: MPVPlayerView.Coordinator) {
        self.coordinator = coordinator
        bindCoordinator()
        state = .ready
    }

    convenience init() {
        self.init(coordinator: MPVPlayerView.Coordinator())
    }

    private func bindCoordinator() {
        markerCoordinator.onCurrentMarkerChanged = { [weak self] marker in
            self?.currentMarker = marker
        }
        markerCoordinator.onMarkersChanged = { [weak self] markers in
            self?.markers = markers
        }
        markerCoordinator.onAutoSkip = { [weak self] marker in
            guard let self else { return }
            let skipTo = TimeInterval(marker.endTimeOffset ?? 0) / 1000.0 + 0.75
            if skipTo > 0 {
                seek(to: skipTo)
                onEvent?("auto-skip-\(marker.type ?? "marker")")
            }
        }

        coordinator.onPropertyChange = { [weak self] _, property, data in
            guard let self else { return }
            handlePropertyChange(property: property, value: data)
        }

        coordinator.onMediaLoaded = { [weak self] in
            guard let self else { return }
            cachedLoadGuardTask?.cancel()
            cachedLoadGuardTask = nil
            applyPendingRestoreStateIfNeeded()
            refreshMergedTrackOptions()
            applyTrackPreferencesIfNeeded()
            state = isPaused ? .paused : .playing
            onEvent?("file-loaded")
        }

        coordinator.onPlaybackEnded = { [weak self] in
            guard let self else { return }
            if isRebuilding {
                return
            }
            state = .stopped
            markerCoordinator.resetCurrentMarker()
            onPlaybackCompleted?(currentRatingKey, currentTime, duration)
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
                markerCoordinator.update(currentTime: time, duration: duration)
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

        isShuttingDown = false
        activeLoadToken = UUID()
        let loadToken = activeLoadToken
        loadTask?.cancel()
        cachedLoadGuardTask?.cancel()
        cachedLoadGuardTask = nil

        if url.hasPrefix("plex:") || url.contains("/library/metadata/") {
            guard let ratingKey = parsePlexRatingKey(url) else {
                state = .error(NSError(domain: "MPV", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Plex metadata URL"]))
                return
            }
            currentRatingKey = ratingKey
            loadTask = Task { [weak self] in
                await self?.loadPlexContent(ratingKey: ratingKey, loadToken: loadToken, preserveState: nil)
            }
            return
        }

        currentRatingKey = nil
        currentMetadata = nil
        sourceWidth = nil
        mergedAudioOptions = []
        mergedSubtitleOptions = []
        markers = []
        currentMarker = nil
        hasAppliedTrackPreferencesForCurrentLoad = false
        markerCoordinator.setMarkers([])
        markerCoordinator.setRatingKey(nil)

        guard let playURL = URL(string: url) else {
            state = .error(NSError(domain: "MPV", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
            return
        }

        coordinator.setPendingURL(playURL)
        coordinator.play(playURL)
    }

    func availableQualities() -> [PlaybackQuality] {
        PlaybackQuality.availableQualities(sourceWidth: sourceWidth)
    }

    func audioOptions() -> [PlayerAudioOption] {
        mergedAudioOptions
    }

    func subtitleOptions() -> [PlayerSubtitleOption] {
        mergedSubtitleOptions
    }

    func changeQuality(to quality: PlaybackQuality) async {
        guard quality != activeOverride.quality else { return }
        guard currentRatingKey != nil else {
            activeOverride.quality = quality
            selectedQuality = quality
            return
        }

        #if DEBUG
        print("🎚️ [MPV] Quality override: \(activeOverride.quality.rawValue) -> \(quality.rawValue)")
        #endif
        activeOverride.quality = quality
        selectedQuality = quality
        await rebuildCurrentSession(reason: "quality-change")
    }

    func selectAudioOption(_ option: PlayerAudioOption?) async {
        guard let option else { return }
        if let mediaId = currentRatingKey {
            let seriesId = currentMetadata?.grandparentRatingKey
            trackPreferenceService.saveAudioPreference(for: mediaId, seriesId: seriesId, from: option)
        }
        if let trackID = option.mpvTrackID {
            selectAudioTrack(id: trackID)
            activeOverride.audioStreamID = option.plexStreamID
            refreshMergedTrackOptions()
            return
        }

        guard let streamID = option.plexStreamID else { return }
        activeOverride.audioStreamID = streamID
        #if DEBUG
        print("🎵 [MPV] Audio option requires rebuild: streamID=\(streamID)")
        #endif
        await rebuildCurrentSession(reason: "audio-override")
    }

    func selectSubtitleOption(_ option: PlayerSubtitleOption?) async {
        if option == nil {
            activeOverride.subtitleStreamID = nil
            selectSubtitleTrack(id: nil)
            if let mediaId = currentRatingKey {
                let seriesId = currentMetadata?.grandparentRatingKey
                trackPreferenceService.saveSubtitlePreference(for: mediaId, seriesId: seriesId, languageToken: "none")
            }
            refreshMergedTrackOptions()
            return
        }

        guard let option else { return }
        if let mediaId = currentRatingKey {
            let seriesId = currentMetadata?.grandparentRatingKey
            trackPreferenceService.saveSubtitlePreference(for: mediaId, seriesId: seriesId, from: option)
        }
        if let trackID = option.mpvTrackID {
            activeOverride.subtitleStreamID = option.plexStreamID
            selectSubtitleTrack(id: trackID)
            refreshMergedTrackOptions()
            return
        }

        guard let streamID = option.plexStreamID else { return }
        activeOverride.subtitleStreamID = streamID
        #if DEBUG
        print("💬 [MPV] Subtitle option requires rebuild: streamID=\(streamID), kind=\(option.kind.rawValue)")
        #endif
        await rebuildCurrentSession(reason: "subtitle-override")
    }

    private func loadPlexContent(
        ratingKey: String,
        loadToken: UUID,
        preserveState: PendingRestoreState?,
        forceFreshDecision: Bool = false
    ) async {
        do {
            try Task.checkCancellation()
            try await resolvePlexConnectionContext()
            try Task.checkCancellation()
            guard isLoadTokenCurrent(loadToken) else { return }

            let metadata = try await fetchMetadata(ratingKey: ratingKey)
            guard isLoadTokenCurrent(loadToken) else { return }

            currentMetadata = metadata
            sourceWidth = metadata.Media?.first?.width
            currentRatingKey = ratingKey
            hasAppliedTrackPreferencesForCurrentLoad = false
            markerCoordinator.setRatingKey(ratingKey)
            await refreshMarkers(for: ratingKey)

            let available = PlaybackQuality.availableQualities(sourceWidth: sourceWidth)
            if !available.contains(activeOverride.quality) {
                activeOverride.quality = .original
            }
            selectedQuality = activeOverride.quality

            let options = buildStreamingOptions(for: activeOverride)
            let cacheKey = streamCacheKey(ratingKey: ratingKey, override: activeOverride)

            if profileSettings.useCachedStreams, !forceFreshDecision,
               let cached = streamSessionCache.read(for: cacheKey, ttl: profileSettings.streamCacheTTL) {
                sessionMode = cached.mode
                pendingRestoreState = preserveState
                guard let finalURL = URL(string: cached.url) else {
                    streamSessionCache.remove(for: cacheKey)
                    throw NSError(domain: "MPV", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid cached stream URL"])
                }
                coordinator.setPendingURL(finalURL)
                coordinator.play(finalURL)
                armCachedLoadGuard(cacheKey: cacheKey, ratingKey: ratingKey, preserveState: preserveState, loadToken: loadToken)
                return
            }

            #if DEBUG
            print("📡 [MPV] Decision mode request:")
            print("   quality=\(activeOverride.quality.rawValue)")
            print("   directPlay=\(options.directPlay) directStream=\(options.directStream)")
            print("   bitrate=\(options.maxVideoBitrate.map(String.init) ?? "nil") resolution=\(options.videoResolution ?? "nil")")
            print("   audioStreamID=\(options.audioStreamID ?? "nil") subtitleStreamID=\(options.subtitleStreamID ?? "nil")")
            #endif

            guard let streamingManager else {
                throw NSError(domain: "MPV", code: -1, userInfo: [NSLocalizedDescriptionKey: "Streaming manager unavailable"])
            }

            let decision = try await streamingManager.getStreamingDecision(
                ratingKey: ratingKey,
                options: options
            )
            guard isLoadTokenCurrent(loadToken) else { return }

            pendingRestoreState = preserveState
            let finalURLString = try await loadDecision(decision, loadToken: loadToken)

            if profileSettings.useCachedStreams {
                streamSessionCache.write(
                    TVStreamSessionCache.Record(
                        url: finalURLString,
                        mode: sessionMode,
                        timestamp: Date()
                    ),
                    for: cacheKey
                )
            }

            refreshMergedTrackOptions()
        } catch is CancellationError {
            return
        } catch {
            guard isLoadTokenCurrent(loadToken) else { return }
            state = .error(error)
        }
    }

    private func buildStreamingOptions(for override: PlaybackOverride) -> PlexStreamingManager.StreamingOptions {
        if override.quality == .original {
            return PlexStreamingManager.StreamingOptions(
                streamingProtocol: "hls",
                directPlay: true,
                directStream: true,
                maxVideoBitrate: nil,
                videoResolution: nil,
                audioStreamID: override.audioStreamID,
                subtitleStreamID: override.subtitleStreamID,
                autoAdjustQuality: true
            )
        }

        return PlexStreamingManager.StreamingOptions(
            streamingProtocol: "hls",
            directPlay: false,
            directStream: false,
            maxVideoBitrate: override.quality.bitrate,
            videoResolution: override.quality.resolution,
            audioStreamID: override.audioStreamID,
            subtitleStreamID: override.subtitleStreamID,
            autoAdjustQuality: false
        )
    }

    private func resolvePlexConnectionContext() async throws {
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
    }

    private func fetchMetadata(ratingKey: String) async throws -> FlixorKit.PlexMediaItem {
        try await APIClient.shared.get("/api/plex/metadata/\(ratingKey)", bypassCache: true)
    }

    private func isLoadTokenCurrent(_ token: UUID) -> Bool {
        !isShuttingDown && activeLoadToken == token
    }

    @discardableResult
    private func loadDecision(_ decision: PlexStreamingManager.StreamingDecision, loadToken: UUID) async throws -> String {
        sessionId = decision.sessionId

        var finalURLString: String
        switch decision.method {
        case .directPlay(let url):
            sessionMode = .directPlay
            finalURLString = url
        case .directStream(let url):
            sessionMode = .directStream
            if url.contains("start.m3u8") {
                finalURLString = try await startStreamSession(url: url, sessionId: decision.sessionId)
            } else {
                finalURLString = url
            }
        case .transcode(let url):
            sessionMode = .transcode
            if url.contains("start.m3u8") {
                finalURLString = try await startStreamSession(url: url, sessionId: decision.sessionId)
            } else {
                finalURLString = url
            }
        }

        guard isLoadTokenCurrent(loadToken) else { throw CancellationError() }

        guard let finalURL = URL(string: finalURLString) else {
            throw NSError(domain: "MPV", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid MPV stream URL"])
        }

        coordinator.setPendingURL(finalURL)
        coordinator.play(finalURL)
        return finalURLString
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

        try await Task.sleep(nanoseconds: 1_500_000_000)

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

    private func applyPendingRestoreStateIfNeeded() {
        guard let pending = pendingRestoreState else { return }
        pendingRestoreState = nil

        if pending.position > 0 {
            coordinator.seek(to: pending.position)
        }

        if pending.wasPaused {
            coordinator.pause()
            isPaused = true
            state = .paused
        } else {
            coordinator.resume()
            isPaused = false
            state = .playing
        }
    }

    private func refreshMergedTrackOptions() {
        let tracks = coordinator.trackList()
        let audioTracks = tracks.filter { $0.type == .audio }
        let subtitleTracks = tracks.filter { $0.type == .subtitle }
        let streams = activePlexStreams()

        let audioStreams = streams.filter { $0.streamType == 2 }
        let subtitleStreams = streams.filter { $0.streamType == 3 }

        var usedAudioStreamIDs = Set<String>()
        var usedSubtitleStreamIDs = Set<String>()

        var audioOptions: [PlayerAudioOption] = audioTracks.map { track in
            let matched = matchPlexStream(for: track, in: audioStreams)
            if let sid = matched?.id { usedAudioStreamIDs.insert(sid) }

            let subtitle = [
                (track.language?.isEmpty == false ? track.language?.uppercased() : nil),
                codecLabel(track.codec ?? matched?.codec),
                matched?.displayTitle
            ].compactMap { $0 }.joined(separator: " • ")

            return PlayerAudioOption(
                id: "mpv-audio-\(track.id)",
                title: track.displayName,
                subtitle: subtitle.isEmpty ? nil : subtitle,
                mpvTrackID: track.id,
                plexStreamID: matched?.id,
                isSelected: track.isSelected,
                requiresSessionRebuild: false
            )
        }

        let hasSelectedAudio = audioOptions.contains(where: { $0.isSelected })
        let metadataAudio: [PlayerAudioOption] = audioStreams.compactMap { stream in
            guard let sid = stream.id, !usedAudioStreamIDs.contains(sid) else { return nil }
            let subtitle = [
                (stream.languageTag ?? stream.language)?.uppercased(),
                codecLabel(stream.codec),
                "Reload required"
            ].compactMap { $0 }.joined(separator: " • ")

            return PlayerAudioOption(
                id: "plex-audio-\(sid)",
                title: stream.displayTitle ?? stream.title ?? (stream.language ?? "Audio"),
                subtitle: subtitle,
                mpvTrackID: nil,
                plexStreamID: sid,
                isSelected: !hasSelectedAudio && (stream.selected ?? false),
                requiresSessionRebuild: true
            )
        }
        audioOptions.append(contentsOf: metadataAudio)

        var subtitleOptions: [PlayerSubtitleOption] = subtitleTracks.map { track in
            let matched = matchPlexStream(for: track, in: subtitleStreams)
            if let sid = matched?.id { usedSubtitleStreamIDs.insert(sid) }
            let kind = subtitleKind(codec: track.codec ?? matched?.codec)
            let subtitle = [
                (track.language?.isEmpty == false ? track.language?.uppercased() : nil),
                codecLabel(track.codec ?? matched?.codec),
                kind == .unknown ? nil : kind.label
            ].compactMap { $0 }.joined(separator: " • ")

            return PlayerSubtitleOption(
                id: "mpv-sub-\(track.id)",
                title: track.displayName,
                subtitle: subtitle.isEmpty ? nil : subtitle,
                mpvTrackID: track.id,
                plexStreamID: matched?.id,
                kind: kind,
                isSelected: track.isSelected,
                requiresSessionRebuild: false
            )
        }

        let hasSelectedSubtitle = subtitleOptions.contains(where: { $0.isSelected })
        let metadataSubtitles: [PlayerSubtitleOption] = subtitleStreams.compactMap { stream in
            guard let sid = stream.id, !usedSubtitleStreamIDs.contains(sid) else { return nil }
            let kind = subtitleKind(codec: stream.codec)
            let subtitle = [
                (stream.languageTag ?? stream.language)?.uppercased(),
                codecLabel(stream.codec),
                kind == .unknown ? nil : kind.label,
                "Reload required"
            ].compactMap { $0 }.joined(separator: " • ")

            return PlayerSubtitleOption(
                id: "plex-sub-\(sid)",
                title: stream.displayTitle ?? stream.title ?? (stream.language ?? "Subtitle"),
                subtitle: subtitle,
                mpvTrackID: nil,
                plexStreamID: sid,
                kind: kind,
                isSelected: !hasSelectedSubtitle && (stream.selected ?? false),
                requiresSessionRebuild: true
            )
        }
        subtitleOptions.append(contentsOf: metadataSubtitles)

        mergedAudioOptions = audioOptions
        mergedSubtitleOptions = subtitleOptions

        #if DEBUG
        let metadataOnlySubtitleCount = subtitleOptions.filter { $0.requiresSessionRebuild }.count
        print("💬 [MPV] Subtitle options merged: mpv-track=\(subtitleTracks.count), plex-metadata=\(subtitleStreams.count), merged=\(subtitleOptions.count), requires-rebuild=\(metadataOnlySubtitleCount)")
        #endif

        applyTrackPreferencesIfNeeded()
    }

    private func activePlexStreams() -> [PlexStream] {
        currentMetadata?.Media?.first?.Part?.first?.Stream ?? []
    }

    private func matchPlexStream(for track: PlayerTrack, in streams: [PlexStream]) -> PlexStream? {
        if let ffIndex = track.ffIndex, let exact = streams.first(where: { $0.index == ffIndex }) {
            return exact
        }

        let trackLanguage = normalizeToken(track.language)
        let trackCodec = normalizeToken(track.codec)

        return streams.first { stream in
            let streamLanguage = normalizeToken(stream.languageTag ?? stream.language)
            let streamCodec = normalizeToken(stream.codec)
            return (!trackLanguage.isEmpty && streamLanguage == trackLanguage) &&
                   (!trackCodec.isEmpty && streamCodec == trackCodec)
        }
    }

    private func normalizeToken(_ token: String?) -> String {
        guard let token else { return "" }
        return token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func codecLabel(_ codec: String?) -> String? {
        guard let codec, !codec.isEmpty else { return nil }
        return codec.uppercased()
    }

    private func subtitleKind(codec: String?) -> SubtitleKind {
        let normalized = normalizeToken(codec)
        if normalized.isEmpty {
            return .unknown
        }

        let textCodecs: Set<String> = ["srt", "subrip", "ass", "ssa", "webvtt", "vtt", "tx3g"]
        if textCodecs.contains(normalized) {
            return .text
        }

        let imageCodecs: Set<String> = ["pgs", "hdmv_pgs_subtitle", "vobsub", "dvd_subtitle"]
        if imageCodecs.contains(normalized) {
            return .image
        }

        return .unknown
    }

    private func rebuildCurrentSession(reason: String) async {
        guard let ratingKey = currentRatingKey else { return }
        if isRebuilding {
            return
        }

        isRebuilding = true
        defer { isRebuilding = false }

        let loadToken = UUID()
        activeLoadToken = loadToken
        loadTask?.cancel()

        let restore = PendingRestoreState(
            position: max(currentTime, 0),
            wasPaused: isPaused
        )

        #if DEBUG
        print("🔄 [MPV] Rebuild start (\(reason))")
        print("   restoreTime=\(Int(restore.position))s paused=\(restore.wasPaused)")
        print("   mode=\(sessionMode.rawValue)")
        #endif

        await stopTranscodeSession()
        await loadPlexContent(ratingKey: ratingKey, loadToken: loadToken, preserveState: restore)
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

    func setPlaybackRate(_ rate: Float) {
        coordinator.setPlaybackRate(rate)
    }

    func selectAudioTrack(id: Int?) {
        coordinator.selectAudioTrack(id: id)
    }

    func selectSubtitleTrack(id: Int?) {
        coordinator.selectSubtitleTrack(id: id)
    }

    func trackList() -> [PlayerTrack] {
        coordinator.trackList()
    }

    func setVolume(_ volume: Double) {
        self.volume = min(max(volume, 0), 100)
        coordinator.setVolume(self.volume)
    }

    func shutdown() {
        isShuttingDown = true
        activeLoadToken = UUID()
        loadTask?.cancel()
        loadTask = nil
        cachedLoadGuardTask?.cancel()
        cachedLoadGuardTask = nil
        markerCoordinator.setMarkers([])
        markerCoordinator.setRatingKey(nil)
        markers = []
        currentMarker = nil

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

        #if DEBUG
        print("🛑 [MPV] Stopping transcode session: \(sessionId)")
        #endif
        _ = try? await URLSession.shared.data(from: stopURL)
        self.sessionId = nil
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

    private func refreshMarkers(for ratingKey: String) async {
        do {
            let fetched = try await APIClient.shared.getPlexMarkers(ratingKey: ratingKey)
            markerCoordinator.setMarkers(fetched)
        } catch {
            markerCoordinator.setMarkers([])
        }
    }

    private func streamCacheKey(ratingKey: String, override: PlaybackOverride) -> String {
        [
            ratingKey,
            override.quality.rawValue,
            override.audioStreamID ?? "audio:none",
            override.subtitleStreamID ?? "sub:none"
        ].joined(separator: "|")
    }

    private func armCachedLoadGuard(
        cacheKey: String,
        ratingKey: String,
        preserveState: PendingRestoreState?,
        loadToken: UUID
    ) {
        cachedLoadGuardTask?.cancel()
        cachedLoadGuardTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            guard !Task.isCancelled else { return }
            guard self.isLoadTokenCurrent(loadToken) else { return }
            guard self.state != .playing, self.state != .paused else { return }
            self.streamSessionCache.remove(for: cacheKey)
            await self.loadPlexContent(
                ratingKey: ratingKey,
                loadToken: loadToken,
                preserveState: preserveState,
                forceFreshDecision: true
            )
        }
    }

    private func applyTrackPreferencesIfNeeded() {
        guard !hasAppliedTrackPreferencesForCurrentLoad else { return }
        guard profileSettings.rememberTrackSelections else {
            hasAppliedTrackPreferencesForCurrentLoad = true
            return
        }
        hasAppliedTrackPreferencesForCurrentLoad = true

        guard let mediaId = currentRatingKey else { return }
        let seriesId = currentMetadata?.grandparentRatingKey
        if let preferredAudio = trackPreferenceService.recommendedAudioOption(
            options: mergedAudioOptions,
            mediaId: mediaId,
            seriesId: seriesId
        ) {
            if let trackID = preferredAudio.mpvTrackID {
                selectAudioTrack(id: trackID)
            } else if preferredAudio.requiresSessionRebuild {
                activeOverride.audioStreamID = preferredAudio.plexStreamID
                Task { [weak self] in await self?.rebuildCurrentSession(reason: "track-preference-audio") }
                return
            }
        }

        if trackPreferenceService.shouldDisableSubtitles(mediaId: mediaId, seriesId: seriesId) {
            selectSubtitleTrack(id: nil)
            return
        }

        if let preferredSubtitle = trackPreferenceService.recommendedSubtitleOption(
            options: mergedSubtitleOptions,
            mediaId: mediaId,
            seriesId: seriesId
        ) {
            if let trackID = preferredSubtitle.mpvTrackID {
                selectSubtitleTrack(id: trackID)
            } else if preferredSubtitle.requiresSessionRebuild {
                activeOverride.subtitleStreamID = preferredSubtitle.plexStreamID
                Task { [weak self] in await self?.rebuildCurrentSession(reason: "track-preference-subtitle") }
            }
        }
    }
}

@MainActor
final class TVPlaybackMarkerCoordinator {
    private(set) var markers: [PlexMarker] = []
    private var activeMarkerId: Int?
    private var triggeredMarkerIds = Set<Int>()
    private var ratingKey: String?
    private let profileSettings: TVProfileSettings

    var onMarkersChanged: (([PlexMarker]) -> Void)?
    var onCurrentMarkerChanged: ((PlexMarker?) -> Void)?
    var onAutoSkip: ((PlexMarker) -> Void)?

    init(profileSettings: TVProfileSettings) {
        self.profileSettings = profileSettings
    }

    func setRatingKey(_ ratingKey: String?) {
        self.ratingKey = ratingKey
        activeMarkerId = nil
        triggeredMarkerIds.removeAll()
    }

    func setMarkers(_ markers: [PlexMarker]) {
        self.markers = markers
        activeMarkerId = nil
        triggeredMarkerIds.removeAll()
        onMarkersChanged?(markers)
        onCurrentMarkerChanged?(nil)
    }

    func resetCurrentMarker() {
        activeMarkerId = nil
        onCurrentMarkerChanged?(nil)
    }

    func update(currentTime: TimeInterval, duration: TimeInterval) {
        guard !markers.isEmpty else {
            if activeMarkerId != nil {
                activeMarkerId = nil
                onCurrentMarkerChanged?(nil)
            }
            return
        }

        let currentMs = Int(currentTime * 1000)
        let marker = markers.first { marker in
            guard let start = marker.startTimeOffset, let end = marker.endTimeOffset else { return false }
            return currentMs >= start && currentMs <= end
        }

        if marker?.id != activeMarkerId {
            activeMarkerId = marker?.id
            onCurrentMarkerChanged?(marker)
        }

        guard let marker,
              let markerId = marker.id,
              !triggeredMarkerIds.contains(markerId) else { return }

        let type = marker.type?.lowercased() ?? ""
        let shouldSkip =
            (type == "intro" && profileSettings.skipIntroAutomatically) ||
            (type == "credits" && profileSettings.skipCreditsAutomatically)
        if shouldSkip {
            triggeredMarkerIds.insert(markerId)
            onAutoSkip?(marker)
        }
    }
}

@MainActor
final class TVTrackPreferenceService {
    static let shared = TVTrackPreferenceService()

    private let defaults = UserDefaults.standard
    private let audioPrefsKey = "tvos.audioTrackPreferences"
    private let subtitlePrefsKey = "tvos.subtitleTrackPreferences"

    private init() {}

    func saveAudioPreference(for mediaId: String, seriesId: String?, from option: PlayerAudioOption) {
        guard defaults.rememberTrackSelections else { return }
        guard let token = languageToken(from: option) else { return }
        var prefs = defaults.dictionary(forKey: audioPrefsKey) as? [String: String] ?? [:]
        prefs[mediaId] = token
        if let seriesId, !seriesId.isEmpty {
            prefs["series:\(seriesId)"] = token
        }
        defaults.set(prefs, forKey: audioPrefsKey)
    }

    func saveSubtitlePreference(for mediaId: String, seriesId: String?, from option: PlayerSubtitleOption) {
        guard defaults.rememberTrackSelections else { return }
        guard let token = languageToken(from: option) else { return }
        saveSubtitlePreference(for: mediaId, seriesId: seriesId, languageToken: token)
    }

    func saveSubtitlePreference(for mediaId: String, seriesId: String?, languageToken: String) {
        guard defaults.rememberTrackSelections else { return }
        var prefs = defaults.dictionary(forKey: subtitlePrefsKey) as? [String: String] ?? [:]
        prefs[mediaId] = languageToken
        if let seriesId, !seriesId.isEmpty {
            prefs["series:\(seriesId)"] = languageToken
        }
        defaults.set(prefs, forKey: subtitlePrefsKey)
    }

    func recommendedAudioOption(options: [PlayerAudioOption], mediaId: String, seriesId: String?) -> PlayerAudioOption? {
        let preferred = preferredLanguage(fromKey: audioPrefsKey, mediaId: mediaId, seriesId: seriesId)
        guard let preferred else { return nil }
        return options.first { languageToken(from: $0) == preferred }
    }

    func recommendedSubtitleOption(options: [PlayerSubtitleOption], mediaId: String, seriesId: String?) -> PlayerSubtitleOption? {
        let preferred = preferredLanguage(fromKey: subtitlePrefsKey, mediaId: mediaId, seriesId: seriesId)
        guard let preferred, preferred != "none" else { return nil }
        return options.first { languageToken(from: $0) == preferred }
    }

    func shouldDisableSubtitles(mediaId: String, seriesId: String?) -> Bool {
        preferredLanguage(fromKey: subtitlePrefsKey, mediaId: mediaId, seriesId: seriesId) == "none"
    }

    private func preferredLanguage(fromKey key: String, mediaId: String, seriesId: String?) -> String? {
        guard defaults.rememberTrackSelections else { return nil }
        let prefs = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        if let media = prefs[mediaId] {
            return media
        }
        if let seriesId, let series = prefs["series:\(seriesId)"] {
            return series
        }
        return mostFrequentValue(in: prefs)
    }

    private func mostFrequentValue(in values: [String: String]) -> String? {
        var frequency: [String: Int] = [:]
        for value in values.values where !value.isEmpty {
            frequency[value, default: 0] += 1
        }
        return frequency.max(by: { $0.value < $1.value })?.key
    }

    private func languageToken(from option: PlayerAudioOption) -> String? {
        if let subtitle = option.subtitle {
            let first = subtitle.split(separator: "•").first?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let first, !first.isEmpty {
                return first.lowercased()
            }
        }
        let fallback = option.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? nil : fallback.lowercased()
    }

    private func languageToken(from option: PlayerSubtitleOption) -> String? {
        if let subtitle = option.subtitle {
            let first = subtitle.split(separator: "•").first?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let first, !first.isEmpty {
                return first.lowercased()
            }
        }
        let fallback = option.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? nil : fallback.lowercased()
    }
}

@MainActor
final class TVStreamSessionCache {
    struct Record: Codable {
        let url: String
        let mode: MPVSessionMode
        let timestamp: Date
    }

    static let shared = TVStreamSessionCache()
    private let defaults = UserDefaults.standard
    private let storageKey = "tvos.streamSessionCache.v1"

    private init() {}

    func read(for key: String, ttl: Int) -> Record? {
        guard ttl > 0 else { return nil }
        var all = allRecords()
        guard let record = all[key] else { return nil }
        if Date().timeIntervalSince(record.timestamp) > TimeInterval(ttl) {
            all.removeValue(forKey: key)
            persist(all)
            return nil
        }
        return record
    }

    func write(_ record: Record, for key: String) {
        var all = allRecords()
        all[key] = record
        persist(all)
    }

    func remove(for key: String) {
        var all = allRecords()
        all.removeValue(forKey: key)
        persist(all)
    }

    private func allRecords() -> [String: Record] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: Record].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func persist(_ value: [String: Record]) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
