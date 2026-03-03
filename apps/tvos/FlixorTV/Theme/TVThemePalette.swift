import SwiftUI

struct TVThemePalette: Equatable {
    let accent: Color
    let accentStrong: Color
    let focusRing: Color
    let focusFill: Color
    let background: Color
    let backgroundElevated: Color
    let backgroundCard: Color
    let surfaceMuted: Color
    let surfaceGlass: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let strokeDefault: Color
    let strokeFocused: Color
    let success: Color
    let warning: Color
    let error: Color

    private init(
        accent: Color,
        accentStrong: Color,
        focusRing: Color,
        focusFill: Color,
        background: Color,
        backgroundElevated: Color,
        backgroundCard: Color,
        surfaceMuted: Color,
        surfaceGlass: Color,
        textPrimary: Color,
        textSecondary: Color,
        textTertiary: Color,
        strokeDefault: Color,
        strokeFocused: Color,
        success: Color,
        warning: Color,
        error: Color
    ) {
        self.accent = accent
        self.accentStrong = accentStrong
        self.focusRing = focusRing
        self.focusFill = focusFill
        self.background = background
        self.backgroundElevated = backgroundElevated
        self.backgroundCard = backgroundCard
        self.surfaceMuted = surfaceMuted
        self.surfaceGlass = surfaceGlass
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.textTertiary = textTertiary
        self.strokeDefault = strokeDefault
        self.strokeFocused = strokeFocused
        self.success = success
        self.warning = warning
        self.error = error
    }

    init(theme: TVAccentTheme) {
        switch theme {
        case .white:
            self = .build(accent: "#F5F5F5", accentStrong: "#FFFFFF", background: "#060606", elevated: "#101113", card: "#16181C", tint: "#F8FAFC")
        case .crimson:
            self = .build(accent: "#F0446B", accentStrong: "#FF6E8F", background: "#090608", elevated: "#140B10", card: "#1B1117", tint: "#FFD8E1")
        case .ocean:
            self = .build(accent: "#32B7FF", accentStrong: "#79D5FF", background: "#05090D", elevated: "#0C1620", card: "#10202D", tint: "#D8F3FF")
        case .violet:
            self = .build(accent: "#A271FF", accentStrong: "#C5A1FF", background: "#08060D", elevated: "#131022", card: "#1A1630", tint: "#F0E8FF")
        case .emerald:
            self = .build(accent: "#31D08C", accentStrong: "#6BE8B0", background: "#050A08", elevated: "#0C1813", card: "#112219", tint: "#D9FFE9")
        case .amber:
            self = .build(accent: "#FFB547", accentStrong: "#FFC977", background: "#0B0906", elevated: "#17110A", card: "#20180E", tint: "#FFF0D2")
        case .rose:
            self = .build(accent: "#FF7BA5", accentStrong: "#FFAAC7", background: "#0B0709", elevated: "#170F14", card: "#22161C", tint: "#FFE0EA")
        }
    }

    private static func build(
        accent: String,
        accentStrong: String,
        background: String,
        elevated: String,
        card: String,
        tint: String
    ) -> TVThemePalette {
        TVThemePalette(
            accent: Color(hex: accent),
            accentStrong: Color(hex: accentStrong),
            focusRing: Color(hex: accentStrong),
            focusFill: Color(hex: accent, opacity: 0.22),
            background: Color(hex: background),
            backgroundElevated: Color(hex: elevated),
            backgroundCard: Color(hex: card),
            surfaceMuted: Color.white.opacity(0.08),
            surfaceGlass: Color.white.opacity(0.12),
            textPrimary: Color(hex: tint),
            textSecondary: Color.white.opacity(0.76),
            textTertiary: Color.white.opacity(0.56),
            strokeDefault: Color.white.opacity(0.12),
            strokeFocused: Color(hex: accentStrong, opacity: 0.92),
            success: Color(hex: "34D399"),
            warning: Color(hex: "FBBF24"),
            error: Color(hex: "F87171")
        )
    }
}

extension Color {
    init(hex: String, opacity: Double = 1) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)

        let r: UInt64
        let g: UInt64
        let b: UInt64

        switch cleaned.count {
        case 3:
            r = ((int >> 8) & 0xF) * 17
            g = ((int >> 4) & 0xF) * 17
            b = (int & 0xF) * 17
        default:
            r = (int >> 16) & 0xFF
            g = (int >> 8) & 0xFF
            b = int & 0xFF
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: opacity
        )
    }
}
