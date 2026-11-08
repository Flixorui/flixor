//
//  PushAppearance.swift
//  FlixorMac
//
//  Appearance animation for pages pushed onto a tab's NavigationStack
//  (details, person, browse pages). macOS 13 has no zoom navigation
//  transition, so the stack itself eases in from a slight scale and fade,
//  anchored where the user clicked (the tapped card) so the page appears to
//  grow out of it. Pushes are never delayed: the new page is in place on the
//  first frame and only its rendering animates. Pops are instant, the player
//  is not animated, and Reduce Motion turns the effect off.
//

import SwiftUI

private struct PushAppearanceModifier: ViewModifier {
    /// Number of pages on the stack (NavigationPath.count).
    let depth: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.flixorTheme) private var theme
    @ObservedObject private var playback = PlaybackCommandState.shared
    @State private var settledDepth: Int
    /// Latest depth seen, readable from the deferred animation closure.
    @State private var latestDepth: Int
    @State private var anchor: UnitPoint = .center

    private static let startScale: CGFloat = 0.97

    init(depth: Int) {
        self.depth = depth
        _settledDepth = State(initialValue: depth)
        _latestDepth = State(initialValue: depth)
    }

    /// True on the frames between a push and the end of its animation. Derived
    /// in the same body pass that sees the new depth, so the first frame of
    /// the new page already renders in its start state (no flash).
    private var isEntering: Bool {
        depth > settledDepth && !reduceMotion && !playback.isPlayerActive
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(isEntering ? Self.startScale : 1, anchor: anchor)
            .opacity(isEntering ? 0 : 1)
            // While the page fades in, fade it in over the app background
            // rather than the lighter window background. Removed without a
            // fade (identity) once the page is fully opaque.
            .background {
                if isEntering {
                    theme.background.transition(.identity)
                }
            }
            .onChange(of: depth) { newDepth in
                latestDepth = newDepth
                guard newDepth > settledDepth, !reduceMotion else {
                    settledDepth = newDepth
                    return
                }
                anchor = BackNavigationController.shared.recentClickAnchor()
                // Animate on the next turn so the start state has been committed.
                DispatchQueue.main.async {
                    // A pop or another push already happened: nothing to animate.
                    guard latestDepth == newDepth else { return }
                    withAnimation(DS.Motion.decelerate) {
                        settledDepth = newDepth
                    }
                }
            }
    }
}

extension View {
    /// Eases a NavigationStack's newly pushed page in (scale ~0.97 to 1 plus
    /// fade, anchored at the last click). `depth` is the stack's path count.
    func pushAppearance(depth: Int) -> some View {
        modifier(PushAppearanceModifier(depth: depth))
    }
}
