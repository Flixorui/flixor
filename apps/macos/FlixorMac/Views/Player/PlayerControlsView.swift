//
//  PlayerControlsView.swift
//  FlixorMac
//
//  Player controls overlay: top bar, quality menu, seek bar, transport, volume and panel buttons
//

import SwiftUI
import AppKit

// MARK: - Player Controls

struct PlayerControlsView: View {
    @ObservedObject var viewModel: PlayerViewModel
    @Binding var isFullScreen: Bool
    let isPiPActive: Bool
    let mpvPiPViewController: NSViewController?
    let onClose: () -> Void
    let onToggleFullScreen: () -> Void
    let onToggleMPVPiP: () -> Void
    /// Reports whether a panel (episodes, speed, tracks, chapters, aspect) is open.
    let onPanelOpenChanged: (Bool) -> Void
    /// Each change closes whichever panel is open.
    let closePanelsRequest: Int

    @Environment(\.flixorTheme) private var theme
    @Environment(\.windowMetrics) private var metrics

    @State private var showEpisodesList = false
    @State private var showPlaybackSpeed = false
    @State private var showVolumeSlider = false
    @State private var showAudioSubtitles = false
    @State private var showChaptersPanel = false
    @State private var showAspectPanel = false
    @State private var showSourcesPanel = false
    @State private var settingsMenuAnchor = MenuAnchor()
    @State private var isSettingsHovered = false

    /// Seek-bar hover preview. Held, not observed: mouse moves over the seek bar
    /// redraw only the preview, not these controls.
    @State private var seekHover = SeekBarHoverModel()

    // Hover states for all control buttons
    @State private var isBackHovered = false
    @State private var isPlayPauseHovered = false
    @State private var isSkipBackHovered = false
    @State private var isSkipForwardHovered = false
    @State private var isVolumeButtonHovered = false
    @State private var isNextEpisodeHovered = false
    @State private var showNextEpisodeHover = false
    @State private var isEpisodeListHovered = false
    @State private var isSpeedHovered = false
    @State private var isAudioSubtitlesHovered = false
    @State private var isPiPHovered = false
    @State private var isFullscreenHovered = false
    @State private var isStatsHovered = false
    @State private var isChaptersHovered = false
    @State private var isAspectHovered = false

