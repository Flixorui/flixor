//
//  HomeScreenAppearanceView.swift
//  FlixorMac
//
//  Visual appearance settings for the home screen
//

import SwiftUI

struct HomeScreenAppearanceView: View {
    @ObservedObject private var profileSettings = ProfileSettings.shared

    @State private var showHeroPreview: Bool = false
    @State private var showContinueWatchingPreview: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            // Hero
            SettingsSectionHeader(title: "Hero")
            SettingsGroupCard {
                SettingsRow(icon: "rectangle.inset.filled", iconColor: .blue, title: "Show Hero", showDivider: profileSettings.showHeroSection) {
                    Toggle("", isOn: $profileSettings.showHeroSection).labelsHidden()
                }
                if profileSettings.showHeroSection {
                    SettingsRow(title: "Layout") {
                        Picker("", selection: $profileSettings.heroLayout) {
                            Text("Billboard").tag("billboard")
                            Text("Carousel").tag("carousel")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    SettingsRow(title: "Auto-Rotate") {
                        Toggle("", isOn: $profileSettings.heroAutoRotate).labelsHidden()
                    }
                    HeroSourceSettingsRow()
                }
            }
            if profileSettings.showHeroSection {
                CollapsiblePreviewSection(title: "Hero Preview", isExpanded: $showHeroPreview) {
                    if profileSettings.heroLayout == "billboard" {
                        billboardPreview
                    } else {
                        carouselPreview
                    }
                }
            }

            // Rows: one list to reorder, rename and hide, then whole sources
            HomeRowsEditor()
            HomeRowSourcesSection()

            // Continue Watching
            HomeContinueWatchingSection()
            CollapsiblePreviewSection(title: "Continue Watching Preview", isExpanded: $showContinueWatchingPreview) {
                switch ContinueWatchingCardStyle(storageValue: profileSettings.continueWatchingLayout) {
                case .landscape: continueWatchingLandscapePreview
                case .poster: continueWatchingPosterPreview
                case .wide: ContinueWatchingWidePreview(blurUpNext: HomeRowsStore.shared.continueWatchingBlurNextUp)
                }
            }

            // Cards in every other row
            SettingsSectionHeader(title: "Catalog Rows")
            SettingsGroupCard {
                SettingsRow(title: "Card Shape", subtitle: "Plex, Stremio and discovery rows") {
                    Picker("", selection: $profileSettings.rowLayout) {
                        Text("Landscape").tag("landscape")
                        Text("Poster").tag("poster")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsRow(title: "Show Library Titles", showDivider: false) {
                    Toggle("", isOn: $profileSettings.showLibraryTitles).labelsHidden()
                }
            }
            CardStyleSettingsSection()
        }
    }

    // MARK: - Hero Previews

    private var billboardPreview: some View {
        VStack(alignment: .leading, spacing: DS.Space.s12) {
            // Single large billboard card
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: DS.Radius.r12)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .aspectRatio(21/9, contentMode: .fit)

                // Gradient overlay
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r12))

                // Content
                VStack(alignment: .leading, spacing: DS.Space.s8) {
                    RoundedRectangle(cornerRadius: DS.Radius.r4)
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 120, height: 30)

                    HStack(spacing: DS.Space.s6) {
                        ForEach(["2024", "2h 15m", "PG-13"], id: \.self) { text in
                            Text(text)
                                .font(.flixor(.micro))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 200, height: 8)

                    HStack(spacing: DS.Space.s8) {
                        RoundedRectangle(cornerRadius: DS.Radius.r6)
                            .fill(Color.white)
                            .frame(width: 60, height: 28)
                        RoundedRectangle(cornerRadius: DS.Radius.r6)
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 60, height: 28)
                    }
                }
                .padding(DS.Space.s16)
            }

            Text("Billboard: Single featured item with full-width display")
                .font(.flixor(.caption))
                .foregroundStyle(.secondary)
        }
    }

    private var carouselPreview: some View {
        VStack(alignment: .leading, spacing: DS.Space.s12) {
            // Multiple carousel cards
            HStack(spacing: DS.Space.s12) {
                ForEach(0..<3, id: \.self) { index in
                    ZStack(alignment: .bottomLeading) {
                        RoundedRectangle(cornerRadius: DS.Radius.r10)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        [Color.blue, Color.indigo],
                                        [Color.purple, Color.pink],
                                        [Color.orange, Color.red]
                                    ][index].map { $0.opacity(0.4) },
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .aspectRatio(16/9, contentMode: .fit)

                        // Gradient
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.6)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r10))

                        // Content
                        VStack(alignment: .leading, spacing: DS.Space.s4) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.9))
                                .frame(width: 60, height: 16)
                            RoundedRectangle(cornerRadius: DS.Radius.r2)
                                .fill(Color.white.opacity(0.5))
                                .frame(width: 80, height: 6)
                        }
                        .padding(DS.Space.s10)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.r10)
                            .stroke(index == 0 ? Color.white.opacity(0.5) : Color.clear, lineWidth: 2)
                    )
                }
            }

            // Page indicators
            HStack(spacing: DS.Space.s6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(index == 0 ? Color.white : Color.white.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            .frame(maxWidth: .infinity)

            Text("Carousel: Multiple items with swipe navigation")
                .font(.flixor(.caption))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Continue Watching Previews

    private var continueWatchingLandscapePreview: some View {
        HStack(spacing: DS.Space.s12) {
            ForEach(0..<3, id: \.self) { index in
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: DS.Radius.r8)
                            .fill(Color.white.opacity(0.1))
                            .aspectRatio(16/9, contentMode: .fit)

                        // Progress bar
                        GeometryReader { geo in
                            VStack {
                                Spacer()
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.3))
                                        .frame(height: 3)

                                    Rectangle()
                                        .fill(Color.blue)
                                        .frame(width: geo.size.width * CGFloat([0.3, 0.65, 0.45][index]), height: 3)
                                }
                            }
                        }

                        // Play icon
                        Image(systemName: "play.circle.fill")
                            .font(.flixorIcon(DS.Icon.xl))
                            .foregroundStyle(.white.opacity(0.9))
                    }

                    Text(["Breaking Bad", "The Office", "Stranger Things"][index])
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Text(["S5 E14", "S3 E7", "S4 E2"][index])
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 120)
            }
        }
    }

    private var continueWatchingPosterPreview: some View {
        HStack(spacing: DS.Space.s12) {
            ForEach(0..<4, id: \.self) { index in
                VStack(alignment: .center, spacing: DS.Space.s6) {
                    ZStack {
                        RoundedRectangle(cornerRadius: DS.Radius.r8)
                            .fill(Color.white.opacity(0.1))
                            .aspectRatio(2/3, contentMode: .fit)

                        // Progress ring
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 3)
                            .frame(width: 32, height: 32)

                        Circle()
                            .trim(from: 0, to: CGFloat([0.3, 0.65, 0.45, 0.8][index]))
                            .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(width: 32, height: 32)
                            .rotationEffect(.degrees(-90))

                        Image(systemName: "play.fill")
                            .font(.flixor(.micro))
                            .foregroundStyle(.white)
                    }

                    Text(["Breaking Bad", "The Office", "Stranger", "Dark"][index])
                        .font(.caption2)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                .frame(width: 70)
            }
        }
    }
}

