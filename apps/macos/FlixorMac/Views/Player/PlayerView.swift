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

    // Playback is fixed to MPV on macOS.
    private var playerBackend: PlayerBackend { .mpv }

    private init(resolvedItem: MediaItem, viewModel: PlayerViewModel) {
        self.item = resolvedItem
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    init(item: MediaItem) {
        self.init(resolvedItem: item, viewModel: PlayerViewModel(item: item))
    }

    /// Initialize with an offline (downloaded) media item
    init(offlineItem: OfflineMediaItem) {
        // Create a minimal MediaItem from the offline item
        let item = MediaItem(
            id: offlineItem.ratingKey,
            title: offlineItem.title,
            type: offlineItem.type,
            thumb: nil,
            art: nil,
            year: offlineItem.year,
            rating: nil,
            duration: nil,
            viewOffset: nil,
            summary: nil,
            grandparentTitle: offlineItem.grandparentTitle,
            grandparentThumb: nil,
            grandparentArt: nil,
            grandparentRatingKey: offlineItem.grandparentRatingKey,
            parentIndex: offlineItem.parentIndex,
            index: offlineItem.index,
            parentRatingKey: nil,
            parentTitle: nil,
            leafCount: nil,
            viewedLeafCount: nil
        )
        self.init(
            resolvedItem: item,
            viewModel: PlayerViewModel(offlineFilePath: offlineItem.filePath, title: offlineItem.displayTitle)
        )
    }

    init(destination: PlayerDestination) {
        switch destination {
        case .plex(let item):
            self.init(item: item)
        case .offline(let offlineItem):
            self.init(offlineItem: offlineItem)
        case .stream(let streamItem):
            let item = MediaItem(
                id: "stream:\(streamItem.contentKey)",
                title: streamItem.mediaType == .episode ? (streamItem.episodeTitle ?? streamItem.title) : streamItem.title,
                type: streamItem.mediaType == .movie ? "movie" : "episode",
                thumb: streamItem.posterURL,
                art: streamItem.backdropURL,
                year: nil,
                rating: nil,
                duration: nil,
                viewOffset: streamItem.resumePositionMs,
                summary: nil,
                grandparentTitle: streamItem.mediaType == .episode ? streamItem.title : nil,
                grandparentThumb: streamItem.posterURL,
                grandparentArt: streamItem.backdropURL,
                grandparentRatingKey: nil,
                parentIndex: streamItem.seasonNumber,
                index: streamItem.episodeNumber,
                parentRatingKey: nil,
                parentTitle: nil,
                leafCount: nil,
                viewedLeafCount: nil
            )
            self.init(resolvedItem: item, viewModel: PlayerViewModel(streamItem: streamItem))
        }
    }

    private var pipDisplayTitle: String {
        if item.type == "episode",
           let showName = item.grandparentTitle,
           item.parentIndex != nil,
           item.index != nil {
            return showName
        }
        return item.title
    }

    private var pipDisplaySubtitle: String? {
        if item.type == "episode",
           let seasonNum = item.parentIndex,
           let episodeNum = item.index {
            return "S\(seasonNum)E\(episodeNum) • \(item.title)"
        }
        if let year = item.year {
            return String(year)
        }
        return nil
    }

    private var pipAspectRatio: CGSize? {
        guard let width = viewModel.sourceWidth,
              let height = viewModel.sourceHeight,
              width > 0,
              height > 0 else {
            return nil
        }

        return CGSize(width: width, height: height)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Video Player - Switch based on backend
            Group {
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

            // Performance Overlay (top-left corner)
            if viewModel.showPerformanceOverlay, let stats = viewModel.performanceStats {
                VStack {
                    HStack {
                        PerformanceOverlayView(stats: stats)
                            .padding(.leading, 20)
                            .padding(.top, 60)
                        Spacer()
                    }
                    Spacer()
                }
                .transition(.opacity)
                .allowsHitTesting(false)
            }

            // Skip Intro Button - Plezy style
            if let marker = viewModel.currentMarker, marker.type.lowercased() == "intro" {
                SkipIntroButton(viewModel: viewModel, marker: marker)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            // Next Episode Overlay - Plezy style
            if let countdown = viewModel.nextEpisodeCountdown, let nextEp = viewModel.nextEpisode {
                NextEpisodeOverlay(
                    episode: nextEp,
                    countdown: countdown,
                    onCancel: { viewModel.cancelCountdown() },
                    onPlayNow: { viewModel.playNext() }
                )
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .onDisappear {
            // Cancel any pending hide controls task FIRST to prevent cursor hiding after dismiss
            hideControlsTask?.cancel()
            hideControlsTask = nil

            viewModel.onDisappear()
            stopMouseTracking()
            stopKeyboardMonitoring()
            PlaybackCommandState.shared.isPlayerActive = false
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
            PlaybackCommandState.shared.isPlayerActive = true

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
                    case .downloads: router.downloadsPath.append(nextItem)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mpvPiPDidClose)) { _ in
            isPiPActive = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .togglePlayPause)) { _ in
            viewModel.togglePlayPause()
        }
        .onReceive(NotificationCenter.default.publisher(for: .skipForward)) { _ in
            viewModel.skip(seconds: seekSeconds(large: false))
        }
        .onReceive(NotificationCenter.default.publisher(for: .skipBackward)) { _ in
            viewModel.skip(seconds: -seekSeconds(large: false))
        }
        .onReceive(NotificationCenter.default.publisher(for: .togglePictureInPicture)) { _ in
            toggleMPVPiP()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mpvPiPRequestedPlayerClose)) { _ in
            viewModel.stopPlayback()
            dismiss()
        }
        .onChange(of: viewModel.isPlaying) { isPlaying in
            MPVPiPWindowManager.shared.updatePlaybackState(isPlaying: isPlaying)
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

    /// Seek step from the profile's Player settings (Small Seek / Large Seek).
    private func seekSeconds(large: Bool) -> TimeInterval {
        let value = large ? UserDefaults.standard.seekTimeLarge : UserDefaults.standard.seekTimeSmall
        return TimeInterval(max(1, value))
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

        case 123: // Left arrow (Shift = large seek)
            viewModel.skip(seconds: -seekSeconds(large: event.modifierFlags.contains(.shift)))
            return true

        case 124: // Right arrow (Shift = large seek)
            viewModel.skip(seconds: seekSeconds(large: event.modifierFlags.contains(.shift)))
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
            switch characters {
            case "m":
                viewModel.toggleMute()
                return true
            case "p":
                toggleMPVPiP()
                return true
            case "f":
                toggleFullScreen()
                return true
            case "i":
                // Toggle performance stats overlay
                viewModel.togglePerformanceOverlay()
                return true
            case "[":
                // Previous chapter
                viewModel.previousChapter()
                return true
            case "]":
                // Next chapter
                viewModel.nextChapter()
                return true
            default:
                return false
            }
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

        MPVPiPWindowManager.shared.togglePiP(
            mpvViewController: mpvViewController,
            stateBinding: $isPiPActive,
            title: pipDisplayTitle,
            subtitle: pipDisplaySubtitle,
            aspectRatio: pipAspectRatio,
            isPlaying: viewModel.isPlaying
        )
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
        if let controller = AVPictureInPictureController(playerLayer: playerLayer) {
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
    @State private var showChaptersPanel = false

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
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    panelContent
                }
            }
        }
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Episodes")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().background(Color.white.opacity(0.1))

            // Episodes List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(episodes) { episode in
                            EpisodeListRow(
                                episode: episode,
                                isCurrentEpisode: episode.ratingKey == currentEpisodeKey,
                                onSelect: { onSelectEpisode(episode) }
                            )
                            .id(episode.ratingKey)
                        }
                    }
                    .padding(8)
                }
                .onAppear {
                    proxy.scrollTo(currentEpisodeKey, anchor: .center)
                }
            }
            .frame(maxHeight: 350)
        }
        .frame(width: 360)
        .background(Color.black.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
        .padding(.trailing, 32)
        .padding(.bottom, 140)
    }
}