    var body: some View {
        VStack {
            // Top Bar
            HStack {
                Button(action: onClose) {
                    BackArrowIcon()
                        .frame(width: 32, height: 32)
                        .foregroundStyle(.white)
                        .scaleEffect(isBackHovered ? 1.1 : 1.0)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(DS.Motion.standard) {
                        isBackHovered = hovering
                    }
                }

                Spacer()

                playerTitle

                Spacer()

                // Balances the back button so the title stays centred.
                Color.clear.frame(width: 32, height: 32)
            }
            .padding(.horizontal, DS.Space.s20)
            .padding(.top, DS.Space.s20)

            Spacer()

            // Bottom Controls
            VStack(spacing: DS.Space.s12) {
                // Timeline
                PlayerSeekBar(
                    clock: viewModel.playbackClock,
                    hover: seekHover,
                    duration: viewModel.duration,
                    marks: seekBarMarks,
                    accent: theme.accent,
                    segmentColor: theme.warning.opacity(DS.Opacity.strong),
                    onSeek: { viewModel.seek(to: $0) },
                    requestThumbnail: { requestThumbnail(at: $0) }
                )
                .padding(.horizontal, DS.Space.s20)

                // Play/Pause & Volume
                HStack(spacing: metrics.sizeClass == .compact ? DS.Space.s12 : DS.Space.s20) {
                    // Play/Pause (first)
                    Button(action: { viewModel.togglePlayPause() }) {
                        if viewModel.isPlaying {
                            PauseIcon()
                                .frame(width: 40, height: 40)
                                .foregroundStyle(.white)
                        } else {
                            PlayIcon()
                                .frame(width: 40, height: 40)
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(isPlayPauseHovered ? 1.1 : 1.0)
                    .onHover { hovering in
                        withAnimation(DS.Motion.standard) {
                            isPlayPauseHovered = hovering
                        }
                    }

                    // Skip back
                    Button(action: { viewModel.skip(seconds: -10) }) {
                        Replay10Icon()
                            .frame(width: 32, height: 32)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(isSkipBackHovered ? 1.1 : 1.0)
                    .onHover { hovering in
                        withAnimation(DS.Motion.standard) {
                            isSkipBackHovered = hovering
                        }
                    }

                    // Skip forward
                    Button(action: { viewModel.skip(seconds: 10) }) {
                        Forward10Icon()
                            .frame(width: 32, height: 32)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(isSkipForwardHovered ? 1.1 : 1.0)
                    .onHover { hovering in
                        withAnimation(DS.Motion.standard) {
                            isSkipForwardHovered = hovering
                        }
                    }

                    // Volume control
                    HStack(spacing: 0) {
                        Button(action: {
                            withAnimation(DS.Motion.standard) {
                                showVolumeSlider.toggle()
                            }
                        }) {
                            VolumeIcon(volume: viewModel.volume, isMuted: viewModel.isMuted)
                                .frame(width: 32, height: 32)
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .scaleEffect(isVolumeButtonHovered ? 1.1 : 1.0)
                        .onHover { hovering in
                            withAnimation(DS.Motion.standard) {
                                isVolumeButtonHovered = hovering
                            }
                        }

                        if showVolumeSlider {
                            VolumeSliderPopover(
                                volume: Binding(
                                    get: { viewModel.volume },
                                    set: { viewModel.setVolume($0) }
                                ),
                                isMuted: viewModel.isMuted
                            )
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .leading)),
                                removal: .opacity
                            ))
                        }
                    }

                    Spacer()

                    // Episode controls (next episode & episodes list) - only for TV shows
                    if viewModel.item.type == "episode" {
                        // Next Episode button
                        if let nextEp = viewModel.nextEpisode {
                            Button(action: {
                                viewModel.playNext()
                            }) {
                                NextEpisodeIcon()
                                    .frame(width: 32, height: 32)
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                            .scaleEffect(isNextEpisodeHovered ? 1.1 : 1.0)
                            .onHover { hovering in
                                withAnimation(DS.Motion.standard) {
                                    isNextEpisodeHovered = hovering
                                    showNextEpisodeHover = hovering
                                }
                            }
                            .help("Next Episode: \(nextEp.title)")
                        }
                        // Episodes list button
                        Button(action: {
                            togglePanel(showEpisodesList) {
                                showEpisodesList = true
                                viewModel.prepareEpisodeBrowser()
                            }
                        }) {
                            EpisodeListIcon()
                                .frame(width: 32, height: 32)
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .scaleEffect(isEpisodeListHovered ? 1.1 : 1.0)
                        .onHover { hovering in
                            withAnimation(DS.Motion.standard) {
                                isEpisodeListHovered = hovering
                            }
                        }
                        .help("Episodes")
                    }

                    // Audio & Subtitles button (MPV only)
                    if viewModel.mpvController != nil {
                        Button(action: {
                            togglePanel(showAudioSubtitles) { showAudioSubtitles = true }
                        }) {
                            SubtitlesIcon()
                                .frame(width: 32, height: 32)
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .scaleEffect(isAudioSubtitlesHovered ? 1.1 : 1.0)
                        .onHover { hovering in
                            withAnimation(DS.Motion.standard) {
                                isAudioSubtitlesHovered = hovering
                            }
                        }
                        .help("Audio & Subtitles")
                    }

                    // Playback speed button
                    Button(action: {
                        togglePanel(showPlaybackSpeed) { showPlaybackSpeed = true }
                    }) {
                        PlaybackSpeedIcon()
                            .frame(width: 32, height: 32)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(isSpeedHovered ? 1.1 : 1.0)
                    .onHover { hovering in
                        withAnimation(DS.Motion.standard) {
                            isSpeedHovered = hovering
                        }
                    }
                    .help("Playback Speed")

                    // Quality, sources, chapters, aspect ratio and stats
                    settingsButton

                    // Picture-in-Picture button (custom MPV PiP window)
                    if mpvPiPViewController != nil {
                        Button(action: {
                            onToggleMPVPiP()
                        }) {
                            Image(systemName: isPiPActive ? "pip.exit" : "pip.enter")
                                .font(.flixorIcon(DS.Icon.lg))
                                .frame(width: 32, height: 32)
                                .foregroundStyle(isPiPActive ? theme.accent : .white)
                        }
                        .buttonStyle(.plain)
                        .scaleEffect(isPiPHovered ? 1.1 : 1.0)
                        .onHover { hovering in
                            withAnimation(DS.Motion.standard) {
                                isPiPHovered = hovering
                            }
                        }
                        .help("Picture in Picture")
                    }

                    // Fullscreen button
                    Button(action: onToggleFullScreen) {
                        if isFullScreen {
                            FullscreenExitIcon()
                                .frame(width: 32, height: 32)
                                .foregroundStyle(.white)
                        } else {
                            FullscreenEnterIcon()
                                .frame(width: 32, height: 32)
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(isFullscreenHovered ? 1.1 : 1.0)
                    .onHover { hovering in
                        withAnimation(DS.Motion.standard) {
                            isFullscreenHovered = hovering
                        }
                    }
                }
                .padding(.horizontal, DS.Space.s20)
            }
            .padding(.bottom, DS.Space.s20)
            .background(
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 200)
            )
        }
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.6), .clear, .clear],
                startPoint: .top,
                endPoint: .center
            )
            .frame(height: 120)
            .frame(maxHeight: .infinity, alignment: .top)
        )
        .overlay {
            if showEpisodesList && !viewModel.seasonEpisodes.isEmpty {
                EpisodesListPanel(
                    episodes: viewModel.episodesForBrowser,
                    currentEpisodeKey: viewModel.currentEpisodeListKey,
                    seasons: viewModel.episodeBrowserSeasons,
                    selectedSeason: viewModel.episodeBrowserSeason,
                    isLoading: viewModel.isLoadingEpisodeBrowser,
                    onSelectSeason: { viewModel.selectEpisodeBrowserSeason($0) },
                    onSelectEpisode: { episode in
                        showEpisodesList = false
                        viewModel.playEpisode(episode)
                    },
                    onClose: { showEpisodesList = false }
                )
                .transition(.opacity)
            }
        }
        .overlay {
            if showPlaybackSpeed {
                PlaybackSpeedModal(
                    currentSpeed: viewModel.playbackSpeed,
                    onSelectSpeed: { speed in
                        viewModel.setPlaybackSpeed(speed)
                        showPlaybackSpeed = false
                    },
                    onClose: {
                        showPlaybackSpeed = false
                    }
                )
                .transition(.opacity)
            }
        }
        .overlay {
            if showAudioSubtitles {
                AudioSubtitlesModal(
                    viewModel: viewModel,
                    onClose: { showAudioSubtitles = false }
                )
                .transition(.opacity)
            }
        }
        .overlay {
            if showChaptersPanel && !viewModel.chapters.isEmpty {
                ChaptersPanel(
                    viewModel: viewModel,
                    onClose: { showChaptersPanel = false }
                )
                .transition(.opacity)
            }
        }
        .overlay {
            if showSourcesPanel {
                PlayerSourcesPanel(viewModel: viewModel, onClose: { showSourcesPanel = false })
                    .transition(.opacity)
            }

            if showAspectPanel {
                PlayerAspectPanel(
                    viewModel: viewModel,
                    onClose: { showAspectPanel = false }
                )
                .transition(.opacity)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            // Next Episode Hover Card - positioned independently
            if showNextEpisodeHover, let nextEp = viewModel.nextEpisode {
                NextEpisodeHoverCard(episode: nextEp)
                    .padding(.trailing, 120)
                    .padding(.bottom, DS.Space.s80)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .overlay(alignment: .bottomLeading) {
            // Thumbnail preview - positioned completely independently
            SeekBarPreviewOverlay(hover: seekHover, label: { seekBarLabel(at: $0) })
        }
        .onChange(of: isAnyPanelOpen) { onPanelOpenChanged($0) }
        .onChange(of: closePanelsRequest) { _ in closeAllPanels() }
        .onDisappear {
            // Panels live in this view: they go with it (loading, errors, closing).
            if isAnyPanelOpen { onPanelOpenChanged(false) }
        }
    }

    private func closeAllPanels() {
        showEpisodesList = false
        showPlaybackSpeed = false
        showAudioSubtitles = false
        showChaptersPanel = false
        showAspectPanel = false
        showSourcesPanel = false
    }

    /// Panels share the same corner, so opening one closes any other.
    // MARK: - Title and settings menu

    /// Show name in bold and "S2 E14 · Episode" below; movies show the title (and year).
    @ViewBuilder
    private var playerTitle: some View {
        let item = viewModel.item
        VStack(spacing: 1) {
            if item.type == "episode", let showName = item.grandparentTitle {
                Text(showName)
                    .font(.flixor(.bodyLarge, weight: .bold))
                let episode = [item.parentIndex.map { "S\($0)" }, item.index.map { "E\($0)" }]
                    .compactMap { $0 }.joined(separator: " ")
                Text([episode.isEmpty ? nil : episode, item.title].compactMap { $0 }.joined(separator: " · "))
                    .font(.flixor(.callout))
                    .foregroundStyle(.white.opacity(0.75))
            } else {
                Text(item.title)
                    .font(.flixor(.bodyLarge, weight: .bold))
                if let year = item.year {
                    Text(String(year))
                        .font(.flixor(.callout))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
        .foregroundStyle(.white)
        .lineLimit(1)
        .truncationMode(.tail)
        .multilineTextAlignment(.center)
        .shadow(color: .black.opacity(0.5), radius: 4)
    }

    private var settingsButton: some View {
        Button(action: showSettingsMenu) {
            Image(systemName: "gearshape")
                .font(.system(size: 22, weight: .regular))
                .frame(width: 32, height: 32)
                .foregroundStyle(.white)
                .overlay(alignment: .topTrailing) {
                    // Transcoding used to show on the quality pill.
                    if viewModel.isTranscoding {
                        Circle().fill(Color.orange).frame(width: 7, height: 7).offset(x: 1, y: 3)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(MenuAnchorReader(anchor: settingsMenuAnchor))
        .scaleEffect(isSettingsHovered ? 1.1 : 1.0)
        .onHover { hovering in
            withAnimation(DS.Motion.standard) { isSettingsHovered = hovering }
        }
        .help("Quality, Sources, Chapters, Aspect Ratio and Stats")
        .accessibilityLabel("Playback settings")
    }

    /// Native menu (keyboard and VoiceOver friendly). Each item opens the panel
    /// or setting it opened before the controls were grouped.
    private func showSettingsMenu() {
        guard let view = settingsMenuAnchor.view else { return }
        closeAllPanels()
        let menu = NSMenu()
        menu.autoenablesItems = false

        if !viewModel.availableQualities.isEmpty {
            let qualityMenu = NSMenu()
            for quality in viewModel.availableQualities {
                let detail = quality == .original ? String(localized: "Direct Play") : String(localized: "Transcoded")
                let item = MenuActionItem(title: "\(quality.rawValue)  ·  \(detail)") { viewModel.changeQuality(quality) }
                item.state = quality == viewModel.selectedQuality ? .on : .off
                qualityMenu.addItem(item)
            }
            let item = NSMenuItem(title: String(localized: "Quality: \(viewModel.selectedQuality.rawValue)"), action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: "sparkles.tv", accessibilityDescription: nil)
            item.submenu = qualityMenu
            menu.addItem(item)
        }

        if viewModel.isStreamPlayback {
            menu.addItem(MenuActionItem(title: String(localized: "Sources…"), systemImage: "square.stack.3d.up") {
                showSourcesPanel = true
            })
        }

        if viewModel.mpvController != nil && !viewModel.chapters.isEmpty {
            menu.addItem(MenuActionItem(title: String(localized: "Chapters…"), systemImage: "list.bullet.rectangle") {
                showChaptersPanel = true
            })
        }

        if viewModel.mpvController != nil {
            menu.addItem(MenuActionItem(title: String(localized: "Aspect Ratio: \(viewModel.aspectMode.displayName)…"), systemImage: viewModel.aspectMode.systemImage) {
                showAspectPanel = true
            })
            menu.addItem(.separator())
            let stats = MenuActionItem(title: String(localized: "Playback Stats"), systemImage: "info.circle") {
                viewModel.togglePerformanceOverlay()
            }
            stats.state = viewModel.showPerformanceOverlay ? .on : .off
            stats.keyEquivalent = "i"
            stats.keyEquivalentModifierMask = []
            menu.addItem(stats)
        }

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + DS.Space.s6), in: view)
    }

    private func togglePanel(_ isOpen: Bool, open: () -> Void) {
        closeAllPanels()
        if !isOpen { open() }
    }

    private var isAnyPanelOpen: Bool {
        showEpisodesList || showPlaybackSpeed || showAudioSubtitles || showChaptersPanel || showAspectPanel || showSourcesPanel
    }

    private var seekBarMarks: SeekBarMarksModel {
        SeekBarMarksModel(markers: viewModel.markers, chapters: viewModel.chapters, duration: viewModel.duration)
    }

    /// Name shown in the seek preview: the marker and/or chapter at `time`.
    private func seekBarLabel(at time: TimeInterval) -> String? {
        let timeMs = Int(time * 1000)
        let marker = viewModel.markers.first { timeMs >= $0.startTimeOffset && timeMs <= $0.endTimeOffset }
        let markerName = marker.map { $0.segmentType?.displayName ?? $0.type.capitalized }
        let chapterName = viewModel.chapters.last { $0.time <= time }?.displayName
        let names = [markerName, chapterName].compactMap { $0 }
        return names.isEmpty ? nil : names.joined(separator: " · ")
    }

    private func requestThumbnail(at time: TimeInterval) {
        guard let generator = viewModel.thumbnailGenerator else { return }
        let hover = seekHover
        hover.requestID &+= 1
        let requestID = hover.requestID
        if !hover.isLoading { hover.isLoading = true }

        generator.generateThumbnail(at: time) { image in
            // Called on the main thread. An older request finishing late is ignored.
            guard hover.requestID == requestID else { return }
            hover.image = image
            hover.isLoading = false
        }
    }
}

// MARK: - Seek Bar

/// Seek-bar hover preview state (see `PlayerControlsView.seekHover`).
final class SeekBarHoverModel: ObservableObject {
    @Published var isVisible = false
    @Published var time: TimeInterval = 0
    @Published var position: CGFloat = 0
    @Published var image: NSImage?
    @Published var isLoading = false
    /// Newest thumbnail request; completions of older ones are dropped.
    var requestID = 0
}

/// Seek bar and time labels. Observes the playback clock, so position updates
/// redraw only this.
private struct PlayerSeekBar: View {
    @ObservedObject var clock: PlaybackClock
    let hover: SeekBarHoverModel
    let duration: TimeInterval
    let marks: SeekBarMarksModel
    let accent: Color
    let segmentColor: Color
    let onSeek: (TimeInterval) -> Void
    let requestThumbnail: (TimeInterval) -> Void

    @State private var isDraggingTimeline = false
    @State private var draggedTime: TimeInterval = 0
    /// Right-hand time label: remaining ("−3:20") or the total. Click to switch.
    @AppStorage("playerShowsRemainingTime") private var showsRemainingTime = true

    var body: some View {
        VStack(spacing: DS.Space.s4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 4)

                    // Progress
                    Rectangle()
                        .fill(accent)
                        .frame(width: geometry.size.width * CGFloat(currentProgress), height: 4)

                    // Chapter ticks and intro/recap/credits ranges
                    SeekBarMarksView(model: marks, segmentColor: segmentColor)
                        .equatable()

                    // Scrubber
                    Circle()
                        .fill(accent)
                        .frame(width: 12, height: 12)
                        .offset(x: geometry.size.width * CGFloat(currentProgress) - 6)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDraggingTimeline = true
                            let progress = min(max(0, value.location.x / geometry.size.width), 1)
                            draggedTime = duration * progress

                            // Update thumbnail preview during drag
                            showPreview(at: draggedTime, x: value.location.x)
                        }
                        .onEnded { _ in
                            isDraggingTimeline = false
                            onSeek(draggedTime)
                            if hover.isVisible { hover.isVisible = false }
                        }
                )
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        // Show preview and request thumbnail
                        if !isDraggingTimeline {
                            let progress = min(max(0, location.x / geometry.size.width), 1)
                            showPreview(at: duration * progress, x: location.x)
                        }
                    case .ended:
                        // Hide preview when hover ends
                        if !isDraggingTimeline {
                            if hover.isVisible { hover.isVisible = false }
                            if hover.image != nil { hover.image = nil }
                        }
                    }
                }
            }
            .frame(height: 12)

            // Time Labels
            HStack {
                Text(formatTime(displayedTime))
                    .font(.caption)
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    showsRemainingTime.toggle()
                } label: {
                    Text(showsRemainingTime
                         ? "−" + formatTime(max(0, duration - displayedTime))
                         : formatTime(duration))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .help(showsRemainingTime ? "Time remaining. Click to show the total." : "Total time. Click to show time remaining.")
            }
        }
    }

    private func showPreview(at time: TimeInterval, x: CGFloat) {
        hover.time = time
        hover.position = x
        if !hover.isVisible { hover.isVisible = true }
        requestThumbnail(time)
    }

    private var displayedTime: TimeInterval {
        isDraggingTimeline ? draggedTime : clock.time
    }

    private var currentProgress: Double {
        guard duration > 0 else { return 0 }
        return displayedTime / duration
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "0:00" }
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

/// The hover thumbnail above the seek bar. Only this observes the hover model.
private struct SeekBarPreviewOverlay: View {
    @ObservedObject var hover: SeekBarHoverModel
    let label: (TimeInterval) -> String?

    var body: some View {
        if hover.isVisible {
            ThumbnailPreviewView(
                time: hover.time,
                label: label(hover.time),
                image: hover.image,
                isLoading: hover.isLoading
            )
            .offset(x: hover.position + 20 - 100) // 20px is the horizontal padding, center 200px wide preview
            .offset(y: -140) // Position above timeline
            .allowsHitTesting(false)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }
}

// MARK: - Volume Slider Popover

private struct VolumeSliderPopover: View {
    @Environment(\.flixorTheme) private var theme
    @Binding var volume: Float
    let isMuted: Bool

    var body: some View {
        HStack(spacing: DS.Space.s12) {
            // Volume icon in popover
            VolumeIcon(volume: volume, isMuted: isMuted)
                .frame(width: 20, height: 20)
                .foregroundStyle(.white)

            // Slider
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 6)
                        .cornerRadius(3)

                    // Progress fill
                    theme.accent
                        .frame(width: geometry.size.width * CGFloat(volume), height: 6)
                        .cornerRadius(3)

                    // Thumb
                    Circle()
                        .strokeBorder(Color.white.opacity(0.6), lineWidth: 4)
                        .background(Circle().fill(Color.white))
                        .frame(width: 20, height: 20)
                        .offset(x: geometry.size.width * CGFloat(volume) - 10)
                }
                .frame(height: 6)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let newVolume = Float(min(max(0, value.location.x / geometry.size.width), 1))
                            volume = newVolume
                        }
                )
            }
            .frame(height: 20)

            // Percentage display
            Text("\(Int(volume * 100))%")
                .font(.flixor(.footnote))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 38, alignment: .trailing)
        }
        .padding(.horizontal, DS.Space.s16)
        .padding(.vertical, DS.Space.s12)
        .frame(width: 288)
        .background(theme.playerPanelBackground(opacity: 0.9))
        .cornerRadius(DS.Radius.r16)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.r16)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
        .padding(.leading, DS.Space.s12)
    }
}

