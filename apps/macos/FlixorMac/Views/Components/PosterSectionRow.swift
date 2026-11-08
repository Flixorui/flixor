//
//  PosterSectionRow.swift
//  FlixorMac
//
//  Generic poster section row for displaying any content as poster cards
//

import SwiftUI

struct PosterSectionRow: View {
    let section: LibrarySection
    var onTap: (MediaItem) -> Void
    var onBrowse: ((BrowseContext) -> Void)?

    @ObservedObject private var profileSettings = ProfileSettings.shared
    @ObservedObject private var cardStyle = CardStyleStore.shared
    @Environment(\.windowMetrics) private var metrics

    private var posterWidth: CGFloat {
        metrics.posterWidth(base: CardPosterSize(stored: profileSettings.posterSize).baseWidth)
    }

    private var posterHeight: CGFloat {
        posterWidth * DS.Layout.posterAspect
    }

    /// Posters plus, when titles are always shown, their caption.
    private var rowHeight: CGFloat {
        posterHeight + (cardStyle.titleMode == .always ? CardMetrics.posterCaptionHeight : 0)
    }

    var body: some View {
        CarouselRow(
            title: section.title,
            items: section.items,
            itemWidth: posterWidth,
            spacing: 14,
            rowHeight: rowHeight, // Match exact content height to fix hover offset
            browseAction: section.browseContext.map { context in
                { onBrowse?(context) }
            }
        ) { item in
            PosterSectionCard(
                item: item,
                width: posterWidth,
                onTap: { onTap(item) }
            )
        }
    }
}

// MARK: - Poster Section Card

struct PosterSectionCard: View {
    let item: MediaItem
    let width: CGFloat
    var onTap: (() -> Void)?

    @State private var isHovered = false
    @State private var posterURL: URL?
    @ObservedObject private var cardStyle = CardStyleStore.shared

    private var height: CGFloat { width * 1.5 }

    private var cornerRadius: CGFloat { cardStyle.cornerStyle.posterRadius }

    private var ratingBadgeValue: Double? {
        guard cardStyle.showRatingBadges, let rating = item.rating, rating > 0 else { return nil }
        return rating
    }

    private var showsHoverTitle: Bool { isHovered && cardStyle.titleMode == .hover }

    // For episodes: show series title, otherwise item title
    private var displayTitle: String {
        if item.type == "episode", let seriesTitle = item.grandparentTitle {
            return seriesTitle
        }
        return item.title
    }

    // For episodes: format as S1E1
    private var episodeLabel: String? {
        guard item.type == "episode" else { return nil }
        let season = item.parentIndex ?? 1
        let episode = item.index ?? 1
        return "S\(season)E\(episode)"
    }

    // Check if this is a grouped recently added item (flagged by groupEpisodesBySeries)
    private var isGroupedRecentlyAdded: Bool {
        item.isGroupedRecentlyAddedShow
    }

    // Badge text: shows episode count for grouped items, otherwise TV/episode label
    private var badgeText: String {
        // For grouped recently added shows - show just the count
        if isGroupedRecentlyAdded, let count = item.leafCount, count > 0 {
            return "\(count)"
        }
        // For individual episodes
        if item.type == "episode" {
            return episodeLabel ?? "TV"
        }
        // Default for shows
        return "TV"
    }

