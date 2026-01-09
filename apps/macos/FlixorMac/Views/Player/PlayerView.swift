//
//  PlayerView.swift
//  FlixorMac
//
//  Video player with AVPlayer and custom controls
//

import SwiftUI
import AVKit


struct PlayerView: View {
    let item: MediaItem
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: NavigationRouter
    @EnvironmentObject private var mainViewState: MainViewState
    @StateObject private var viewModel: PlayerViewModel
    @State private var showControls = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var isFullScreen = false
    @State private var lastMousePosition: CGPoint = .zero
    @State private var mouseMovementTimer: Timer?
    @State private var pipController: AVPictureInPictureController?
    @State private var isPiPActive = false
    @State private var isCursorHidden = false
    @State private var mpvPiPViewController: NSViewController?
    @State private var keyboardMonitor: Any?
    @AppStorage("playerBackend") private var selectedBackend: String = PlayerBackend.avplayer.rawValue

    private var playerBackend: PlayerBackend {
        PlayerBackend(rawValue: selectedBackend) ?? .avplayer
    }

    init(item: MediaItem) {
        self.item = item
        _viewModel = StateObject(wrappedValue: PlayerViewModel(item: item))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Video Player - Switch based on backend
            Group {
                switch playerBackend {
                case .avplayer:
                    if let player = viewModel.player {
                        VideoPlayerView(player: player, pipController: $pipController, isPiPActive: $isPiPActive)
                            .ignoresSafeArea()
                            .onTapGesture {
                                viewModel.togglePlayPause()
                            }
                            .onTapGesture(count: 2) {
                                toggleFullScreen()
                            }
                    }
                case .mpv:
                    if let mpvController = viewModel.mpvController {
                        MPVVideoViewWrapper(mpvController: mpvController, isPiPActive: $isPiPActive, mpvPiPViewController: $mpvPiPViewController)
                            .ignoresSafeArea()
                            .onTapGesture {
                                viewModel.togglePlayPause()
                            }
                            .onTapGesture(count: 2) {
                                toggleFullScreen()
                            }
                    }
                }
            }

            // Loading Indicator
            if viewModel.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)

                    // Show quality change message if applicable
                    if viewModel.isChangingQuality {
                        VStack(spacing: 4) {
                            Text("Switching to \(viewModel.selectedQuality.rawValue)")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)

                            if viewModel.isTranscoding {
                                Text("Starting transcode...")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.7))
                            } else {
                                Text("Loading direct play...")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                    }
                }
            }

            // Error State
            if let error = viewModel.error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)

                    Text("Playback Error")
                        .font(.title2.bold())
                        .foregroundStyle(.white)

                    Text(error)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)

                    HStack(spacing: 12) {
                        Button("Close") {
                            viewModel.stopPlayback()
                            dismiss()
                        }
                        .buttonStyle(.bordered)

                        Button("Retry") {
                            viewModel.retry()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }

            // Controls Overlay
            if showControls && !viewModel.isLoading && viewModel.error == nil {
                PlayerControlsView(
                    viewModel: viewModel,
                    isFullScreen: $isFullScreen,
                    pipController: pipController,
                    isPiPActive: isPiPActive,
                    mpvPiPViewController: mpvPiPViewController,
                    playerBackend: playerBackend,
                    onClose: {
                        // Stop playback BEFORE dismissing
                        viewModel.stopPlayback()
                        dismiss()
                    },
                    onToggleFullScreen: toggleFullScreen,
                    onToggleMPVPiP: toggleMPVPiP
                )
                .transition(.opacity)
            }

            // Skip Intro/Credits Button - white pill, bottom-right; only for intro/credits
            if let marker = viewModel.currentMarker, ["intro","credits"].contains(marker.type.lowercased()) {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            viewModel.skipMarker()
                        }) {
                            Text(marker.type.lowercased() == "intro" ? "SKIP INTRO" : "SKIP CREDITS")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .background(Color.white)
                                .clipShape(Capsule())
                                .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 32)
                        .padding(.bottom, 96)
                    }
                }
                .transition(.opacity)
            }

            // Next Episode Countdown (web style)
            if let countdown = viewModel.nextEpisodeCountdown, let nextEp = viewModel.nextEpisode {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Up Next • Playing in \(countdown)s")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)

                            Text(nextEp.title)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.white.opacity(0.9))
                                .lineLimit(1)

                            HStack(spacing: 8) {
                                Button("Cancel") {
                                    viewModel.cancelCountdown()
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.1))
                                .foregroundStyle(.white)
                                .cornerRadius(4)

                                Button("Play Now") {
                                    viewModel.playNext()
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.red)
                                .foregroundStyle(.white)
                                .cornerRadius(4)
                            }
                        }
                        .padding(16)
                        .background(Color.black.opacity(0.85))
                        .cornerRadius(12)
                        .shadow(radius: 20)
                        .padding(.trailing, 32)
                        .padding(.bottom, 140)
                    }
                }
                .transition(.opacity)
            }
        }
        .onDisappear {
            // Cancel any pending hide controls task FIRST to prevent cursor hiding after dismiss
            hideControlsTask?.cancel()
            hideControlsTask = nil

            viewModel.onDisappear()
            stopMouseTracking()
            stopKeyboardMonitoring()
            forceShowCursor() // Force cursor to be visible when leaving

            // Exit fullscreen when leaving player
            if isFullScreen {
                toggleFullScreen()
            }
        }
        .onAppear {
            showControls = true
            scheduleHideControls()
            startMouseTracking()
            startKeyboardMonitoring()

            // Setup navigation callback for next episode
            viewModel.onPlayNext = { [weak router, weak mainViewState] nextItem in
                guard let router = router, let mainViewState = mainViewState else { return }
                // Dismiss current player
                dismiss()
                // Small delay to ensure dismiss completes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    // Navigate to next episode using correct tab path
                    switch mainViewState.selectedTab {
                    case .home: router.homePath.append(nextItem)
                    case .search: router.searchPath.append(nextItem)
                    case .library: router.libraryPath.append(nextItem)
                    case .myList: router.myListPath.append(nextItem)
                    case .newPopular: router.newPopularPath.append(nextItem)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mpvPiPDidClose)) { _ in
            isPiPActive = false
        }
    }

    // MARK: - Keyboard Controls

    private func startKeyboardMonitoring() {
        #if os(macOS)
        // Remove any existing monitor first
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }

        // Add new monitor and store the reference
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            if handleKeyDown(event) {
                return nil // Event handled, don't propagate
            }
            return event // Event not handled, propagate
        }
        #endif
    }

    private func stopKeyboardMonitoring() {
        #if os(macOS)
        // IMPORTANT: Must explicitly remove the event monitor
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }
        #endif
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        // Get the key code and characters
        let keyCode = event.keyCode
        let characters = event.charactersIgnoringModifiers?.lowercased() ?? ""

        // Handle arrow keys and special keys
        switch keyCode {
        case 49: // Space bar
            viewModel.togglePlayPause()
            return true

        case 123: // Left arrow
            viewModel.skip(seconds: -10)
            return true

        case 124: // Right arrow
            viewModel.skip(seconds: 10)
            return true

        case 126: // Up arrow
            let newVolume = min(1.0, viewModel.volume + 0.1)
            viewModel.setVolume(newVolume)
            return true

        case 125: // Down arrow
            let newVolume = max(0.0, viewModel.volume - 0.1)
            viewModel.setVolume(newVolume)
            return true

        case 53: // Escape
            if isFullScreen {
                toggleFullScreen()
            } else {
                viewModel.stopPlayback()
                dismiss()
            }
            return true

        default:
            // Handle character keys
            if characters == "m" {
                viewModel.toggleMute()
                return true
            } else if characters == "f" {
                toggleFullScreen()
                return true
            }
            return false
        }
    }

    private func toggleFullScreen() {
        #if os(macOS)
        if let window = NSApp.keyWindow {
            window.toggleFullScreen(nil)
            isFullScreen.toggle()
        }
        #endif
    }

    private func toggleMPVPiP() {
        #if os(macOS)
        guard let mpvViewController = mpvPiPViewController as? MPVVideoViewWrapper.MPVPiPViewController else {
            return
        }

        MPVPiPWindowManager.shared.togglePiP(mpvViewController: mpvViewController, stateBinding: $isPiPActive)
        #endif
    }

    private func startMouseTracking() {
        #if os(macOS)
        // Start a timer that checks mouse position periodically
        mouseMovementTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [self] _ in
            if let window = NSApp.keyWindow,
               let contentView = window.contentView {
                let mouseLocation = NSEvent.mouseLocation
                let windowLocation = window.convertPoint(fromScreen: NSPoint(x: mouseLocation.x, y: mouseLocation.y))
                let viewLocation = contentView.convert(windowLocation, from: nil)

                // Check if mouse position changed
                if viewLocation.x != lastMousePosition.x || viewLocation.y != lastMousePosition.y {
                    lastMousePosition = viewLocation
                    onMouseMoved()
                }
            }
        }
        #endif
    }

    private func stopMouseTracking() {
        mouseMovementTimer?.invalidate()
        mouseMovementTimer = nil
        forceShowCursor() // Force show cursor when stopping tracking
    }

    private func hideCursor() {
        #if os(macOS)
        if !isCursorHidden {
            NSCursor.hide()
            isCursorHidden = true
        }
        #endif
    }

    private func showCursor() {
        #if os(macOS)
        if isCursorHidden {
            NSCursor.unhide()
            isCursorHidden = false
        }
        #endif
    }

    private func forceShowCursor() {
        #if os(macOS)
        // NSCursor.hide() uses an internal counter, so we need to ensure we fully unhide
        // Call unhide multiple times to clear any pending hides
        for _ in 0..<10 {
            NSCursor.unhide()
        }
        // Additionally, use setHiddenUntilMouseMoves to ensure cursor becomes visible
        NSCursor.setHiddenUntilMouseMoves(false)
        isCursorHidden = false
        #endif
    }

    private func onMouseMoved() {
        // Show cursor on mouse movement
        showCursor()

        // Show controls on mouse movement
        withAnimation(.easeInOut(duration: 0.2)) {
            showControls = true
        }
        // Restart the hide timer
        scheduleHideControls()
    }

    private func scheduleHideControls() {
        hideControlsTask?.cancel()
        hideControlsTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds of inactivity
            // Double-check task wasn't cancelled and we're still playing
            guard !Task.isCancelled && viewModel.isPlaying else { return }

            withAnimation(.easeInOut(duration: 0.2)) {
                showControls = false
            }
            // Only hide cursor if task is still valid (not cancelled)
            if !Task.isCancelled {
                hideCursor()
            }
        }
    }
}

