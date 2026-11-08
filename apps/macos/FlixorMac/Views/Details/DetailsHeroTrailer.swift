//
//  DetailsHeroTrailer.swift
//  FlixorMac
//
//  Inline hero trailer: once the details page has been idle for a few seconds,
//  the title's best YouTube trailer (TrailerService) plays muted behind the hero
//  and crossfades over the backdrop. It pauses when the hero is scrolled away,
//  the window loses focus, the tab is switched or a sheet is up, resumes when
//  those clear, and is torn down when the page disappears (e.g. playback starts).
//  Never autoplays with Reduce Motion on. Settings: UserDefaults+DetailsHero.
//

import SwiftUI
import Combine
import YouTubePlayerKit

@MainActor
final class DetailsHeroTrailerController: ObservableObject {
    enum Phase: Equatable {
        /// Nothing loaded (waiting for a key, the idle delay, or conditions).
        case idle
        /// Player created, buffering behind the backdrop.
        case loading
        /// Video visible.
        case playing
        /// Paused by a condition (scrolled away, focus lost...). Backdrop shown.
        case paused
        /// Reached the end (or the end-screen zone). Backdrop shown, replay offered.
        case ended
        /// Player error (e.g. embedding disabled); don't retry for this title.
        case failed
    }

    struct Conditions: Equatable {
        var isPageVisible = false
        var isHeroVisible = true
        var isWindowFocused = true
        var isTabActive = true
        var isReduceMotion = false
        /// The in-page browse overlay covers the hero.
        var isObscured = false
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var isMuted = true
    @Published private(set) var player: YouTubePlayer?

    /// Seconds the page must be idle before the trailer starts.
    static let idleDelay: Double = 2.5
    /// Stop this many seconds before the end so YouTube end screens never show.
    private static let endScreenMargin: Double = 8

    private var videoKey: String?
    private var conditions = Conditions()
    private var idleTask: Task<Void, Never>?
    private var keyTask: Task<Void, Never>?
    private var playerCancellables = Set<AnyCancellable>()
    private var duration: Double?

    private var isEnabled: Bool { UserDefaults.standard.detailsHeroInlineTrailerEnabled }

    private var canPlay: Bool {
        isEnabled && conditions.isPageVisible && conditions.isHeroVisible
            && conditions.isWindowFocused && conditions.isTabActive && !conditions.isReduceMotion
            && !conditions.isObscured
    }

    /// Whether the hero should show the trailer controls.
    var showsControls: Bool {
        player != nil && (phase == .playing || phase == .paused || phase == .ended)
    }

    // MARK: - Title

    /// Looks up the best trailer for the loaded title and arms the idle timer.
    /// Pass nil ids to clear (e.g. while a new title loads).
    func configure(tmdbId: String?, mediaKind: String?) {
        teardown()
        phase = .idle
        videoKey = nil
        keyTask?.cancel()
        guard isEnabled, let tmdbId, let id = Int(tmdbId) else { return }
        let mediaType: TMDBMediaType = mediaKind == "tv" ? .tv : .movie
        keyTask = Task { [weak self] in
            let key = await TrailerService.shared.bestTrailerKey(tmdbId: id, mediaType: mediaType)
            guard !Task.isCancelled, let self else { return }
            self.videoKey = key
            self.evaluate()
        }
    }

    // MARK: - Conditions

    func update(_ change: (inout Conditions) -> Void) {
        var next = conditions
        change(&next)
        guard next != conditions else { return }
        let pageWentAway = conditions.isPageVisible && !next.isPageVisible
        conditions = next
        if pageWentAway {
            teardown()
        } else {
            evaluate()
        }
    }

    /// Scrolling or other interaction: restarts the idle countdown if the trailer
    /// hasn't started yet.
    func noteActivity() {
        guard phase == .idle, idleTask != nil else { return }
        armIdleTimer()
    }

    private func evaluate() {
        if canPlay {
            switch phase {
            case .idle:
                if videoKey != nil, idleTask == nil { armIdleTimer() }
            case .paused:
                phase = .loading
                Task { try? await player?.play() }
            default:
                break
            }
        } else {
            idleTask?.cancel()
            idleTask = nil
            if phase == .playing || phase == .loading {
                phase = player == nil ? .idle : .paused
                Task { try? await player?.pause() }
            }
        }
    }

