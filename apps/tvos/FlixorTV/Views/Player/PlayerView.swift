//
//  PlayerView.swift
//  FlixorTV
//
//  Player view for actual playback (from details screen)
//

import SwiftUI
import FlixorKit

struct PlayerView: View {
    let item: MediaItem
    @StateObject private var playerSettings = PlayerSettings()
    @EnvironmentObject private var profileSettings: TVProfileSettings
    @State private var avkitController: AVKitPlayerController?
    @State private var mpvController: MPVPlayerController?
    @Environment(\.dismiss) private var dismiss

    @State private var controlsVisible = true
    @State private var hideControlsWorkItem: DispatchWorkItem?
    @State private var isScrubbing = false
    @State private var timelinePosition = 0.0
    @State private var currentTime = 0.0
    @State private var duration = 0.0
    @State private var bufferedAhead = 0.0
    @State private var isPaused = true
    @State private var supportsHDR = false
    @State private var hasLoadedPlayback = false
    @State private var audioTracks: [PlayerTrack] = []
    @State private var subtitleTracks: [PlayerTrack] = []
    @State private var settingsAudioTracks: [TVPlaybackSettingsTrack] = []
    @State private var settingsSubtitleTracks: [TVPlaybackSettingsTrack] = []
    @State private var selectedAudioTrackID: String?
    @State private var selectedSubtitleTrackID: String?
    @State private var availableQualities: [PlaybackQuality] = PlaybackQuality.allCases
    @State private var selectedQuality: PlaybackQuality = .original
    @State private var playbackRate: Float = 1.0
    @State private var activeSettingsSheet: TVPlayerSettingsSheet?
    @State private var activeItem: MediaItem?
    @State private var currentRatingKey: String?

    private let controlsHideDelay: TimeInterval = 3.0
    private var seekBackwardSeconds: Int { max(1, profileSettings.seekTimeSmall) }
    private var seekForwardSeconds: Int { max(1, profileSettings.seekTimeSmall) }
    private let scrobbler = TVTraktScrobbler.shared
    private let traktSync = TVTraktSyncCoordinator.shared
    private let progressReporter = TVPlaybackProgressReporter()

    private var currentItem: MediaItem {
        activeItem ?? item
    }

    private var isMPVActive: Bool {
        playerSettings.backend == .mpv && mpvController != nil
    }

    private var isAVKitActive: Bool {
        playerSettings.backend == .avkit && avkitController != nil
    }

    private var effectiveDuration: Double {
        if duration > 0 { return duration }
        if let ms = currentItem.duration, ms > 0 { return Double(ms) / 1000.0 }
        return 0
    }

    private var titleText: String {
        if !currentItem.title.isEmpty { return currentItem.title }
        return "Now Playing"
    }

