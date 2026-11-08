//
//  LandscapeCard.swift
//  FlixorMac
//
//  Generic landscape (backdrop) card used for rows like On Deck and Recently Added
//

import SwiftUI
import FlixorKit

struct LandscapeCard: View {
    let item: MediaItem
    let width: CGFloat
    var onTap: (() -> Void)?
    var showProgressBar: Bool = false // Optional progress bar overlay

    @State private var isHovered = false
    @State private var altURL: URL? = nil
    @ObservedObject private var cardStyle = CardStyleStore.shared
    @Environment(\.flixorTheme) private var theme

    private var height: CGFloat {
        width * 0.5 // 2:1 aspect to match web rows
    }

    private var cornerRadius: CGFloat { cardStyle.cornerStyle.landscapeRadius }

    private var ratingBadgeValue: Double? {
        guard cardStyle.showRatingBadges, let rating = item.rating, rating > 0 else { return nil }
        return rating
    }

    private var progressPercentage: Double {
        guard showProgressBar,
              let duration = item.duration, duration > 0,
              let viewOffset = item.viewOffset else {
            return 0
        }
        return (Double(viewOffset) / Double(duration)) * 100.0
    }

    private var yearEditionText: String {
        var parts: [String] = []
        if let year = item.year {
            parts.append(String(year))
        }
        if let edition = item.editionTitle {
            parts.append(edition)
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Button(action: { onTap?() }) {
            ZStack(alignment: .bottomLeading) {
                // Backdrop image
                CachedAsyncImage(url: altURL ?? ResolvedArtworkCache.shared.url(for: artworkCacheKey) ?? ImageService.shared.continueWatchingURL(for: item, width: Int(width * 2), height: Int(height * 2)))
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipped()
                    .background(Color.white.opacity(0.05))
                    .accessibilityHidden(true)

                // Gradient overlay (only on hover)
                if isHovered {
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
                if isHovered {
                    VStack(alignment: .leading, spacing: DS.Space.s4) {
                        // For episodes, show the show name (grandparentTitle)
                        // For movies, show the movie title
                        Text(item.type == "episode" ? (item.grandparentTitle ?? item.title) : item.title)
                            .font(.flixor(.bodyLarge, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if let label = item.episodeLabel {
                            Text(label)
                                .font(.flixor(.footnote))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                        } else if item.year != nil || item.editionTitle != nil {
                            // For movies/shows, show year and edition
                            Text(yearEditionText)
                                .font(.flixor(.footnote))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                        }
                    }
                    .padding(DS.Space.s12)
                    .transition(.opacity)
                }

                // Progress bar overlay (optional)
                if progressPercentage > 0 {
                    VStack {
                        Spacer()
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.2))
                                    .frame(height: 6)

                                Rectangle()
                                    .fill(theme.accent)
                                    .frame(width: geometry.size.width * CGFloat(min(100, max(0, progressPercentage))) / 100.0, height: 6)
                            }
                        }
                        .frame(height: 6)
                    }
                }
            }
            .frame(width: width, height: height)
            .overlay(alignment: .topLeading) {
                if let rating = ratingBadgeValue {
                    CardRatingBadge(rating: rating).padding(DS.Space.s8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(isHovered ? 0.9 : 0.15), lineWidth: isHovered ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .cardInteractions(item: item, cornerRadius: cornerRadius, isHovered: $isHovered, onOpen: onTap)
        .task(id: item.id) {
            await fetchTMDBBackdrop()
        }
    }

    // MARK: - TMDB Backdrop Upgrade (original size via proxy)
    private var artworkCacheKey: String { "landscape:\(item.id):\(Int(width))" }

    private func fetchTMDBBackdrop() async {
        guard !ResolvedArtworkCache.shared.isResolved(artworkCacheKey) else { return }
        // Only attempt upgrade when underlying image is Plex-based or missing
        let url = try? await resolveTMDBBackdropURL(for: item, width: Int(width * 2), height: Int(height * 2))
        guard !Task.isCancelled else { return }
        ResolvedArtworkCache.shared.store(url, for: artworkCacheKey)
        if let url { altURL = url }
    }

    private func resolveTMDBBackdropURL(for item: MediaItem, width: Int, height: Int) async throws -> URL? {
        // For episodes, use the parent show's backdrop (grandparentRatingKey)
        if item.type == "episode", let showKey = item.grandparentRatingKey {
            print("🎬 [LandscapeCard] Episode detected, fetching parent show backdrop (showKey: \(showKey))")
            return try await fetchTMDBBackdropForPlexItem(ratingKey: showKey, width: width, height: height, forceMediaType: "tv")
        }

        // For seasons, use the parent show's backdrop (parentRatingKey)
        if item.type == "season", let showKey = item.parentRatingKey {
            print("🎬 [LandscapeCard] Season detected, fetching parent show backdrop (showKey: \(showKey))")
            return try await fetchTMDBBackdropForPlexItem(ratingKey: showKey, width: width, height: height, forceMediaType: "tv")
        }

        // Case 1: TMDB id already encoded in item.id (tmdb:movie:123 or tmdb:tv:123)
        if item.id.hasPrefix("tmdb:") {
            let parts = item.id.split(separator: ":")
            if parts.count == 3 {
                let media = (parts[1] == "movie") ? "movie" : "tv"
                let id = String(parts[2])
                if let url = try await fetchTMDBBestBackdropURL(mediaType: media, id: id, width: width, height: height) {
                    return url
                }
            }
            return nil
        }

        // Case 2: Plex item with plex: prefix – resolve TMDB guid from metadata
        if item.id.hasPrefix("plex:") {
            let rk = String(item.id.dropFirst(5))
            return try await fetchTMDBBackdropForPlexItem(ratingKey: rk, width: width, height: height)
        }

        // Case 3: Raw numeric ID (Plex rating key without prefix)
        // This happens for library items loaded from /api/plex/library/{key}/all
        if item.id.allSatisfy({ $0.isNumber }) {
            print("🔍 [LandscapeCard] Detected numeric ID, treating as Plex rating key: \(item.id)")
            return try await fetchTMDBBackdropForPlexItem(ratingKey: item.id, width: width, height: height)
        }

        return nil
    }

    private func fetchTMDBBackdropForPlexItem(ratingKey: String, width: Int, height: Int, forceMediaType: String? = nil) async throws -> URL? {
        guard let plexServer = FlixorCore.shared.plexServer else { return nil }

        let meta = try await plexServer.getMetadata(ratingKey: ratingKey)

        // For seasons, fetch the parent show's backdrop instead (fallback if not caught earlier)
        if meta.type == "season", let parentKey = meta.parentRatingKey {
            print("🎬 [LandscapeCard] Season detected in metadata, fetching parent show backdrop (parentKey: \(parentKey))")
            return try await fetchTMDBBackdropForPlexItem(ratingKey: parentKey, width: width, height: height, forceMediaType: "tv")
        }

        let mediaType = forceMediaType ?? ((meta.type == "movie") ? "movie" : "tv")

        // Extract TMDB ID from Guid array
        if let tmdbGuid = meta.guids.first(where: { $0.contains("tmdb://") || $0.contains("themoviedb://") }),
           let tmdbId = tmdbGuid.components(separatedBy: "://").last {
            return try await fetchTMDBBestBackdropURL(mediaType: mediaType, id: tmdbId, width: width, height: height)
        }
        return nil
    }

    private func fetchTMDBBestBackdropURL(mediaType: String, id: String, width: Int, height: Int) async throws -> URL? {
        guard let tmdbId = Int(id) else { return nil }

        let imgs = try await FlixorCore.shared.tmdb.getImages(mediaType: mediaType, id: tmdbId)
        let backs = imgs.backdrops
        if backs.isEmpty { return nil }

        let pick: ([FlixorKit.TMDBImage]) -> FlixorKit.TMDBImage? = { arr in
            return arr.sorted { ($0.voteAverage ?? 0) > ($1.voteAverage ?? 0) }.first
        }

        // Priority 1: English backdrops (with title text burned in)
        let en = pick(backs.filter { $0.iso6391 == "en" })
        if let path = en?.filePath {
            return URL(string: "https://image.tmdb.org/t/p/original\(path)")
        }

        // Priority 2: Any language with title (iso_639_1 is not null)
        let withLanguage = pick(backs.filter { $0.iso6391 != nil })
        if let path = withLanguage?.filePath {
            return URL(string: "https://image.tmdb.org/t/p/original\(path)")
        }

        // Priority 3: Fallback to any backdrop (including textless)
        let any = pick(backs)
        guard let path = any?.filePath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/original\(path)")
    }
}
#if DEBUG && canImport(PreviewsMacros)
#Preview {
    HStack(spacing: DS.Space.s20) {
        LandscapeCard(
            item: MediaItem(
                id: "1",
                title: "The Matrix",
                type: "movie",
                thumb: nil,
                art: "/library/metadata/1/art/123456",
                year: 1999,
                rating: 8.7,
                duration: 8100000,
                viewOffset: nil,
                summary: nil,
                grandparentTitle: nil,
                grandparentThumb: nil,
                grandparentArt: nil,
                parentIndex: nil,
                index: nil
            ),
            width: 420
        )

        LandscapeCard(
            item: MediaItem(
                id: "2",
                title: "Breaking Bad - S1:E2",
                type: "episode",
                thumb: nil,
                art: "/library/metadata/2/art/123457",
                year: nil,
                rating: nil,
                duration: nil,
                viewOffset: nil,
                summary: nil,
                grandparentTitle: "Breaking Bad",
                grandparentThumb: nil,
                grandparentArt: "/library/metadata/show1/art/123",
                parentIndex: 1,
                index: 2
            ),
            width: 420
        )
    }
    .padding()
    .background(Color.black)
}
#endif
