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
    @State private var isCursorHidden = false
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
            if viewModel.showPerformanceOverlay, let stats = viewModel.performanceStats {
                VStack {
                    HStack {
                        PerformanceOverlayView(stats: stats)
                            .padding(.leading, DS.Space.s20)
                            .padding(.top, DS.Space.s60)
                        Spacer()
                    }
                    Spacer()
                }
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
            viewModel.isLeavingPlayer = false
            showControls = true
            scheduleHideControls()
            startMouseTracking()
            startKeyboardMonitoring()
            PlaybackCommandState.shared.isPlayerActive = true

            // Setup navigation callbacks (next episode, sources picker)
            viewModel.onPlayNext = { nextItem in
                leavePlayerAndNavigate(to: nextItem)
            }
            viewModel.onOpenStremioSources = { destination in
                leavePlayerAndNavigate(to: destination)
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
    private func leavePlayerAndNavigate<Destination: Hashable>(to destination: Destination) {
        dismiss()
        // Small delay to ensure dismiss completes
        let router = router
        let selectedTab = mainViewState.selectedTab
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