    private var subtitleText: String? {
        let parts = [currentItem.grandparentTitle, currentItem.parentTitle].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if playerSettings.backend == .avkit, let controller = avkitController {
                AVKitPlayerView(controller: controller)
                    .ignoresSafeArea()
            } else if playerSettings.backend == .mpv, let controller = mpvController {
                MPVPlayerView(coordinator: controller.coordinator)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showControls(temporarily: true)
                    }
            }
        }
        .overlay {
            if isMPVActive {
                ZStack {
                    if !controlsVisible {
                        Color.clear
                            .contentShape(Rectangle())
                            .focusable()
                            .onTapGesture {
                                showControls(temporarily: true)
                            }
                            .onMoveCommand { _ in
                                showControls(temporarily: true)
                            }
                    }

                    if controlsVisible {
                        TVPlayerControlsOverlay(
                            title: titleText,
                            subtitle: subtitleText,
                            isPaused: isPaused,
                            supportsHDR: supportsHDR,
                            position: timelineBinding,
                            duration: effectiveDuration > 0 ? effectiveDuration : nil,
                            bufferedAhead: bufferedAhead,
                            bufferBasePosition: currentTime,
                            isScrubbing: isScrubbing,
                            seekBackwardSeconds: seekBackwardSeconds,
                            seekForwardSeconds: seekForwardSeconds,
                            onSeekBackward: { jump(by: -Double(seekBackwardSeconds)) },
                            onSeekForward: { jump(by: Double(seekForwardSeconds)) },
                            onShowSpeedSettings: showSpeedSettings,
                            onShowQualitySettings: showQualitySettings,
                            onShowAudioSettings: showAudioSettings,
                            onShowSubtitleSettings: showSubtitleSettings,
                            onPlayPause: togglePlayPause,
                            onScrubbingChanged: handleScrubbing(editing:),
                            onUserInteraction: { showControls(temporarily: true) }
                        )
                        .transition(.opacity)
                    }
                }
            } else if isAVKitActive {
                avkitHeaderOverlay
            }
        }
        .onAppear {
            activeItem = item
            currentRatingKey = extractRatingKey(from: item.id)
            print("🎬 [PlayerView] Loading item: \(item.id)")
            loadVideoIfNeeded()
        }
        .onDisappear {
            cleanup()
        }
        .onPlayPauseCommand {
            guard isMPVActive else { return }
            togglePlayPause()
        }
        .onExitCommand {
            closePlayer()
        }
        .sheet(item: $activeSettingsSheet) { sheet in
            switch sheet {
            case .audio:
                TVPlayerTrackSelectionView(
                    title: "Audio",
                    tracks: settingsAudioTracks,
                    selectedTrackID: selectedAudioTrackID,
                    showOffOption: false,
                    onSelect: selectAudioTrack(_:),
                    onClose: { activeSettingsSheet = nil }
                )
            case .subtitle:
                TVPlayerTrackSelectionView(
                    title: "Subtitles",
                    tracks: settingsSubtitleTracks,
                    selectedTrackID: selectedSubtitleTrackID,
                    showOffOption: true,
                    onSelect: selectSubtitleTrack(_:),
                    onClose: { activeSettingsSheet = nil }
                )
            case .speed:
                TVPlayerPlaybackSettingsView(
                    selectedRate: playbackRate,
                    onSelect: selectPlaybackRate(_:),
                    onClose: { activeSettingsSheet = nil }
                )
            case .quality:
                TVPlayerQualitySelectionView(
                    selectedQuality: selectedQuality,
                    availableQualities: availableQualities,
                    onSelectQuality: selectPlaybackQuality(_:),
                    onClose: { activeSettingsSheet = nil }
                )
            }
        }
    }

    private var avkitHeaderOverlay: some View {
        VStack {
            HStack {
                Button(action: closePlayer) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                }
                .padding()

                Spacer()

                Text(playerSettings.backend.rawValue)
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(8)
                    .padding()
            }

            Spacer()
        }
    }

    private var timelineBinding: Binding<Double> {
        Binding(
            get: { timelinePosition },
            set: { timelinePosition = $0 }
        )
    }

    private func loadVideoIfNeeded() {
        guard !hasLoadedPlayback else { return }
        hasLoadedPlayback = true
        playbackRate = Float(profileSettings.defaultPlaybackSpeed)
        if profileSettings.defaultQuality >= 0 && profileSettings.defaultQuality < PlaybackQuality.allCases.count {
            selectedQuality = PlaybackQuality.allCases[profileSettings.defaultQuality]
        }

        switch playerSettings.backend {
        case .avkit:
            controlsVisible = false
            let controller = AVKitPlayerController()
            avkitController = controller

            controller.onEvent = { event in
                print("🎬 [PlayerView/AVKit] Event: \(event)")
            }

            controller.onHDRDetected = { isHDR, gamma, primaries in
                if isHDR {
                    print("🌈 [PlayerView/AVKit] HDR Detected! Gamma: \(gamma ?? "unknown"), Primaries: \(primaries ?? "unknown")")
                } else {
                    print("📺 [PlayerView/AVKit] SDR Content")
                }
            }

            controller.loadFile(currentItem.id)

        case .mpv:
            let controller = MPVPlayerController()
            mpvController = controller
            Task {
                await controller.changeQuality(to: selectedQuality)
            }

            controller.onEvent = { event in
                print("🎬 [PlayerView/MPV] Event: \(event)")
                if event == "file-loaded" {
                    refreshTracks()
                    Task { await startScrobblingIfNeeded() }
                } else if event == "file-ended" {
                    Task { await handlePlaybackEnded() }
                }
            }

            controller.onPlaybackCompleted = { _, time, total in
                Task { @MainActor in
                    await finishProgressAndScrobble(currentTime: time, duration: total)
                }
            }

            controller.onHDRDetected = { isHDR, gamma, primaries in
                supportsHDR = isHDR
                if isHDR {
                    print("🌈 [PlayerView/MPV] HDR Detected! Gamma: \(gamma ?? "unknown"), Primaries: \(primaries ?? "unknown")")
                } else {
                    print("📺 [PlayerView/MPV] SDR Content")
                }
            }

            controller.onPropertyChange = { property, value in
                switch property {
                case PlayerProperty.pause.rawValue:
                    if let paused = value as? Bool {
                        let wasPaused = isPaused
                        isPaused = paused
                        if paused != wasPaused {
                            Task {
                                if paused {
                                    await scrobbler.pauseScrobble(progress: currentProgressPercent)
                                } else {
                                    await scrobbler.resumeScrobble(progress: currentProgressPercent)
                                }
                            }
                        }
                    }
                case PlayerProperty.timePos.rawValue:
                    if let time = value as? Double {
                        currentTime = time
                        if !isScrubbing {
                            timelinePosition = time
                        }
                        reportPlaybackProgressIfNeeded(state: isPaused ? "paused" : "playing")
                    }
                case PlayerProperty.duration.rawValue:
                    if let total = value as? Double {
                        duration = max(0, total)
                    }
                case PlayerProperty.demuxerCacheDuration.rawValue:
                    if let buffered = value as? Double {
                        bufferedAhead = max(0, buffered)
                    }
                default:
                    break
                }
            }

            controller.setPlaybackRate(playbackRate)
            selectedQuality = controller.selectedQuality
            availableQualities = controller.availableQualities()
            controller.loadFile(currentItem.id)
            showControls(temporarily: true)
        }
    }

    private func togglePlayPause() {
        guard let controller = mpvController else { return }
        if isPaused {
            controller.play()
        } else {
            controller.pause()
        }
        showControls(temporarily: true)
    }

    private func showAudioSettings() {
        refreshTracks()
        activeSettingsSheet = .audio
        showControls(temporarily: true)
    }

    private func showSubtitleSettings() {
        refreshTracks()
        activeSettingsSheet = .subtitle
        showControls(temporarily: true)
    }

    private func showSpeedSettings() {
        activeSettingsSheet = .speed
        showControls(temporarily: true)
    }

    private func showQualitySettings() {
        activeSettingsSheet = .quality
        showControls(temporarily: true)
    }

    private func refreshTracks() {
        guard let controller = mpvController else { return }

        availableQualities = controller.availableQualities()
        selectedQuality = controller.selectedQuality

        let audioOptions = controller.audioOptions()
        let subtitleOptions = controller.subtitleOptions()

        settingsAudioTracks = audioOptions.map(TVPlaybackSettingsTrack.init(audioOption:))
        settingsSubtitleTracks = subtitleOptions.map(TVPlaybackSettingsTrack.init(subtitleOption:))

        if let activeAudio = audioOptions.first(where: { $0.isSelected })?.id {
            selectedAudioTrackID = activeAudio
        } else if selectedAudioTrackID == nil {
            selectedAudioTrackID = audioOptions.first?.id
        }

        if let activeSubtitle = subtitleOptions.first(where: { $0.isSelected })?.id {
            selectedSubtitleTrackID = activeSubtitle
        }

        if !settingsAudioTracks.isEmpty || !settingsSubtitleTracks.isEmpty {
            return
        }

        let tracks = controller.trackList()
        let audio = tracks.filter { $0.type == .audio }
        let subtitles = tracks.filter { $0.type == .subtitle }

        audioTracks = audio
        subtitleTracks = subtitles
        settingsAudioTracks = audio.map(TVPlaybackSettingsTrack.init(track:))
        settingsSubtitleTracks = subtitles.map(TVPlaybackSettingsTrack.init(track:))

        if let activeAudio = audio.first(where: { $0.isSelected })?.id {
            selectedAudioTrackID = "mpv-audio-\(activeAudio)"
        } else if selectedAudioTrackID == nil {
            selectedAudioTrackID = audio.first.map { "mpv-audio-\($0.id)" }
        }

        if let activeSubtitle = subtitles.first(where: { $0.isSelected })?.id {
            selectedSubtitleTrackID = "mpv-sub-\(activeSubtitle)"
        } else if selectedSubtitleTrackID == nil {
            selectedSubtitleTrackID = nil
        }
    }

    private func selectAudioTrack(_ id: String?) {
        selectedAudioTrackID = id
        guard let controller = mpvController else { return }
        guard let id, let option = controller.audioOptions().first(where: { $0.id == id }) else { return }
        Task {
            await controller.selectAudioOption(option)
            refreshTracks()
        }
        showControls(temporarily: true)
    }

    private func selectSubtitleTrack(_ id: String?) {
        selectedSubtitleTrackID = id
        guard let controller = mpvController else { return }
        Task {
            if let id, let option = controller.subtitleOptions().first(where: { $0.id == id }) {
                await controller.selectSubtitleOption(option)
            } else {
                await controller.selectSubtitleOption(nil)
            }
            refreshTracks()
        }
        showControls(temporarily: true)
    }

    private func selectPlaybackRate(_ rate: Float) {
        playbackRate = rate
        mpvController?.setPlaybackRate(rate)
        showControls(temporarily: true)
    }

    private func selectPlaybackQuality(_ quality: PlaybackQuality) {
        selectedQuality = quality
        guard let controller = mpvController else { return }
        Task {
            await controller.changeQuality(to: quality)
            refreshTracks()
        }
        showControls(temporarily: true)
    }

    private func jump(by delta: Double) {
        guard effectiveDuration > 0 else { return }
        let target = min(max(timelinePosition + delta, 0), effectiveDuration)
        timelinePosition = target
        currentTime = target
        mpvController?.seek(to: target)
        showControls(temporarily: true)
    }

    private func handleScrubbing(editing: Bool) {
        isScrubbing = editing
        if editing {
            hideControlsWorkItem?.cancel()
        } else {
            guard effectiveDuration > 0 else { return }
            let target = min(max(timelinePosition, 0), effectiveDuration)
            timelinePosition = target
            currentTime = target
            mpvController?.seek(to: target)
            showControls(temporarily: true)
        }
    }

    private func showControls(temporarily: Bool) {
        controlsVisible = true

        hideControlsWorkItem?.cancel()
        hideControlsWorkItem = nil

        guard temporarily, isMPVActive, !isPaused, !isScrubbing else { return }

        let workItem = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.2)) {
                controlsVisible = false
            }
        }
        hideControlsWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + controlsHideDelay, execute: workItem)
    }

    private func closePlayer() {
        Task { await finishProgressAndScrobble(currentTime: currentTime, duration: effectiveDuration) }
        cleanup()
        dismiss()
    }

    private func cleanup() {
        hideControlsWorkItem?.cancel()
        hideControlsWorkItem = nil

        guard hasLoadedPlayback || avkitController != nil || mpvController != nil else { return }
        print("🧹 [PlayerView] Cleaning up player")

        Task {
            await scrobbler.stopScrobble(progress: currentProgressPercent)
            await progressReporter.flush(
                ratingKey: currentRatingKey,
                currentTime: currentTime,
                duration: effectiveDuration,
                state: "stopped"
            )
        }

        avkitController?.shutdown()
        avkitController = nil

        mpvController?.shutdown()
        mpvController = nil

        audioTracks = []
        subtitleTracks = []
        settingsAudioTracks = []
        settingsSubtitleTracks = []
        selectedAudioTrackID = nil
        selectedSubtitleTrackID = nil
        availableQualities = PlaybackQuality.allCases
        selectedQuality = .original
        activeSettingsSheet = nil
        currentRatingKey = nil

        hasLoadedPlayback = false
    }

    private var currentProgressPercent: Double {
        guard effectiveDuration > 0 else { return 0 }
        return min(max((currentTime / effectiveDuration) * 100, 0), 100)
    }

    private func extractRatingKey(from id: String) -> String? {
        if id.hasPrefix("plex:") {
            let key = String(id.dropFirst("plex:".count))
            return key.isEmpty ? nil : key
        }
        return id.allSatisfy(\.isNumber) ? id : nil
    }

    private func startScrobblingIfNeeded() async {
        guard profileSettings.traktScrobbleEnabled else { return }
        await scrobbler.startScrobble(for: currentItem, initialProgress: currentProgressPercent)
    }

    private func finishProgressAndScrobble(currentTime: Double, duration: Double) async {
        let progress = duration > 0 ? min(max((currentTime / duration) * 100, 0), 100) : 0
        await scrobbler.stopScrobble(progress: progress)
        await progressReporter.flush(
            ratingKey: currentRatingKey,
            currentTime: currentTime,
            duration: duration,
            state: "stopped"
        )
    }

    private func reportPlaybackProgressIfNeeded(state: String) {
        Task {
            await progressReporter.reportIfNeeded(
                ratingKey: currentRatingKey,
                currentTime: currentTime,
                duration: effectiveDuration,
                state: state
            )
        }
    }

    private func handlePlaybackEnded() async {
        await finishProgressAndScrobble(currentTime: currentTime, duration: effectiveDuration)
        if profileSettings.traktAutoSyncWatched {
            await traktSync.markWatchedIfNeeded(item: currentItem)
        }
        guard profileSettings.autoPlayNext else { return }
        guard let next = await resolveNextEpisode(from: currentItem) else { return }
        activeItem = next
        currentRatingKey = extractRatingKey(from: next.id)
        timelinePosition = 0
        currentTime = 0
        duration = 0
        mpvController?.loadFile(next.id)
    }

    private func resolveNextEpisode(from item: MediaItem) async -> MediaItem? {
        guard item.type == "episode" || item.type == "show" else { return nil }
        guard let ratingKey = extractRatingKey(from: item.id) else { return nil }

        struct Meta: Decodable {
            let type: String?
            let parentRatingKey: String?
            let grandparentRatingKey: String?
            let parentIndex: Int?
            let index: Int?
            let grandparentTitle: String?
        }
        struct Children: Decodable {
            let Metadata: [Child]?
            let MediaContainer: Container?
            struct Container: Decodable { let Metadata: [Child]? }
            struct Child: Decodable {
                let ratingKey: String?
                let title: String?
                let type: String?
                let thumb: String?
                let art: String?
                let grandparentTitle: String?
                let grandparentThumb: String?
                let grandparentArt: String?
                let parentIndex: Int?
                let index: Int?
                let parentRatingKey: String?
                let parentTitle: String?
                let year: Int?
                let duration: Int?
                let summary: String?
            }
        }

        guard let currentMeta: Meta = try? await APIClient.shared.get("/api/plex/metadata/\(ratingKey)") else { return nil }
        guard currentMeta.type == "episode",
              let seasonKey = currentMeta.parentRatingKey,
              let showKey = currentMeta.grandparentRatingKey else { return nil }

        func childrenItems(from children: Children) -> [Children.Child] {
            children.Metadata ?? children.MediaContainer?.Metadata ?? []
        }

        if let seasonChildren: Children = try? await APIClient.shared.get("/api/plex/dir/library/metadata/\(seasonKey)/children") {
            let episodes = childrenItems(from: seasonChildren)
                .filter { ($0.type ?? "").lowercased() == "episode" }
                .sorted { ($0.index ?? 0) < ($1.index ?? 0) }
            if let currentIndex = currentMeta.index,
               let nextEpisode = episodes.first(where: { ($0.index ?? -1) > currentIndex }),
               let nextItem = mediaItemFromPlexChild(nextEpisode) {
                return nextItem
            }
        }

        guard let showChildren: Children = try? await APIClient.shared.get("/api/plex/dir/library/metadata/\(showKey)/children") else { return nil }
        let seasons = childrenItems(from: showChildren)
            .filter { ($0.type ?? "").lowercased() == "season" }
            .sorted { ($0.index ?? 0) < ($1.index ?? 0) }
        guard let currentSeasonIndex = currentMeta.parentIndex else { return nil }
        guard let nextSeason = seasons.first(where: { ($0.index ?? -1) > currentSeasonIndex }),
              let nextSeasonKey = nextSeason.ratingKey else { return nil }

        guard let nextSeasonChildren: Children = try? await APIClient.shared.get("/api/plex/dir/library/metadata/\(nextSeasonKey)/children") else { return nil }
        let nextEpisodes = childrenItems(from: nextSeasonChildren)
            .filter { ($0.type ?? "").lowercased() == "episode" }
            .sorted { ($0.index ?? 0) < ($1.index ?? 0) }
        guard let firstEpisode = nextEpisodes.first else { return nil }
        return mediaItemFromPlexChild(firstEpisode)
    }

    private func mediaItemFromPlexChild(_ child: Any) -> MediaItem? {
        let mirror = Mirror(reflecting: child)
        func value<T>(_ key: String) -> T? {
            mirror.children.first(where: { $0.label == key })?.value as? T
        }

        guard let ratingKey: String = value("ratingKey") else { return nil }
        let title: String = value("title") ?? "Episode"
        let episodeType: String = value("type") ?? "episode"
        let thumb: String? = value("thumb")
        let art: String? = value("art")
        let summary: String? = value("summary")
        let grandparentTitle: String? = value("grandparentTitle")
        let parentRatingKey: String? = value("parentRatingKey")
        let parentTitle: String? = value("parentTitle")
        let parentIndex: Int? = value("parentIndex")
        let index: Int? = value("index")
        let year: Int? = value("year")
        let durationMs: Int? = value("duration")

        return MediaItem(
            id: ratingKey.hasPrefix("plex:") ? ratingKey : "plex:\(ratingKey)",
            title: title,
            type: episodeType.isEmpty ? "episode" : episodeType,
            thumb: thumb,
            art: art,
            year: year,
            rating: nil,
            duration: durationMs,
            viewOffset: nil,
            summary: summary,
            grandparentTitle: grandparentTitle,
            grandparentThumb: nil,
            grandparentArt: nil,
            parentIndex: parentIndex,
            index: index,
            parentRatingKey: parentRatingKey,
            parentTitle: parentTitle
        )
    }
}