    // Badge color: semi-transparent black for all badges
    private var badgeColor: Color {
        return Color.black.opacity(0.6)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            artworkButton

            if cardStyle.titleMode == .always {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    Text(displayTitle)
                        .flixorFont(.callout, weight: .medium)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let caption = captionText {
                        Text(caption)
                            .flixorFont(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                // Fixed height keeps artwork aligned when a card has no caption line.
                .frame(width: width, height: CardMetrics.posterCaptionHeight - DS.Space.s6, alignment: .topLeading)
                .accessibilityHidden(true) // Part of the card's label
            }
        }
        .frame(width: width, alignment: .top)
        .task(id: item.id) {
            await loadPoster()
        }
    }

    private var captionText: String? {
        let parts = [episodeLabel, item.year.map(String.init)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var artworkButton: some View {
        Button(action: { onTap?() }) {
            ZStack(alignment: .bottom) {
                // Poster Image - for episodes, use series poster (grandparentThumb)
                CachedAsyncImage(
                    url: posterURL ?? resolveDefaultPosterURL()
                )
                .aspectRatio(contentMode: .fill)
                .frame(width: width, height: height)
                .clipped()
                .background(Color.gray.opacity(0.2))
                .accessibilityHidden(true)

                // Gradient overlay (only on hover)
                if showsHoverTitle {
                    LinearGradient(
                        colors: [
                            .black.opacity(0.0),
                            .black.opacity(0.75)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: width, height: height)
                    .transition(.opacity)
                }

                // Title overlay (only on hover)
                if showsHoverTitle {
                    VStack(alignment: .leading, spacing: DS.Space.s4) {
                        // Series/Movie title
                        Text(displayTitle)
                            .font(.flixor(.callout, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        HStack(spacing: DS.Space.s6) {
                            // Episode label (S1E1 format)
                            if let epLabel = episodeLabel {
                                Text(epLabel)
                                    .font(.flixor(.caption, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.85))
                            }

                            if let year = item.year {
                                Text(String(year))
                                    .font(.flixor(.caption))
                                    .foregroundStyle(.white.opacity(0.85))
                            }

                            if let rating = item.rating {
                                HStack(spacing: DS.Space.s2) {
                                    Image(systemName: "star.fill")
                                        .font(.flixor(.nano))
                                    Text(String(format: "%.1f", rating))
                                        .font(.flixor(.caption))
                                }
                                .foregroundStyle(.yellow.opacity(0.9))
                            }
                        }
                    }
                    .frame(width: width - 16, alignment: .leading)
                    .padding(DS.Space.s8)
                    .transition(.opacity)
                }

                // Type badge (top trailing)
                // Shows "X new" for grouped recently added episodes, otherwise shows TV/episode label
                if item.type == "show" || item.type == "episode" {
                    VStack {
                        HStack {
                            Spacer()
                            Text(badgeText)
                                .font(.flixor(.micro, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, DS.Space.s6)
                                .padding(.vertical, 3)
                                .background(badgeColor)
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r4))
                                .padding(DS.Space.s6)
                        }
                        Spacer()
                    }
                }
            }
            .frame(width: width, height: height)
            .overlay(alignment: .topLeading) {
                if let rating = ratingBadgeValue {
                    CardRatingBadge(rating: rating).padding(DS.Space.s6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(isHovered ? 0.6 : 0.1), lineWidth: isHovered ? 2 : 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle()) // Ensures full button area is clickable
        .cardInteractions(item: item, cornerRadius: cornerRadius, isHovered: $isHovered, onOpen: onTap)
    }

    /// Resolve default poster URL - for episodes use series poster
    private func resolveDefaultPosterURL() -> URL? {
        if item.type == "episode", let grandparentThumb = item.grandparentThumb {
            // Use series poster for episodes
            return ImageService.shared.plexImageURL(path: grandparentThumb, width: Int(width * 2), height: Int(height * 2))
        }
        return ImageService.shared.thumbURL(
            for: item,
            width: Int(width * 2),
            height: Int(height * 2)
        )
    }

    private func loadPoster() async {
        // Try to get TMDB poster
        do {
            if let url = try await resolveTMDBPoster() {
                await MainActor.run {
                    self.posterURL = url
                }
            }
        } catch {
            // Silent fallback to Plex image
        }
    }

    private func resolveTMDBPoster() async throws -> URL? {
        // Handle tmdb: prefix
        if item.id.hasPrefix("tmdb:") {
            let parts = item.id.split(separator: ":")
            if parts.count == 3 {
                let media = (parts[1] == "movie") ? "movie" : "tv"
                let id = String(parts[2])
                return try await fetchTMDBPoster(mediaType: media, id: id)
            }
            return nil
        }

        // For episodes, try to get series poster via grandparentRatingKey
        if item.type == "episode", let seriesKey = item.grandparentRatingKey {
            return try await fetchPlexTMDBPoster(ratingKey: seriesKey, mediaType: "tv")
        }

        // Handle plex: prefix
        if item.id.hasPrefix("plex:") {
            let rk = String(item.id.dropFirst(5))
            return try await fetchPlexTMDBPoster(ratingKey: rk)
        }

        // Handle raw numeric ID
        if item.id.allSatisfy({ $0.isNumber }) {
            return try await fetchPlexTMDBPoster(ratingKey: item.id)
        }

        return nil
    }

    private func fetchPlexTMDBPoster(ratingKey: String, mediaType: String? = nil) async throws -> URL? {
        struct PlexMeta: Codable { let type: String?; let Guid: [PlexGuid]? }
        struct PlexGuid: Codable { let id: String? }

        let meta: PlexMeta = try await APIClient.shared.get("/api/plex/metadata/\(ratingKey)")
        let resolvedType = mediaType ?? ((meta.type == "movie") ? "movie" : "tv")

        if let guid = meta.Guid?.compactMap({ $0.id }).first(where: { $0.contains("tmdb://") || $0.contains("themoviedb://") }),
           let tid = guid.components(separatedBy: "://").last {
            return try await fetchTMDBPoster(mediaType: resolvedType, id: tid)
        }
        return nil
    }

    private func fetchTMDBPoster(mediaType: String, id: String) async throws -> URL? {
        struct TMDBDetails: Codable { let poster_path: String? }

        let details: TMDBDetails = try await APIClient.shared.get("/api/tmdb/\(mediaType)/\(id)")

        guard let path = details.poster_path else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(path)")
    }
}