// MARK: - MPV Video View Wrapper (for PiP support)

struct MPVVideoViewWrapper: NSViewControllerRepresentable {
    let mpvController: MPVPlayerController
    @Binding var isPiPActive: Bool
    @Binding var mpvPiPViewController: NSViewController?

    func makeNSViewController(context: Context) -> NSViewController {
        let viewController = MPVPiPViewController()
        viewController.mpvController = mpvController
        viewController.isPiPActiveBinding = $isPiPActive

        // Store the view controller for PiP control
        DispatchQueue.main.async {
            self.mpvPiPViewController = viewController
        }

        return viewController
    }

    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {
        if let pipVC = nsViewController as? MPVPiPViewController {
            pipVC.mpvController = mpvController
        }
    }

    class MPVPiPViewController: NSViewController {
        var mpvController: MPVPlayerController?
        var isPiPActiveBinding: Binding<Bool>?
        private(set) var hostingView: NSHostingView<MPVVideoView>?

        override func loadView() {
            guard let mpvController = mpvController else {
                view = NSView()
                return
            }

            // Create the MPV video view hosting view
            let hosting = NSHostingView(rootView: MPVVideoView(mpvController: mpvController))
            hosting.translatesAutoresizingMaskIntoConstraints = false
            self.hostingView = hosting
            view = hosting
        }

        override func viewWillAppear() {
            super.viewWillAppear()
            // macOS 13.0+ PiP support
            if #available(macOS 13.0, *) {
                // PiP is available
            }
        }

        // Extract the actual MPVNSView from the hosting view hierarchy
        func getMPVNSView() -> MPVNSView? {
            // The NSHostingView contains the MPVNSView as a subview
            return findMPVNSView(in: hostingView)
        }

        private func findMPVNSView(in view: NSView?) -> MPVNSView? {
            guard let view = view else { return nil }

            // Check if this is the MPVNSView
            if let mpvView = view as? MPVNSView {
                return mpvView
            }

            // Recursively search subviews
            for subview in view.subviews {
                if let mpvView = findMPVNSView(in: subview) {
                    return mpvView
                }
            }

            return nil
        }
    }
}

// MARK: - Video Player View (AVPlayerLayer wrapper)

struct VideoPlayerView: NSViewRepresentable {
    let player: AVPlayer
    @Binding var pipController: AVPictureInPictureController?
    @Binding var isPiPActive: Bool

    func makeNSView(context: Context) -> NSView {
        let view = PlayerContainerView()
        view.player = player
        view.pipController = pipController
        view.isPiPActiveBinding = $isPiPActive

        // Setup PiP controller
        if let playerLayer = view.playerLayer {
            setupPiPController(for: playerLayer, context: context, view: view)
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let playerView = nsView as? PlayerContainerView {
            playerView.player = player

            // Setup PiP if not already set up
            if pipController == nil, let playerLayer = playerView.playerLayer {
                setupPiPController(for: playerLayer, context: context, view: playerView)
            }
        }
    }

    private func setupPiPController(for playerLayer: AVPlayerLayer, context: Context, view: PlayerContainerView) {
        // Check if PiP is supported
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            print("Picture-in-Picture not supported on this device")
            return
        }

        // Create PiP controller
        if let controller = try? AVPictureInPictureController(playerLayer: playerLayer) {
            controller.delegate = context.coordinator
            DispatchQueue.main.async {
                self.pipController = controller
                view.pipController = controller
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isPiPActive: $isPiPActive)
    }

    class Coordinator: NSObject, AVPictureInPictureControllerDelegate {
        @Binding var isPiPActive: Bool

        init(isPiPActive: Binding<Bool>) {
            _isPiPActive = isPiPActive
        }

        func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
            DispatchQueue.main.async {
                self.isPiPActive = true
            }
        }

        func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
            print("PiP started")
        }

        func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
            DispatchQueue.main.async {
                self.isPiPActive = false
            }
        }

        func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
            print("PiP stopped")
        }

        func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
            print("Failed to start PiP: \(error.localizedDescription)")
        }
    }

    class PlayerContainerView: NSView {
        private(set) var playerLayer: AVPlayerLayer?
        var pipController: AVPictureInPictureController?
        var isPiPActiveBinding: Binding<Bool>?

        var player: AVPlayer? {
            didSet {
                setupPlayerLayer()
            }
        }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func setupPlayerLayer() {
            playerLayer?.removeFromSuperlayer()

            guard let player = player else { return }

            let newPlayerLayer = AVPlayerLayer(player: player)
            newPlayerLayer.frame = bounds
            newPlayerLayer.videoGravity = .resizeAspect
            layer?.addSublayer(newPlayerLayer)
            playerLayer = newPlayerLayer
        }

        override func layout() {
            super.layout()
            playerLayer?.frame = bounds
        }
    }
}

// MARK: - Player Controls

