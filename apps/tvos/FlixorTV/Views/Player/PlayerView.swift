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

    private let controlsHideDelay: TimeInterval = 3.0
    private let seekBackwardSeconds = 10
    private let seekForwardSeconds = 10

    private var isMPVActive: Bool {
        playerSettings.backend == .mpv && mpvController != nil
    }

    private var isAVKitActive: Bool {
        playerSettings.backend == .avkit && avkitController != nil
    }

    private var effectiveDuration: Double {
        if duration > 0 { return duration }
        if let ms = item.duration, ms > 0 { return Double(ms) / 1000.0 }
        return 0
    }

    private var titleText: String {
        if !item.title.isEmpty { return item.title }
        return "Now Playing"
    }

    private var subtitleText: String? {
        let parts = [item.grandparentTitle, item.parentTitle].compactMap { value -> String? in
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

            controller.loadFile(item.id)

        case .mpv:
            let controller = MPVPlayerController()
            mpvController = controller

            controller.onEvent = { event in
                print("🎬 [PlayerView/MPV] Event: \(event)")
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
                        isPaused = paused
                    }
                case PlayerProperty.timePos.rawValue:
                    if let time = value as? Double {
                        currentTime = time
                        if !isScrubbing {
                            timelinePosition = time
                        }
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

            controller.loadFile(item.id)
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
        cleanup()
        dismiss()
    }

    private func cleanup() {
        hideControlsWorkItem?.cancel()
        hideControlsWorkItem = nil

        guard hasLoadedPlayback || avkitController != nil || mpvController != nil else { return }
        print("🧹 [PlayerView] Cleaning up player")

        avkitController?.shutdown()
        avkitController = nil

        mpvController?.shutdown()
        mpvController = nil

        hasLoadedPlayback = false
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
                .foregroundStyle(.white)
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
                .foregroundStyle(.white)
                .frame(width: 108, height: 108)
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
