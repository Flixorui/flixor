import SwiftUI

struct TVThemeSettingsView: View {
    @EnvironmentObject private var profileSettings: TVProfileSettings
    @Environment(\.tvThemePalette) private var theme
    @Environment(\.tvTypography) private var typography

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TVSettingsPanel(title: "Accent Theme", subtitle: "Apply Nuvio-style accent palettes across focus and chrome") {
                TVSettingsChoiceRow(
                    title: "Accent Palette",
                    subtitle: "Changes focus rings, active pills, and CTA emphasis",
                    selection: $profileSettings.accentTheme,
                    options: TVAccentTheme.allCases.map { TVSettingsChoice(value: $0, label: $0.displayName) }
                )

                themeSwatchGrid
            }

            TVSettingsPanel(title: "Font Family", subtitle: "Switch the app-wide visual voice") {
                TVSettingsChoiceRow(
                    title: "App Font",
                    subtitle: "System keeps the current default; the others mirror Nuvio's customization options",
                    selection: $profileSettings.appFont,
                    options: TVAppFont.allCases.map { TVSettingsChoice(value: $0, label: $0.displayName) }
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("Preview")
                        .font(typography.label)
                        .foregroundStyle(theme.textPrimary)
                    Text("Flixor")
                        .font(typography.hero)
                        .foregroundStyle(theme.textPrimary)
                    Text("Because you watched richly styled tvOS layouts, keep the typography expressive but legible from a distance.")
                        .font(typography.body)
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(theme.backgroundCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(theme.strokeDefault, lineWidth: 1)
                        )
                )
            }
        }
    }

    private var themeSwatchGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 14) {
            ForEach(TVAccentTheme.allCases) { accentTheme in
                TVAccentThemeCard(
                    accentTheme: accentTheme,
                    isSelected: profileSettings.accentTheme == accentTheme
                )
                .onTapGesture {
                    profileSettings.accentTheme = accentTheme
                }
            }
        }
    }
}

private struct TVAccentThemeCard: View {
    let accentTheme: TVAccentTheme
    let isSelected: Bool

    @State private var isFocused = false

    private var palette: TVThemePalette { TVThemePalette(theme: accentTheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Circle()
                    .fill(palette.accent)
                    .frame(width: 18, height: 18)
                Text(accentTheme.displayName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(palette.accentStrong)
                }
            }

            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.focusFill)
                    .frame(height: 52)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(palette.focusRing, lineWidth: 2)
                    )

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.backgroundCard)
                    .frame(width: 48, height: 52)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(palette.strokeDefault, lineWidth: 1)
                    )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(palette.backgroundElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(isFocused || isSelected ? palette.strokeFocused : palette.strokeDefault, lineWidth: isFocused || isSelected ? 2 : 1)
                )
        )
        .scaleEffect(isFocused ? 1.02 : 1.0)
        .shadow(color: .black.opacity(isFocused ? 0.3 : 0.15), radius: isFocused ? 14 : 8, y: isFocused ? 8 : 4)
        .focusable(true) { isFocused = $0 }
        .animation(.easeOut(duration: UX.focusDur), value: isFocused)
    }
}