private struct EpisodeListRow: View {
    let episode: EpisodeMetadata
    let isCurrentEpisode: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Episode number with progress indicator
                ZStack {
                    Circle()
                        .fill(progressColor)
                        .frame(width: 32, height: 32)

                    if let progress = episode.progressPercent, progress > 0, progress < 95 {
                        Circle()
                            .trim(from: 0, to: CGFloat(progress) / 100.0)
                            .stroke(Color.accentColor, lineWidth: 2)
                            .frame(width: 32, height: 32)
                            .rotationEffect(.degrees(-90))
                    }

                    if let index = episode.index {
                        Text("\(index)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isCurrentEpisode ? .white : .white.opacity(0.8))
                    }
                }

                // Thumbnail
                ZStack {
                    if let thumbPath = episode.thumb,
                       let imageURL = ImageService.shared.plexImageURL(path: thumbPath, width: 200, height: 112) {
                        CachedAsyncImage(url: imageURL)
                            .frame(width: 100, height: 56)
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 100, height: 56)
                    }

                    // Hover play overlay
                    if isHovered {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.black.opacity(0.4))
                            .frame(width: 100, height: 56)

                        Image(systemName: "play.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 100, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 4))

                // Episode info
                VStack(alignment: .leading, spacing: 3) {
                    Text(episode.title)
                        .font(.system(size: 13, weight: isCurrentEpisode ? .semibold : .regular))
                        .foregroundStyle(isCurrentEpisode ? .white : .white.opacity(0.85))
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if let duration = episode.duration {
                            Text("\(duration / 60000) min")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.5))
                        }

                        if let progress = episode.progressPercent, progress >= 95 {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.green.opacity(0.8))
                        }
                    }
                }

                Spacer()

                if isCurrentEpisode {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isCurrentEpisode ? Color.white.opacity(0.1) : (isHovered ? Color.white.opacity(0.05) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var progressColor: Color {
        if let progress = episode.progressPercent {
            if progress >= 95 {
                return Color.accentColor.opacity(0.3)
            } else if progress > 0 {
                return Color.white.opacity(0.15)
            }
        }
        return Color.white.opacity(0.1)
    }
}

// MARK: - Audio & Subtitles Combined Modal

private struct AudioSubtitlesModal: View {
    @ObservedObject var viewModel: PlayerViewModel
    let onClose: () -> Void

    @State private var selectedTab: Int = 0 // 0 = Audio, 1 = Subtitles, 2 = Sources

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    modalContent
                }
            }
        }
    }

    private var modalContent: some View {
        VStack(spacing: 0) {
            // Tab Header
            HStack(spacing: 0) {
                TabButton(title: "Audio", isSelected: selectedTab == 0) { selectedTab = 0 }
                TabButton(title: "Subtitles", isSelected: selectedTab == 1) { selectedTab = 1 }
                if viewModel.canSwitchStreamSources {
                    TabButton(title: "Sources", isSelected: selectedTab == 2) { selectedTab = 2 }
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)

            Divider().background(Color.white.opacity(0.1)).padding(.top, 8)

            // Tab Content
            if selectedTab == 0 {
                AudioTabContent(viewModel: viewModel)
            } else if selectedTab == 1 {
                SubtitlesTabContent(viewModel: viewModel)
            } else {
                SourcesTabContent(viewModel: viewModel)
            }
        }
        .frame(width: 340)
        .background(Color.black.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
        .padding(.trailing, 32)
        .padding(.bottom, 140)
    }
}

private struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isSelected ? Color.white.opacity(0.1) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct AudioTabContent: View {
    @ObservedObject var viewModel: PlayerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Track Selection
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(viewModel.availableAudioTracks, id: \.id) { track in
                        TrackRow(
                            title: track.displayName,
                            isSelected: track.id == viewModel.currentAudioTrackId
                        ) {
                            viewModel.setAudioTrack(track.id)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 150)

            Divider().background(Color.white.opacity(0.1))

            // Audio Sync
            SyncOffsetControl(
                label: "Audio Sync",
                value: viewModel.audioDelay,
                onDecrement: { viewModel.setAudioDelay(max(-2.0, viewModel.audioDelay - 0.05)) },
                onIncrement: { viewModel.setAudioDelay(min(2.0, viewModel.audioDelay + 0.05)) },
                onReset: { viewModel.setAudioDelay(0) }
            )
            .padding(12)
        }
    }
}

