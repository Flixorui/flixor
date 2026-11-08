//
//  OriginalLanguageResolver.swift
//  FlixorMac
//
//  Original language of a movie/show (TMDB `original_language`), used by the
//  "Original language" audio preference. Results are cached for the session.
//

import Foundation
import FlixorKit

actor OriginalLanguageResolver {
    static let shared = OriginalLanguageResolver()

    /// "movie:603" / "tv:1399" -> ISO 639-1 code ("" = looked up, unknown)
    private var cache: [String: String] = [:]

    /// Original language for a Plex/TMDB item or addon stream, or nil when it
    /// cannot be determined (offline files, no ids, TMDB failure).
    func originalLanguage(for item: MediaItem, stream: StreamPlaybackItem?) async -> String? {
        if let stream {
            let isShow = stream.mediaType != .movie
            if let tmdb = stream.tmdbId {
                return await originalLanguage(tmdbId: tmdb, isShow: isShow)
            }
            if let imdb = stream.imdbId, !imdb.isEmpty,
               let tmdb = await MediaIdentityResolver.shared.tmdbId(imdbId: imdb, isShow: isShow) {
                return await originalLanguage(tmdbId: tmdb, isShow: isShow)
            }
            return nil
        }
        guard item.id != "offline",
              let identity = await MediaIdentityResolver.shared.tmdbIdentity(for: item) else { return nil }
        return await originalLanguage(tmdbId: identity.id, isShow: identity.mediaType == .tv)
    }

    func originalLanguage(tmdbId: Int, isShow: Bool) async -> String? {
        let key = "\(isShow ? "tv" : "movie"):\(tmdbId)"
        if let cached = cache[key] { return cached.isEmpty ? nil : cached }
        do {
            let language: String?
            if isShow {
                language = try await FlixorCore.shared.tmdb.getTVDetails(id: tmdbId).originalLanguage
            } else {
                language = try await FlixorCore.shared.tmdb.getMovieDetails(id: tmdbId).originalLanguage
            }
            let code = language?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            cache[key] = code
            return code.isEmpty ? nil : code
        } catch {
            // Not cached: failures may be transient
            return nil
        }
    }
}