    private func armIdleTimer() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.idleDelay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.idleTask = nil
            if self.canPlay, self.phase == .idle { self.start() }
        }
    }

    // MARK: - Player

    private func start() {
        guard let key = videoKey, player == nil else { return }
        isMuted = UserDefaults.standard.detailsHeroTrailerStartsMuted
        duration = nil

        let newPlayer = YouTubePlayer(
            source: .video(id: key),
            parameters: .init(
                autoPlay: false,
                loopEnabled: false,
                showControls: false,
                showFullscreenButton: false,
                keyboardControlsDisabled: true,
                showCaptions: false,
                restrictRelatedVideosToSameChannel: true
            ),
            configuration: .init(fullscreenMode: .web, allowsPictureInPictureMediaPlayback: false)
        )
        player = newPlayer
        phase = .loading

        newPlayer.statePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self, weak newPlayer] state in
                guard let self, let newPlayer, newPlayer === self.player else { return }
                switch state {
                case .ready:
                    Task {
                        if self.isMuted { try? await newPlayer.mute() }
                        if self.canPlay { try? await newPlayer.play() } else { self.phase = .paused }
                    }
                case .error:
                    self.teardown()
                    self.phase = .failed
                case .idle:
                    break
                }
            }
            .store(in: &playerCancellables)

        newPlayer.playbackStatePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self, weak newPlayer] state in
                guard let self, let newPlayer, newPlayer === self.player else { return }
                switch state {
                case .playing:
                    if self.canPlay {
                        self.phase = .playing
                    } else {
                        self.phase = .paused
                        Task { try? await newPlayer.pause() }
                    }
                case .ended:
                    self.phase = .ended
                default:
                    break
                }
            }
            .store(in: &playerCancellables)

        newPlayer.durationPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.duration = value.converted(to: .seconds).value
            }
            .store(in: &playerCancellables)

        newPlayer.currentTimePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self, weak newPlayer] time in
                guard let self, let newPlayer, newPlayer === self.player,
                      self.phase == .playing,
                      let duration = self.duration, duration > Self.endScreenMargin * 3 else { return }
                if time.converted(to: .seconds).value >= duration - Self.endScreenMargin {
                    self.phase = .ended
                    Task { try? await newPlayer.pause() }
                }
            }
            .store(in: &playerCancellables)
    }

    func toggleMute() {
        guard let player else { return }
        isMuted.toggle()
        let mute = isMuted
        Task {
            if mute { try? await player.mute() } else { try? await player.unmute() }
        }
    }

    /// Plays again from the start (works after it ended, or while it plays).
    func replay() {
        guard let player else { return }
        phase = .loading
        Task {
            try? await player.seek(to: .init(value: 0, unit: .seconds))
            if canPlay { try? await player.play() } else { phase = .paused }
        }
    }

    /// Stops playback and releases the web view.
    func teardown() {
        idleTask?.cancel()
        idleTask = nil
        playerCancellables.removeAll()
        if let player {
            Task { try? await player.stop() }
        }
        player = nil
        if phase != .failed { phase = .idle }
    }
}

// MARK: - Environment

private struct DetailsHeroTrailerKey: EnvironmentKey {
    static let defaultValue: DetailsHeroTrailerController? = nil
}

extension EnvironmentValues {
    /// Inline hero trailer controller (set by DetailsView).
    var detailsHeroTrailer: DetailsHeroTrailerController? {
        get { self[DetailsHeroTrailerKey.self] }
        set { self[DetailsHeroTrailerKey.self] = newValue }
    }
}

// MARK: - Views

/// The video layer, placed between the backdrop image and the hero gradients.
struct DetailsHeroTrailerLayer: View {
    @ObservedObject var controller: DetailsHeroTrailerController
    let size: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Slight zoom so YouTube's title strip and logo fall outside the clip.
    private static let overscan: CGFloat = 1.18

    var body: some View {
        ZStack {
            if let player = controller.player {
                YouTubePlayerView(player)
                    .frame(width: size.width * Self.overscan, height: size.height * Self.overscan)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .allowsHitTesting(false)
                    .opacity(controller.phase == .playing ? 1 : 0)
                    .animation(reduceMotion ? nil : DS.Motion.cinematic, value: controller.phase)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }
}

/// Small mute/unmute and replay buttons shown while the inline trailer is active.
struct DetailsHeroTrailerControls: View {
    @ObservedObject var controller: DetailsHeroTrailerController

    @Environment(\.flixorTheme) private var theme

    var body: some View {
        if controller.showsControls {
            HStack(spacing: DS.Space.s8) {
                if controller.phase != .ended {
                    controlButton(
                        systemImage: controller.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        label: controller.isMuted ? String(localized: "Unmute trailer") : String(localized: "Mute trailer"),
                        action: controller.toggleMute
                    )
                }
                controlButton(
                    systemImage: "arrow.counterclockwise",
                    label: String(localized: "Replay trailer"),
                    action: controller.replay
                )
            }
            .transition(.opacity)
        }
    }

    private func controlButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.flixorIcon(DS.Icon.xs, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .frame(width: 32, height: 32)
                .background(theme.scrim(DS.Opacity.scrimMedium))
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(theme.separatorStrong, lineWidth: DS.Border.thin))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}