private struct SubtitlesTabContent: View {
    @ObservedObject var viewModel: PlayerViewModel
    @State private var showStyling = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Track Selection
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(spacing: 2) {
                        TrackRow(title: "Off", isSelected: viewModel.currentSubtitleTrackId == nil && viewModel.selectedExternalSubtitleId == nil) {
                            viewModel.disableSubtitles()
                        }

                        ForEach(viewModel.availableSubtitleTracks, id: \.id) { track in
                            TrackRow(
                                title: track.displayName,
                                isSelected: track.id == viewModel.currentSubtitleTrackId && viewModel.selectedExternalSubtitleId == nil
                            ) {
                                viewModel.setSubtitleTrack(track.id)
                            }
                        }
                    }

                    if !viewModel.availableExternalSubtitleOptions.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("External")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)

                            ForEach(viewModel.availableExternalSubtitleOptions) { subtitle in
                                TrackRow(
                                    title: "\(subtitle.lang.uppercased()) • \(subtitle.addonName ?? "Stremio")",
                                    isSelected: subtitle.id == viewModel.selectedExternalSubtitleId
                                ) {
                                    viewModel.loadExternalSubtitle(subtitle)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 150)

            Divider().background(Color.white.opacity(0.1))

            // Subtitle Sync
            SyncOffsetControl(
                label: "Subtitle Sync",
                value: viewModel.subtitleDelay,
                onDecrement: { viewModel.setSubtitleDelay(max(-2.0, viewModel.subtitleDelay - 0.05)) },
                onIncrement: { viewModel.setSubtitleDelay(min(2.0, viewModel.subtitleDelay + 0.05)) },
                onReset: { viewModel.setSubtitleDelay(0) }
            )
            .padding(.horizontal, 12)
            .padding(.top, 12)

            // Styling Toggle
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showStyling.toggle() } }) {
                HStack {
                    Text("Subtitle Styling")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    Image(systemName: showStyling ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if showStyling {
                SubtitleStylingControls(viewModel: viewModel)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
    }
}

private struct SourcesTabContent: View {
    @ObservedObject var viewModel: PlayerViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(viewModel.availableStremioSources) { source in
                    Button(action: { viewModel.switchStreamSource(source) }) {
                        HStack(spacing: 10) {
                            Image(systemName: source.id == viewModel.currentStremioSourceId ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 16))
                                .foregroundStyle(source.id == viewModel.currentStremioSourceId ? Color.accentColor : .white.opacity(0.3))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.title ?? source.name ?? "Source")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(source.addonName ?? "Stremio")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if let quality = source.quality {
                                Text(quality.uppercased())
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.16), in: Capsule())
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(source.id == viewModel.currentStremioSourceId ? Color.white.opacity(0.08) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(maxHeight: 180)
    }
}

private struct TrackRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Color.accentColor : .white.opacity(0.3))

                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.7))
                    .lineLimit(1)

                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(isSelected ? Color.white.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

private struct SyncOffsetControl: View {
    let label: String
    let value: Double
    let onDecrement: () -> Void
    let onIncrement: () -> Void
    let onReset: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.8))

            Spacer()

            HStack(spacing: 8) {
                // Decrement button
                Button(action: onDecrement) {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                // Value display (tappable to reset)
                Button(action: onReset) {
                    Text(String(format: "%+.0fms", value * 1000))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(value == 0 ? .white.opacity(0.6) : .orange)
                        .frame(width: 70)
                }
                .buttonStyle(.plain)
                .help("Click to reset")

                // Increment button
                Button(action: onIncrement) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct SubtitleStylingControls: View {
    @ObservedObject var viewModel: PlayerViewModel

    var body: some View {
        VStack(spacing: 12) {
            // Font Size
            CompactSliderRow(
                label: "Size",
                value: "\(viewModel.subtitleFontSize)",
                sliderValue: Double(viewModel.subtitleFontSize),
                range: 30...80,
                step: 5
            ) { viewModel.setSubtitleFontSize(Int($0)) }

            // Border
            CompactSliderRow(
                label: "Border",
                value: String(format: "%.1f", viewModel.subtitleBorderSize),
                sliderValue: viewModel.subtitleBorderSize,
                range: 0...5,
                step: 0.5
            ) { viewModel.setSubtitleBorderSize($0) }

            // Background
            CompactSliderRow(
                label: "Background",
                value: "\(Int(viewModel.subtitleBackgroundOpacity * 100))%",
                sliderValue: viewModel.subtitleBackgroundOpacity,
                range: 0...1,
                step: 0.1
            ) { viewModel.setSubtitleBackgroundOpacity($0) }
        }
    }
}

private struct CompactSliderRow: View {
    let label: String
    let value: String
    let sliderValue: Double
    let range: ClosedRange<Double>
    let step: Double
    let onChange: (Double) -> Void

    @State private var localValue: Double = 0

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 70, alignment: .leading)

            Slider(value: $localValue, in: range, step: step)
                .tint(Color.accentColor)
                .onAppear { localValue = sliderValue }
                .onChange(of: localValue) { newValue in onChange(newValue) }

            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 40, alignment: .trailing)
        }
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

