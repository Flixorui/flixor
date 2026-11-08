//
//  AppearanceSettingsView.swift
//  FlixorMac
//
//  Settings > Appearance: accent colour and background (pure black) options,
//  with a live preview. Stored per profile via AppearanceStore.
//

import SwiftUI

struct AppearanceSettingsView: View {
    @ObservedObject private var store = AppearanceStore.shared

    private let swatchColumns = [GridItem(.adaptive(minimum: 72, maximum: 96), spacing: DS.Space.s12)]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s24) {
            // Accent
            SettingsSectionHeader(title: "Accent Color")
            SettingsGroupCard {
                VStack(alignment: .leading, spacing: DS.Space.s12) {
                    LazyVGrid(columns: swatchColumns, alignment: .leading, spacing: DS.Space.s16) {
                        ForEach(AccentPalette.allCases) { palette in
                            AccentSwatchButton(
                                palette: palette,
                                isSelected: store.palette == palette
                            ) {
                                withAnimation(DS.Motion.standard) {
                                    store.palette = palette
                                }
                            }
                        }
                    }

                    Text("Used for selection, progress bars, toggles and highlights. The Flixor logo always stays red.")
                        .font(.flixor(.caption))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(DS.Space.cardPadding)
            }

            // Background
            SettingsSectionHeader(title: "Background")
            SettingsGroupCard {
                SettingsRow(
                    icon: "circle.lefthalf.filled",
                    iconColor: .gray,
                    title: "Pure Black Background",
                    subtitle: "True black instead of near-black. Looks best on OLED and mini-LED displays.",
                    showDivider: false
                ) {
                    Toggle("", isOn: $store.pureBlack)
                        .labelsHidden()
                        .accessibilityLabel("Pure black background")
                }
            }

            // Preview
            SettingsSectionHeader(title: "Preview")
            AppearancePreviewCard(theme: store.theme)

            HStack {
                Spacer()
                Button("Reset to Default") {
                    withAnimation(DS.Motion.standard) {
                        store.resetToDefaults()
                    }
                }
                .disabled(store.theme == .default)
                .accessibilityLabel("Reset appearance to default")
            }
        }
    }
}

// MARK: - Swatch

private struct AccentSwatchButton: View {
    let palette: AccentPalette
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: DS.Space.s6) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [palette.bright, palette.color, palette.strong],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 34, height: 34)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.flixorIcon(DS.Icon.sm, weight: .bold))
                            .foregroundStyle(palette.onAccent)
                    }
                }
                .padding(DS.Space.s4)
                .overlay(
                    Circle()
                        .strokeBorder(
                            isSelected ? palette.bright : Color.white.opacity(isHovered ? 0.25 : 0),
                            lineWidth: DS.Border.focus
                        )
                )
                .scaleEffect(isHovered && !isSelected ? 1.06 : 1)

                Text(palette.displayName)
                    .font(.flixor(.caption, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DS.Motion.quick) { isHovered = hovering }
        }
        .accessibilityLabel("\(palette.displayName) accent color")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Live preview

/// A small mock of app UI drawn with the theme tokens, so changes are visible
/// without leaving Settings.
private struct AppearancePreviewCard: View {
    let theme: FlixorTheme

    @State private var previewToggle = true

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            // Nav row
            HStack(spacing: DS.Space.s20) {
                HStack(spacing: DS.Space.s6) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.flixorIcon(DS.Icon.md))
                        .foregroundStyle(theme.brand)
                    Text("FLIXOR")
                        .font(.flixor(.callout, weight: .bold))
                        .foregroundStyle(theme.textPrimary)
                }
                Text("Home")
                    .font(.flixor(.footnote, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Text("Library")
                    .font(.flixor(.footnote, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                Spacer()
            }

            HStack(alignment: .top, spacing: DS.Space.s16) {
                // Poster with progress
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    RoundedRectangle(cornerRadius: DS.Radius.poster, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [theme.surfaceElevated, theme.surface],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 72, height: 108)
                        .overlay(
                            Image(systemName: "film")
                                .font(.flixorIcon(DS.Icon.xl))
                                .foregroundStyle(theme.textTertiary)
                        )
                        .overlay(alignment: .bottom) {
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.25))
                                    Capsule().fill(theme.accent)
                                        .frame(width: proxy.size.width * 0.6)
                                }
                            }
                            .frame(height: 3)
                            .padding(DS.Space.s8)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.poster, style: .continuous)
                                .strokeBorder(theme.focusRing, lineWidth: DS.Border.focus)
                        )
                }

                VStack(alignment: .leading, spacing: DS.Space.s12) {
                    Text("Selected Title")
                        .font(.flixor(.headline, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text("Secondary details and metadata")
                        .font(.flixor(.footnote))
                        .foregroundStyle(theme.textSecondary)

                    HStack(spacing: DS.Space.s8) {
                        HStack(spacing: DS.Space.s6) {
                            Image(systemName: "play.fill")
                                .font(.flixorIcon(DS.Icon.xs, weight: .bold))
                            Text("Play")
                                .font(.flixor(.footnote, weight: .semibold))
                        }
                        .foregroundStyle(theme.onAccent)
                        .padding(.horizontal, DS.Space.s14)
                        .padding(.vertical, DS.Space.s6)
                        .background(theme.accent, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))

                        Text("4K HDR")
                            .font(.flixor(.micro, weight: .semibold))
                            .foregroundStyle(theme.accentBright)
                            .padding(.horizontal, DS.Space.s10)
                            .padding(.vertical, DS.Space.s4)
                            .background(theme.accentSoft, in: Capsule())
                    }

                    HStack(spacing: DS.Space.s8) {
                        Toggle("", isOn: $previewToggle)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .tint(theme.accent)
                            .accessibilityLabel("Preview toggle")
                        Text("Autoplay next episode")
                            .font(.flixor(.caption))
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(DS.Space.s12)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: DS.Radius.compactCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.compactCard, style: .continuous)
                    .strokeBorder(theme.separator, lineWidth: DS.Border.thin)
            )
        }
        .padding(DS.Space.cardPadding)
        .background(theme.background, in: RoundedRectangle(cornerRadius: DS.Radius.group, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.group, style: .continuous)
                .strokeBorder(theme.separator, lineWidth: DS.Border.thin)
        )
        .animation(DS.Motion.standard, value: theme)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Appearance preview")
    }
}
