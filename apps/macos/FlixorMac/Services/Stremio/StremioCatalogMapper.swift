//
//  StremioCatalogMapper.swift
//  FlixorMac
//
//  Turns Stremio catalog entries into MediaItems the rest of the app can navigate.
//
//  Catalog addons (Cinemeta and friends) return IMDb ids, but the details screen,
//  season/episode loading and the Stremio stream resolver are all built around
//  `tmdb:<media>:<id>`. Mapping IMDb -> TMDB here means catalog rows reuse the whole
//  existing pipeline instead of needing a parallel one.
//
//  Titles TMDB can't match keep a `stremio:` id and fall back to addon metadata.
//

import Foundation
import FlixorKit

actor StremioCatalogMapper {
    static let shared = StremioCatalogMapper()

    /// IMDb id -> resolved TMDB id, or nil when TMDB has no match.
    /// Cached for the session so a row of 30 items costs at most 30 lookups once.
    private var tmdbIdCache: [String: Int?] = [:]
    /// IMDb id -> TMDB poster path from the same lookup.
    private var posterPathCache: [String: String] = [:]

    /// How many id lookups to run at once. Several catalog rows map in parallel, so
    /// an unbounded task group here would fire hundreds of TMDB requests at once.
    private let lookupBatchSize = 10

    /// Maps a catalog page, resolving ids in bounded batches and preserving order.
    func mediaItems(from previews: [StremioMetaPreview]) async -> [MediaItem] {
        guard !previews.isEmpty else { return [] }

        var resolved: [Int: MediaItem] = [:]
        for batch in previews.enumerated().chunked(into: lookupBatchSize) {
            await withTaskGroup(of: (Int, MediaItem).self) { group in
                for (index, preview) in batch {
                    group.addTask {
                        (index, await self.mediaItem(from: preview))
                    }
                }
                for await (index, item) in group {
                    resolved[index] = item
                }
            }
        }

        return previews.indices.compactMap { resolved[$0] }
    }

    func mediaItem(from preview: StremioMetaPreview) async -> MediaItem {
        let isSeries = preview.type == "series"
        let itemId = await resolveItemId(for: preview, isSeries: isSeries)
        // Many addons serve posters with ratings printed on them; prefer the plain
        // TMDB poster unless the user chose addon posters (Settings > Stremio).
        let tmdbPoster = preview.imdbId
            .flatMap { posterPathCache[$0] }
            .map { "https://image.tmdb.org/t/p/w500\($0)" }
        let poster = UserDefaults.standard.stremioUseAddonPosters ? preview.poster : (tmdbPoster ?? preview.poster)

        return MediaItem(
            id: itemId,
            title: preview.name,
            type: isSeries ? "show" : "movie",
            thumb: poster,
            art: preview.background,
            year: preview.year,
            rating: preview.imdbRating.flatMap(Double.init),
            duration: nil,
            viewOffset: nil,
            summary: preview.description,
            grandparentTitle: nil,
            grandparentThumb: nil,
            grandparentArt: nil,
            grandparentRatingKey: nil,
            parentIndex: nil,
            index: nil,
            parentRatingKey: nil,
            parentTitle: nil,
            leafCount: nil,
            viewedLeafCount: nil
        )
    }

    /// Prefers a `tmdb:` id so the existing details pipeline handles the item.
    private func resolveItemId(for preview: StremioMetaPreview, isSeries: Bool) async -> String {
        let media = isSeries ? "tv" : "movie"

        // Some addons already hand back TMDB ids.
        if preview.id.hasPrefix("tmdb:"), let numeric = preview.id.split(separator: ":").last {
            return "tmdb:\(media):\(numeric)"
        }

        if let imdbId = preview.imdbId,
           let tmdbId = await tmdbId(forImdbId: imdbId, isSeries: isSeries) {
            return "tmdb:\(media):\(tmdbId)"
        }

        // Unmappable: keep the addon id so Details can fall back to /meta.
        return "stremio:\(preview.type):\(preview.id)"
    }

    private func tmdbId(forImdbId imdbId: String, isSeries: Bool) async -> Int? {
        if let cached = tmdbIdCache[imdbId] {
            return cached
        }

        do {
            let response = try await FlixorCore.shared.tmdb.findByExternalId(imdbId)
            let match = isSeries
                ? (response.tvResults.first ?? response.movieResults.first)
                : (response.movieResults.first ?? response.tvResults.first)
            tmdbIdCache[imdbId] = match?.id
            if let path = match?.posterPath { posterPathCache[imdbId] = path }
            return match?.id
        } catch {
            // Don't cache failures - this may just be a transient network error.
            AppLogger.shared.warn("[Stremio] TMDB lookup failed for \(imdbId)", data: [
                "error": error.localizedDescription,
            ])
            return nil
        }
    }
}

private extension Sequence {
    /// Splits into fixed-size batches, used to bound lookup concurrency.
    func chunked(into size: Int) -> [[Element]] {
        var chunks: [[Element]] = []
        var current: [Element] = []
        for element in self {
            current.append(element)
            if current.count == size {
                chunks.append(current)
                current = []
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}
