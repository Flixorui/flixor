//
//  FlixorTheme.swift
//  FlixorMac
//
//  Accent palettes, the resolved theme value and how it reaches views.
//
//  Reading the theme in a view:
//
//      @Environment(\.flixorTheme) private var theme
//      ...
//      .background(theme.background)
//      .foregroundStyle(theme.accent)
//
//  For interactive accents `Color.flixorAccent` (== Color.accentColor) also
//  works, because `.flixorAppearance()` applies the accent with `.tint` and
//  `.accentColor` at the root of every window.
//

import SwiftUI

// MARK: - Accent palettes

/// User-selectable accent colours. The raw value is what gets stored.
enum AccentPalette: String, CaseIterable, Identifiable {
    case crimson
    case orange
    case amber
    case emerald
    case teal
    case sky
    case blue
    case violet
    case pink
    case mono

    static let `default`: AccentPalette = .crimson

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .crimson: return String(localized: "Flixor Red")
        case .orange: return String(localized: "Orange")
        case .amber: return String(localized: "Amber")
        case .emerald: return String(localized: "Emerald")
        case .teal: return String(localized: "Teal")
        case .sky: return String(localized: "Sky")
        case .blue: return String(localized: "Blue")
        case .violet: return String(localized: "Violet")
        case .pink: return String(localized: "Pink")
        case .mono: return String(localized: "Graphite")
        }
    }

    /// Base accent. Mid-to-deep shades so white text on an accent fill stays
    /// readable (existing views put white labels on `Color.accentColor`).
    var color: Color {
        switch self {
        case .crimson: return Color(hex: 0xE50914)  // Flixor red, same as the AccentColor asset
        case .orange: return Color(hex: 0xEA580C)
        case .amber: return Color(hex: 0xD97706)
        case .emerald: return Color(hex: 0x059669)
        case .teal: return Color(hex: 0x0D9488)
        case .sky: return Color(hex: 0x0284C7)
        case .blue: return Color(hex: 0x2563EB)
        case .violet: return Color(hex: 0x7C3AED)
        case .pink: return Color(hex: 0xDB2777)
        case .mono: return Color(hex: 0x8E8E93)
        }
    }

    /// Deeper shade for hover/pressed fills.
    var strong: Color {
        switch self {
        case .crimson: return Color(hex: 0xB20710)
        case .orange: return Color(hex: 0xC2410C)
        case .amber: return Color(hex: 0xB45309)
        case .emerald: return Color(hex: 0x047857)
        case .teal: return Color(hex: 0x0F766E)
        case .sky: return Color(hex: 0x0369A1)
        case .blue: return Color(hex: 0x1D4ED8)
        case .violet: return Color(hex: 0x6D28D9)
        case .pink: return Color(hex: 0xBE185D)
        case .mono: return Color(hex: 0x636366)
        }
    }

    /// Lighter shade for accent text and icons on dark backgrounds.
    var bright: Color {
        switch self {
        case .crimson: return Color(hex: 0xFF3B47)
        case .orange: return Color(hex: 0xFB923C)
        case .amber: return Color(hex: 0xFBBF24)
        case .emerald: return Color(hex: 0x34D399)
        case .teal: return Color(hex: 0x2DD4BF)
        case .sky: return Color(hex: 0x38BDF8)
        case .blue: return Color(hex: 0x60A5FA)
        case .violet: return Color(hex: 0xA78BFA)
        case .pink: return Color(hex: 0xF472B6)
        case .mono: return Color(hex: 0xD1D1D6)
        }
    }

    /// Content colour on top of an accent fill.
    var onAccent: Color { .white }
}

// MARK: - Resolved theme

/// The resolved appearance for the current profile: accent palette plus
/// background mode, with all derived colour tokens.
struct FlixorTheme: Equatable {
    var palette: AccentPalette
    /// AMOLED-style true black backgrounds instead of the default near-black.
    var pureBlack: Bool

    static let `default` = FlixorTheme(palette: .default, pureBlack: false)

    // MARK: Accent

