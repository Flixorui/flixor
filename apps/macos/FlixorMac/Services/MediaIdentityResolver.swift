//
//  MediaIdentityResolver.swift
//  FlixorMac
//
//  Turns the app's item ids (Plex ratingKeys, `tmdb:` ids, IMDb ids from Stremio)
//  into the external ids other services need, with in-memory caching. Shared by
//  WatchStateService, TrailerService, EpisodeRatingsService and TraktCommentsService.
//
//  These mappings never change for a given item, so results are cached for the
//  session. Failures are not cached (they may be transient).
//

import Foundation
import FlixorKit

/// External ids for a movie or show.
struct ExternalMediaIds: Hashable {
    var tmdbId: Int?
    var imdbId: String?
    var tvdbId: Int?

    var isEmpty: Bool { tmdbId == nil && (imdbId ?? "").isEmpty && tvdbId == nil }

    /// Parses Plex GUIDs like `tmdb://603`, `imdb://tt0133093`, `tvdb://81189`,
    /// plus legacy agent forms (`com.plexapp.agents.themoviedb://603?lang=en`).
    init(plexGuids: [String]) {
        for guid in plexGuids {
            let lowered = guid.lowercased()
            guard let value = guid.components(separatedBy: "://").last?
                .components(separatedBy: "?").first?
                .components(separatedBy: "/").first,
                  !value.isEmpty else { continue }
            if lowered.hasPrefix("tmdb://") || lowered.contains("themoviedb://") {
                tmdbId = tmdbId ?? Int(value)
            } else if lowered.hasPrefix("imdb://") || lowered.contains("agents.imdb://") {
                imdbId = imdbId ?? value
            } else if lowered.hasPrefix("tvdb://") || lowered.contains("thetvdb://") {
                tvdbId = tvdbId ?? Int(value)
            }
        }
    }

    init(tmdbId: Int? = nil, imdbId: String? = nil, tvdbId: Int? = nil) {
        self.tmdbId = tmdbId
        self.imdbId = imdbId
        self.tvdbId = tvdbId
    }
}

/// Structural facts about a Plex item (no view state, safe to cache).
struct PlexItemContext: Hashable {
    let ratingKey: String
    /// movie, show, season, episode
    let type: String
    let title: String?
    /// Season number for episodes (Plex `parentIndex`).
    let parentIndex: Int?
    /// Episode number for episodes, season number for seasons (Plex `index`).
    let index: Int?
    let parentRatingKey: String?
    let grandparentRatingKey: String?
    let ids: ExternalMediaIds
}

actor MediaIdentityResolver {
    static let shared = MediaIdentityResolver()

    private var plexContexts: [String: PlexItemContext] = [:]
    private var imdbToTmdb: [String: Int] = [:]
    private var tmdbToImdb: [String: String] = [:]

    // MARK: - Plex

    /// Metadata context for a Plex ratingKey, or nil when no server is connected
    /// (or in Stremio-only mode) or the lookup fails.
    func plexContext(ratingKey: String) async -> PlexItemContext? {
        if let cached = plexContexts[ratingKey] { return cached }
        guard !isStremioOnlyMode, let plex = await FlixorCore.shared.plexServer else { return nil }
        do {
            let meta = try await plex.getMetadata(ratingKey: ratingKey)
            let context = PlexItemContext(
                ratingKey: ratingKey,
                type: meta.type ?? "",
                title: meta.title,
                parentIndex: meta.parentIndex,
                index: meta.index,
                parentRatingKey: meta.parentRatingKey,
                grandparentRatingKey: meta.grandparentRatingKey,
                ids: ExternalMediaIds(plexGuids: meta.guids)
            )
            plexContexts[ratingKey] = context
            return context
        } catch {
            AppLogger.shared.warn("[Identity] Plex metadata lookup failed", data: [
                "ratingKey": ratingKey, "error": error.localizedDescription,
            ])
            return nil
        }
    }

    /// External ids of the movie/show a Plex item belongs to. For seasons and
    /// episodes this is the SHOW's ids (what Trakt and TMDB need).
    func titleIds(plexRatingKey: String) async -> ExternalMediaIds? {
        guard let context = await plexContext(ratingKey: plexRatingKey) else { return nil }
        switch context.type {
        case "episode":
            guard let show = context.grandparentRatingKey else { return nil }
            return await plexContext(ratingKey: show)?.ids
        case "season":
            guard let show = context.parentRatingKey else { return nil }
            return await plexContext(ratingKey: show)?.ids
        default:
            return context.ids
        }
    }

    // MARK: - TMDB / IMDb

    /// TMDB id for an IMDb id (movie or show).
    func tmdbId(imdbId: String, isShow: Bool) async -> Int? {
        let key = "\(isShow ? "tv" : "movie"):\(imdbId.lowercased())"
        if let cached = imdbToTmdb[key] { return cached }
        do {
            let response = try await FlixorCore.shared.tmdb.findByExternalId(imdbId)
            let match = isShow
                ? (response.tvResults.first ?? response.movieResults.first)
                : (response.movieResults.first ?? response.tvResults.first)
            if let id = match?.id { imdbToTmdb[key] = id }
            return match?.id
        } catch {
            return nil
        }
    }

    /// IMDb id for a TMDB id (movie or show).
    func imdbId(tmdbId: Int, isShow: Bool) async -> String? {
        let key = "\(isShow ? "tv" : "movie"):\(tmdbId)"
        if let cached = tmdbToImdb[key] { return cached }
        do {
            let ext = try await FlixorCore.shared.tmdb.getExternalIds(mediaType: isShow ? "tv" : "movie", id: tmdbId)
            if let imdb = ext.imdbId, !imdb.isEmpty {
                tmdbToImdb[key] = imdb
                return imdb
            }
            return nil
        } catch {
            return nil
        }
    }

    /// The TMDB movie/show behind any MediaItem. Episodes and seasons resolve to
    /// their show. Nil when nothing can be matched.
    func tmdbIdentity(for item: MediaItem) async -> (id: Int, mediaType: TMDBMediaType)? {
        let type = item.type.lowercased()
        let isShowLike = type != "movie"

        guard let target = WatchStateTarget(item: item) else { return nil }
        if let tmdb = target.tmdbId {
            return (tmdb, isShowLike ? .tv : .movie)
        }
        if let imdb = target.imdbId, let tmdb = await tmdbId(imdbId: imdb, isShow: isShowLike) {
            return (tmdb, isShowLike ? .tv : .movie)
        }
        if let key = target.plexRatingKey, let ids = await titleIds(plexRatingKey: key) {
            if let tmdb = ids.tmdbId { return (tmdb, isShowLike ? .tv : .movie) }
            if let imdb = ids.imdbId, let tmdb = await tmdbId(imdbId: imdb, isShow: isShowLike) {
                return (tmdb, isShowLike ? .tv : .movie)
            }
        }
        return nil
    }
}
