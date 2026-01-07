//
//  HomeScreenSettingsView.swift
//  FlixorMac
//
//  Home screen customization settings
//

import SwiftUI

struct HomeScreenSettingsView: View {
    @AppStorage("heroLayout") private var heroLayout: String = "billboard"
    @AppStorage("showHeroSection") private var showHeroSection: Bool = true
    @AppStorage("showContinueWatching") private var showContinueWatching: Bool = true
    @AppStorage("showTrendingRows") private var showTrendingRows: Bool = true
    @AppStorage("showTraktRows") private var showTraktRows: Bool = true
    @AppStorage("showPlexPopular") private var showPlexPopular: Bool = true
    @AppStorage("rowLayout") private var rowLayout: String = "landscape"
    @AppStorage("posterSize") private var posterSize: String = "medium"
    @AppStorage("showPosterTitles") private var showPosterTitles: Bool = true
    @AppStorage("episodeLayout") private var episodeLayout: String = "horizontal"

    private let heroOptions = [
        ("billboard", "Billboard"),
        ("carousel", "Carousel")
    ]

    private let rowLayoutOptions = [
        ("landscape", "Landscape"),
        ("poster", "Poster")
    ]

    private let episodeLayoutOptions = [
        ("horizontal", "Horizontal"),
        ("vertical", "Vertical")
    ]

    private let posterSizeOptions = [
        ("small", "Small"),
        ("medium", "Medium"),
        ("large", "Large")
    ]

    @State private var showContinueWatchingOptions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            heroSection
            rowLayoutSection
            episodeLayoutSection
            rowVisibilitySection
            continueWatchingSection
            posterDisplaySection
        }
        .sheet(isPresented: $showContinueWatchingOptions) {
            ContinueWatchingSettingsView()
                .frame(width: 500, height: 600)
                .padding(20)
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hero Section")
                .font(.headline)

            Toggle("Show Hero Section", isOn: $showHeroSection)

            if showHeroSection {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Layout")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ForEach(heroOptions, id: \.0) { value, label in
                            Button(action: { heroLayout = value }) {
                                Text(label)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        heroLayout == value
                                            ? Color.white
                                            : Color.white.opacity(0.06)
                                    )
                                    .foregroundStyle(heroLayout == value ? Color.black : Color.primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.leading, 20)
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var rowLayoutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Row Layout")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Choose how content rows display on the home screen")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(rowLayoutOptions, id: \.0) { value, label in
                        Button(action: { rowLayout = value }) {
                            VStack(spacing: 6) {
                                Image(systemName: value == "landscape" ? "rectangle.split.3x1" : "rectangle.grid.2x2")
                                    .font(.title2)
                                Text(label)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                rowLayout == value
                                    ? Color.white
                                    : Color.white.opacity(0.06)
                            )
                            .foregroundStyle(rowLayout == value ? Color.black : Color.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var episodeLayoutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Episode Layout")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Choose how episodes display on TV show details")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(episodeLayoutOptions, id: \.0) { value, label in
                        Button(action: { episodeLayout = value }) {
                            VStack(spacing: 6) {
                                Image(systemName: value == "horizontal" ? "rectangle.split.1x2.fill" : "list.bullet")
                                    .font(.title2)
                                Text(label)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                episodeLayout == value
                                    ? Color.white
                                    : Color.white.opacity(0.06)
                            )
                            .foregroundStyle(episodeLayout == value ? Color.black : Color.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var rowVisibilitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Row Visibility")
                .font(.headline)

            Toggle("Continue Watching", isOn: $showContinueWatching)
            Toggle("Trending", isOn: $showTrendingRows)
            Toggle("Trakt Rows", isOn: $showTraktRows)
            Toggle("Popular on Plex", isOn: $showPlexPopular)

            Text("Toggle which content rows appear on your home screen.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(18)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var continueWatchingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Continue Watching")
                .font(.headline)

            Button(action: { showContinueWatchingOptions = true }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Display & Caching Options")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Text("Layout style, stream caching settings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var posterDisplaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Poster Display")
                .font(.headline)

            Toggle("Show Titles", isOn: $showPosterTitles)

            VStack(alignment: .leading, spacing: 8) {
                Text("Poster Size")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(posterSizeOptions, id: \.0) { value, label in
                        Button(action: { posterSize = value }) {
                            Text(label)
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    posterSize == value
                                        ? Color.white
                                        : Color.white.opacity(0.06)
                                )
                                .foregroundStyle(posterSize == value ? Color.black : Color.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}