private struct TVPlayerControlsOverlay: View {
    let title: String
    let subtitle: String?
    let isPaused: Bool
    let supportsHDR: Bool
    @Binding var position: Double
    let duration: Double?
    let bufferedAhead: Double
    let bufferBasePosition: Double
    let isScrubbing: Bool
    let seekBackwardSeconds: Int
    let seekForwardSeconds: Int
    let onSeekBackward: () -> Void
    let onSeekForward: () -> Void
    let onShowSpeedSettings: () -> Void
    let onShowQualitySettings: () -> Void
    let onShowAudioSettings: () -> Void
    let onShowSubtitleSettings: () -> Void
    let onPlayPause: () -> Void
    let onScrubbingChanged: (Bool) -> Void
    let onUserInteraction: () -> Void

    @FocusState private var focusedControl: TVPlayerFocusTarget?

    private var playbackBadges: [TVPlayerControlBadge] {
        var badges: [TVPlayerControlBadge] = []
        if supportsHDR {
            badges.append(
                TVPlayerControlBadge(
                    id: "hdr",
                    title: "HDR",
                    systemImage: "sparkles"
                )
            )
        }
        return badges
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(2)
                    }
                }

                Spacer()
            }

            Spacer()

            if !isScrubbing, !playbackBadges.isEmpty {
                HStack {
                    Spacer()
                    HStack(spacing: 8) {
                        ForEach(playbackBadges) { badge in
                            TVPlayerBadge(badge.title, systemImage: badge.systemImage)
                        }
                    }
                }
                .padding(.horizontal, 24)
            }

            TVPlayerTimelineView(
                position: $position,
                duration: duration,
                bufferedAhead: bufferedAhead,
                playbackPosition: bufferBasePosition,
                onEditingChanged: onScrubbingChanged
            )

            ZStack {
                HStack(spacing: 16) {
                    TVPlayerSettingButton(
                        systemName: "speedometer",
                        action: onShowSpeedSettings
                    )

                    TVPlayerSettingButton(
                        systemName: "slider.horizontal.3",
                        action: onShowQualitySettings
                    )

                    TVPlayerSettingButton(
                        systemName: "speaker.wave.2",
                        action: onShowAudioSettings
                    )

                    TVPlayerSettingButton(
                        systemName: "captions.bubble",
                        action: onShowSubtitleSettings
                    )

                    Spacer()
                }

                HStack(spacing: 30) {
                    TVPlayerIconButton(
                        systemName: iconName(prefix: "gobackward", seconds: seekBackwardSeconds),
                        action: onSeekBackward
                    )

                    TVPlayPauseButton(isPaused: isPaused, action: onPlayPause)
                        .focused($focusedControl, equals: .playPause)

                    TVPlayerIconButton(
                        systemName: iconName(prefix: "goforward", seconds: seekForwardSeconds),
                        action: onSeekForward
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 28)
        .background {
            TVPlayerControlsBackground()
        }
        .onAppear {
            focusedControl = .playPause
        }
        .onMoveCommand { _ in
            onUserInteraction()
        }
    }

    private func iconName(prefix: String, seconds: Int) -> String {
        let supported = [5, 10, 15, 30, 45, 60]
        guard supported.contains(seconds) else { return prefix }
        return "\(prefix).\(seconds)"
    }
}