struct PlayerControlsView: View {
    @ObservedObject var viewModel: PlayerViewModel
    @Binding var isFullScreen: Bool
    let pipController: AVPictureInPictureController?
    let isPiPActive: Bool
    let mpvPiPViewController: NSViewController?
    let playerBackend: PlayerBackend
    let onClose: () -> Void
    let onToggleFullScreen: () -> Void
    let onToggleMPVPiP: () -> Void

    @State private var isDraggingTimeline = false
    @State private var draggedTime: TimeInterval = 0
    @State private var showEpisodesList = false
    @State private var showPlaybackSpeed = false
    @State private var showVolumeSlider = false
    @State private var showAudioSubtitles = false

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

                Spacer()

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
                HStack(spacing: 20) {
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

                    // Picture-in-Picture button (AVPlayer and MPV)
                    if (playerBackend == .avplayer && pipController != nil && AVPictureInPictureController.isPictureInPictureSupported()) ||
                       (playerBackend == .mpv && mpvPiPViewController != nil) {
                        Button(action: {
                            if playerBackend == .avplayer {
                                if isPiPActive {
                                    pipController?.stopPictureInPicture()
                                } else {
                                    pipController?.startPictureInPicture()
                                }
                            } else if playerBackend == .mpv {
                                onToggleMPVPiP()
                            }
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
        .overlay(alignment: .trailing) {
            if showEpisodesList && !viewModel.seasonEpisodes.isEmpty {
                EpisodesListPanel(
                    episodes: viewModel.seasonEpisodes,
                    currentEpisodeKey: viewModel.item.id.replacingOccurrences(of: "plex:", with: ""),
                    onSelectEpisode: { episode in
                        showEpisodesList = false
                        // Use playEpisode to preserve mediaIndex (version selection)
                        viewModel.playEpisode(episode)
                    },
                    onClose: {
                        showEpisodesList = false
                    }
                )
                .transition(.move(edge: .trailing))
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
                    audioTracks: viewModel.availableAudioTracks,
                    subtitleTracks: viewModel.availableSubtitleTracks,
                    currentAudioTrackId: viewModel.currentAudioTrackId,
                    currentSubtitleTrackId: viewModel.currentSubtitleTrackId,
                    onSelectAudioTrack: { trackId in
                        viewModel.setAudioTrack(trackId)
                    },
                    onSelectSubtitleTrack: { trackId in
                        if trackId == 0 {
                            viewModel.disableSubtitles()
                        } else {
                            viewModel.setSubtitleTrack(trackId)
                        }
                    },
                    onClose: {
                        showAudioSubtitles = false
                    }
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
                    image: thumbnailImage,
                    isLoading: isThumbnailLoading
                )
                .offset(x: thumbnailHoverPosition + 20 - 100) // 20px is the horizontal padding, center 200px wide preview
                .offset(y: -140) // Position above timeline
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
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

// MARK: - Episodes List Panel

struct EpisodesListPanel: View {
    let episodes: [EpisodeMetadata]
    let currentEpisodeKey: String
    let onSelectEpisode: (EpisodeMetadata) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Episodes")
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.black.opacity(0.9))

            Divider()
                .background(Color.white.opacity(0.2))

            // Episodes List
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(episodes) { episode in
                        PlayerEpisodeRow(
                            episode: episode,
                            isCurrentEpisode: episode.ratingKey == currentEpisodeKey,
                            onSelect: { onSelectEpisode(episode) }
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
        }
        .frame(width: 450)
        .background(Color.black.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 0))
    }
}

// MARK: - Audio & Subtitles Combined Modal

private struct AudioSubtitlesModal: View {
    let audioTracks: [MPVTrack]
    let subtitleTracks: [MPVTrack]
    let currentAudioTrackId: Int?
    let currentSubtitleTrackId: Int?
    let onSelectAudioTrack: (Int) -> Void
    let onSelectSubtitleTrack: (Int) -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    onClose()
                }

            // Combined track selector card - positioned bottom-right
            VStack {
                Spacer()
                HStack {
                    Spacer()

                    combinedTrackSelectorCard
                }
            }
        }
    }

    private var combinedTrackSelectorCard: some View {
        HStack(alignment: .top, spacing: 0) {
            // Audio column
            VStack(alignment: .leading, spacing: 0) {
                Text("Audio")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .padding(.horizontal, 16)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(audioTracks, id: \.id) { track in
                            Button(action: {
                                onSelectAudioTrack(track.id)
                            }) {
                                HStack(spacing: 8) {
                                    if track.id == currentAudioTrackId {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(Color.accentColor)
                                            .frame(width: 12)
                                    } else {
                                        Color.clear
                                            .frame(width: 12)
                                    }

                                    Text(track.displayName)
                                        .font(.system(size: 13))
                                        .foregroundStyle(track.id == currentAudioTrackId ? .white : .white.opacity(0.7))

                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 5)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 100)
                .padding(.bottom, 10)
            }
            .frame(width: 220)

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 1)
                .padding(.vertical, 10)

            // Subtitles column
            VStack(alignment: .leading, spacing: 0) {
                Text("Subtitles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .padding(.horizontal, 16)

                ScrollView {
                    VStack(spacing: 0) {
                        // "Off" option
                        Button(action: {
                            onSelectSubtitleTrack(0)
                        }) {
                            HStack(spacing: 8) {
                                if currentSubtitleTrackId == nil {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color.accentColor)
                                        .frame(width: 12)
                                } else {
                                    Color.clear
                                        .frame(width: 12)
                                }

                                Text("Off")
                                    .font(.system(size: 13))
                                    .foregroundStyle(currentSubtitleTrackId == nil ? .white : .white.opacity(0.7))

                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)

                        // Subtitle tracks
                        ForEach(subtitleTracks, id: \.id) { track in
                            Button(action: {
                                onSelectSubtitleTrack(track.id)
                            }) {
                                HStack(spacing: 8) {
                                    if track.id == currentSubtitleTrackId {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(Color.accentColor)
                                            .frame(width: 12)
                                    } else {
                                        Color.clear
                                            .frame(width: 12)
                                    }

                                    Text(track.displayName)
                                        .font(.system(size: 13))
                                        .foregroundStyle(track.id == currentSubtitleTrackId ? .white : .white.opacity(0.7))

                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 5)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 100)
                .padding(.bottom, 10)
            }
            .frame(width: 220)
        }
        .background(Color.black.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 20, y: 6)
        .padding(.trailing, 32)
        .padding(.bottom, 140)
    }
}

// MARK: - Playback Speed Modal

private struct PlaybackSpeedModal: View {
    let currentSpeed: Float
    let onSelectSpeed: (Float) -> Void
    let onClose: () -> Void

    private let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5]
    @State private var isDragging = false
    @State private var dragSpeed: Float?

    private var displaySpeed: Float {
        isDragging ? (dragSpeed ?? currentSpeed) : currentSpeed
    }

    private var currentIndex: Int {
        speeds.firstIndex(of: currentSpeed) ?? 2
    }

    private var activeIndex: Int {
        if isDragging, let ds = dragSpeed {
            return speeds.firstIndex(of: ds) ?? currentIndex
        }
        return currentIndex
    }

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    onClose()
                }

            // Speed selector card - positioned bottom-right
            VStack {
                Spacer()
                HStack {
                    Spacer()

                    speedSelectorCard
                }
            }
        }
    }

    private var speedSelectorCard: some View {
        VStack(spacing: 0) {
            // Title
            Text("Playback Speed")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 24)
                .padding(.bottom, 20)

            speedSlider
                .padding(.bottom, 24)
        }
        .frame(width: 600, height: 240)
        .background(Color.black.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.trailing, 32)
        .padding(.bottom, 140)
    }

