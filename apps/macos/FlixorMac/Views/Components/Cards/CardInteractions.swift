//
//  CardInteractions.swift
//  FlixorMac
//
//  One modifier that gives a card's artwork the shared behaviour:
//  hover scale (spring, off with Reduce Motion), the keyboard focus ring, the
//  context menu, the hover preview, and its accessibility label/hint.
//
//      artwork
//          .cardInteractions(item: item, cornerRadius: r, isHovered: $isHovered, onOpen: onTap)
//
//  Plus small shared pieces: `CardAccessibility.label(for:)` and `CardRatingBadge`.
//

import SwiftUI

struct CardInteractionsModifier: ViewModifier {
    let item: MediaItem
    let cornerRadius: CGFloat
    @Binding var isHovered: Bool
    let onOpen: (() -> Void)?
    var previewEnabled: Bool = true
    var extraMenuActions: [CardMenuAction] = []

    // Plain references (see CardNavigationContext): cards must not re-render on
    // every push, pop, tab switch or watchlist change.
    @Environment(\.cardWatchlistController) private var watchlistController
    @Environment(\.cardNavigationContext) private var navigation

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.cardFocusContext) private var focusContext
    @Environment(\.flixorTheme) private var theme

    @State private var token = UUID()
    @State private var anchor = CardAnchorBox()

    func body(content: Content) -> some View {
        content
            .overlay {
                if focusContext?.isFocusRingVisible == true {
                    RoundedRectangle(cornerRadius: cornerRadius + DS.Space.s4, style: .continuous)
                        .strokeBorder(theme.focusRing, lineWidth: DS.Border.focus)
                        .padding(-DS.Space.s4)
                        .allowsHitTesting(false)
                }
            }
            .scaleEffect(isHovered && !reduceMotion ? CardMetrics.hoverScale : 1)
            .animation(reduceMotion ? nil : DS.Motion.spring, value: isHovered)
            .background(CardAnchorView(box: anchor))
            .onHover { hovering in
                withAnimation(reduceMotion ? nil : DS.Motion.quick) {
                    isHovered = hovering
                }
                if hovering {
                    if previewEnabled { HoverPreviewController.shared.cardHoverBegan(previewRequest()) }
                } else {
                    HoverPreviewController.shared.cardHoverEnded(token: token)
                }
            }
            .onDisappear {
                HoverPreviewController.shared.cardDisappeared(token: token)
                isHovered = false
            }
            .onAppear {
                if let onOpen { focusContext?.registerOpenAction(onOpen) }
            }
            .cardContextMenu(
                item: item,
                onOpen: onOpen,
                onPlay: playAction,
                watchlistController: watchlistController,
                extraActions: extraMenuActions
            )
            .accessibilityLabel(Text(CardAccessibility.label(for: item)))
            .accessibilityHint(onOpen == nil ? Text("") : Text("Opens details"))
            .accessibilityAddTraits(.isButton)
    }

    private var playAction: (() -> Void)? {
        guard let navigation, let destination = CardActions.playDestination(for: item) else { return nil }
        let router = navigation.router
        let mainViewState = navigation.mainViewState
        return {
            HoverPreviewController.shared.dismiss(animated: false)
            router.push(destination, on: mainViewState.selectedTab)
        }
    }

    private func previewRequest() -> HoverPreviewRequest {
        HoverPreviewRequest(
            token: token,
            item: item,
            anchor: anchor,
            onOpen: onOpen,
            onPlay: playAction,
            watchlistController: watchlistController
        )
    }
}

extension View {
    /// Shared card behaviour (see CardInteractions.swift). Apply to the card's
    /// artwork (the tappable part). `previewEnabled: false` keeps everything but
    /// the hover preview.
    func cardInteractions(
        item: MediaItem,
        cornerRadius: CGFloat,
        isHovered: Binding<Bool>,
        onOpen: (() -> Void)?,
        previewEnabled: Bool = true,
        extraMenuActions: [CardMenuAction] = []
    ) -> some View {
        modifier(CardInteractionsModifier(
            item: item,
            cornerRadius: cornerRadius,
            isHovered: isHovered,
            onOpen: onOpen,
            previewEnabled: previewEnabled,
            extraMenuActions: extraMenuActions
        ))
    }
}