private struct TVPlayerTimelineView: View {
    @Binding var position: Double
    let duration: Double?
    let bufferedAhead: Double
    let playbackPosition: Double
    let onEditingChanged: (Bool) -> Void

    private var sliderUpperBound: Double {
        max(duration ?? 0, position, playbackPosition, 1)
    }

    private var bufferedEnd: Double {
        let bufferedPosition = playbackPosition + bufferedAhead
        guard let duration else { return bufferedPosition }
        return min(bufferedPosition, duration)
    }

    private var bufferedProgress: Double {
        guard sliderUpperBound > 0 else { return 0 }
        return min(max(bufferedEnd / sliderUpperBound, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TVPlayerTimelineScrubber(
                position: $position,
                upperBound: sliderUpperBound,
                duration: duration,
                bufferedProgress: bufferedProgress,
                onEditingChanged: onEditingChanged
            )

            HStack {
                Text(formatTime(position))
                Spacer()
                Text(remainingText)
            }
            .font(.footnote.monospacedDigit())
            .foregroundStyle(.white.opacity(0.9))
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }

    private var remainingText: String {
        guard let duration else { return "--:--" }
        let remaining = max(duration - position, 0)
        return "-\(formatTime(remaining))"
    }

    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = max(Int(seconds.rounded()), 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }
}

private struct TVPlayerTimelineScrubber: View {
    @Binding var position: Double
    let upperBound: Double
    let duration: Double?
    let bufferedProgress: Double
    let onEditingChanged: (Bool) -> Void

    @State private var consecutiveMoves = 0
    @State private var isScrubbing = false
    @State private var commitWorkItem: DispatchWorkItem?
    @FocusState private var isFocused: Bool

    private let scrubCommitDelay: TimeInterval = 0.4

    private var playbackProgress: Double {
        guard upperBound > 0 else { return 0 }
        return min(max(position / upperBound, 0), 1)
    }

    private var scrubStep: Double {
        guard let duration else { return 10 }
        return min(max(duration / 300, 5), 60)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let progressWidth = width * playbackProgress
            let bufferedWidth = width * min(max(bufferedProgress, 0), 1)
            let thumbX = min(max(progressWidth, 0), width)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.35))
                    .frame(height: 8)

                Capsule()
                    .fill(Color.white.opacity(0.65))
                    .frame(width: bufferedWidth)
                    .frame(height: 8)

                Capsule()
                    .fill(Color.white)
                    .frame(width: progressWidth)
                    .frame(height: 8)

                Circle()
                    .fill(Color.white)
                    .frame(width: 28, height: 28)
                    .scaleEffect(isFocused ? 1.0 : 0.75)
                    .shadow(color: .black.opacity(0.45), radius: 10, x: 0, y: 6)
                    .offset(x: max(0, thumbX - 16))
                    .animation(.easeInOut(duration: 0.15), value: isFocused)
            }
            .animation(.easeInOut(duration: 0.15), value: isFocused)
        }
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, maxHeight: 32)
        .focusable()
        .focused($isFocused)
        .onMoveCommand { direction in
            guard isFocused else { return }

            startScrubbingIfNeeded()
            consecutiveMoves += 1
            let multiplier = min(Double(consecutiveMoves), 5)
            let delta = scrubStep * multiplier

            switch direction {
            case .left:
                position = max(0, position - delta)
            case .right:
                position = min(upperBound, position + delta)
            default:
                break
            }

            scheduleCommit()
        }
        .onChange(of: isFocused) { focused in
            if !focused {
                finishScrubbingIfNeeded()
            }
        }
        .onDisappear {
            commitWorkItem?.cancel()
        }
        .accessibilityHidden(true)
    }

    private func startScrubbingIfNeeded() {
        guard !isScrubbing else { return }
        isScrubbing = true
        onEditingChanged(true)
    }

    private func scheduleCommit() {
        commitWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            isScrubbing = false
            consecutiveMoves = 0
            onEditingChanged(false)
        }
        commitWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + scrubCommitDelay, execute: workItem)
    }

    private func finishScrubbingIfNeeded() {
        consecutiveMoves = 0
        commitWorkItem?.cancel()
        commitWorkItem = nil
        guard isScrubbing else { return }
        isScrubbing = false
        onEditingChanged(false)
    }
}

