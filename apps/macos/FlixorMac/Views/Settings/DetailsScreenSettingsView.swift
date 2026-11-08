//
//  DetailsScreenSettingsView.swift
//  FlixorMac
//
//  Settings for the details/media info screen
//

import SwiftUI

struct DetailsScreenSettingsView: View {
    @ObservedObject private var profileSettings = ProfileSettings.shared
    @ObservedObject private var sectionsStore = DetailsSectionsStore.shared

    @State private var showEpisodePreview: Bool = false
    @State private var showSuggestedPreview: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s24) {
            // Screen Layout
            SettingsSectionHeader(title: "Screen Layout")
            SettingsGroupCard {
                VStack(alignment: .leading, spacing: DS.Space.s12) {
                    Text("Details Page Style")
                        .font(.flixor(.callout, weight: .medium))
                        .padding(.horizontal, DS.Space.s12)
                        .padding(.top, DS.Space.s12)

                    Text("Choose between tabbed navigation or a unified scrollable page. Tabs follow the section order below.")
                        .font(.flixor(.caption))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, DS.Space.s12)

                    HStack(spacing: DS.Space.s12) {
                        LayoutOptionButton(
                            title: "Tabbed",
                            icon: "rectangle.split.3x1",
                            isSelected: profileSettings.detailsScreenLayout == "tabbed"
                        ) {
                            profileSettings.detailsScreenLayout = "tabbed"
                        }

                        LayoutOptionButton(
                            title: "Unified",
                            icon: "rectangle.portrait",
                            isSelected: profileSettings.detailsScreenLayout == "unified"
                        ) {
                            profileSettings.detailsScreenLayout = "unified"
                        }
                    }
                    .padding(.horizontal, DS.Space.s12)
                    .padding(.bottom, DS.Space.s12)
                }
            }

            // Page Sections (order + visibility)
            SettingsSectionHeader(title: "Page Sections")
            DetailsSectionOrderList()

            DetailsHeroSettingsSection()

            // Episode Layout
            SettingsSectionHeader(title: "Episode Display")
            SettingsGroupCard {
                VStack(alignment: .leading, spacing: DS.Space.s12) {
                    Text("Layout Style")
                        .font(.flixor(.callout, weight: .medium))
                        .padding(.horizontal, DS.Space.s12)
                        .padding(.top, DS.Space.s12)

                    Text("How episodes appear on TV show details")
                        .font(.flixor(.caption))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, DS.Space.s12)

                    HStack(spacing: DS.Space.s12) {
                        LayoutOptionButton(
                            title: "Horizontal",
                            icon: "rectangle.split.3x1.fill",
                            isSelected: profileSettings.episodeLayout == "horizontal"
                        ) {
                            profileSettings.episodeLayout = "horizontal"
                        }

                        LayoutOptionButton(
                            title: "Vertical",
                            icon: "list.bullet",
                            isSelected: profileSettings.episodeLayout == "vertical"
                        ) {
                            profileSettings.episodeLayout = "vertical"
                        }
                    }
                    .padding(.horizontal, DS.Space.s12)
                    .padding(.bottom, DS.Space.s12)
                }
            }

            SettingsGroupCard {
                SettingsRow(
                    icon: "square.grid.2x2.fill",
                    iconColor: .indigo,
                    title: "Season Picker",
                    subtitle: "Text chips, or season posters with episode counts"
                ) {
                    Picker("", selection: $sectionsStore.seasonPickerStyle) {
                        Text("Chips").tag(DetailsSeasonPickerStyle.chips)
                        Text("Posters").tag(DetailsSeasonPickerStyle.posters)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 160)
                    .accessibilityLabel(Text("Season picker style"))
                }
                SettingsRow(
                    icon: "eye.slash.fill",
                    iconColor: .gray,
                    title: "Hide Spoilers for Unwatched Episodes",
                    subtitle: "Blur thumbnails and hide descriptions until you hover"
                ) {
                    Toggle("", isOn: $sectionsStore.hideEpisodeSpoilers)
                        .labelsHidden()
                        .accessibilityLabel(Text("Hide spoilers for unwatched episodes"))
                }
                SettingsRow(
                    icon: "star.leadinghalf.filled",
                    iconColor: .yellow,
                    title: "Episode Ratings",
                    subtitle: "Show the TMDB rating on each episode",
                    showDivider: false
                ) {
                    Toggle("", isOn: $sectionsStore.showEpisodeRatings)
                        .labelsHidden()
                        .accessibilityLabel(Text("Show episode ratings"))
                }
            }

            // Episode Layout Preview
            CollapsiblePreviewSection(title: "Episode Preview", isExpanded: $showEpisodePreview) {
                if profileSettings.episodeLayout == "horizontal" {
                    horizontalEpisodePreview
                } else {
                    verticalEpisodePreview
                }
            }

            // Suggested Rows Layout
            SettingsSectionHeader(title: "Suggested Rows")
            SettingsGroupCard {
                VStack(alignment: .leading, spacing: DS.Space.s12) {
                    Text("Layout Style")
                        .font(.flixor(.callout, weight: .medium))
                        .padding(.horizontal, DS.Space.s12)
                        .padding(.top, DS.Space.s12)

                    Text("How Related and Similar content appears")
                        .font(.flixor(.caption))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, DS.Space.s12)

                    HStack(spacing: DS.Space.s12) {
                        LayoutOptionButton(
                            title: "Landscape",
                            icon: "rectangle.fill",
                            isSelected: profileSettings.suggestedLayout == "landscape"
                        ) {
                            profileSettings.suggestedLayout = "landscape"
                        }

                        LayoutOptionButton(
                            title: "Poster",
                            icon: "rectangle.portrait.fill",
                            isSelected: profileSettings.suggestedLayout == "poster"
                        ) {
                            profileSettings.suggestedLayout = "poster"
                        }
                    }
                    .padding(.horizontal, DS.Space.s12)
                    .padding(.bottom, DS.Space.s12)
                }
            }

            // Suggested Layout Preview
            CollapsiblePreviewSection(title: "Suggested Preview", isExpanded: $showSuggestedPreview) {
                if profileSettings.suggestedLayout == "landscape" {
                    suggestedLandscapePreview
                } else {
                    suggestedPosterPreview
                }
            }

            // Ratings Display
            SettingsSectionHeader(title: "Ratings Display")
            SettingsGroupCard {
                SettingsRow(icon: "star.fill", iconColor: .yellow, title: "IMDb Rating", subtitle: "Show IMDb score") {
                    Toggle("", isOn: $profileSettings.showIMDbRating).labelsHidden()
                }
                SettingsRow(icon: "leaf.fill", iconColor: .red, title: "Rotten Tomatoes (Critics)", subtitle: "Tomatometer score") {
                    Toggle("", isOn: $profileSettings.showRottenTomatoesCritic).labelsHidden()
                }
                SettingsRow(icon: "popcorn.fill", iconColor: .orange, title: "Rotten Tomatoes (Audience)", subtitle: "Audience score", showDivider: false) {
                    Toggle("", isOn: $profileSettings.showRottenTomatoesAudience).labelsHidden()
                }
            }

            Text("These settings apply to movie and TV show detail pages.")
                .font(.flixor(.caption))
                .foregroundStyle(.secondary)
                .padding(.horizontal, DS.Space.s4)
        }
    }

    // MARK: - Episode Previews

    private var horizontalEpisodePreview: some View {
        VStack(alignment: .leading, spacing: DS.Space.s12) {
            // Horizontal scroll of episode cards
            HStack(spacing: DS.Space.s12) {
                ForEach(0..<3, id: \.self) { index in
                    ZStack(alignment: .bottomLeading) {
                        // Thumbnail
                        RoundedRectangle(cornerRadius: DS.Radius.r10)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        [Color.blue, Color.cyan],
                                        [Color.purple, Color.indigo],
                                        [Color.orange, Color.yellow]
                                    ][index].map { $0.opacity(0.3) },
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .aspectRatio(16/9, contentMode: .fit)

                        // Gradient overlay
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r10))

                        // Content
                        VStack(alignment: .leading, spacing: DS.Space.s4) {
                            Text("EPISODE \(index + 1)")
                                .font(.system(size: 8, weight: .bold))
                                .tracking(0.5)
                                .foregroundStyle(.white.opacity(0.8))
                                .padding(.horizontal, DS.Space.s6)
                                .padding(.vertical, 3)
                                .background(Color.black.opacity(0.4))
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r4))

                            Text(["Pilot", "The One Where...", "Winter Is Coming"][index])
                                .font(.flixor(.caption, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            Text("45m")
                                .font(.flixor(.nano))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .padding(DS.Space.s8)

                        // Progress bar
                        VStack {
                            Spacer()
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.3))
                                        .frame(height: 3)
                                    Rectangle()
                                        .fill(Color.white)
                                        .frame(width: geo.size.width * CGFloat([0.7, 0.3, 0.0][index]), height: 3)
                                }
                            }
                            .frame(height: 3)
                        }
                    }
                    .frame(width: 140)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r10))
                }
            }

            Text("Horizontal: Scrollable cards with thumbnails and progress")
                .font(.flixor(.caption))
                .foregroundStyle(.secondary)
        }
    }

    private var verticalEpisodePreview: some View {
        VStack(alignment: .leading, spacing: DS.Space.s12) {
            // Vertical list of episode rows
            VStack(spacing: DS.Space.s8) {
                ForEach(0..<3, id: \.self) { index in
                    HStack(spacing: DS.Space.s12) {
                        // Thumbnail
                        ZStack {
                            RoundedRectangle(cornerRadius: DS.Radius.r8)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            [Color.blue, Color.cyan],
                                            [Color.purple, Color.indigo],
                                            [Color.orange, Color.yellow]
                                        ][index].map { $0.opacity(0.3) },
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .aspectRatio(16/9, contentMode: .fit)

                            Image(systemName: "play.circle.fill")
                                .font(.flixorIcon(DS.Icon.lg))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .frame(width: 100)

                        // Info
                        VStack(alignment: .leading, spacing: DS.Space.s4) {
                            HStack {
                                Text("\(index + 1). \(["Pilot", "The One Where...", "Winter Is Coming"][index])")
                                    .font(.flixor(.footnote, weight: .semibold))
                                    .lineLimit(1)

                                Spacer()

                                if index == 0 {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.flixorIcon(DS.Icon.sm))
                                        .foregroundStyle(.green)
                                }
                            }

                            Text("A brief description of the episode goes here...")
                                .font(.flixor(.micro))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)

                            Text("45 min")
                                .font(.flixor(.nano))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(DS.Space.s8)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.r8)
                            .fill(Color.white.opacity(0.05))
                    )
                }
            }

            Text("Vertical: Compact list with descriptions and watched status")
                .font(.flixor(.caption))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Suggested Row Previews

    private var suggestedLandscapePreview: some View {
        VStack(alignment: .leading, spacing: DS.Space.s12) {
            // Section header
            HStack {
                Text("Related")
                    .font(.flixor(.body, weight: .semibold))
                Spacer()
                Text("See All")
                    .font(.flixor(.caption))
                    .foregroundStyle(.secondary)
            }

            // Landscape cards
            HStack(spacing: DS.Space.s12) {
                ForEach(0..<3, id: \.self) { index in
                    VStack(alignment: .leading, spacing: DS.Space.s6) {
                        ZStack {
                            RoundedRectangle(cornerRadius: DS.Radius.r8)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            [Color.red, Color.orange],
                                            [Color.green, Color.teal],
                                            [Color.indigo, Color.purple]
                                        ][index].map { $0.opacity(0.3) },
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .aspectRatio(16/9, contentMode: .fit)

                            Image(systemName: "play.circle.fill")
                                .font(.flixorIcon(DS.Icon.xl))
                                .foregroundStyle(.white.opacity(0.8))
                        }

                        Text(["The Godfather", "Goodfellas", "Casino"][index])
                            .font(.flixor(.caption, weight: .medium))
                            .lineLimit(1)

                        HStack(spacing: DS.Space.s4) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.yellow)
                            Text(["9.2", "8.7", "8.2"][index])
                                .font(.flixor(.nano))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 130)
                }
            }

            Text("Landscape: Wide thumbnails with ratings")
                .font(.flixor(.caption))
                .foregroundStyle(.secondary)
        }
    }

    private var suggestedPosterPreview: some View {
        VStack(alignment: .leading, spacing: DS.Space.s12) {
            // Section header
            HStack {
                Text("Related")
                    .font(.flixor(.body, weight: .semibold))
                Spacer()
                Text("See All")
                    .font(.flixor(.caption))
                    .foregroundStyle(.secondary)
            }

            // Poster cards
            HStack(spacing: DS.Space.s10) {
                ForEach(0..<5, id: \.self) { index in
                    VStack(alignment: .center, spacing: DS.Space.s6) {
                        ZStack(alignment: .topTrailing) {
                            RoundedRectangle(cornerRadius: DS.Radius.r8)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            [Color.red, Color.orange],
                                            [Color.green, Color.teal],
                                            [Color.indigo, Color.purple],
                                            [Color.pink, Color.red],
                                            [Color.blue, Color.cyan]
                                        ][index].map { $0.opacity(0.3) },
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .aspectRatio(2/3, contentMode: .fit)

                            // Rating badge
                            HStack(spacing: DS.Space.s2) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 7))
                                Text(["9.2", "8.7", "8.2", "7.9", "8.5"][index])
                                    .font(.system(size: 8, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r4))
                            .padding(DS.Space.s4)
                        }

                        Text(["Godfather", "Goodfellas", "Casino", "Scarface", "Heat"][index])
                            .font(.flixor(.micro, weight: .medium))
                            .lineLimit(1)
                    }
                    .frame(width: 70)
                }
            }

            Text("Poster: More items visible with compact layout")
                .font(.flixor(.caption))
                .foregroundStyle(.secondary)
        }
    }
}
