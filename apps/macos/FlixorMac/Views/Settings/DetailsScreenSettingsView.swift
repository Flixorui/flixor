//
//  DetailsScreenSettingsView.swift
//  FlixorMac
//
//  Settings for the details/media info screen
//

import SwiftUI

struct DetailsScreenSettingsView: View {
    @AppStorage("episodeLayout") private var episodeLayout: String = "horizontal"
    @AppStorage("suggestedLayout") private var suggestedLayout: String = "landscape"
    @AppStorage("showRelatedContent") private var showRelatedContent: Bool = true
    @AppStorage("showCastCrew") private var showCastCrew: Bool = true

    @State private var showEpisodePreview: Bool = false
    @State private var showSuggestedPreview: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Episode Layout
            SettingsSectionHeader(title: "Episode Display")
            SettingsGroupCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Layout Style")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.top, 12)

                    Text("How episodes appear on TV show details")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)

                    HStack(spacing: 12) {
                        LayoutOptionButton(
                            title: "Horizontal",
                            icon: "rectangle.split.3x1.fill",
                            isSelected: episodeLayout == "horizontal"
                        ) {
                            episodeLayout = "horizontal"
                        }

                        LayoutOptionButton(
                            title: "Vertical",
                            icon: "list.bullet",
                            isSelected: episodeLayout == "vertical"
                        ) {
                            episodeLayout = "vertical"
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }

            // Episode Layout Preview
            CollapsiblePreviewSection(title: "Episode Preview", isExpanded: $showEpisodePreview) {
                if episodeLayout == "horizontal" {
                    horizontalEpisodePreview
                } else {
                    verticalEpisodePreview
                }
            }

            // Suggested Rows Layout
            SettingsSectionHeader(title: "Suggested Rows")
            SettingsGroupCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Layout Style")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.top, 12)

                    Text("How Related and Similar content appears")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)

                    HStack(spacing: 12) {
                        LayoutOptionButton(
                            title: "Landscape",
                            icon: "rectangle.fill",
                            isSelected: suggestedLayout == "landscape"
                        ) {
                            suggestedLayout = "landscape"
                        }

                        LayoutOptionButton(
                            title: "Poster",
                            icon: "rectangle.portrait.fill",
                            isSelected: suggestedLayout == "poster"
                        ) {
                            suggestedLayout = "poster"
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }

            // Suggested Layout Preview
            CollapsiblePreviewSection(title: "Suggested Preview", isExpanded: $showSuggestedPreview) {
                if suggestedLayout == "landscape" {
                    suggestedLandscapePreview
                } else {
                    suggestedPosterPreview
                }
            }

            // Content Display
            SettingsSectionHeader(title: "Content Display")
            SettingsGroupCard {
                SettingsRow(icon: "rectangle.stack.fill", iconColor: .blue, title: "Show Related Content") {
                    Toggle("", isOn: $showRelatedContent).labelsHidden()
                }
                SettingsRow(icon: "person.2.fill", iconColor: .purple, title: "Show Cast & Crew", showDivider: false) {
                    Toggle("", isOn: $showCastCrew).labelsHidden()
                }
            }

            Text("These settings apply to movie and TV show detail pages.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Episode Previews

    private var horizontalEpisodePreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Horizontal scroll of episode cards
            HStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { index in
                    ZStack(alignment: .bottomLeading) {
                        // Thumbnail
                        RoundedRectangle(cornerRadius: 10)
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
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        // Content
                        VStack(alignment: .leading, spacing: 4) {
                            Text("EPISODE \(index + 1)")
                                .font(.system(size: 8, weight: .bold))
                                .tracking(0.5)
                                .foregroundStyle(.white.opacity(0.8))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.black.opacity(0.4))
                                .clipShape(RoundedRectangle(cornerRadius: 4))

                            Text(["Pilot", "The One Where...", "Winter Is Coming"][index])
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            Text("45m")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .padding(8)

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
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            Text("Horizontal: Scrollable cards with thumbnails and progress")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var verticalEpisodePreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Vertical list of episode rows
            VStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    HStack(spacing: 12) {
                        // Thumbnail
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
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
                                .font(.system(size: 20))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .frame(width: 100)

                        // Info
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("\(index + 1). \(["Pilot", "The One Where...", "Winter Is Coming"][index])")
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(1)

                                Spacer()

                                if index == 0 {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.green)
                                }
                            }

                            Text("A brief description of the episode goes here...")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)

                            Text("45 min")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.05))
                    )
                }
            }

            Text("Vertical: Compact list with descriptions and watched status")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Suggested Row Previews

    private var suggestedLandscapePreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Text("Related")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("See All")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            // Landscape cards
            HStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 6) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
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
                                .font(.system(size: 24))
                                .foregroundStyle(.white.opacity(0.8))
                        }

                        Text(["The Godfather", "Goodfellas", "Casino"][index])
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)

                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.yellow)
                            Text(["9.2", "8.7", "8.2"][index])
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 130)
                }
            }

            Text("Landscape: Wide thumbnails with ratings")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var suggestedPosterPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Text("Related")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("See All")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            // Poster cards
            HStack(spacing: 10) {
                ForEach(0..<5, id: \.self) { index in
                    VStack(alignment: .center, spacing: 6) {
                        ZStack(alignment: .topTrailing) {
                            RoundedRectangle(cornerRadius: 8)
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
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 7))
                                Text(["9.2", "8.7", "8.2", "7.9", "8.5"][index])
                                    .font(.system(size: 8, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .padding(4)
                        }

                        Text(["Godfather", "Goodfellas", "Casino", "Scarface", "Heat"][index])
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                    }
                    .frame(width: 70)
                }
            }

            Text("Poster: More items visible with compact layout")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}