private struct TVPlayerIconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.foreground)
                .frame(width: 88, height: 88)
        }
    }
}

private struct TVPlayPauseButton: View {
    let isPaused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                .font(.largeTitle.weight(.black))
                .foregroundStyle(.foreground)
                .frame(width: 108, height: 108)
        }
    }
}

private struct TVPlayerSettingButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .foregroundStyle(.foreground)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
    }
}

private struct TVPlayerBadge: View {
    let title: String
    let systemImage: String?

    init(_ title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
                .font(.footnote.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: [
                    .white.opacity(0.24),
                    .white.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: Capsule()
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
        )
    }
}

private enum TVPlayerSettingsSheet: String, Identifiable {
    case audio
    case subtitle
    case speed
    case quality

    var id: String { rawValue }
}

private struct TVPlaybackSettingsTrack: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?

    init(track: PlayerTrack) {
        self.id = track.type == .audio ? "mpv-audio-\(track.id)" : "mpv-sub-\(track.id)"
        self.title = track.displayName

        var tokens: [String] = []
        if let language = track.language, !language.isEmpty {
            tokens.append(language.uppercased())
        }
        if let codec = track.codec, !codec.isEmpty {
            tokens.append(codec.uppercased())
        }
        if track.isDefault {
            tokens.append("DEFAULT")
        }
        self.subtitle = tokens.isEmpty ? nil : tokens.joined(separator: " • ")
    }