    private var speedSlider: some View {
        VStack(spacing: 16) {
            // Current speed display
            Text(String(format: "%.2fx", displaySpeed))
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)

            if abs(displaySpeed - 1.0) < 0.01 {
                Text("Normal")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))
            }

            // Draggable slider track
            GeometryReader { geometry in
                draggableTrack(width: geometry.size.width)
            }
            .frame(height: 28)
            .padding(.horizontal, 40)

            // Speed labels
            speedLabels
                .padding(.horizontal, 40)
        }
    }

    private func draggableTrack(width: CGFloat) -> some View {
        let trackWidth = width
        let progressWidth = trackWidth * CGFloat(activeIndex) / CGFloat(speeds.count - 1)
        let thumbPosition = trackWidth * CGFloat(activeIndex) / CGFloat(speeds.count - 1)

        return ZStack(alignment: .leading) {
            // Background track
            backgroundTrack

            // Progress fill
            progressFill(width: progressWidth)

            // Speed markers
            speedMarkers(trackWidth: trackWidth)

            // Draggable thumb
            thumb(position: thumbPosition)
        }
        .frame(height: 28)
        .gesture(dragGesture(trackWidth: trackWidth))
    }

    private var backgroundTrack: some View {
        Rectangle()
            .fill(Color.white.opacity(0.2))
            .frame(height: 4)
            .cornerRadius(2)
    }

    private func progressFill(width: CGFloat) -> some View {
        Rectangle()
            .fill(Color.white)
            .frame(width: width, height: 4)
            .cornerRadius(2)
    }

    private func speedMarkers(trackWidth: CGFloat) -> some View {
        ForEach(Array(speeds.enumerated()), id: \.offset) { index, _ in
            let xPosition = trackWidth * CGFloat(index) / CGFloat(speeds.count - 1)
            Circle()
                .fill(index <= activeIndex ? Color.white : Color.white.opacity(0.3))
                .frame(width: 16, height: 16)
                .offset(x: xPosition - 8)
        }
    }

    private func thumb(position: CGFloat) -> some View {
        Circle()
            .strokeBorder(Color.white.opacity(0.8), lineWidth: 3)
            .background(Circle().fill(Color.white))
            .frame(width: 28, height: 28)
            .offset(x: position - 14)
            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
    }

    private func dragGesture(trackWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                isDragging = true
                let progress = min(max(0, value.location.x / trackWidth), 1)
                let index = Int(round(progress * CGFloat(speeds.count - 1)))
                dragSpeed = speeds[index]
            }
            .onEnded { _ in
                isDragging = false
                if let selectedSpeed = dragSpeed {
                    onSelectSpeed(selectedSpeed)
                }
                dragSpeed = nil
            }
    }

    private var speedLabels: some View {
        HStack {
            ForEach(speeds, id: \.self) { speed in
                Text(String(format: "%.2gx", speed))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Custom PNG Icons

private struct BackArrowIcon: View {
    var body: some View {
        if let nsImage = NSImage(named: "back-arrow") {
            Image(nsImage: nsImage)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "chevron.left")
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

private struct PlayIcon: View {
    var body: some View {
        if let nsImage = NSImage(named: "play") {
            Image(nsImage: nsImage)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "play.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

private struct PauseIcon: View {
    var body: some View {
        if let nsImage = NSImage(named: "pause") {
            Image(nsImage: nsImage)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "pause.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

private struct Replay10Icon: View {
    var body: some View {
        if let nsImage = NSImage(named: "replay10") {
            Image(nsImage: nsImage)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "gobackward.10")
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

private struct Forward10Icon: View {
    var body: some View {
        if let nsImage = NSImage(named: "forward10") {
            Image(nsImage: nsImage)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "goforward.10")
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

private struct NextEpisodeIcon: View {
    var body: some View {
        if let nsImage = NSImage(named: "next-episode") {
            Image(nsImage: nsImage)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "forward.end.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

private struct EpisodeListIcon: View {
    var body: some View {
        if let nsImage = NSImage(named: "episode-list") {
            Image(nsImage: nsImage)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "list.bullet")
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

private struct FullscreenEnterIcon: View {
    var body: some View {
        if let nsImage = NSImage(named: "fullscreen-enter") {
            Image(nsImage: nsImage)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

private struct FullscreenExitIcon: View {
    var body: some View {
        if let nsImage = NSImage(named: "fullscreen-exit") {
            Image(nsImage: nsImage)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

private struct PlaybackSpeedIcon: View {
    var body: some View {
        if let nsImage = NSImage(named: "playback-speed") {
            Image(nsImage: nsImage)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "gauge")
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

private struct SubtitlesIcon: View {
    var body: some View {
        if let nsImage = NSImage(named: "subtitles") {
            Image(nsImage: nsImage)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "captions.bubble")
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

// MARK: - Volume Components

private struct VolumeIcon: View {
    let volume: Float
    let isMuted: Bool

    var body: some View {
        let level: VolumeLevel = isMuted || volume == 0 ? .off : volume <= 0.33 ? .low : volume <= 0.66 ? .medium : .high

        GeometryReader { geometry in
            Path { path in
                switch level {
                case .off:
                    // Volume off with X
                    path.addPath(volumeOffPath(in: geometry.size))
                case .low:
                    // Low volume - one wave
                    path.addPath(volumeLowPath(in: geometry.size))
                case .medium:
                    // Medium volume - two waves
                    path.addPath(volumeMediumPath(in: geometry.size))
                case .high:
                    // High volume - three waves
                    path.addPath(volumeHighPath(in: geometry.size))
                }
            }
            .fill(Color.white)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    enum VolumeLevel {
        case off, low, medium, high
    }

    private func volumeOffPath(in size: CGSize) -> Path {
        let scale = size.width / 24
        var path = Path()
        // Speaker base
        path.move(to: CGPoint(x: 11 * scale, y: 4 * scale))
        path.addLine(to: CGPoint(x: 11 * scale, y: 20 * scale))
        path.addLine(to: CGPoint(x: 4.586 * scale, y: 16 * scale))
        path.addLine(to: CGPoint(x: 1 * scale, y: 16 * scale))
        path.addLine(to: CGPoint(x: 1 * scale, y: 8 * scale))
        path.addLine(to: CGPoint(x: 4.586 * scale, y: 8 * scale))
        path.closeSubpath()
        // X mark
        path.move(to: CGPoint(x: 15.293 * scale, y: 9.707 * scale))
        path.addLine(to: CGPoint(x: 17.586 * scale, y: 12 * scale))
        path.addLine(to: CGPoint(x: 15.293 * scale, y: 14.293 * scale))
        path.addLine(to: CGPoint(x: 16.707 * scale, y: 15.707 * scale))
        path.addLine(to: CGPoint(x: 19 * scale, y: 13.414 * scale))
        path.addLine(to: CGPoint(x: 21.293 * scale, y: 15.707 * scale))
        path.addLine(to: CGPoint(x: 22.707 * scale, y: 14.293 * scale))
        path.addLine(to: CGPoint(x: 20.414 * scale, y: 12 * scale))
        path.addLine(to: CGPoint(x: 22.707 * scale, y: 9.707 * scale))
        path.addLine(to: CGPoint(x: 21.293 * scale, y: 8.293 * scale))
        path.addLine(to: CGPoint(x: 19 * scale, y: 10.586 * scale))
        path.addLine(to: CGPoint(x: 16.707 * scale, y: 8.293 * scale))
        path.closeSubpath()
        return path
    }

    private func volumeLowPath(in size: CGSize) -> Path {
        let scale = size.width / 24
        var path = Path()
        // Speaker base
        path.move(to: CGPoint(x: 11 * scale, y: 4 * scale))
        path.addLine(to: CGPoint(x: 11 * scale, y: 20 * scale))
        path.addLine(to: CGPoint(x: 4.586 * scale, y: 16 * scale))
        path.addLine(to: CGPoint(x: 1 * scale, y: 16 * scale))
        path.addLine(to: CGPoint(x: 1 * scale, y: 8 * scale))
        path.addLine(to: CGPoint(x: 4.586 * scale, y: 8 * scale))
        path.closeSubpath()
        // One wave
        path.move(to: CGPoint(x: 14.243 * scale, y: 7.757 * scale))
        path.addLine(to: CGPoint(x: 12.828 * scale, y: 9.172 * scale))
        path.addCurve(to: CGPoint(x: 14 * scale, y: 12 * scale), control1: CGPoint(x: 13.579 * scale, y: 9.922 * scale), control2: CGPoint(x: 14 * scale, y: 10.939 * scale))
        path.addCurve(to: CGPoint(x: 12.828 * scale, y: 14.828 * scale), control1: CGPoint(x: 14 * scale, y: 13.061 * scale), control2: CGPoint(x: 13.579 * scale, y: 14.078 * scale))
        path.addLine(to: CGPoint(x: 14.243 * scale, y: 16.243 * scale))
        path.addCurve(to: CGPoint(x: 16 * scale, y: 12 * scale), control1: CGPoint(x: 15.368 * scale, y: 15.118 * scale), control2: CGPoint(x: 16 * scale, y: 13.591 * scale))
        path.addCurve(to: CGPoint(x: 14.243 * scale, y: 7.757 * scale), control1: CGPoint(x: 16 * scale, y: 10.409 * scale), control2: CGPoint(x: 15.368 * scale, y: 8.882 * scale))
        path.closeSubpath()
        return path
    }

    private func volumeMediumPath(in size: CGSize) -> Path {
        let scale = size.width / 24
        var path = Path()
        // Speaker base
        path.move(to: CGPoint(x: 11 * scale, y: 4 * scale))
        path.addLine(to: CGPoint(x: 11 * scale, y: 20 * scale))
        path.addLine(to: CGPoint(x: 4.586 * scale, y: 16 * scale))
        path.addLine(to: CGPoint(x: 1 * scale, y: 16 * scale))
        path.addLine(to: CGPoint(x: 1 * scale, y: 8 * scale))
        path.addLine(to: CGPoint(x: 4.586 * scale, y: 8 * scale))
        path.closeSubpath()
        // Two waves
        path.move(to: CGPoint(x: 17.071 * scale, y: 4.929 * scale))
        path.addLine(to: CGPoint(x: 15.657 * scale, y: 6.343 * scale))
        path.addCurve(to: CGPoint(x: 18 * scale, y: 12 * scale), control1: CGPoint(x: 17.157 * scale, y: 7.844 * scale), control2: CGPoint(x: 18 * scale, y: 9.878 * scale))
        path.addCurve(to: CGPoint(x: 15.657 * scale, y: 17.657 * scale), control1: CGPoint(x: 18 * scale, y: 14.122 * scale), control2: CGPoint(x: 17.157 * scale, y: 16.156 * scale))
        path.addLine(to: CGPoint(x: 17.071 * scale, y: 19.071 * scale))
        path.addCurve(to: CGPoint(x: 20 * scale, y: 12 * scale), control1: CGPoint(x: 18.946 * scale, y: 17.195 * scale), control2: CGPoint(x: 20 * scale, y: 14.652 * scale))
        path.addCurve(to: CGPoint(x: 17.071 * scale, y: 4.929 * scale), control1: CGPoint(x: 20 * scale, y: 9.348 * scale), control2: CGPoint(x: 18.946 * scale, y: 6.805 * scale))
        path.closeSubpath()
        path.move(to: CGPoint(x: 14.243 * scale, y: 7.757 * scale))
        path.addLine(to: CGPoint(x: 12.828 * scale, y: 9.172 * scale))
        path.addCurve(to: CGPoint(x: 14 * scale, y: 12 * scale), control1: CGPoint(x: 13.579 * scale, y: 9.922 * scale), control2: CGPoint(x: 14 * scale, y: 10.939 * scale))
        path.addCurve(to: CGPoint(x: 12.828 * scale, y: 14.828 * scale), control1: CGPoint(x: 14 * scale, y: 13.061 * scale), control2: CGPoint(x: 13.579 * scale, y: 14.078 * scale))
        path.addLine(to: CGPoint(x: 14.243 * scale, y: 16.243 * scale))
        path.addCurve(to: CGPoint(x: 16 * scale, y: 12 * scale), control1: CGPoint(x: 15.368 * scale, y: 15.118 * scale), control2: CGPoint(x: 16 * scale, y: 13.591 * scale))
        path.addCurve(to: CGPoint(x: 14.243 * scale, y: 7.757 * scale), control1: CGPoint(x: 16 * scale, y: 10.409 * scale), control2: CGPoint(x: 15.368 * scale, y: 8.882 * scale))
        path.closeSubpath()
        return path
    }

    private func volumeHighPath(in size: CGSize) -> Path {
        let scale = size.width / 24
        var path = Path()
        // Speaker base
        path.move(to: CGPoint(x: 11 * scale, y: 4 * scale))
        path.addLine(to: CGPoint(x: 11 * scale, y: 20 * scale))
        path.addLine(to: CGPoint(x: 4.586 * scale, y: 16 * scale))
        path.addLine(to: CGPoint(x: 1 * scale, y: 16 * scale))
        path.addLine(to: CGPoint(x: 1 * scale, y: 8 * scale))
        path.addLine(to: CGPoint(x: 4.586 * scale, y: 8 * scale))
        path.closeSubpath()
        // Three waves
        path.move(to: CGPoint(x: 19.9 * scale, y: 2.1 * scale))
        path.addLine(to: CGPoint(x: 18.485 * scale, y: 3.515 * scale))
        path.addCurve(to: CGPoint(x: 22 * scale, y: 12 * scale), control1: CGPoint(x: 20.736 * scale, y: 5.765 * scale), control2: CGPoint(x: 22 * scale, y: 8.817 * scale))
        path.addCurve(to: CGPoint(x: 18.485 * scale, y: 20.485 * scale), control1: CGPoint(x: 22 * scale, y: 15.183 * scale), control2: CGPoint(x: 20.736 * scale, y: 18.235 * scale))
        path.addLine(to: CGPoint(x: 19.9 * scale, y: 21.9 * scale))
        path.addCurve(to: CGPoint(x: 24 * scale, y: 12 * scale), control1: CGPoint(x: 22.525 * scale, y: 19.274 * scale), control2: CGPoint(x: 24 * scale, y: 15.713 * scale))
        path.addCurve(to: CGPoint(x: 19.9 * scale, y: 2.1 * scale), control1: CGPoint(x: 24 * scale, y: 8.287 * scale), control2: CGPoint(x: 22.525 * scale, y: 4.726 * scale))
        path.closeSubpath()
        path.move(to: CGPoint(x: 17.071 * scale, y: 4.929 * scale))
        path.addLine(to: CGPoint(x: 15.657 * scale, y: 6.343 * scale))
        path.addCurve(to: CGPoint(x: 18 * scale, y: 12 * scale), control1: CGPoint(x: 17.157 * scale, y: 7.844 * scale), control2: CGPoint(x: 18 * scale, y: 9.878 * scale))
        path.addCurve(to: CGPoint(x: 15.657 * scale, y: 17.657 * scale), control1: CGPoint(x: 18 * scale, y: 14.122 * scale), control2: CGPoint(x: 17.157 * scale, y: 16.156 * scale))
        path.addLine(to: CGPoint(x: 17.071 * scale, y: 19.071 * scale))
        path.addCurve(to: CGPoint(x: 20 * scale, y: 12 * scale), control1: CGPoint(x: 18.946 * scale, y: 17.195 * scale), control2: CGPoint(x: 20 * scale, y: 14.652 * scale))
        path.addCurve(to: CGPoint(x: 17.071 * scale, y: 4.929 * scale), control1: CGPoint(x: 20 * scale, y: 9.348 * scale), control2: CGPoint(x: 18.946 * scale, y: 6.805 * scale))
        path.closeSubpath()
        path.move(to: CGPoint(x: 14.243 * scale, y: 7.757 * scale))
        path.addLine(to: CGPoint(x: 12.828 * scale, y: 9.172 * scale))
        path.addCurve(to: CGPoint(x: 14 * scale, y: 12 * scale), control1: CGPoint(x: 13.579 * scale, y: 9.922 * scale), control2: CGPoint(x: 14 * scale, y: 10.939 * scale))
        path.addCurve(to: CGPoint(x: 12.828 * scale, y: 14.828 * scale), control1: CGPoint(x: 14 * scale, y: 13.061 * scale), control2: CGPoint(x: 13.579 * scale, y: 14.078 * scale))
        path.addLine(to: CGPoint(x: 14.243 * scale, y: 16.243 * scale))
        path.addCurve(to: CGPoint(x: 16 * scale, y: 12 * scale), control1: CGPoint(x: 15.368 * scale, y: 15.118 * scale), control2: CGPoint(x: 16 * scale, y: 13.591 * scale))
        path.addCurve(to: CGPoint(x: 14.243 * scale, y: 7.757 * scale), control1: CGPoint(x: 16 * scale, y: 10.409 * scale), control2: CGPoint(x: 15.368 * scale, y: 8.882 * scale))
        path.closeSubpath()
        return path
    }
}

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

// MARK: - Player Episode Row Component
private struct PlayerEpisodeRow: View {
    let episode: EpisodeMetadata
    let isCurrentEpisode: Bool
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Episode thumbnail with progress bar and hover overlay
                ZStack {
                    // Thumbnail image or number badge fallback
                    if let thumbPath = episode.thumb,
                       let imageURL = ImageService.shared.plexImageURL(path: thumbPath, width: 320, height: 180) {
                        CachedAsyncImage(url: imageURL)
                            .frame(width: 160, height: 90)
                    } else if let index = episode.index {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isCurrentEpisode ? Color.orange.opacity(0.2) : Color.white.opacity(0.1))
                            .frame(width: 160, height: 90)
                            .overlay(
                                Text("\(index)")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.6))
                            )
                    }

                    // Hover overlay
                    if isHovered {
                        Rectangle()
                            .fill(Color.black.opacity(0.25))
                            .frame(width: 160, height: 90)

                        // Play button
                        Text("Play")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white)
                            .clipShape(Capsule())
                    }

                    // Progress bar (matching web implementation)
                    // Don't show progress bar for currently playing episode
                    if !isCurrentEpisode, let progress = episode.progressPercent, progress > 0 {
                        VStack {
                            Spacer()
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.2))
                                        .frame(height: 6)

                                    Rectangle()
                                        .fill(Color(red: 229/255, green: 9/255, blue: 20/255))
                                        .frame(width: geometry.size.width * CGFloat(min(100, max(0, progress))) / 100.0, height: 6)
                                }
                            }
                            .frame(height: 6)
                        }
                    }
                }
                .frame(width: 160, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Episode info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(episode.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        // Current indicator
                        if isCurrentEpisode {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                        }
                    }

                    // Duration
                    if let duration = episode.duration {
                        Text("\(duration / 60000) min")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    if let summary = episode.summary {
                        Text(summary)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(2)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isCurrentEpisode ? Color.white.opacity(0.05) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Thumbnail Preview View

private struct ThumbnailPreviewView: View {
    let time: TimeInterval
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

            // Timestamp label
            Text(formatTime(time))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
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

// MARK: - Next Episode Hover Card

private struct NextEpisodeHoverCard: View {
    let episode: EpisodeMetadata
    @ObservedObject var viewModel: PlayerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("Next Episode")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.05))

            // Content grid
            HStack(spacing: 12) {
                // Episode thumbnail with play icon overlay
                ZStack {
                    // Thumbnail
                    if let thumbPath = episode.thumb,
                       let imageURL = ImageService.shared.plexImageURL(path: thumbPath, width: 320, height: 180) {
                        CachedAsyncImage(url: imageURL)
                            .frame(width: 180, height: 100)
                            .background(Color.black.opacity(0.4))
                    } else {
                        Rectangle()
                            .fill(Color.black.opacity(0.4))
                            .frame(width: 180, height: 100)
                    }

                    // Play icon overlay
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.5))
                            .frame(width: 40, height: 40)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                            )

                        // Play icon
                        Path { path in
                            let scale: CGFloat = 1.6
                            path.move(to: CGPoint(x: 5 * scale, y: 2.69127 * scale))
                            path.addCurve(
                                to: CGPoint(x: 5 * scale, y: 21.3087 * scale),
                                control1: CGPoint(x: 5 * scale, y: 1.93067 * scale),
                                control2: CGPoint(x: 5 * scale, y: 22.0693 * scale)
                            )
                            path.addCurve(
                                to: CGPoint(x: 23.4069 * scale, y: 12.8762 * scale),
                                control1: CGPoint(x: 5.81546 * scale, y: 22.5515 * scale),
                                control2: CGPoint(x: 24.0977 * scale, y: 12.4963 * scale)
                            )
                            path.addLine(to: CGPoint(x: 6.48192 * scale, y: 1.81506 * scale))
                            path.closeSubpath()
                        }
                        .fill(Color.white)
                        .frame(width: 24, height: 24)
                    }
                }
                .frame(width: 180, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Episode info
                VStack(alignment: .leading, spacing: 4) {
                    // Season and Episode number (compact)
                    if let parentIndex = episode.parentIndex, let index = episode.index {
                        Text("\(parentIndex) Episode \(index)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }

                    // Episode title
                    Text(episode.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    // Episode summary
                    if let summary = episode.summary {
                        Text(summary)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineSpacing(2)
                            .lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
        }
        .frame(width: 440)
        .background(Color.black.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
    }
}

// MARK: - MPV PiP Window Manager

#if os(macOS)
extension Notification.Name {
    static let mpvPiPDidClose = Notification.Name("mpvPiPDidClose")
}

class MPVPiPWindowManager {
    static let shared = MPVPiPWindowManager()

    private var pipWindow: NSWindow?
    private var windowDelegate: PiPWindowDelegate?
    private var mpvView: MPVNSView?
    private var originalParentView: NSView?
    private var originalConstraints: [NSLayoutConstraint] = []
    private var isPiPActive = false
    private var isClosing = false
    private var controlOverlay: PiPControlOverlay?
    private var isCleaningUp = false
    private var stateBinding: Binding<Bool>?

    private init() {}

    func enterPiP(mpvViewController: MPVVideoViewWrapper.MPVPiPViewController, stateBinding: Binding<Bool>? = nil) {
        self.stateBinding = stateBinding
        guard !isPiPActive else {
            return
        }

        guard !isCleaningUp else {
            return
        }

        // Clear any stale references from previous PiP session
        self.mpvView = nil
        self.originalParentView = nil
        self.originalConstraints = []

        // Extract the actual MPVNSView from the hosting view hierarchy
        guard let mpvView = mpvViewController.getMPVNSView() else {
            showError(message: "Unable to find MPV video view")
            return
        }


        // Store the original parent view and capture a weak reference to mpvView
        self.originalParentView = mpvView.superview
        self.mpvView = mpvView

        // Set flag to prevent display link from stopping during transition
        mpvView.isPiPTransitioning = true

        // Remove all existing constraints
        mpvView.removeConstraints(mpvView.constraints)
        originalConstraints = mpvView.superview?.constraints.filter { constraint in
            constraint.firstItem as? NSView == mpvView || constraint.secondItem as? NSView == mpvView
        } ?? []

        // Deactivate constraints
        NSLayoutConstraint.deactivate(originalConstraints)

        // Remove from parent (display link won't stop due to flag)
        mpvView.removeFromSuperview()

        // Reuse existing window or create new one
        let window: NSWindow
        if let existingWindow = self.pipWindow {
            // Reuse the existing window
            window = existingWindow
        } else {
            // Create PiP window (floating, 16:9 aspect ratio, borderless)
            let pipWidth: CGFloat = 480
            let pipHeight: CGFloat = 270
            let screenFrame = NSScreen.main?.visibleFrame ?? .zero
            let pipX = screenFrame.maxX - pipWidth - 20
            let pipY = screenFrame.maxY - pipHeight - 20
            let pipFrame = NSRect(x: pipX, y: pipY, width: pipWidth, height: pipHeight)

            window = NSWindow(
                contentRect: pipFrame,
                styleMask: [.borderless, .resizable],
                backing: .buffered,
                defer: false
            )

            window.level = .floating
            window.isMovableByWindowBackground = true
            window.backgroundColor = .black
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.aspectRatio = NSSize(width: 16, height: 9)
            window.minSize = NSSize(width: 320, height: 180)
            window.hasShadow = true
            window.isOpaque = false

            // Style the content view with rounded corners
            if let contentView = window.contentView {
                contentView.wantsLayer = true
                contentView.layer?.cornerRadius = 8
                contentView.layer?.masksToBounds = true
            }

            self.pipWindow = window
        }

        // Set delegate
        let delegate = PiPWindowDelegate()
        window.delegate = delegate
        self.windowDelegate = delegate

        // Add MPV view to PiP window with constraints (like IINA does)
        if let contentView = window.contentView {
            mpvView.removeFromSuperview() // Ensure clean state
            contentView.addSubview(mpvView)

            // Use Auto Layout instead of manual frame management
            mpvView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                mpvView.topAnchor.constraint(equalTo: contentView.topAnchor),
                mpvView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                mpvView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                mpvView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
            ])

            // Force layout to apply constraints immediately
            contentView.layoutSubtreeIfNeeded()


            // CRITICAL: Force layer to update for PiP bounds
            if let layer = mpvView.layer as? MPVVideoLayer {
                layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
                layer.contentsScale = window.backingScaleFactor

                // Force layer to update its internal state
                let pipBounds = CGRect(origin: .zero, size: mpvView.bounds.size)
                layer.forceUpdateForNewBounds(pipBounds)

            }

            // Add control overlay if not already present
            if controlOverlay == nil {
                let overlay = PiPControlOverlay(frame: contentView.bounds)
                overlay.translatesAutoresizingMaskIntoConstraints = false
                contentView.addSubview(overlay, positioned: .above, relativeTo: mpvView)

                NSLayoutConstraint.activate([
                    overlay.topAnchor.constraint(equalTo: contentView.topAnchor),
                    overlay.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                    overlay.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                    overlay.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
                ])

                // Set up button actions
                overlay.setReturnAction { [weak self] in
                    self?.exitPiP()
                }

                overlay.setCloseAction { [weak self] in
                    self?.exitPiP()
                    // Post notification to close player
                    NotificationCenter.default.post(name: .mpvPiPDidClose, object: nil)
                }

                overlay.setPlayPauseAction { [weak self] in
                    self?.togglePlayPause()
                }

                controlOverlay = overlay
            }

        }

        // Clear flag after transition is complete
        mpvView.isPiPTransitioning = false

        // pipWindow was already set above when creating or reusing
        self.isPiPActive = true

        // Update SwiftUI state
        DispatchQueue.main.async { [weak self] in
            self?.stateBinding?.wrappedValue = true
        }

        window.makeKeyAndOrderFront(nil)

        // Force redraw after transition (IINA pattern)
        DispatchQueue.main.async {
            // Force both view and layer to redraw
            mpvView.layer?.setNeedsDisplay()
            mpvView.layer?.displayIfNeeded()
            mpvView.needsDisplay = true
            mpvView.display()
        }

    }

    func exitPiP() {
        guard isPiPActive else {
            return
        }

        // Prevent re-entry
        guard !isClosing else {
            return
        }

        isClosing = true

        // CRITICAL: Set flag BEFORE closing window to prevent display link from stopping
        mpvView?.isPiPTransitioning = true

        // Close the window - this will trigger windowWillClose delegate
        pipWindow?.close()
    }

    // Called by window delegate when PiP window is closing
    fileprivate func restoreVideoView() {
        guard let mpvView = self.mpvView else {
            return
        }


        // Set flag to prevent display link from stopping during transition
        mpvView.isPiPTransitioning = true

        // Remove from PiP window (display link won't stop due to flag)
        mpvView.removeFromSuperview()

        // Restore to original parent
        if let originalParent = originalParentView {
            originalParent.addSubview(mpvView)

            // Restore constraints or set frame
            if !originalConstraints.isEmpty {
                NSLayoutConstraint.activate(originalConstraints)
                mpvView.translatesAutoresizingMaskIntoConstraints = false
            } else {
                mpvView.translatesAutoresizingMaskIntoConstraints = true
                mpvView.autoresizingMask = [.width, .height]
                mpvView.frame = originalParent.bounds
            }

            // Force layout to apply constraints/frame immediately
            originalParent.layoutSubtreeIfNeeded()


            // CRITICAL: Force layer to update for restored bounds
            if let layer = mpvView.layer as? MPVVideoLayer,
               let mainWindow = originalParent.window {
                layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
                layer.contentsScale = mainWindow.backingScaleFactor

                // Force layer to update its internal state
                let restoredBounds = CGRect(origin: .zero, size: mpvView.bounds.size)
                layer.forceUpdateForNewBounds(restoredBounds)

            }


            // Clear flag after transition is complete
            mpvView.isPiPTransitioning = false

            // Force redraw after restoration (IINA pattern)
            DispatchQueue.main.async {
                // Force both view and layer to redraw
                mpvView.layer?.setNeedsDisplay()
                mpvView.layer?.displayIfNeeded()
                mpvView.needsDisplay = true
                mpvView.display()
                originalParent.needsDisplay = true
                originalParent.needsLayout = true
                originalParent.layout()
            }
        }

        // Update SwiftUI state immediately
        stateBinding?.wrappedValue = false

        // Notify that PiP closed
        NotificationCenter.default.post(name: .mpvPiPDidClose, object: nil)


        // Update state immediately (before cleanup to prevent re-entry)
        self.isPiPActive = false
        self.isClosing = false
        self.isCleaningUp = false

        // Cleanup - safe deallocation sequence
        // Clear references immediately to prevent re-entry
        self.originalParentView = nil
        self.originalConstraints = []
        self.stateBinding = nil
        // DON'T clear mpvView - it's now back in the main window and in use!

        // Close window with proper cleanup sequence
        if let window = self.pipWindow {
            // Remove all subviews FIRST to break retain cycles
            // (mpvView is already back in main window at this point)
            window.contentView?.subviews.forEach { $0.removeFromSuperview() }

            // Detach delegate to prevent any further callbacks
            window.delegate = nil

            // Just hide the window, don't deallocate it to avoid crash
            window.orderOut(nil)

            // Keep window alive but hidden - will be reused on next PiP
            // This avoids the deallocation crash
        }

        // Clear delegate reference (window keeps the window alive)
        self.windowDelegate = nil
        // DON'T clear pipWindow - keep it for reuse

    }

    func togglePiP(mpvViewController: MPVVideoViewWrapper.MPVPiPViewController, stateBinding: Binding<Bool>) {
        if isPiPActive {
            exitPiP()
        } else {
            enterPiP(mpvViewController: mpvViewController, stateBinding: stateBinding)
        }
    }

    private func togglePlayPause() {
        print("🎬 [PiP] togglePlayPause called")

        // Get the MPV controller from the view
        guard let mpvView = mpvView else {
            print("❌ [PiP] mpvView is nil")
            return
        }

        print("✅ [PiP] mpvView exists: \(mpvView)")

        guard let videoLayer = mpvView.videoLayer else {
            print("❌ [PiP] videoLayer is nil")
            return
        }

        print("✅ [PiP] videoLayer exists: \(videoLayer)")

        guard let mpvController = videoLayer.mpvController else {
            print("❌ [PiP] mpvController is nil")
            return
        }

        print("✅ [PiP] mpvController exists, calling togglePlayPause()")

        // Toggle play/pause using MPV's built-in toggle
        mpvController.togglePlayPause()

        print("✅ [PiP] togglePlayPause() called on controller")

        // Get current state and update UI
        // Note: We get the state after toggle, so if it was paused it's now playing
        if let isPaused: Bool = mpvController.getProperty("pause", type: .flag) {
            print("✅ [PiP] Current pause state: \(isPaused), updating UI to isPlaying: \(!isPaused)")
            controlOverlay?.updatePlayPauseState(isPlaying: !isPaused)
        } else {
            print("⚠️ [PiP] Could not get pause state from MPV")
        }
    }

    private func showError(message: String) {
        let alert = NSAlert()
        alert.messageText = "Picture-in-Picture Error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // Custom PiP control overlay view
    private class PiPControlOverlay: NSView {
        private let closeButton = NSButton()
        private let returnButton = NSButton()
        private let playPauseButton = NSButton()
        private let controlsContainer = NSView()
        private var trackingArea: NSTrackingArea?
        private var isHovered = false
        private var isPlaying = true

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setupUI()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func setupUI() {
            wantsLayer = true

            // Controls container with semi-transparent background
            controlsContainer.wantsLayer = true
            controlsContainer.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
            controlsContainer.alphaValue = 0.0
            controlsContainer.translatesAutoresizingMaskIntoConstraints = false
            addSubview(controlsContainer)

            // Play/Pause button (center) - larger, more prominent
            playPauseButton.image = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: "Pause")
            playPauseButton.isBordered = false
            playPauseButton.bezelStyle = .shadowlessSquare
            playPauseButton.imagePosition = .imageOnly
            playPauseButton.contentTintColor = .white
            playPauseButton.imageScaling = .scaleProportionallyUpOrDown
            playPauseButton.translatesAutoresizingMaskIntoConstraints = false

            // Add visual effect to play/pause button
            if let cell = playPauseButton.cell as? NSButtonCell {
                cell.imageScaling = .scaleProportionallyDown
            }

            controlsContainer.addSubview(playPauseButton)

            // Close button (top-right corner) - smaller, circular
            closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
            closeButton.isBordered = false
            closeButton.bezelStyle = .shadowlessSquare
            closeButton.imagePosition = .imageOnly
            closeButton.contentTintColor = .white
            closeButton.wantsLayer = true
            closeButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor
            closeButton.layer?.cornerRadius = 14
            closeButton.translatesAutoresizingMaskIntoConstraints = false
            addSubview(closeButton)

            // Return to main window button (top-left corner) - smaller, circular
            returnButton.image = NSImage(systemSymbolName: "arrow.down.forward.and.arrow.up.backward", accessibilityDescription: "Return to main window")
            returnButton.isBordered = false
            returnButton.bezelStyle = .shadowlessSquare
            returnButton.imagePosition = .imageOnly
            returnButton.contentTintColor = .white
            returnButton.wantsLayer = true
            returnButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor
            returnButton.layer?.cornerRadius = 14
            returnButton.translatesAutoresizingMaskIntoConstraints = false
            addSubview(returnButton)

            NSLayoutConstraint.activate([
                // Controls container - fills entire view
                controlsContainer.topAnchor.constraint(equalTo: topAnchor),
                controlsContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
                controlsContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
                controlsContainer.trailingAnchor.constraint(equalTo: trailingAnchor),

                // Play/Pause button - centered and large
                playPauseButton.centerXAnchor.constraint(equalTo: controlsContainer.centerXAnchor),
                playPauseButton.centerYAnchor.constraint(equalTo: controlsContainer.centerYAnchor),
                playPauseButton.widthAnchor.constraint(equalToConstant: 60),
                playPauseButton.heightAnchor.constraint(equalToConstant: 60),

                // Close button - top right corner
                closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
                closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                closeButton.widthAnchor.constraint(equalToConstant: 28),
                closeButton.heightAnchor.constraint(equalToConstant: 28),

                // Return button - top left corner
                returnButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
                returnButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                returnButton.widthAnchor.constraint(equalToConstant: 28),
                returnButton.heightAnchor.constraint(equalToConstant: 28)
            ])

            updateTrackingAreas()
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()

            if let trackingArea = trackingArea {
                removeTrackingArea(trackingArea)
            }

            trackingArea = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways],
                owner: self,
                userInfo: nil
            )

            if let trackingArea = trackingArea {
                addTrackingArea(trackingArea)
            }
        }

        override func mouseEntered(with event: NSEvent) {
            super.mouseEntered(with: event)
            isHovered = true
            showControls()
        }

        override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            isHovered = false
            hideControls()
        }

        private func showControls() {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.allowsImplicitAnimation = true
                controlsContainer.animator().alphaValue = 1.0
                closeButton.animator().alphaValue = 1.0
                returnButton.animator().alphaValue = 1.0
            }
        }

        private func hideControls() {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.allowsImplicitAnimation = true
                controlsContainer.animator().alphaValue = 0.0
                closeButton.animator().alphaValue = 0.0
                returnButton.animator().alphaValue = 0.0
            }
        }

        func setCloseAction(_ action: @escaping () -> Void) {
            closeButton.target = self
            closeButton.action = #selector(handleClose)
            self.closeAction = action
        }

        func setReturnAction(_ action: @escaping () -> Void) {
            returnButton.target = self
            returnButton.action = #selector(handleReturn)
            self.returnAction = action
        }

        func setPlayPauseAction(_ action: @escaping () -> Void) {
            playPauseButton.target = self
            playPauseButton.action = #selector(handlePlayPause)
            self.playPauseAction = action
        }

        func updatePlayPauseState(isPlaying: Bool) {
            self.isPlaying = isPlaying
            let imageName = isPlaying ? "pause.fill" : "play.fill"
            playPauseButton.image = NSImage(systemSymbolName: imageName, accessibilityDescription: isPlaying ? "Pause" : "Play")
        }

        private var closeAction: (() -> Void)?
        private var returnAction: (() -> Void)?
        private var playPauseAction: (() -> Void)?

        @objc private func handleClose() {
            closeAction?()
        }

        @objc private func handleReturn() {
            returnAction?()
        }

        @objc private func handlePlayPause() {
            playPauseAction?()
        }
    }

    // Window delegate to handle close event
    private class PiPWindowDelegate: NSObject, NSWindowDelegate {
        private var hasHandledClose = false

        func windowWillClose(_ notification: Notification) {
            guard !hasHandledClose else {
                return
            }
            hasHandledClose = true

            // Guard against double-close by checking if view still exists
            guard MPVPiPWindowManager.shared.mpvView != nil else {
                return
            }
            // Restore the video view to the main window
            MPVPiPWindowManager.shared.restoreVideoView()
        }

        deinit {
        }
    }
}
#endif

#if DEBUG && canImport(PreviewsMacros)
#Preview {
    PlayerView(item: MediaItem(
        id: "plex:1",
        title: "Sample Title",
        type: "movie",
        thumb: nil,
        art: nil,
        year: 2024,
        rating: 8.1,
        duration: 7200000,
        viewOffset: nil,
        summary: "A minimal player preview",
        grandparentTitle: nil,
        grandparentThumb: nil,
        grandparentArt: nil,
        parentIndex: nil,
        index: nil
    ))
}
#endif
