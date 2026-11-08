//
//  StreamEpisodeNavigator.swift
//  FlixorMac
//
//  Episode lists and "next episode" for addon (Stremio) series streams, from TMDB
//  first and the Stremio addon meta as a fallback.
//

import Foundation
import FlixorKit

/// One episode of a series being played from an addon stream.
struct StreamEpisodeInfo: Hashable {
    let season: Int
    let episode: Int
    let title: String
    let overview: String?
    /// Absolute image URL (TMDB still or addon thumbnail).
    let stillURL: String?
    let airDate: String?
    let runtimeMinutes: Int?
    let hasAired: Bool

    var label: String { "S\(season)E\(episode)" }
}

/// The series + episode behind a StreamPlaybackItem, parsed from its content key
/// (`series:<baseId>:<season>:<episode>`; baseId may itself contain colons).
struct StreamSeriesRef: Hashable {
    let baseId: String
    let season: Int
    let episode: Int
    let imdbId: String?
    let tmdbId: Int?

    init?(item: StreamPlaybackItem) {
        guard item.mediaType == .episode else { return nil }
        let parts = item.contentKey.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 4, parts[0] == StremioRequestType.series.rawValue,
              let season = Int(parts[parts.count - 2]) ?? item.seasonNumber,
              let episode = Int(parts[parts.count - 1]) ?? item.episodeNumber else { return nil }
        let baseId = parts[1..<(parts.count - 2)].joined(separator: ":")
        guard !baseId.isEmpty else { return nil }
        self.baseId = baseId
        self.season = season
        self.episode = episode
        self.imdbId = item.imdbId ?? (baseId.hasPrefix("tt") ? baseId : nil)
        self.tmdbId = item.tmdbId ?? (baseId.hasPrefix("tmdb:") ? Int(baseId.dropFirst(5)) : nil)
    }

    /// Anime-database id embedded in the base id (`kitsu:123`, `mal:456`).
    var kitsuId: String? { baseId.hasPrefix("kitsu:") ? String(baseId.dropFirst(6)) : nil }
    var malId: String? { baseId.hasPrefix("mal:") ? String(baseId.dropFirst(4)) : nil }

    /// Stremio request identity for another episode of the same series.
    func identity(season: Int, episode: Int, source: String) -> StremioContentIdentity {
        StremioContentIdentity(
            requestType: StremioRequestType.series.rawValue,
            baseId: baseId,
            requestId: "\(baseId):\(season):\(episode)",
            imdbId: imdbId,
            tmdbId: tmdbId,
            seasonNumber: season,
            episodeNumber: episode,
            source: source
        )
    }
}

@MainActor
enum StreamEpisodeNavigator {
    struct Result {
        /// Episodes of the current season, in order.
        let seasonEpisodes: [StreamEpisodeInfo]
        /// The next aired episode (same season, else first episode of the next season).
        let next: StreamEpisodeInfo?
    }

    static func episodes(for ref: StreamSeriesRef) async -> Result {
        if let tmdbId = await resolveTmdbId(ref), let result = await tmdbEpisodes(tmdbId: tmdbId, ref: ref) {
            return result
        }
        if let result = await stremioMetaEpisodes(ref: ref) {
            return result
        }
        return Result(seasonEpisodes: [], next: nil)
    }

    /// Season numbers of the series, regular seasons first, specials last.
    static func seasonNumbers(for ref: StreamSeriesRef) async -> [Int] {
        guard let tmdbId = await resolveTmdbId(ref),
              let details = try? await FlixorCore.shared.tmdb.getTVDetails(id: tmdbId) else { return [] }
        let numbers = details.seasons.compactMap { summary -> Int? in
            guard let number = summary.seasonNumber, (summary.episodeCount ?? 0) > 0 else { return nil }
            return number
        }
        return numbers.filter { $0 > 0 }.sorted() + numbers.filter { $0 == 0 }
    }

    /// All episodes of one season.
    static func episodes(for ref: StreamSeriesRef, season: Int) async -> [StreamEpisodeInfo] {
        guard let tmdbId = await resolveTmdbId(ref),
              let details = try? await FlixorCore.shared.tmdb.getSeasonDetails(tvId: tmdbId, seasonNumber: season) else { return [] }
        return details.episodes
            .compactMap { info(from: $0, season: season) }
            .sorted { $0.episode < $1.episode }
    }

    // MARK: - TMDB

    private static func resolveTmdbId(_ ref: StreamSeriesRef) async -> Int? {
        if let tmdbId = ref.tmdbId { return tmdbId }
        if let imdbId = ref.imdbId {
            return await MediaIdentityResolver.shared.tmdbId(imdbId: imdbId, isShow: true)
        }
        return nil
    }