    init(audioOption: PlayerAudioOption) {
        id = audioOption.id
        title = audioOption.title
        subtitle = audioOption.subtitle
    }

    init(subtitleOption: PlayerSubtitleOption) {
        id = subtitleOption.id
        title = subtitleOption.title
        subtitle = subtitleOption.subtitle
    }
}

private struct TVPlayerTrackSelectionView: View {
    let title: String
    let tracks: [TVPlaybackSettingsTrack]
    let selectedTrackID: String?
    let showOffOption: Bool
    let onSelect: (String?) -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if showOffOption {
                    TVTrackSelectionRow(
                        title: "Off",
                        subtitle: "Disable subtitles",
                        isSelected: selectedTrackID == nil
                    ) {
                        onSelect(nil)
                    }
                    .padding(.horizontal, 24)
                }

                if tracks.isEmpty, !showOffOption {
                    Text("No audio tracks available")
                        .foregroundStyle(.secondary)
                } else {
                    VStack {
                        ForEach(tracks) { track in
                            TVTrackSelectionRow(
                                title: track.title,
                                subtitle: track.subtitle,
                                isSelected: selectedTrackID == track.id
                            ) {
                                onSelect(track.id)
                            }
                            .padding(.horizontal, 24)
                        }
                    }
                }
            }
            .listStyle(.automatic)
            .navigationTitle(title)
            .onExitCommand(perform: onClose)
        }
    }
}

private struct TVPlayerPlaybackSettingsView: View {
    let selectedRate: Float
    let onSelect: (Float) -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(TVPlaybackSpeedOption.allCases) { option in
                    TVTrackSelectionRow(
                        title: option.title,
                        subtitle: nil,
                        isSelected: abs(selectedRate - option.rate) < 0.001
                    ) {
                        onSelect(option.rate)
                    }
                    .padding(.horizontal, 24)
                }
            }
            .listStyle(.automatic)
            .navigationTitle("Playback Speed")
            .onExitCommand(perform: onClose)
        }
    }
}

private struct TVPlayerQualitySelectionView: View {
    let selectedQuality: PlaybackQuality
    let availableQualities: [PlaybackQuality]
    let onSelectQuality: (PlaybackQuality) -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(availableQualities) { quality in
                    TVTrackSelectionRow(
                        title: quality.rawValue,
                        subtitle: quality == .original ? "Direct Play" : "Transcode",
                        isSelected: selectedQuality == quality
                    ) {
                        onSelectQuality(quality)
                    }
                    .padding(.horizontal, 24)
                }
            }
            .listStyle(.automatic)
            .navigationTitle("Playback Quality")
            .onExitCommand(perform: onClose)
        }
    }
}

private struct TVTrackSelectionRow: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private enum TVPlaybackSpeedOption: CaseIterable, Identifiable {
    case quarter
    case half
    case threeQuarter
    case normal
    case oneQuarter
    case oneHalf
    case twoX

    var id: String { title }

    var rate: Float {
        switch self {
        case .quarter:
            return 0.25
        case .half:
            return 0.5
        case .threeQuarter:
            return 0.75
        case .normal:
            return 1.0
        case .oneQuarter:
            return 1.25
        case .oneHalf:
            return 1.5
        case .twoX:
            return 2.0
        }
    }

    var title: String {
        switch self {
        case .quarter:
            return "0.25x"
        case .half:
            return "0.5x"
        case .threeQuarter:
            return "0.75x"
        case .normal:
            return "Normal"
        case .oneQuarter:
            return "1.25x"
        case .oneHalf:
            return "1.5x"
        case .twoX:
            return "2x"
        }
    }
}

private enum TVPlayerFocusTarget: Hashable {
    case playPause
}

private struct TVPlayerControlBadge: Identifiable {
    let id: String
    let title: String
    let systemImage: String?
}

private struct TVPlayerControlsBackground: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.black.opacity(0.55), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 200)

            Spacer()

            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 280)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private enum TVResolvedScrobbleMedia {
    case movie(TraktScrobbleMovie)
    case episode(show: TraktScrobbleShow, episode: TraktScrobbleEpisode)
}

private struct TVResolvedPlaybackIdentity {
    let ids: TraktScrobbleIds
    let mediaType: String
    let season: Int?
    let episode: Int?
}

@MainActor
private final class TVTraktIdentityResolver {
    static let shared = TVTraktIdentityResolver()
    private let api = APIClient.shared

    private init() {}