// MARK: - Thumbnail Preview View

private struct ThumbnailPreviewView: View {
    let time: TimeInterval
    let label: String?
    let image: NSImage?
    let isLoading: Bool

    var body: some View {
        VStack(spacing: DS.Space.s8) {
            // Thumbnail image or loading state
            ZStack {
                if let image = image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 200, height: 112)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r6))
                } else if isLoading {
                    // Loading state
                    RoundedRectangle(cornerRadius: DS.Radius.r6)
                        .fill(Color.black.opacity(0.6))
                        .frame(width: 200, height: 112)
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        )
                } else {
                    // Placeholder
                    RoundedRectangle(cornerRadius: DS.Radius.r6)
                        .fill(Color.black.opacity(0.6))
                        .frame(width: 200, height: 112)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.flixorIcon(DS.Icon.xxl))
                                .foregroundStyle(.white.opacity(0.3))
                        )
                }
            }

            // Timestamp, with the marker/chapter name when there is one
            VStack(spacing: DS.Space.s2) {
                if let label {
                    Text(label)
                        .font(.flixor(.footnote, weight: .medium))
                        .foregroundStyle(.white.opacity(DS.Opacity.strong))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Text(formatTime(time))
                    .font(.flixor(.body, weight: .semibold))
                    .foregroundStyle(.white)
            }
                .frame(maxWidth: 200)
                .padding(.horizontal, DS.Space.s12)
                .padding(.vertical, DS.Space.s6)
                .background(Color.black.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r6))
        }
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "0:00" }
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}
