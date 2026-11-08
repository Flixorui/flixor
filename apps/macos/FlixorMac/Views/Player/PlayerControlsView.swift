//
//  PlayerControlsView.swift
//  FlixorMac
//
//  Player controls overlay: top bar, quality menu, seek bar, transport, volume and panel buttons
//

import SwiftUI

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

    @Environment(\.flixorTheme) private var theme
    @Environment(\.windowMetrics) private var metrics

    @State private var isDraggingTimeline = false
    @State private var draggedTime: TimeInterval = 0
    @State private var showEpisodesList = false
    @State private var showPlaybackSpeed = false
    @State private var showVolumeSlider = false
    @State private var showAudioSubtitles = false
    @State private var showChaptersPanel = false
    @State private var showAspectPanel = false

    // Thumbnail preview states
    @State private var showThumbnailPreview = false
    @State private var thumbnailHoverTime: TimeInterval = 0
    @State private var thumbnailHoverPosition: CGFloat = 0
    @State private var thumbnailImage: NSImage? = nil
    @State private var isThumbnailLoading = false

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

    // Computed property for formatted player title
    // For episodes: "Show Name - S#E# - Episode Title"
    // For other content: just the title
    private var formattedPlayerTitle: String {
        let item = viewModel.item
        if item.type == "episode",
           let showName = item.grandparentTitle,
           let seasonNum = item.parentIndex,
           let episodeNum = item.index {
            return "\(showName) - S\(seasonNum)E\(episodeNum) - \(item.title)"
        }
        return item.title
    }

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
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isBackHovered = hovering
                    }
                }

                Spacer()

                // Display formatted title: "Show : S#E# : Episode Title" for episodes
                Text(formattedPlayerTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                // Performance stats toggle (MPV only) - Top bar position
                if viewModel.mpvController != nil {
                    Button(action: {
                        viewModel.togglePerformanceOverlay()
                    }) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 18))
                            .frame(width: 32, height: 32)
                            .foregroundStyle(viewModel.showPerformanceOverlay ? Color.accentColor : .white)
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(isStatsHovered ? 1.1 : 1.0)
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isStatsHovered = hovering
                        }
                    }
                    .help("Performance Stats (I)")
                }

                // Quality Selector
                Menu {
                    ForEach(viewModel.availableQualities) { quality in
                        Button(action: {
                            viewModel.changeQuality(quality)
                        }) {
                            HStack(spacing: 8) {
                                // Checkmark
                                if quality == viewModel.selectedQuality {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color.accentColor)
                                        .frame(width: 12)
                                } else {
                                    Color.clear.frame(width: 12)
                                }

                                // Quality name
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(quality.rawValue)
                                        .font(.system(size: 13, weight: quality == viewModel.selectedQuality ? .semibold : .regular))
                                        .foregroundStyle(quality == viewModel.selectedQuality ? .white : .white.opacity(0.85))

                                    // Description
                                    if quality == .original {
                                        Text("Direct Play • Best Quality")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.white.opacity(0.5))
                                    } else {
                                        Text("Transcoded • H.264")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.orange.opacity(0.7))
                                    }
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 4)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        // Quality text
                        Text(viewModel.selectedQuality.rawValue)
                            .font(.system(size: 14, weight: .medium))

                        // Transcoding indicator badge
                        if viewModel.isTranscoding {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 6, height: 6)
                        }

                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(viewModel.isTranscoding ? Color.orange.opacity(0.2) : Color.black.opacity(0.5))
                    .clipShape(Capsule())
                }
                .menuStyle(.borderlessButton)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            Spacer()

            // Bottom Controls
            VStack(spacing: 12) {
                // Timeline
                VStack(spacing: 4) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background
                            Rectangle()
                                .fill(Color.white.opacity(0.3))
                                .frame(height: 4)

                            // Progress
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(width: geometry.size.width * CGFloat(currentProgress), height: 4)

                            // Chapter ticks and intro/recap/credits ranges
                            SeekBarMarksView(model: seekBarMarks, segmentColor: theme.warning.opacity(DS.Opacity.strong))
                                .equatable()

                            // Scrubber
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 12, height: 12)
                                .offset(x: geometry.size.width * CGFloat(currentProgress) - 6)
                        }
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    isDraggingTimeline = true
                                    let progress = min(max(0, value.location.x / geometry.size.width), 1)
                                    draggedTime = viewModel.duration * progress

                                    // Update thumbnail preview during drag
                                    thumbnailHoverTime = draggedTime
                                    thumbnailHoverPosition = value.location.x
                                    showThumbnailPreview = true
                                    requestThumbnail(at: draggedTime)
                                }
                                .onEnded { value in
                                    isDraggingTimeline = false
                                    viewModel.seek(to: draggedTime)
                                    showThumbnailPreview = false
                                }
                        )
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                // Calculate time from hover position
                                let progress = min(max(0, location.x / geometry.size.width), 1)
                                thumbnailHoverTime = viewModel.duration * progress
                                thumbnailHoverPosition = location.x

                                // Show preview and request thumbnail
                                if !isDraggingTimeline {
                                    showThumbnailPreview = true
                                    requestThumbnail(at: thumbnailHoverTime)
                                }
                            case .ended:
                                // Hide preview when hover ends
                                if !isDraggingTimeline {
                                    showThumbnailPreview = false
                                    thumbnailImage = nil // Clear cached image
                                }
                            }
                        }
                    }
                    .frame(height: 12)

                    // Time Labels
                    HStack {
                        Text(formatTime(isDraggingTimeline ? draggedTime : viewModel.currentTime))
                            .font(.caption)
                            .foregroundStyle(.white)
                        Spacer()
                        Text(formatTime(viewModel.duration))
                            .font(.caption)
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 20)

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
                        withAnimation(.easeInOut(duration: 0.2)) {
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
                        withAnimation(.easeInOut(duration: 0.2)) {
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
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSkipForwardHovered = hovering
                        }
                    }

                    // Volume control
                    HStack(spacing: 0) {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
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
                            withAnimation(.easeInOut(duration: 0.2)) {
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
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isNextEpisodeHovered = hovering
                                    showNextEpisodeHover = hovering
                                }
                            }
                            .help("Next Episode: \(nextEp.title)")
                        }
                        // Episodes list button
                        Button(action: {
                            showEpisodesList.toggle()
                        }) {
                            EpisodeListIcon()
                                .frame(width: 32, height: 32)
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .scaleEffect(isEpisodeListHovered ? 1.1 : 1.0)
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isEpisodeListHovered = hovering
                            }
                        }
                        .help("Episodes")
                    }

                    // Audio & Subtitles button (MPV only)
                    if viewModel.mpvController != nil {
                        Button(action: {
                            showAudioSubtitles.toggle()
                        }) {
                            SubtitlesIcon()
                                .frame(width: 32, height: 32)
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .scaleEffect(isAudioSubtitlesHovered ? 1.1 : 1.0)
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isAudioSubtitlesHovered = hovering
                            }
                        }
                        .help("Audio & Subtitles")
                    }

                    // Playback speed button
                    Button(action: {
                        showPlaybackSpeed.toggle()
                    }) {
                        PlaybackSpeedIcon()
                            .frame(width: 32, height: 32)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(isSpeedHovered ? 1.1 : 1.0)
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSpeedHovered = hovering
                        }
                    }
                    .help("Playback Speed")

                    // Chapters button (MPV only, when chapters exist)
                    if viewModel.mpvController != nil && !viewModel.chapters.isEmpty {
                        Button(action: {
                            showChaptersPanel.toggle()
                        }) {
                            Image("chaptericon")
                                .resizable()
                                .renderingMode(.template)
                                .scaledToFit()
                                .frame(width: 42, height: 42)
                                .foregroundStyle(showChaptersPanel ? Color.accentColor : .white)
                        }
                        .buttonStyle(.plain)
                        .scaleEffect(isChaptersHovered ? 1.1 : 1.0)
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isChaptersHovered = hovering
                            }
                        }
                        .help("Chapters")
                    }

                    // Aspect mode button (MPV only)
                    if viewModel.mpvController != nil {
                        Button(action: {
                            showAspectPanel.toggle()
                        }) {
                            Image(systemName: viewModel.aspectMode.systemImage)
                                .font(.flixorIcon(DS.Icon.lg))
                                .frame(width: 32, height: 32)
                                .foregroundStyle(showAspectPanel ? theme.accent : .white)
                        }
                        .buttonStyle(.plain)
                        .scaleEffect(isAspectHovered ? 1.1 : 1.0)
                        .onHover { hovering in
                            withAnimation(DS.Motion.standard) {
                                isAspectHovered = hovering
                            }
                        }
                        .help("Aspect Ratio (A)")
                        .accessibilityLabel("Aspect ratio, \(viewModel.aspectMode.displayName)")
                    }

                    // Picture-in-Picture button (custom MPV PiP window)
                    if mpvPiPViewController != nil {
                        Button(action: {
                            onToggleMPVPiP()
                        }) {
                            Image(systemName: isPiPActive ? "pip.exit" : "pip.enter")
                                .font(.system(size: 20))
                                .frame(width: 32, height: 32)
                                .foregroundStyle(isPiPActive ? Color.accentColor : .white)
                        }
                        .buttonStyle(.plain)
                        .scaleEffect(isPiPHovered ? 1.1 : 1.0)
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.2)) {
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
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isFullscreenHovered = hovering
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 20)
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
                    episodes: viewModel.seasonEpisodes,
                    currentEpisodeKey: viewModel.item.id.replacingOccurrences(of: "plex:", with: ""),
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
                NextEpisodeHoverCard(episode: nextEp, viewModel: viewModel)
                    .padding(.trailing, 120)
                    .padding(.bottom, 80)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .overlay(alignment: .bottomLeading) {
            // Thumbnail preview - positioned completely independently
            if showThumbnailPreview {
                ThumbnailPreviewView(
                    time: thumbnailHoverTime,
                    label: seekBarLabel(at: thumbnailHoverTime),
                    image: thumbnailImage,
                    isLoading: isThumbnailLoading
                )
                .offset(x: thumbnailHoverPosition + 20 - 100) // 20px is the horizontal padding, center 200px wide preview
                .offset(y: -140) // Position above timeline
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .onChange(of: isAnyPanelOpen) { onPanelOpenChanged($0) }
        .onDisappear {
            // Panels live in this view: they go with it (loading, errors, closing).
            if isAnyPanelOpen { onPanelOpenChanged(false) }
        }
    }

    private var isAnyPanelOpen: Bool {
        showEpisodesList || showPlaybackSpeed || showAudioSubtitles || showChaptersPanel || showAspectPanel
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

    private var currentProgress: Double {
        guard viewModel.duration > 0 else { return 0 }
        let time = isDraggingTimeline ? draggedTime : viewModel.currentTime
        return time / viewModel.duration
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

    private func requestThumbnail(at time: TimeInterval) {
        guard let generator = viewModel.thumbnailGenerator else { return }

        isThumbnailLoading = true

        generator.generateThumbnail(at: time) { image in
            Task { @MainActor in
                self.thumbnailImage = image
                self.isThumbnailLoading = false
            }
        }
    }
}

// MARK: - Volume Slider Popover

private struct VolumeSliderPopover: View {
    @Binding var volume: Float
    let isMuted: Bool

    var body: some View {
        HStack(spacing: 12) {
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

                    // Progress fill with red gradient
                    LinearGradient(
                        colors: [Color(red: 0.898, green: 0.035, blue: 0.078), Color(red: 0.9, green: 0.035, blue: 0.078)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
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
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 38, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 288)
        .background(Color.black.opacity(0.9))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
        .padding(.leading, 12)
    }
}

// MARK: - Thumbnail Preview View

private struct ThumbnailPreviewView: View {
    let time: TimeInterval
    let label: String?
    let image: NSImage?
    let isLoading: Bool

    var body: some View {
        VStack(spacing: 8) {
            // Thumbnail image or loading state
            ZStack {
                if let image = image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 200, height: 112)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else if isLoading {
                    // Loading state
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.6))
                        .frame(width: 200, height: 112)
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        )
                } else {
                    // Placeholder
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.6))
                        .frame(width: 200, height: 112)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 32))
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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
                .frame(maxWidth: 200)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 6))
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