    func resolve(for item: MediaItem) async -> TVResolvedPlaybackIdentity? {
        if let tmdb = parseTMDBId(from: item.id) {
            let ids = TraktScrobbleIds(imdb: nil, tmdb: tmdb, tvdb: nil)
            let mediaType = item.type.lowercased() == "movie" ? "movie" : "show"
            return TVResolvedPlaybackIdentity(
                ids: ids,
                mediaType: mediaType,
                season: item.parentIndex,
                episode: item.index
            )
        }

        guard let ratingKey = parsePlexRatingKey(from: item.id) else { return nil }
        do {
            let full: MediaItemFull = try await api.get("/api/plex/metadata/\(ratingKey)")

            var tmdbId: Int?
            var imdbId: String?
            var tvdbId: Int?

            for guid in full.Guid ?? [] {
                if guid.id.hasPrefix("tmdb://") {
                    tmdbId = Int(guid.id.replacingOccurrences(of: "tmdb://", with: ""))
                } else if guid.id.hasPrefix("imdb://") {
                    imdbId = guid.id.replacingOccurrences(of: "imdb://", with: "")
                } else if guid.id.hasPrefix("tvdb://") {
                    tvdbId = Int(guid.id.replacingOccurrences(of: "tvdb://", with: ""))
                }
            }

            if tmdbId == nil || imdbId == nil || tvdbId == nil {
                if let mainGuid = full.guid {
                    if tmdbId == nil, mainGuid.hasPrefix("com.plexapp.agents.themoviedb://") {
                        let value = mainGuid
                            .replacingOccurrences(of: "com.plexapp.agents.themoviedb://", with: "")
                            .components(separatedBy: "?").first
                        tmdbId = value.flatMap(Int.init)
                    }
                    if imdbId == nil, mainGuid.hasPrefix("com.plexapp.agents.imdb://") {
                        imdbId = mainGuid
                            .replacingOccurrences(of: "com.plexapp.agents.imdb://", with: "")
                            .components(separatedBy: "?").first
                    }
                    if tvdbId == nil, mainGuid.hasPrefix("com.plexapp.agents.thetvdb://") {
                        let value = mainGuid
                            .replacingOccurrences(of: "com.plexapp.agents.thetvdb://", with: "")
                            .components(separatedBy: "/").first
                        tvdbId = value.flatMap(Int.init)
                    }
                }
            }

            guard tmdbId != nil || imdbId != nil || tvdbId != nil else { return nil }
            let ids = TraktScrobbleIds(imdb: imdbId, tmdb: tmdbId, tvdb: tvdbId)
            let mediaType = full.type.lowercased() == "movie" ? "movie" : "show"
            return TVResolvedPlaybackIdentity(
                ids: ids,
                mediaType: mediaType,
                season: full.parentIndex ?? item.parentIndex,
                episode: full.index ?? item.index
            )
        } catch {
            return nil
        }
    }

    private func parsePlexRatingKey(from id: String) -> String? {
        if id.hasPrefix("plex:") {
            let value = String(id.dropFirst("plex:".count))
            return value.isEmpty ? nil : value
        }
        return id.allSatisfy(\.isNumber) ? id : nil
    }

    private func parseTMDBId(from id: String) -> Int? {
        guard id.hasPrefix("tmdb:") else { return nil }
        return Int(id.split(separator: ":").last ?? "")
    }
}

@MainActor
final class TVTraktScrobbler: ObservableObject {
    static let shared = TVTraktScrobbler()

    @Published private(set) var isScrobbling = false
    @Published private(set) var currentTitle: String?

    private var currentMedia: TVResolvedScrobbleMedia?
    private let identityResolver = TVTraktIdentityResolver.shared

    private init() {}

    func startScrobble(for item: MediaItem, initialProgress: Double = 0) async {
        guard FlixorCore.shared.isTraktAuthenticated else { return }
        guard UserDefaults.standard.traktScrobbleEnabled else { return }

        if currentMedia != nil {
            await stopScrobble(progress: initialProgress)
        }

        guard let resolved = await identityResolver.resolve(for: item) else { return }
        let media = buildScrobbleMedia(item: item, resolved: resolved)

        do {
            switch media {
            case .movie(let movie):
                _ = try await FlixorCore.shared.trakt.scrobbleStart(movie: movie, progress: initialProgress)
                currentTitle = movie.title ?? item.title
            case .episode(let show, let episode):
                _ = try await FlixorCore.shared.trakt.scrobbleStart(show: show, episode: episode, progress: initialProgress)
                currentTitle = "\(show.title ?? item.title) S\(episode.season)E\(episode.number)"
            }
            currentMedia = media
            isScrobbling = true
        } catch {
            #if DEBUG
            print("⚠️ [TVTraktScrobbler] start failed: \(error)")
            #endif
        }
    }

    func pauseScrobble(progress: Double) async {
        guard isScrobbling, let media = currentMedia else { return }
        do {
            switch media {
            case .movie(let movie):
                _ = try await FlixorCore.shared.trakt.scrobblePause(movie: movie, progress: progress)
            case .episode(let show, let episode):
                _ = try await FlixorCore.shared.trakt.scrobblePause(show: show, episode: episode, progress: progress)
            }
        } catch {
            #if DEBUG
            print("⚠️ [TVTraktScrobbler] pause failed: \(error)")
            #endif
        }
    }

    func resumeScrobble(progress: Double) async {
        guard let media = currentMedia else { return }
        do {
            switch media {
            case .movie(let movie):
                _ = try await FlixorCore.shared.trakt.scrobbleStart(movie: movie, progress: progress)
            case .episode(let show, let episode):
                _ = try await FlixorCore.shared.trakt.scrobbleStart(show: show, episode: episode, progress: progress)
            }
            isScrobbling = true
        } catch {
            #if DEBUG
            print("⚠️ [TVTraktScrobbler] resume failed: \(error)")
            #endif
        }
    }

    func stopScrobble(progress: Double? = nil) async {
        guard let media = currentMedia else { return }
        let finalProgress = progress ?? 0
        do {
            switch media {
            case .movie(let movie):
                _ = try await FlixorCore.shared.trakt.scrobbleStop(movie: movie, progress: finalProgress)
            case .episode(let show, let episode):
                _ = try await FlixorCore.shared.trakt.scrobbleStop(show: show, episode: episode, progress: finalProgress)
            }
        } catch {
            #if DEBUG
            print("⚠️ [TVTraktScrobbler] stop failed: \(error)")
            #endif
        }
        currentMedia = nil
        currentTitle = nil
        isScrobbling = false
    }