    /// Interactive accent (selection, progress, toggles, focus).
    var accent: Color { palette.color }
    /// Hover / pressed accent fill.
    var accentStrong: Color { palette.strong }
    /// Accent for text and small icons on dark backgrounds.
    var accentBright: Color { palette.bright }
    /// Tinted background for selected chips and rows.
    var accentSoft: Color { palette.color.opacity(DS.Opacity.selected) }
    /// Text / icons placed on an accent fill.
    var onAccent: Color { palette.onAccent }
    /// Focus and selection rings.
    var focusRing: Color { palette.bright }

    /// Brand red for logos. Does not follow the accent.
    var brand: Color { .flixorBrand }

    // MARK: Surfaces

    /// Window / page background. #000 in pure black mode, else #0a0a0a
    /// (same as `Color.backgroundPrimary`).
    var background: Color { pureBlack ? .black : Color(hex: 0x0A0A0A) }
    /// Secondary page background (gradients, side panels).
    var backgroundSecondary: Color { pureBlack ? .black : Color(hex: 0x0F0F10) }
    /// Cards, rows, grouped boxes resting on the background.
    var surface: Color { pureBlack ? Color(hex: 0x0A0A0A) : Color(hex: 0x141414) }
    /// Popovers, menus, hovered cards, sheets.
    var surfaceElevated: Color { pureBlack ? Color(hex: 0x141414) : Color(hex: 0x1C1C1E) }
    /// Translucent fill for cards drawn over artwork or gradients.
    var surfaceOverlay: Color { Color.white.opacity(DS.Opacity.subtle) }
    /// Hover highlight fill.
    var hoverFill: Color { Color.white.opacity(DS.Opacity.hover) }
    /// Pressed highlight fill.
    var pressedFill: Color { Color.white.opacity(DS.Opacity.pressed) }

    // MARK: Lines

    /// Hairline separators and card outlines.
    var separator: Color { Color.white.opacity(pureBlack ? 0.10 : 0.08) }
    /// Stronger outline (inputs, focused containers).
    var separatorStrong: Color { Color.white.opacity(pureBlack ? 0.18 : 0.14) }

    // MARK: Text

    var textPrimary: Color { .white }
    var textSecondary: Color { Color.white.opacity(DS.Opacity.secondary) }
    var textTertiary: Color { Color.white.opacity(DS.Opacity.tertiary) }
    var textDisabled: Color { Color.white.opacity(DS.Opacity.disabled) }

    // MARK: Status

    var success: Color { Color(hex: 0x30D158) }
    var warning: Color { Color(hex: 0xFFC857) }
    var danger: Color { Color(hex: 0xFF453A) }
    var info: Color { Color(hex: 0x0A84FF) }

    // MARK: Overlays

    /// Black scrim over artwork.
    func scrim(_ opacity: Double = DS.Opacity.scrimMedium) -> Color {
        Color.black.opacity(opacity)
    }
}

// MARK: - Environment

private struct FlixorThemeKey: EnvironmentKey {
    static let defaultValue = FlixorTheme.default
}

extension EnvironmentValues {
    /// The current profile's appearance. Injected at the root by `.flixorAppearance()`.
    var flixorTheme: FlixorTheme {
        get { self[FlixorThemeKey.self] }
        set { self[FlixorThemeKey.self] = newValue }
    }
}

// MARK: - Root modifier

private struct FlixorAppearanceModifier: ViewModifier {
    @ObservedObject private var store = AppearanceStore.shared

    func body(content: Content) -> some View {
        let theme = store.theme
        content
            .environment(\.flixorTheme, theme)
            .tint(theme.accent)
            // Keeps `Color.accentColor` (used by many existing views) in step
            // with the picked accent; `.tint` alone does not drive it everywhere.
            .accentColor(theme.accent)
    }
}

extension View {
    /// Applies the current profile's appearance: injects `\.flixorTheme` and
    /// tints system controls and `Color.accentColor` with the accent. Apply
    /// once at the root of each window / scene.
    func flixorAppearance() -> some View {
        modifier(FlixorAppearanceModifier())
    }

    /// Fills the background with the theme's page background (honours pure black).
    func flixorPageBackground() -> some View {
        modifier(FlixorPageBackgroundModifier())
    }
}

private struct FlixorPageBackgroundModifier: ViewModifier {
    @Environment(\.flixorTheme) private var theme

    func body(content: Content) -> some View {
        content.background(theme.background.ignoresSafeArea())
    }
}
