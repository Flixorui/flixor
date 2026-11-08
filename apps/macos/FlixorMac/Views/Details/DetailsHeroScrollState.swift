//
//  DetailsHeroScrollState.swift
//  FlixorMac
//
//  Tracks where the details hero sits in the page scroll view. The hero reports
//  its frame through a preference key; this object turns that per-frame value
//  into a couple of booleans (floating header shown, hero visible enough for the
//  inline trailer) and only publishes when one of them flips, so scrolling does
//  not re-render the page.
//

import SwiftUI
import Combine

enum DetailsScrollSpace {
    static let name = "detailsPageScroll"
}

struct DetailsHeroFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

extension View {
    /// Reports this view's frame in the details scroll view (used by the hero).
    func reportsDetailsHeroFrame() -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: DetailsHeroFramePreferenceKey.self,
                    value: geo.frame(in: .named(DetailsScrollSpace.name))
                )
            }
        )
    }
}

/// Not actor-isolated so `onPreferenceChange` (a Sendable closure in newer SDKs)
/// can call it directly; it is only ever used from the main thread.
final class DetailsHeroScrollState: ObservableObject {
    /// The hero has scrolled (nearly) out of view: show the compact header.
    @Published private(set) var isHeroScrolledAway = false
    /// At least about half of the hero is on screen (inline trailer may play).
    @Published private(set) var isHeroMostlyVisible = true

    /// Fires on every scroll movement (not published, so it doesn't re-render).
    let scrollActivity = PassthroughSubject<Void, Never>()

    /// Drives the page tint. Its own object, so its changes don't reach whoever
    /// observes this one.
    let backdrop = DetailsBackdropScroll()

    /// Bottom edge of the hero (scroll-view coordinates) below which the header
    /// appears / above which it hides again. The gap is hysteresis against flicker.
    private let headerShowBelow: CGFloat = 132
    private let headerHideAbove: CGFloat = 156

    private var lastMinY: CGFloat?

    func update(heroFrame frame: CGRect) {
        guard frame.height > 0 else { return }

        if let lastMinY, abs(lastMinY - frame.minY) > 0.5 {
            scrollActivity.send()
        }
        lastMinY = frame.minY
        backdrop.update(scrollOffset: -frame.minY, heroHeight: frame.height)

        let bottom = frame.maxY
        if isHeroScrolledAway {
            if bottom > headerHideAbove { isHeroScrolledAway = false }
        } else if bottom < headerShowBelow {
            isHeroScrolledAway = true
        }

        let visibleFraction = max(0, min(frame.height, bottom)) / frame.height
        let mostlyVisible = visibleFraction > 0.55
        if mostlyVisible != isHeroMostlyVisible {
            isHeroMostlyVisible = mostlyVisible
        }
    }

    func reset() {
        lastMinY = nil
        backdrop.reset()
        if isHeroScrolledAway { isHeroScrolledAway = false }
        if !isHeroMostlyVisible { isHeroMostlyVisible = true }
    }
}