// MARK: - Chapters Panel

private struct ChaptersPanel: View {
    @ObservedObject var viewModel: PlayerViewModel
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    panelContent
                }
            }
        }
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Chapters")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().background(Color.white.opacity(0.1))

            // Chapters List
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(viewModel.chapters) { chapter in
                            ChapterListRow(
                                chapter: chapter,
                                isCurrent: chapter.index == viewModel.currentChapterIndex,
                                progress: calculateProgress(for: chapter)
                            ) {
                                viewModel.seekToChapter(chapter.index)
                            }
                            .id(chapter.index)
                        }
                    }
                    .padding(8)
                }
                .onAppear {
                    if let currentIndex = viewModel.currentChapterIndex {
                        proxy.scrollTo(currentIndex, anchor: .center)
                    }
                }
            }
            .frame(maxHeight: 350)
        }
        .frame(width: 320)
        .background(Color.black.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
        .padding(.trailing, 32)
        .padding(.bottom, 140)
    }

    private func calculateProgress(for chapter: MPVChapter) -> Double? {
        guard let currentIndex = viewModel.currentChapterIndex else { return nil }
        if chapter.index < currentIndex {
            return 1.0 // Completed
        } else if chapter.index == currentIndex {
            let chapterStart = chapter.time
            let nextChapterStart = viewModel.chapters.count > chapter.index + 1
                ? viewModel.chapters[chapter.index + 1].time
                : viewModel.duration
            let chapterDuration = nextChapterStart - chapterStart
            guard chapterDuration > 0 else { return 0 }
            return min(1.0, max(0, (viewModel.currentTime - chapterStart) / chapterDuration))
        }
        return nil
    }
}