// MARK: - Non-observing environment

/// MainView's router and tab state, for views that only need them inside
/// actions. Reading this never subscribes to their changes, unlike
/// `@EnvironmentObject`. Equal by identity, so re-injecting it is free.
struct CardNavigationContext: Equatable {
    let router: NavigationRouter
    let mainViewState: MainViewState

    static func == (lhs: CardNavigationContext, rhs: CardNavigationContext) -> Bool {
        lhs.router === rhs.router && lhs.mainViewState === rhs.mainViewState
    }
}

private struct CardNavigationContextKey: EnvironmentKey {
    static let defaultValue: CardNavigationContext? = nil
}

private struct CardWatchlistControllerKey: EnvironmentKey {
    static let defaultValue: WatchlistController? = nil
}

extension EnvironmentValues {
    /// Set by MainView. Nil outside it (previews), where cards offer no Play.
    var cardNavigationContext: CardNavigationContext? {
        get { self[CardNavigationContextKey.self] }
        set { self[CardNavigationContextKey.self] = newValue }
    }

    /// The app's WatchlistController without observing it. Set by RootView.
    var cardWatchlistController: WatchlistController? {
        get { self[CardWatchlistControllerKey.self] }
        set { self[CardWatchlistControllerKey.self] = newValue }
    }
}

// MARK: - Accessibility

enum CardAccessibility {
    /// "Title, 2019, Movie, 40% watched" / "Show, Season 1 Episode 2, Pilot, Episode".
    static func label(for item: MediaItem) -> String {
        var parts: [String] = []
        let type = item.type.lowercased()

        switch type {
        case "episode":
            parts.append(item.grandparentTitle ?? item.title)
            if let season = item.parentIndex, let episode = item.index {
                parts.append(String(localized: "Season \(String(season)) Episode \(String(episode))"))
            }
            if item.grandparentTitle != nil { parts.append(item.title) }
        case "season":
            if let show = item.parentTitle { parts.append(show) }
            parts.append(item.title)
        default:
            parts.append(item.title)
        }

        if let year = item.year { parts.append(String(year)) }
        if let edition = item.editionTitle, !edition.isEmpty { parts.append(edition) }

        switch type {
        case "movie": parts.append("Movie")
        case "show": parts.append("TV show")
        case "season": parts.append("Season")
        case "episode": parts.append("Episode")
        default: break
        }

        if let progress = progressDescription(for: item) { parts.append(progress) }
        return parts.joined(separator: ", ")
    }

    private static func progressDescription(for item: MediaItem) -> String? {
        if let total = item.leafCount, total > 0, let viewed = item.viewedLeafCount {
            if viewed >= total { return String(localized: "Watched") }
            if viewed > 0 { return String(localized: "\(viewed) of \(total) episodes watched") }
        }
        if let duration = item.duration, duration > 0, let offset = item.viewOffset, offset > 0 {
            let percent = Int((Double(offset) / Double(duration) * 100).rounded())
            return percent >= 95 ? String(localized: "Watched") : String(localized: "\(percent)% watched")
        }
        return nil
    }
}

// MARK: - Rating badge

/// Small "★ 7.8" chip for card artwork (shown when the setting is on).
struct CardRatingBadge: View {
    let rating: Double

    @Environment(\.flixorTheme) private var theme

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            Image(systemName: "star.fill")
                .font(.flixorIcon(DS.Icon.xs - 4, weight: .bold))
                .foregroundStyle(theme.warning)
            Text(String(format: "%.1f", rating))
                .flixorFont(.micro)
                .foregroundStyle(theme.textPrimary)
        }
        .padding(.horizontal, DS.Space.s6)
        .padding(.vertical, DS.Space.s2 + 1)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.badge, style: .continuous)
                .fill(theme.scrim(DS.Opacity.scrimMedium))
        )
        .accessibilityHidden(true)
    }
}

// MARK: - Z-order

/// Draws a hovered cell above its neighbours in a stack or grid.
struct RaiseOnHoverModifier: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .onHover { isHovered = $0 }
            .zIndex(isHovered ? 1 : 0)
    }
}