// MARK: - Layout Option Button

struct LayoutOptionButton: View {
    @Environment(\.flixorTheme) private var theme
    let title: LocalizedStringKey
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: DS.Space.s6) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Space.s10)
            .background(
                isSelected ? Color.white.opacity(0.14) : Color.white.opacity(0.04),
                in: RoundedRectangle(cornerRadius: DS.Radius.r8, style: .continuous)
            )
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.r8, style: .continuous)
                    .strokeBorder(isSelected ? Color.white.opacity(0.7) : Color.white.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Collapsible Preview Section

struct CollapsiblePreviewSection<Content: View>: View {
    @Environment(\.flixorTheme) private var theme
    let title: LocalizedStringKey
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s12) {
            // Header with toggle button
            Button(action: {
                withAnimation(DS.Motion.standard) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Text(title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, DS.Space.s10)

                    Spacer()

                    HStack(spacing: DS.Space.s4) {
                        Text(isExpanded ? "Hide" : "Show")
                            .font(.flixor(.caption, weight: .medium))
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.flixor(.micro, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, DS.Space.s10)
                    .padding(.vertical, 5)
                    .background(theme.settingsGroupBackground)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r6, style: .continuous))
                }
            }
            .buttonStyle(.plain)

            // Collapsible content
            if isExpanded {
                SettingsGroupCard {
                    content()
                        .padding(DS.Space.s16)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
