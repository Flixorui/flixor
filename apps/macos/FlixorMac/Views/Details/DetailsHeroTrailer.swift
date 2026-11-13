//
//  DetailsHeroTrailer.swift
//  FlixorMac
//
//  Inline hero trailer: once the details page has been idle for a few seconds,
//  the title's best YouTube trailer (TrailerService) plays muted behind the hero
//  (natively via TrailerPlayer, or in the YouTube embed when no direct stream is found)
//  and crossfades over the backdrop. It pauses when the hero is scrolled away,
//  the window loses focus, the tab is switched or a sheet is up, resumes when
//  those clear, and is torn down when the page disappears (e.g. playback starts).
//  Never autoplays with Reduce Motion on. Settings: UserDefaults+DetailsHero.
//

import SwiftUI
import Combine

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
    @Published private(set) var player: TrailerPlayer?

    /// Seconds the page must be idle before the trailer starts.
    static let idleDelay: Double = 2.5
    /// With the YouTube embed fallback, stop this many seconds before the end so
    /// its end screens never show.
    private static let endScreenMargin: Double = 8

    private var trailer: Trailer?
    private var conditions = Conditions()
    private var idleTask: Task<Void, Never>?
    private var keyTask: Task<Void, Never>?
    private var playerCancellables = Set<AnyCancellable>()

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
        trailer = nil
        keyTask?.cancel()
        guard isEnabled, let tmdbId, let id = Int(tmdbId) else { return }
        let mediaType: TMDBMediaType = mediaKind == "tv" ? .tv : .movie
        keyTask = Task { [weak self] in
            let best = await TrailerService.shared.bestTrailer(tmdbId: id, mediaType: mediaType)
            guard !Task.isCancelled, let self else { return }
            self.trailer = best
            // Resolve the YouTube stream while the idle timer runs (Apple TV
            // trailers are direct streams already).
            if let best, !best.isDirect { YouTubeStreamExtractor.shared.prefetch(best.key) }
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
                if trailer != nil, idleTask == nil { armIdleTimer() }
            case .paused:
                phase = .loading
                player?.play()
            default:
                break
            }
        } else {
            idleTask?.cancel()
            idleTask = nil
            if phase == .playing || phase == .loading {
                phase = player == nil ? .idle : .paused
                player?.pause()
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
        guard let trailer, player == nil else { return }
        isMuted = UserDefaults.standard.detailsHeroTrailerStartsMuted

        // 1080p is plenty behind the hero text; 4K is kept for the full-screen
        // trailer. Buffer a little ahead only, in case the page is left.
        var options = TrailerPlayer.Options()
        options.forwardBufferSeconds = 20
        let newPlayer = TrailerPlayer(trailer: trailer, muted: isMuted, options: options)
        player = newPlayer
        phase = .loading

        newPlayer.$status
            .receive(on: RunLoop.main)
            .sink { [weak self, weak newPlayer] status in
                guard let self, let newPlayer, newPlayer === self.player else { return }
                switch status {
                case .ready:
                    if self.canPlay { newPlayer.play() } else { self.phase = .paused }
                case .failed:
                    self.teardown()
                    self.phase = .failed
                case .resolving:
                    break
                }
            }
            .store(in: &playerCancellables)

        newPlayer.$playback
            .receive(on: RunLoop.main)
            .sink { [weak self, weak newPlayer] state in
                guard let self, let newPlayer, newPlayer === self.player else { return }
                switch state {
                case .playing:
                    if self.canPlay {
                        self.phase = .playing
                    } else {
                        self.phase = .paused
                        newPlayer.pause()
                    }
                case .ended:
                    self.phase = .ended
                case .idle, .paused:
                    break
                }
            }
            .store(in: &playerCancellables)

        // Only the YouTube embed shows end screens; the native video plays to
        // the real end.
        newPlayer.$currentTime
            .receive(on: RunLoop.main)
            .sink { [weak self, weak newPlayer] time in
                guard let self, let newPlayer, newPlayer === self.player,
                      newPlayer.usesEmbed, self.phase == .playing,
                      let duration = newPlayer.duration, duration > Self.endScreenMargin * 3 else { return }
                if time >= duration - Self.endScreenMargin {
                    self.phase = .ended
                    newPlayer.pause()
                }
            }
            .store(in: &playerCancellables)

        newPlayer.load()
    }

    func toggleMute() {
        guard let player else { return }
        isMuted.toggle()
        player.setMuted(isMuted)
    }

    /// Plays again from the start (works after it ended, or while it plays).
    func replay() {
        guard let player else { return }
        phase = .loading
        player.restart(play: canPlay)
        if !canPlay { phase = .paused }
    }

    /// Stops playback and releases the player.
    func teardown() {
        idleTask?.cancel()
        idleTask = nil
        playerCancellables.removeAll()
        player?.stop()
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

    /// Slight zoom so the embed fallback's title strip and logo fall outside the clip.
    private static let embedOverscan: CGFloat = 1.18

    var body: some View {
        ZStack {
            if let player = controller.player {
                TrailerVideoSurface(player: player, fill: true, embedOverscan: Self.embedOverscan)
                    .frame(width: size.width, height: size.height)
                    .opacity(controller.phase == .playing ? 1 : 0)
                    .animation(reduceMotion ? nil : DS.Motion.cinematic, value: controller.phase)
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