    private func buildScrobbleMedia(item: MediaItem, resolved: TVResolvedPlaybackIdentity) -> TVResolvedScrobbleMedia {
        if resolved.mediaType == "movie" {
            return .movie(
                TraktScrobbleMovie(
                    title: item.title,
                    year: item.year,
                    ids: resolved.ids
                )
            )
        }

        let show = TraktScrobbleShow(
            title: item.grandparentTitle ?? item.title,
            year: item.year,
            ids: resolved.ids
        )
        let episode = TraktScrobbleEpisode(
            season: resolved.season ?? item.parentIndex ?? 1,
            number: resolved.episode ?? item.index ?? 1,
            title: item.title
        )
        return .episode(show: show, episode: episode)
    }
}

@MainActor
final class TVTraktSyncCoordinator {
    static let shared = TVTraktSyncCoordinator()
    private let identityResolver = TVTraktIdentityResolver.shared

    private init() {}

    func markWatchedIfNeeded(item: MediaItem) async {
        guard UserDefaults.standard.traktAutoSyncWatched else { return }
        guard FlixorCore.shared.isTraktAuthenticated else { return }

        guard let resolved = await identityResolver.resolve(for: item) else { return }
        do {
            if resolved.mediaType == "movie" {
                try await FlixorCore.shared.trakt.markMovieWatched(
                    tmdbId: resolved.ids.tmdb,
                    imdbId: resolved.ids.imdb
                )
            } else {
                try await FlixorCore.shared.trakt.markEpisodeWatched(
                    showTmdbId: resolved.ids.tmdb,
                    showImdbId: resolved.ids.imdb,
                    season: resolved.season ?? item.parentIndex ?? 1,
                    episode: resolved.episode ?? item.index ?? 1
                )
            }
        } catch {
            #if DEBUG
            print("⚠️ [TVTraktSync] mark watched failed: \(error)")
            #endif
        }
    }

    @discardableResult
    func addToWatchlistIfEnabled(tmdbId: Int, mediaType: String) async -> Bool {
        guard UserDefaults.standard.traktSyncWatchlist else { return false }
        guard FlixorCore.shared.isTraktAuthenticated else { return false }
        do {
            try await FlixorCore.shared.trakt.addToWatchlist(tmdbId: tmdbId, type: mediaType)
            return true
        } catch {
            #if DEBUG
            print("⚠️ [TVTraktSync] add watchlist failed: \(error)")
            #endif
            return false
        }
    }

    @discardableResult
    func removeFromWatchlistIfEnabled(tmdbId: Int, mediaType: String) async -> Bool {
        guard UserDefaults.standard.traktSyncWatchlist else { return false }
        guard FlixorCore.shared.isTraktAuthenticated else { return false }
        do {
            if mediaType == "show" || mediaType == "tv" {
                try await FlixorCore.shared.trakt.removeShowFromWatchlist(tmdbId: tmdbId)
            } else {
                try await FlixorCore.shared.trakt.removeMovieFromWatchlist(tmdbId: tmdbId)
            }
            return true
        } catch {
            #if DEBUG
            print("⚠️ [TVTraktSync] remove watchlist failed: \(error)")
            #endif
            return false
        }
    }

    @discardableResult
    func rateIfEnabled(mediaType: String, tmdbId: Int?, imdbId: String?, rating: Int) async -> Bool {
        guard UserDefaults.standard.traktSyncRatings else { return false }
        guard FlixorCore.shared.isTraktAuthenticated else { return false }
        do {
            if mediaType == "tv" || mediaType == "show" {
                try await FlixorCore.shared.trakt.rateShow(tmdbId: tmdbId, imdbId: imdbId, rating: rating)
            } else {
                try await FlixorCore.shared.trakt.rateMovie(tmdbId: tmdbId, imdbId: imdbId, rating: rating)
            }
            return true
        } catch {
            #if DEBUG
            print("⚠️ [TVTraktSync] rating sync failed: \(error)")
            #endif
            return false
        }
    }
}

actor TVPlaybackProgressReporter {
    private var lastSentAt: Date?
    private var lastPayloadHash: String?
    private let minimumInterval: TimeInterval = 10

    func reportIfNeeded(
        ratingKey: String?,
        currentTime: Double,
        duration: Double,
        state: String
    ) async {
        guard let ratingKey, !ratingKey.isEmpty else { return }
        guard duration > 0 else { return }

        let now = Date()
        let hash = "\(ratingKey)|\(Int(currentTime))|\(Int(duration))|\(state)"
        let elapsed = now.timeIntervalSince(lastSentAt ?? .distantPast)
        if elapsed < minimumInterval, hash == lastPayloadHash {
            return
        }
        if elapsed < minimumInterval, state == "playing" {
            return
        }

        await send(
            ratingKey: ratingKey,
            currentTime: currentTime,
            duration: duration,
            state: state
        )
    }

    func flush(
        ratingKey: String?,
        currentTime: Double,
        duration: Double,
        state: String
    ) async {
        guard let ratingKey, !ratingKey.isEmpty else { return }
        await send(
            ratingKey: ratingKey,
            currentTime: currentTime,
            duration: duration,
            state: state
        )
    }

    private func send(
        ratingKey: String,
        currentTime: Double,
        duration: Double,
        state: String
    ) async {
        let payload = TVPlexProgressPayload(
            ratingKey: ratingKey,
            time: Int(max(currentTime, 0) * 1000),
            duration: Int(max(duration, 0) * 1000),
            state: state
        )
        do {
            let _: EmptyResponse = try await APIClient.shared.post("/api/plex/progress", body: payload)
            lastSentAt = Date()
            lastPayloadHash = "\(ratingKey)|\(payload.time)|\(payload.duration)|\(state)"
        } catch {
            #if DEBUG
            print("⚠️ [TVProgress] report failed: \(error)")
            #endif
        }
    }
}

private struct TVPlexProgressPayload: Codable {
    let ratingKey: String
    let time: Int
    let duration: Int
    let state: String
}
