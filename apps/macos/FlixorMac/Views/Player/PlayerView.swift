//
//  PlayerView.swift
//  FlixorMac
//
//  Player screen shell: state, lifecycle, mouse/cursor handling and overlay composition
//

import SwiftUI

struct PlayerView: View {
    let item: MediaItem
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var router: NavigationRouter
    @EnvironmentObject private var mainViewState: MainViewState
    @StateObject var viewModel: PlayerViewModel
    @State private var showControls = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State var isFullScreen = false
    @State private var lastMousePosition: CGPoint = .zero
    @State private var mouseMovementTimer: Timer?
    @State private var isPiPActive = false
    @State private var mpvPiPViewController: NSViewController?
    @State var keyboardMonitor: Any?
    /// A panel in the controls is open: keep the controls up (the panel lives inside them).
    @State var isControlsPanelOpen = false
    /// Incremented to ask the controls to close their open panel (Esc).
    @State var closePanelsRequest = 0

    // Hold-Space speed boost (see PlayerView+Keyboard.swift)
    @State var spaceHoldTask: Task<Void, Never>?
    @State var isSpaceHeld = false
    @State var spaceBoostEngaged = false

    // Keyboard feedback and the shortcuts overlay (see PlayerView+Keyboard.swift)
    @State var keyboardFeedback: String?
    @State var keyboardFeedbackTask: Task<Void, Never>?
    @State var showShortcutsOverlay = false

    /// `makeViewModel` runs inside StateObject's autoclosure, so only the instance
    /// SwiftUI keeps is built; SwiftUI may call `init` many times.
    private init(resolvedItem: MediaItem, makeViewModel: @escaping () -> PlayerViewModel) {
        self.item = resolvedItem
        _viewModel = StateObject(wrappedValue: makeViewModel())
    }

    init(item: MediaItem) {
        self.init(resolvedItem: item, makeViewModel: { PlayerViewModel(item: item) })
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
        let filePath = offlineItem.filePath
        let title = offlineItem.displayTitle
        self.init(
            resolvedItem: item,
            makeViewModel: { PlayerViewModel(offlineFilePath: filePath, title: title) }
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
                grandparentTitle: streamItem.mediaType == .episode ? (streamItem.showTitle ?? streamItem.title) : nil,
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
            self.init(resolvedItem: item, makeViewModel: { PlayerViewModel(streamItem: streamItem) })
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

            // Video Player (MPV)
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
                PlayerLoadingOverlay(viewModel: viewModel)
            }

            // Error State
            if let error = viewModel.error {
                PlayerErrorOverlay(
                    message: error,
                    onClose: {
                        viewModel.stopPlayback()
                        dismiss()
                    },
                    onRetry: {
                        viewModel.retry()
                    },
                    onChooseSource: canChooseAnotherSource ? { viewModel.openSourcesPicker() } : nil
                )
            }

            // Controls Overlay
            if showControls && !viewModel.isLoading && viewModel.error == nil {
                PlayerControlsView(
                    viewModel: viewModel,
                    isFullScreen: $isFullScreen,
                    isPiPActive: isPiPActive,
                    mpvPiPViewController: mpvPiPViewController,
                    onClose: {
                        // Stop playback BEFORE dismissing
                        viewModel.stopPlayback()
                        dismiss()
                    },
                    onToggleFullScreen: toggleFullScreen,
                    onToggleMPVPiP: toggleMPVPiP,
                    onPanelOpenChanged: { isOpen in
                        isControlsPanelOpen = isOpen
                        if !isOpen && !viewModel.isLeavingPlayer { scheduleHideControls() }
                    },
                    closePanelsRequest: closePanelsRequest
                )
                .transition(.opacity)
            }

            // Performance Overlay (top-left corner)
            if viewModel.showPerformanceOverlay {
                PerformanceOverlayContainer(model: viewModel.statsModel)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            // Skip button for the current marker (intro, recap, credits, preview).
            // The next-episode card takes the same spot and wins when both apply.
            if let marker = viewModel.currentMarker, marker.isSkippable, !isNextEpisodeOverlayVisible {
                SkipMarkerButton(viewModel: viewModel, marker: marker)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            // Next Episode Overlay - Plezy style
            if let countdown = viewModel.nextEpisodeCountdown, let nextEp = viewModel.nextEpisode {
                NextEpisodeOverlay(
                    episode: nextEp,
                    countdown: countdown,
                    onCancel: { viewModel.userCancelledCountdown() },
                    onPlayNow: { viewModel.playNext() }
                )
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }

            // Stream engine status, 2x badge and keyboard feedback (top centre)
            PlayerStatusStack(
                status: viewModel.streamEngineStatus?.message,
                isSpeedBoostActive: viewModel.isSpeedBoostActive,
                feedback: keyboardFeedback
            )

            // Keyboard shortcuts overlay (?)
            if showShortcutsOverlay {
                PlayerShortcutsOverlay(
                    smallSeek: Int(seekSeconds(large: false)),
                    largeSeek: Int(seekSeconds(large: true)),
                    onClose: { showShortcutsOverlay = false }
                )
                .transition(.opacity)
            }
        }
        .onDisappear {
            viewModel.isLeavingPlayer = true
            // Cancel any pending hide controls task FIRST to prevent cursor hiding after dismiss
            hideControlsTask?.cancel()
            hideControlsTask = nil

            viewModel.onDisappear()
            // These closures hold the navigation state; drop them with the player.
            viewModel.onPlayNext = nil
            viewModel.onOpenStremioSources = nil
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
            // Loading starts here, once (see PlayerViewModel.start()).
            viewModel.start()
            viewModel.isLeavingPlayer = false
            showControls = true
            scheduleHideControls()
            startMouseTracking()
            startKeyboardMonitoring()
            PlaybackCommandState.shared.isPlayerActive = true

            // Setup navigation callbacks (next episode, sources picker). They capture
            // only dismiss, the router and the tab: capturing this view would capture
            // its StateObject storage and keep the view model alive.
            let dismiss = dismiss
            let router = router
            let mainViewState = mainViewState
            viewModel.onPlayNext = { nextItem in
                Self.leavePlayerAndNavigate(to: nextItem, dismiss: dismiss, router: router, selectedTab: mainViewState.selectedTab)
            }
            viewModel.onOpenStremioSources = { destination in
                Self.leavePlayerAndNavigate(to: destination, dismiss: dismiss, router: router, selectedTab: mainViewState.selectedTab)
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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            // The Space key-up goes to another app, so a held boost would stay on.
            releaseSpaceHold()
            // The pointer now belongs to another app (PlayerCursor also does this app-wide).
            PlayerCursor.show()
            // No key window while inactive, so the mouse poll had nothing to do.
            pauseMouseTracking()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard !viewModel.isLeavingPlayer else { return }
            startMouseTracking()
            // Back in front with the pointer left visible on the way out: resume idle auto-hide.
            scheduleHideControls()
        }
        .onChange(of: viewModel.isPlaying) { isPlaying in
            MPVPiPWindowManager.shared.updatePlaybackState(isPlaying: isPlaying)
        }
    }

    private var isNextEpisodeOverlayVisible: Bool {
        viewModel.nextEpisodeCountdown != nil && viewModel.nextEpisode != nil
    }

    /// Addon streams can always go back to the sources page for the same title.
    private var canChooseAnotherSource: Bool {
        viewModel.sourceKind == .stream
            && (viewModel.sourcesPickerDestination ?? viewModel.currentTitleSourcesDestination()) != nil
    }

    /// Dismisses the player, then pushes `destination` on the current tab's path.
    private static func leavePlayerAndNavigate<Destination: Hashable>(
        to destination: Destination,
        dismiss: DismissAction,
        router: NavigationRouter,
        selectedTab: NavItem
    ) {
        dismiss()
        // Small delay to ensure dismiss completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            switch selectedTab {
            case .home: router.homePath.append(destination)
            case .search: router.searchPath.append(destination)
            case .library: router.libraryPath.append(destination)
            case .myList: router.myListPath.append(destination)
            case .newPopular: router.newPopularPath.append(destination)
            case .downloads: router.downloadsPath.append(destination)
            }
        }
    }


