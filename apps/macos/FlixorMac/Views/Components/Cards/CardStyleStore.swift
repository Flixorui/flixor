//
//  CardStyleStore.swift
//  FlixorMac
//
//  Observable owner of the per-profile card settings (UserDefaults+Cards.swift).
//  Cards observe it so a change in Settings applies everywhere at once.
//

import Combine
import SwiftUI

@MainActor
final class CardStyleStore: ObservableObject {
    static let shared = CardStyleStore()

    private let defaults = UserDefaults.standard
    private var profileObserver: AnyCancellable?
    private var isLoading = false

    @Published var cornerStyle: CardCornerStyle {
        didSet { if !isLoading, cornerStyle != oldValue { defaults.cardCornerStyle = cornerStyle } }
    }

    @Published var titleMode: CardTitleMode {
        didSet { if !isLoading, titleMode != oldValue { defaults.cardTitleMode = titleMode } }
    }

    @Published var showRatingBadges: Bool {
        didSet { if !isLoading, showRatingBadges != oldValue { defaults.cardShowRatingBadges = showRatingBadges } }
    }

    @Published var hoverPreviewEnabled: Bool {
        didSet {
            guard !isLoading, hoverPreviewEnabled != oldValue else { return }
            defaults.cardHoverPreviewEnabled = hoverPreviewEnabled
            if !hoverPreviewEnabled { HoverPreviewController.shared.dismiss(animated: false) }
        }
    }

    @Published var hoverPreviewDelay: Double {
        didSet { if !isLoading, hoverPreviewDelay != oldValue { defaults.cardHoverPreviewDelay = hoverPreviewDelay } }
    }

    @Published var hoverTrailerMode: HoverTrailerMode {
        didSet { if !isLoading, hoverTrailerMode != oldValue { defaults.cardHoverTrailerMode = hoverTrailerMode } }
    }

    private init() {
        cornerStyle = defaults.cardCornerStyle
        titleMode = defaults.cardTitleMode
        showRatingBadges = defaults.cardShowRatingBadges
        hoverPreviewEnabled = defaults.cardHoverPreviewEnabled
        hoverPreviewDelay = defaults.cardHoverPreviewDelay
        hoverTrailerMode = defaults.cardHoverTrailerMode

        // Profile switches republish ProfileSettings; follow it like AppearanceStore.
        profileObserver = ProfileSettings.shared.objectWillChange
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.reload() }
            }
    }

    /// Re-reads the values for the current profile; publishes only what changed.
    func reload() {
        isLoading = true
        defer { isLoading = false }
        let corner = defaults.cardCornerStyle
        if corner != cornerStyle { cornerStyle = corner }
        let titles = defaults.cardTitleMode
        if titles != titleMode { titleMode = titles }
        let badges = defaults.cardShowRatingBadges
        if badges != showRatingBadges { showRatingBadges = badges }
        let preview = defaults.cardHoverPreviewEnabled
        if preview != hoverPreviewEnabled { hoverPreviewEnabled = preview }
        let delay = defaults.cardHoverPreviewDelay
        if delay != hoverPreviewDelay { hoverPreviewDelay = delay }
        let trailer = defaults.cardHoverTrailerMode
        if trailer != hoverTrailerMode { hoverTrailerMode = trailer }
    }
}

// MARK: - Shared card constants

enum CardMetrics {
    /// Scale applied to a hovered card.
    static let hoverScale: CGFloat = 1.04
    /// Extra room a row leaves above and below its cards so the hover scale
    /// and focus ring are not clipped by the horizontal scroll view.
    static let rowOverflowInset: CGFloat = DS.Space.s8
    /// Height reserved under a poster for a title + year caption.
    static let posterCaptionHeight: CGFloat = 44
}
