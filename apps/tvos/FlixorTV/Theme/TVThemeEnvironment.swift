import SwiftUI

private struct TVThemePaletteKey: EnvironmentKey {
    static let defaultValue = TVThemePalette(theme: .white)
}

private struct TVTypographyKey: EnvironmentKey {
    static let defaultValue = TVTypographySet(appFont: .system)
}

private struct TVCardVisualTokensKey: EnvironmentKey {
    static let defaultValue = TVCardVisualTokens(posterCornerPreset: .rounded)
}

extension EnvironmentValues {
    var tvThemePalette: TVThemePalette {
        get { self[TVThemePaletteKey.self] }
        set { self[TVThemePaletteKey.self] = newValue }
    }

    var tvTypography: TVTypographySet {
        get { self[TVTypographyKey.self] }
        set { self[TVTypographyKey.self] = newValue }
    }

    var tvCardVisualTokens: TVCardVisualTokens {
        get { self[TVCardVisualTokensKey.self] }
        set { self[TVCardVisualTokensKey.self] = newValue }
    }
}

extension View {
    func tvTheme(
        palette: TVThemePalette,
        typography: TVTypographySet,
        cardVisualTokens: TVCardVisualTokens
    ) -> some View {
        environment(\.tvThemePalette, palette)
            .environment(\.tvTypography, typography)
            .environment(\.tvCardVisualTokens, cardVisualTokens)
    }
}