    private static func tmdbEpisodes(tmdbId: Int, ref: StreamSeriesRef) async -> Result? {
        do {
            let season = try await FlixorCore.shared.tmdb.getSeasonDetails(tvId: tmdbId, seasonNumber: ref.season)
            let current = season.episodes
                .compactMap { info(from: $0, season: ref.season) }
                .sorted { $0.episode < $1.episode }
            guard !current.isEmpty else { return nil }

            if let next = current.first(where: { $0.episode > ref.episode }) {
                return Result(seasonEpisodes: current, next: next.hasAired ? next : nil)
            }
            // Season 0 (specials) never rolls over into season 1.
            guard ref.season > 0 else { return Result(seasonEpisodes: current, next: nil) }

            let details = try await FlixorCore.shared.tmdb.getTVDetails(id: tmdbId)
            let nextSeasonNumber = details.seasons
                .compactMap { summary -> Int? in
                    guard let number = summary.seasonNumber, number > ref.season, (summary.episodeCount ?? 0) > 0 else { return nil }
                    return number
                }
                .min()
            guard let nextSeasonNumber else { return Result(seasonEpisodes: current, next: nil) }
            let nextSeason = try await FlixorCore.shared.tmdb.getSeasonDetails(tvId: tmdbId, seasonNumber: nextSeasonNumber)
            let first = nextSeason.episodes
                .compactMap { info(from: $0, season: nextSeasonNumber) }
                .min { $0.episode < $1.episode }
            return Result(seasonEpisodes: current, next: first?.hasAired == true ? first : nil)
        } catch {
            AppLogger.shared.warn("[StreamNext] TMDB episode lookup failed", data: [
                "tmdbId": tmdbId, "season": ref.season, "error": error.localizedDescription,
            ])
            return nil
        }
    }

    private static func info(from episode: TMDBEpisode, season: Int) -> StreamEpisodeInfo? {
        guard let number = episode.episodeNumber else { return nil }
        return StreamEpisodeInfo(
            season: episode.seasonNumber ?? season,
            episode: number,
            title: episode.name,
            overview: episode.overview,
            stillURL: ImageService.shared.tmdbImageURL(path: episode.stillPath, size: .w500)?.absoluteString,
            airDate: episode.airDate,
            runtimeMinutes: episode.runtime,
            // TMDB lists announced episodes without a date; treat those as not aired.
            hasAired: hasAired(episode.airDate, missingMeansAired: false)
        )
    }

    // MARK: - Stremio meta

    private static func stremioMetaEpisodes(ref: StreamSeriesRef) async -> Result? {
        guard let meta = await StremioService.shared.getMeta(type: StremioRequestType.series.rawValue, id: ref.baseId),
              let videos = meta.videos, !videos.isEmpty else { return nil }
        let all = videos
            .compactMap { video -> StreamEpisodeInfo? in
                guard let season = video.season, let episode = video.episode else { return nil }
                return StreamEpisodeInfo(
                    season: season,
                    episode: episode,
                    title: video.title ?? String(localized: "Episode \(String(episode))"),
                    overview: video.overview,
                    stillURL: video.thumbnail,
                    airDate: video.released,
                    runtimeMinutes: nil,
                    hasAired: hasAired(video.released, missingMeansAired: true)
                )
            }
            .sorted { ($0.season, $0.episode) < ($1.season, $1.episode) }
        guard let currentIndex = all.firstIndex(where: { $0.season == ref.season && $0.episode == ref.episode }) else {
            return nil
        }
        let seasonEpisodes = all.filter { $0.season == ref.season }
        var next: StreamEpisodeInfo?
        if currentIndex + 1 < all.count {
            let candidate = all[currentIndex + 1]
            // Specials don't roll over into regular seasons.
            if candidate.hasAired, ref.season > 0 || candidate.season == 0 {
                next = candidate
            }
        }
        return Result(seasonEpisodes: seasonEpisodes, next: next)
    }

    // MARK: - Helpers

    /// `YYYY-MM-DD…` on or before today.
    static func hasAired(_ raw: String?, missingMeansAired: Bool) -> Bool {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), raw.count >= 10 else { return missingMeansAired }
        let day = String(raw.prefix(10))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: day) else { return missingMeansAired }
        return date <= Date()
    }
}

extension StreamEpisodeInfo {
    /// Adapter for the player's existing next-episode UI (countdown, hover card, episode list).
    func episodeMetadata(baseId: String) -> EpisodeMetadata {
        EpisodeMetadata(
            ratingKey: "stream-episode:\(baseId):\(season):\(episode)",
            title: title,
            index: episode,
            parentIndex: season,
            thumb: stillURL,
            summary: overview,
            viewOffset: nil,
            duration: runtimeMinutes.map { $0 * 60_000 },
            viewCount: nil
        )
    }
}

/// Result of looking up a source for another episode of an addon series.
enum StreamEpisodeSourceOutcome {
    /// A source was picked automatically (same addon + binge group, else best ranked).
    case playable(StreamPlaybackItem)
    /// Sources exist but none could be picked automatically; open the picker.
    case needsPicker(StremioSourcesDestination)
    /// Nothing playable was found; message explains why.
    case unavailable(String)
}
