//
//  DetailsEpisodeExtras.swift
//  FlixorMac
//
//  Small pieces of the Episodes section: rating chip, watched toggle, spoiler
//  notice and the season poster picker.
//

import SwiftUI

// MARK: - Rating chip

/// TMDB episode rating (0-10).
struct EpisodeRatingChip: View {
    let rating: Double

    @Environment(\.flixorTheme) private var theme

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            Image(systemName: "star.fill")
                .font(.flixorIcon(DS.Icon.xs - 3, weight: .semibold))
                .foregroundStyle(theme.warning)
            Text(String(format: "%.1f", rating))
                .flixorFont(.micro)
                .foregroundStyle(theme.textPrimary)
        }
        .padding(.horizontal, DS.Space.s6)
        .padding(.vertical, DS.Space.s4)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                .fill(theme.scrim(DS.Opacity.scrimMedium))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(format: String(localized: "Rated %.1f out of 10"), rating)))
        .help("TMDB rating")
    }
}

// MARK: - Spoiler notice

/// Shown instead of an unwatched episode's description while spoiler
/// protection is on. Hovering the card reveals it.
struct EpisodeSpoilerNotice: View {
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        Label("Description hidden. Hover to reveal.", systemImage: "eye.slash")
            .flixorFont(.footnote)
            .italic()
            .foregroundStyle(theme.textTertiary)
            .lineLimit(1)
    }
}

// MARK: - Watched toggle

/// Watched indicator that toggles the episode's watched state.
struct EpisodeWatchedButton: View {
    enum Style { case compact, regular }

    let isWatched: Bool
    let style: Style
    var isDisabled: Bool = false
    let action: () -> Void

    @Environment(\.flixorTheme) private var theme

    private var size: CGFloat { style == .compact ? 22 : DS.Icon.lg }

    var body: some View {
        Button(action: action) {
            Group {
                if style == .compact {
                    ZStack {
                        Circle()
                            .fill(isWatched ? Color.white : theme.scrim(DS.Opacity.scrimMedium))
                        Circle()
                            .strokeBorder(Color.white.opacity(isWatched ? 0 : DS.Opacity.secondary), lineWidth: DS.Border.thin)
                        Image(systemName: "checkmark")
                            .font(.flixorIcon(DS.Icon.xs, weight: .bold))
                            .foregroundStyle(isWatched ? Color.black : Color.white.opacity(DS.Opacity.secondary))
                    }
                    .frame(width: size, height: size)
                } else {
                    Image(systemName: isWatched ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.flixor(.title3))
                        .foregroundStyle(isWatched ? theme.success : theme.textSecondary)
                        .frame(width: size, height: size)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? DS.Opacity.tertiary : 1)
        .help(isWatched ? "Mark as unwatched" : "Mark as watched")
        .accessibilityLabel(Text(isWatched ? "Watched. Mark as unwatched" : "Mark as watched"))
    }
}

// MARK: - Season poster picker

/// Season picker that shows each season's poster and episode count.
struct SeasonPosterPicker: View {
    let seasons: [DetailsViewModel.Season]
    let selectedKey: String
    let art: [String: DetailsEpisodeStateModel.SeasonArt]
    let fallbackPoster: URL?
    let onSelect: (String) -> Void

    @Environment(\.windowMetrics) private var metrics

    var body: some View {
        DetailsHorizontalRow {
            LazyHStack(alignment: .top, spacing: DS.Space.s14) {
                ForEach(seasons) { season in
                    SeasonPosterTile(
                        season: season,
                        art: art[season.id],
                        fallbackPoster: fallbackPoster,
                        isSelected: season.id == selectedKey,
                        width: metrics.posterWidth(base: 110),
                        onTap: { onSelect(season.id) }
                    )
                }
            }
            .padding(.vertical, DS.Space.s6)
        }
    }
}

private struct SeasonPosterTile: View {
    let season: DetailsViewModel.Season
    let art: DetailsEpisodeStateModel.SeasonArt?
    let fallbackPoster: URL?
    let isSelected: Bool
    let width: CGFloat
    let onTap: () -> Void

    @Environment(\.flixorTheme) private var theme
    @State private var isHovered = false

    private var countText: String? {
        guard let count = art?.episodeCount, count > 0 else { return nil }
        let episodes = String(localized: "\(count) episodes")
        if let watched = art?.watchedCount, watched > 0 {
            return watched >= count ? String(localized: "\(episodes), watched") : String(localized: "\(watched) of \(count) watched")
        }
        return episodes
    }

    private var isFullyWatched: Bool {
        guard let count = art?.episodeCount, let watched = art?.watchedCount, count > 0 else { return false }
        return watched >= count
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                ZStack(alignment: .topTrailing) {
                    poster
                        .frame(width: width, height: width * DS.Layout.posterAspect)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.compactCard, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.compactCard, style: .continuous)
                                .strokeBorder(
                                    isSelected ? theme.accent : Color.white.opacity(isHovered ? DS.Opacity.tertiary : DS.Opacity.pressed),
                                    lineWidth: isSelected ? DS.Border.focus + 1 : DS.Border.thin
                                )
                        )

                    if isFullyWatched {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.flixorIcon(DS.Icon.md))
                            .foregroundStyle(Color.white, theme.success)
                            .padding(DS.Space.s6)
                    }
                }
                .scaleEffect(isHovered && !isSelected ? 1.03 : 1)
                .flixorShadow(isHovered ? .card : .raised)

                Text(season.title)
                    .flixorFont(.callout, weight: isSelected ? .bold : .medium)
                    .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)
                    .lineLimit(1)
                if let countText {
                    Text(countText)
                        .flixorFont(.caption)
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DS.Motion.quick) { isHovered = hovering }
        }
        .accessibilityLabel(Text([season.title, countText].compactMap { $0 }.joined(separator: ", ")))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder private var poster: some View {
        if let url = art?.posterURL ?? fallbackPoster {
            CachedAsyncImage(url: url, aspectRatio: 2.0 / 3.0, contentMode: .fill)
        } else {
            ZStack {
                theme.surfaceElevated
                Text(season.number.map { "S\($0)" } ?? season.title)
                    .flixorFont(.title2)
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }
}