    func toggleFullScreen() {
        #if os(macOS)
        if let window = NSApp.keyWindow {
            window.toggleFullScreen(nil)
            isFullScreen.toggle()
        }
        #endif
    }

    func toggleMPVPiP() {
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
        mouseMovementTimer?.invalidate()
        // Start a timer that checks mouse position periodically
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [self] _ in
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
        timer.tolerance = 0.02
        mouseMovementTimer = timer
        #endif
    }

    /// Stops the mouse poll while the app is inactive (restarted on activation).
    private func pauseMouseTracking() {
        mouseMovementTimer?.invalidate()
        mouseMovementTimer = nil
    }

    private func stopMouseTracking() {
        pauseMouseTracking()
        forceShowCursor() // Force show cursor when stopping tracking
    }

    private func hideCursor() {
        PlayerCursor.hide()
    }

    private func showCursor() {
        PlayerCursor.show()
    }

    private func forceShowCursor() {
        PlayerCursor.show()
        NSCursor.setHiddenUntilMouseMoves(false)
    }

    private func onMouseMoved() {
        // Show cursor on mouse movement
        showCursor()

        // Show controls on mouse movement
        withAnimation(DS.Motion.standard) {
            showControls = true
        }
        // Restart the hide timer
        scheduleHideControls()
    }

    private func scheduleHideControls() {
        hideControlsTask?.cancel()
        hideControlsTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds of inactivity
            // Double-check task wasn't cancelled, we're still playing and no panel is open
            guard !Task.isCancelled && !viewModel.isLeavingPlayer && viewModel.isPlaying && !isControlsPanelOpen else { return }

            withAnimation(DS.Motion.standard) {
                showControls = false
            }
            // Only hide cursor if task is still valid (not cancelled)
            if !Task.isCancelled {
                hideCursor()
            }
        }
    }
}

/// Hides the pointer over the playing video. `NSCursor.hide()`/`unhide()` are counted and
/// app-wide, and a hide made while another app is in front (the idle timer firing just after
/// a Cmd-Tab or a click elsewhere) leaves the pointer invisible over that app until Flixor
/// comes back. So: at most one hide is ever outstanding, it is owned here rather than in view
/// state (which can be rebuilt while the pointer is hidden), it is only made while Flixor is
/// active with the pointer over its key window, and it is given back whenever the app resigns
/// active or a window resigns key.
@MainActor
enum PlayerCursor {
    private static var isHidden = false
    private static var observers: [NSObjectProtocol] = []

    static func hide() {
        installObservers()
        guard !isHidden,
              NSApp.isActive,
              let window = NSApp.keyWindow,
              NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0) == window.windowNumber
        else { return }
        NSCursor.hide()
        isHidden = true
    }

    static func show() {
        guard isHidden else { return }
        NSCursor.unhide()
        isHidden = false
    }

    private static func installObservers() {
        guard observers.isEmpty else { return }
        let names: [Notification.Name] = [
            NSApplication.willResignActiveNotification,
            NSApplication.didResignActiveNotification,
            NSWindow.didResignKeyNotification,
        ]
        for name in names {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { show() }
            })
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
