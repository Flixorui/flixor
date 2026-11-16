//
//  HomeHeroMetrics.swift
//  FlixorMac
//
//  Window-relative sizes for the home hero (billboard and carousel).
//
//  The hero used to be a fixed 1000 pt (billboard) / 580 pt (carousel), which
//  pushed every row below the fold on a laptop. The height is now a fraction
//  of the window: on the 1440 x 900 reference window the first row's title and
//  the top of its cards stay visible under the hero, and very tall windows are
//  capped so the hero never becomes a wall of artwork.
//
//  Budget at 900 pt: hero (576) + hero padding and row spacing (96) + row
//  header (~46) = cards start ~720 pt down, leaving ~120 pt of cards visible
//  under the toolbar.
//

import SwiftUI

extension WindowMetrics {
    /// Home billboard height.
    var homeBillboardHeight: CGFloat {
        heroHeight(for: .fraction(0.64, minimum: 440, maximum: 760))
    }

    /// Home hero carousel height: about 16:9 of the width, at least 460 pt.
    /// It stops at 640 pt on laptop-sized windows (so the first row shows under
    /// it) and grows with taller windows up to 72% of the window height, so a
    /// full-screen window isn't left with a thin strip of artwork.
    var homeCarouselHeight: CGFloat {
        min(max(width * 0.56, 460), max(640, height * 0.72))
    }

    /// True when the hero is short enough that its text should tighten up
    /// (fewer summary lines, smaller logo, less padding).
    func isCompactHero(height: CGFloat) -> Bool {
        height < 540 || sizeClass == .compact
    }
}