private struct ChapterListRow: View {
    let chapter: MPVChapter
    let isCurrent: Bool
    let progress: Double?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Chapter number with progress indicator
                ZStack {
                    Circle()
                        .fill(progressColor)
                        .frame(width: 28, height: 28)

                    if let progress = progress, progress < 1.0 && progress > 0 {
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(Color.accentColor, lineWidth: 2)
                            .frame(width: 28, height: 28)
                            .rotationEffect(.degrees(-90))
                    }

                    Text("\(chapter.index + 1)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isCurrent ? .white : .white.opacity(0.8))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(chapter.displayName)
                        .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? .white : .white.opacity(0.85))
                        .lineLimit(1)

                    Text(chapter.formattedTime)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()

                if isCurrent {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isCurrent ? Color.white.opacity(0.1) : (isHovered ? Color.white.opacity(0.05) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var progressColor: Color {
        if let progress = progress {
            if progress >= 1.0 {
                return Color.accentColor.opacity(0.3)
            } else if progress > 0 {
                return Color.white.opacity(0.15)
            }
        }
        return Color.white.opacity(0.1)
    }
}

// MARK: - MPV PiP Window Manager

#if os(macOS)
extension Notification.Name {
    static let mpvPiPDidClose = Notification.Name("mpvPiPDidClose")
    static let mpvPiPRequestedPlayerClose = Notification.Name("mpvPiPRequestedPlayerClose")
}

class MPVPiPWindowManager {
    static let shared = MPVPiPWindowManager()

    private enum PersistenceKeys {
        static let frame = "mpvPiPWindowFrame"
    }

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
    private var currentAspectRatio = NSSize(width: 16, height: 9)

    private init() {}

    private func fallbackFrame(for visibleFrame: NSRect, aspectRatio: NSSize) -> NSRect {
        let maxWidth = min(560.0, visibleFrame.width * 0.34)
        let width = max(360.0, maxWidth)
        let height = width * (aspectRatio.height / aspectRatio.width)

        return NSRect(
            x: visibleFrame.maxX - width - 20,
            y: visibleFrame.maxY - height - 20,
            width: width,
            height: height
        )
    }

    private func persistedFrame() -> NSRect? {
        guard let frameString = UserDefaults.standard.string(forKey: PersistenceKeys.frame) else {
            return nil
        }

        return NSRectFromString(frameString)
    }

    private func persistFrame(_ frame: NSRect) {
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: PersistenceKeys.frame)
    }

    private func normalizedFrame(_ frame: NSRect, aspectRatio: NSSize, visibleFrame: NSRect) -> NSRect {
        let safeAspect = max(aspectRatio.width, 1) / max(aspectRatio.height, 1)
        let minWidth: CGFloat = 320
        let maxWidth = max(minWidth, min(visibleFrame.width - 40, 720))

        var width = min(max(frame.width, minWidth), maxWidth)
        var height = width / safeAspect

        let maxHeight = max(180.0, visibleFrame.height - 40)
        if height > maxHeight {
            height = maxHeight
            width = height * safeAspect
        }

        var originX = frame.origin.x
        var originY = frame.origin.y

        if originX < visibleFrame.minX + 12 {
            originX = visibleFrame.minX + 12
        }
        if originY < visibleFrame.minY + 12 {
            originY = visibleFrame.minY + 12
        }
        if originX + width > visibleFrame.maxX - 12 {
            originX = visibleFrame.maxX - width - 12
        }
        if originY + height > visibleFrame.maxY - 12 {
            originY = visibleFrame.maxY - height - 12
        }

        return NSRect(x: originX, y: originY, width: width, height: height)
    }

    private func preferredAspectRatio(explicitAspectRatio: CGSize?, mpvView: MPVNSView) -> NSSize {
        if let explicitAspectRatio, explicitAspectRatio.width > 0, explicitAspectRatio.height > 0 {
            return NSSize(width: explicitAspectRatio.width, height: explicitAspectRatio.height)
        }

        let bounds = mpvView.bounds.size
        if bounds.width > 0, bounds.height > 0 {
            return NSSize(width: bounds.width, height: bounds.height)
        }

        return NSSize(width: 16, height: 9)
    }

    func enterPiP(
        mpvViewController: MPVVideoViewWrapper.MPVPiPViewController,
        stateBinding: Binding<Bool>? = nil,
        title: String,
        subtitle: String?,
        aspectRatio: CGSize?,
        isPlaying: Bool
    ) {
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

        currentAspectRatio = preferredAspectRatio(explicitAspectRatio: aspectRatio, mpvView: mpvView)

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
        let window: NSPanel
        if let existingWindow = self.pipWindow as? NSPanel {
            window = existingWindow
        } else {
            let visibleFrame = NSScreen.main?.visibleFrame ?? .zero
            let initialFrame = normalizedFrame(
                fallbackFrame(for: visibleFrame, aspectRatio: currentAspectRatio),
                aspectRatio: currentAspectRatio,
                visibleFrame: visibleFrame
            )

            window = NSPanel(
                contentRect: initialFrame,
                styleMask: [.borderless, .resizable, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )

            window.level = .floating
            window.isMovableByWindowBackground = true
            window.backgroundColor = .black
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.aspectRatio = currentAspectRatio
            window.minSize = NSSize(width: 320, height: 180)
            window.hasShadow = true
            window.isOpaque = false
            window.hidesOnDeactivate = false
            window.becomesKeyOnlyIfNeeded = true
            window.alphaValue = 0.0

            if let contentView = window.contentView {
                contentView.wantsLayer = true
                contentView.layer?.cornerRadius = 10
                contentView.layer?.masksToBounds = true
            }

            self.pipWindow = window
        }

        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let preferredFrame = persistedFrame() ?? window.frame
        let targetFrame = normalizedFrame(preferredFrame, aspectRatio: currentAspectRatio, visibleFrame: visibleFrame)
        window.aspectRatio = currentAspectRatio
        window.setFrame(targetFrame, display: true)

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
            if let layer = mpvView.layer as? MPVMetalLayer {
                layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
                layer.contentsScale = window.backingScaleFactor

                let pipBounds = CGRect(origin: .zero, size: mpvView.bounds.size)
                layer.forceUpdateForNewBounds(pipBounds)
            }

            let overlay: PiPControlOverlay
            if let existingOverlay = controlOverlay {
                overlay = existingOverlay
            } else {
                overlay = PiPControlOverlay(frame: contentView.bounds)
                overlay.translatesAutoresizingMaskIntoConstraints = false
                controlOverlay = overlay
            }

            if overlay.superview !== contentView {
                overlay.removeFromSuperview()
                contentView.addSubview(overlay, positioned: .above, relativeTo: mpvView)
                NSLayoutConstraint.activate([
                    overlay.topAnchor.constraint(equalTo: contentView.topAnchor),
                    overlay.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                    overlay.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                    overlay.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
                ])
            }

            overlay.setTitle(title, subtitle: subtitle)
            overlay.updatePlayPauseState(isPlaying: isPlaying)
            overlay.setReturnAction { [weak self] in
                self?.exitPiP()
            }
            overlay.setCloseAction { [weak self] in
                self?.exitPiP()
                NotificationCenter.default.post(name: .mpvPiPRequestedPlayerClose, object: nil)
            }
            overlay.setPlayPauseAction { [weak self] in
                self?.togglePlayPause()
            }
            overlay.setSkipBackAction { [weak self] in
                self?.skip(seconds: -10)
            }
            overlay.setSkipForwardAction { [weak self] in
                self?.skip(seconds: 10)
            }
            overlay.primeForPresentation()
        }

        // Clear flag after transition is complete
        mpvView.isPiPTransitioning = false

        // pipWindow was already set above when creating or reusing
        self.isPiPActive = true

        // Update SwiftUI state
        DispatchQueue.main.async { [weak self] in
            self?.stateBinding?.wrappedValue = true
        }

        window.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.allowsImplicitAnimation = true
            window.animator().alphaValue = 1.0
        }

        DispatchQueue.main.async {
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

        if let window = pipWindow {
            persistFrame(window.frame)
            window.alphaValue = 0.0
        }

        mpvView.isPiPTransitioning = true

        mpvView.removeFromSuperview()

        // Restore to original parent
        if let originalParent = originalParentView {
            originalParent.addSubview(mpvView)

            if !originalConstraints.isEmpty {
                NSLayoutConstraint.activate(originalConstraints)
                mpvView.translatesAutoresizingMaskIntoConstraints = false
            } else {
                mpvView.translatesAutoresizingMaskIntoConstraints = true
                mpvView.autoresizingMask = [.width, .height]
                mpvView.frame = originalParent.bounds
            }

            originalParent.layoutSubtreeIfNeeded()

            if let layer = mpvView.layer as? MPVMetalLayer,
               let mainWindow = originalParent.window {
                layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
                layer.contentsScale = mainWindow.backingScaleFactor

                let restoredBounds = CGRect(origin: .zero, size: mpvView.bounds.size)
                layer.forceUpdateForNewBounds(restoredBounds)
            }

            mpvView.isPiPTransitioning = false

            DispatchQueue.main.async {
                mpvView.layer?.setNeedsDisplay()
                mpvView.layer?.displayIfNeeded()
                mpvView.needsDisplay = true
                mpvView.display()
                originalParent.needsDisplay = true
                originalParent.needsLayout = true
                originalParent.layout()
            }
        }

        stateBinding?.wrappedValue = false

        NotificationCenter.default.post(name: .mpvPiPDidClose, object: nil)

        self.isPiPActive = false
        self.isClosing = false
        self.isCleaningUp = false

        self.originalParentView = nil
        self.originalConstraints = []
        self.stateBinding = nil

        if let window = self.pipWindow {
            window.contentView?.subviews.forEach { $0.removeFromSuperview() }
            window.delegate = nil
            window.orderOut(nil)
        }

        self.windowDelegate = nil

    }

    func togglePiP(
        mpvViewController: MPVVideoViewWrapper.MPVPiPViewController,
        stateBinding: Binding<Bool>,
        title: String,
        subtitle: String?,
        aspectRatio: CGSize?,
        isPlaying: Bool
    ) {
        if isPiPActive {
            exitPiP()
        } else {
            enterPiP(
                mpvViewController: mpvViewController,
                stateBinding: stateBinding,
                title: title,
                subtitle: subtitle,
                aspectRatio: aspectRatio,
                isPlaying: isPlaying
            )
        }
    }

    func updatePlaybackState(isPlaying: Bool) {
        controlOverlay?.updatePlayPauseState(isPlaying: isPlaying)
    }

    private func skip(seconds: Double) {
        guard let mpvController = mpvView?.mpvController else {
            return
        }

        mpvController.seekRelative(seconds: seconds)
    }

    private func togglePlayPause() {
        print("🎬 [PiP] togglePlayPause called")

        // Get the MPV controller from the view
        guard let mpvView = mpvView else {
            print("❌ [PiP] mpvView is nil")
            return
        }

        print("✅ [PiP] mpvView exists: \(mpvView)")

        guard let mpvController = mpvView.mpvController else {
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
        private let skipBackButton = NSButton()
        private let playPauseButton = NSButton()
        private let skipForwardButton = NSButton()
        private let controlsContainer = NSView()
        private let topBar = NSVisualEffectView()
        private let bottomBar = NSVisualEffectView()
        private let titleLabel = NSTextField(labelWithString: "")
        private let subtitleLabel = NSTextField(labelWithString: "")
        private var trackingArea: NSTrackingArea?
        private var isPlaying = true
        private var hideTimer: Timer?
        private var closeAction: (() -> Void)?
        private var returnAction: (() -> Void)?
        private var playPauseAction: (() -> Void)?
        private var skipBackAction: (() -> Void)?
        private var skipForwardAction: (() -> Void)?

        override var mouseDownCanMoveWindow: Bool {
            true
        }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setupUI()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func setupUI() {
            wantsLayer = true
            controlsContainer.wantsLayer = true
            controlsContainer.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.08).cgColor
            controlsContainer.alphaValue = 0.0
            controlsContainer.translatesAutoresizingMaskIntoConstraints = false
            addSubview(controlsContainer)

            configureBar(topBar)
            configureBar(bottomBar)
            controlsContainer.addSubview(topBar)
            controlsContainer.addSubview(bottomBar)

            configureSmallButton(returnButton, symbolName: "arrow.down.forward.and.arrow.up.backward", description: "Return to player")
            configureSmallButton(closeButton, symbolName: "xmark", description: "Close player")
            configureTransportButton(skipBackButton, symbolName: "gobackward.10", description: "Skip back 10 seconds", diameter: 34)
            configureTransportButton(playPauseButton, symbolName: "pause.fill", description: "Pause", diameter: 52)
            configureTransportButton(skipForwardButton, symbolName: "goforward.10", description: "Skip forward 10 seconds", diameter: 34)

            titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
            titleLabel.textColor = .white
            titleLabel.lineBreakMode = .byTruncatingTail
            titleLabel.maximumNumberOfLines = 1

            subtitleLabel.font = .systemFont(ofSize: 11, weight: .regular)
            subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.72)
            subtitleLabel.lineBreakMode = .byTruncatingTail
            subtitleLabel.maximumNumberOfLines = 1

            let titleStack = NSStackView(views: [titleLabel, subtitleLabel])
            titleStack.orientation = .vertical
            titleStack.alignment = .leading
            titleStack.spacing = 1
            titleStack.translatesAutoresizingMaskIntoConstraints = false

            let topStack = NSStackView(views: [returnButton, titleStack, closeButton])
            topStack.orientation = .horizontal
            topStack.alignment = .centerY
            topStack.spacing = 10
            topStack.translatesAutoresizingMaskIntoConstraints = false
            topBar.addSubview(topStack)

            let transportStack = NSStackView(views: [skipBackButton, playPauseButton, skipForwardButton])
            transportStack.orientation = .horizontal
            transportStack.alignment = .centerY
            transportStack.spacing = 14
            transportStack.translatesAutoresizingMaskIntoConstraints = false
            bottomBar.addSubview(transportStack)

            NSLayoutConstraint.activate([
                controlsContainer.topAnchor.constraint(equalTo: topAnchor),
                controlsContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
                controlsContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
                controlsContainer.trailingAnchor.constraint(equalTo: trailingAnchor),

                topBar.topAnchor.constraint(equalTo: controlsContainer.topAnchor, constant: 10),
                topBar.leadingAnchor.constraint(equalTo: controlsContainer.leadingAnchor, constant: 10),
                topBar.trailingAnchor.constraint(equalTo: controlsContainer.trailingAnchor, constant: -10),
                topBar.heightAnchor.constraint(equalToConstant: 44),

                bottomBar.centerXAnchor.constraint(equalTo: controlsContainer.centerXAnchor),
                bottomBar.bottomAnchor.constraint(equalTo: controlsContainer.bottomAnchor, constant: -14),
                bottomBar.heightAnchor.constraint(equalToConstant: 58),

                topStack.topAnchor.constraint(equalTo: topBar.topAnchor, constant: 8),
                topStack.bottomAnchor.constraint(equalTo: topBar.bottomAnchor, constant: -8),
                topStack.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 10),
                topStack.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -10),
                titleStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),

                transportStack.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 10),
                transportStack.bottomAnchor.constraint(equalTo: bottomBar.bottomAnchor, constant: -10),
                transportStack.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 14),
                transportStack.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -14)
            ])

            updateTrackingAreas()
            hideControls(immediately: true)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()

            if let trackingArea = trackingArea {
                removeTrackingArea(trackingArea)
            }

            trackingArea = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )

            if let trackingArea = trackingArea {
                addTrackingArea(trackingArea)
            }
        }

        override func mouseEntered(with event: NSEvent) {
            super.mouseEntered(with: event)
            showControls(resetAutoHide: true)
        }

        override func mouseMoved(with event: NSEvent) {
            super.mouseMoved(with: event)
            showControls(resetAutoHide: true)
        }

        override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            scheduleHide(after: 0.45)
        }

        private func configureBar(_ view: NSVisualEffectView) {
            view.material = .hudWindow
            view.blendingMode = .withinWindow
            view.state = .active
            view.wantsLayer = true
            view.layer?.cornerRadius = 14
            view.layer?.masksToBounds = true
            view.translatesAutoresizingMaskIntoConstraints = false
        }

        private func configureSmallButton(_ button: NSButton, symbolName: String, description: String) {
            configureTransportButton(button, symbolName: symbolName, description: description, diameter: 28)
            button.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
        }

        private func configureTransportButton(_ button: NSButton, symbolName: String, description: String, diameter: CGFloat) {
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
            button.isBordered = false
            button.bezelStyle = .shadowlessSquare
            button.imagePosition = .imageOnly
            button.contentTintColor = .white
            button.imageScaling = .scaleProportionallyDown
            button.translatesAutoresizingMaskIntoConstraints = false
            button.wantsLayer = true
            button.layer?.cornerRadius = diameter / 2
            button.layer?.backgroundColor = NSColor.white.withAlphaComponent(symbolName == "pause.fill" ? 0.18 : 0.10).cgColor
            button.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
            button.layer?.borderWidth = 1
            button.widthAnchor.constraint(equalToConstant: diameter).isActive = true
            button.heightAnchor.constraint(equalToConstant: diameter).isActive = true
        }

        private func showControls(resetAutoHide: Bool) {
            hideTimer?.invalidate()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.allowsImplicitAnimation = true
                controlsContainer.animator().alphaValue = 1.0
            }
            if resetAutoHide {
                scheduleHide(after: 2.2)
            }
        }

        private func hideControls(immediately: Bool = false) {
            hideTimer?.invalidate()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = immediately ? 0.0 : 0.2
                context.allowsImplicitAnimation = true
                controlsContainer.animator().alphaValue = 0.0
            }
        }

        private func scheduleHide(after delay: TimeInterval) {
            hideTimer?.invalidate()
            hideTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                self?.hideControls()
            }
        }

        func primeForPresentation() {
            showControls(resetAutoHide: true)
        }

        func setTitle(_ title: String, subtitle: String?) {
            titleLabel.stringValue = title
            subtitleLabel.stringValue = subtitle ?? ""
            subtitleLabel.isHidden = subtitle == nil || subtitle?.isEmpty == true
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

        func setSkipBackAction(_ action: @escaping () -> Void) {
            skipBackButton.target = self
            skipBackButton.action = #selector(handleSkipBack)
            self.skipBackAction = action
        }

        func setSkipForwardAction(_ action: @escaping () -> Void) {
            skipForwardButton.target = self
            skipForwardButton.action = #selector(handleSkipForward)
            self.skipForwardAction = action
        }

        func updatePlayPauseState(isPlaying: Bool) {
            self.isPlaying = isPlaying
            let imageName = isPlaying ? "pause.fill" : "play.fill"
            playPauseButton.image = NSImage(systemSymbolName: imageName, accessibilityDescription: isPlaying ? "Pause" : "Play")
            playPauseButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(isPlaying ? 0.18 : 0.24).cgColor
        }

        @objc private func handleClose() {
            showControls(resetAutoHide: false)
            closeAction?()
        }

        @objc private func handleReturn() {
            showControls(resetAutoHide: false)
            returnAction?()
        }

        @objc private func handlePlayPause() {
            showControls(resetAutoHide: true)
            playPauseAction?()
        }

        @objc private func handleSkipBack() {
            showControls(resetAutoHide: true)
            skipBackAction?()
        }

        @objc private func handleSkipForward() {
            showControls(resetAutoHide: true)
            skipForwardAction?()
        }

        deinit {
            hideTimer?.invalidate()
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

        func windowDidMove(_ notification: Notification) {
            if let window = notification.object as? NSWindow {
                MPVPiPWindowManager.shared.persistFrame(window.frame)
            }
        }

        func windowDidEndLiveResize(_ notification: Notification) {
            if let window = notification.object as? NSWindow {
                MPVPiPWindowManager.shared.persistFrame(window.frame)
            }
        }
    }
}
#endif

