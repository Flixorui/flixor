//
//  Color+Theme.swift
//  FlixorMac
//
//  Theme colors matching the web app
//
//  Which red to use:
//  - `theme.accent` (from `\.flixorTheme`) for anything interactive (selection,
//    progress, focus rings, toggles, highlighted icons). It follows the accent
//    colour the user picks in Settings > Appearance (Flixor red by default).
//    Don't use `Color.accentColor`: on macOS it stays the red asset colour.
//  - `Color.flixorBrand` / `Color.brand` for brand marks (the logo, the
//    sign-in screen's primary action). Always Flixor red.
//  Surface colours that honour the "pure black" option come from
//  `@Environment(\.flixorTheme)` (see FlixorTheme.swift).
//

import SwiftUI

extension Color {
    // MARK: - Brand Colors (Netflix Red)
    static let brand = Color(hex: "#e50914")
    static let brandHover = Color(hex: "#b20710")

    /// Brand red for logos and brand marks. Never follows the accent setting.
    static let flixorBrand = brand

    // MARK: - Background Colors
    static let backgroundPrimary = Color(hex: "#0a0a0a")
    static let backgroundSecondary = Color(hex: "#0f0f10")
    static let backgroundTertiary = Color(hex: "#141414")

    // MARK: - Neutral Grays
    static let neutral800 = Color(hex: "#262626")
    static let neutral900 = Color(hex: "#171717")

    // MARK: - Gradient Colors
    static let gradientRedStart = Color(red: 122/255, green: 22/255, blue: 18/255).opacity(0.44)
    static let gradientRedMid = Color(red: 122/255, green: 22/255, blue: 18/255).opacity(0.20)
    static let gradientTealStart = Color(red: 20/255, green: 76/255, blue: 84/255).opacity(0.42)
    static let gradientTealMid = Color(red: 20/255, green: 76/255, blue: 84/255).opacity(0.20)

    // MARK: - Hex initializers

    /// Initialize from a 24-bit RGB integer, e.g. `Color(hex: 0x0a0a0a)`.
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }

    /// Initialize from a hex string: "RGB", "RRGGBB" or "AARRGGBB", with or
    /// without a leading "#". `alpha` multiplies any alpha in the string.
    /// Invalid strings give black.
    init(hex: String, alpha: Double = 1.0) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255 * alpha
        )
    }
}