// MARK: - Skip Intro Button (Plezy Style)

private struct SkipIntroButton: View {
    @ObservedObject var viewModel: PlayerViewModel
    let marker: PlayerMarker

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button(action: {
                    viewModel.skipMarker()
                }) {
                    HStack(spacing: 8) {
                        if let countdown = viewModel.autoSkipCountdown, countdown > 0 {
                            Text("Skip Intro (\(countdown))")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.black)
                        } else {
                            Text("Skip Intro")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.black)
                        }
                        Image(systemName: "forward.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.black)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 24)
                .padding(.bottom, 115)
            }
        }
    }
}

// MARK: - Next Episode Overlay (Plezy Style)

private struct NextEpisodeOverlay: View {
    let episode: EpisodeMetadata
    let countdown: Int
    let onCancel: () -> Void
    let onPlayNow: () -> Void

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 12) {
                    // Header
                    Text("Next Episode")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))

                    // Episode info
                    if let parentIndex = episode.parentIndex, let index = episode.index {
                        Text("S\(parentIndex) E\(index) · \(episode.title)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                    } else {
                        Text(episode.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                    }

                    // Action buttons
                    HStack(spacing: 8) {
                        // Cancel button (outlined)
                        Button(action: onCancel) {
                            Text("Cancel")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)

                        // Play button (filled white with countdown)
                        Button(action: onPlayNow) {
                            HStack(spacing: 4) {
                                if countdown > 0 {
                                    Text("\(countdown)")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.black)
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.black)
                                } else {
                                    Text("Play Now")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.black)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
                .frame(width: 320)
                .background(Color.black.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.trailing, 24)
                .padding(.bottom, 100)
            }
        }
    }
}

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
