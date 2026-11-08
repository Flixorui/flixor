//
//  TraktCommentsService.swift
//  FlixorMac
//
//  Trakt comments for movies, shows, seasons and episodes. Uses the public API
//  (client id header only), so it works without a Trakt login.
//
//  Trakt addresses titles by Trakt id, slug or IMDb id, not TMDB id, so items are
//  resolved to an IMDb id first and fall back to a Trakt id lookup. Pages are
//  cached for 10 minutes.
//

import Foundation
import FlixorKit

actor TraktCommentsService {
    static let shared = TraktCommentsService()

    private struct CachedPage {
        let page: TraktPage<TraktComment>
        let fetchedAt: Date
    }

    private var pages: [String: CachedPage] = [:]
    private var traktIds: [String: String] = [:]
    private let ttl: TimeInterval = 10 * 60

    /// One page of comments for an item. Episodes need season/episode numbers on
    /// the MediaItem (Plex episodes and local Continue Watching episodes have them).
    func comments(
        for item: MediaItem,
        sort: TraktCommentSort = .likes,
        page: Int = 1,
        limit: Int = 20
    ) async throws -> TraktPage<TraktComment> {
        guard let base = WatchStateTarget(item: item) else { throw CommentsError.unresolved }
        let target = await WatchStateService.shared.resolve(base, needTitleIds: true)
        return try await comments(for: target, sort: sort, page: page, limit: limit)
    }

    /// One page of comments for a watch-state target (movie, show, season, episode).
    func comments(
        for target: WatchStateTarget,
        sort: TraktCommentSort = .likes,
        page: Int = 1,
        limit: Int = 20
    ) async throws -> TraktPage<TraktComment> {
        guard let id = await traktId(tmdbId: target.tmdbId, imdbId: target.imdbId, isShow: !target.isMovie) else {
            throw CommentsError.unresolved
        }
        let commentTarget: TraktCommentTarget
        switch target.kind {
        case .movie:
            commentTarget = .movie(id: id)
        case .show:
            commentTarget = .show(id: id)
        case .season(let n):
            guard let n else { throw CommentsError.unresolved }
            commentTarget = .season(showId: id, season: n)
        case .episode(let s, let e):
            guard let s, let e else { throw CommentsError.unresolved }
            commentTarget = .episode(showId: id, season: s, episode: e)
        }
        return try await comments(for: commentTarget, sort: sort, page: page, limit: limit)
    }

    /// One page of comments for an explicit Trakt target.
    func comments(
        for target: TraktCommentTarget,
        sort: TraktCommentSort = .likes,
        page: Int = 1,
        limit: Int = 20
    ) async throws -> TraktPage<TraktComment> {
        let key = "\(target):\(sort.rawValue):\(page):\(limit)"
        if let cached = pages[key], Date().timeIntervalSince(cached.fetchedAt) < ttl {
            return cached.page
        }
        let result = try await FlixorCore.shared.trakt.getComments(for: target, sort: sort, page: page, limit: limit)
        pages[key] = CachedPage(page: result, fetchedAt: Date())
        return result
    }

    /// Replies to a comment (not cached).
    func replies(commentId: Int, page: Int = 1, limit: Int = 20) async throws -> TraktPage<TraktComment> {
        try await FlixorCore.shared.trakt.getCommentReplies(commentId: commentId, page: page, limit: limit)
    }

    // MARK: - Id resolution

    /// An id Trakt's comment endpoints accept: the IMDb id when known, otherwise
    /// the Trakt id looked up from TMDB.
    private func traktId(tmdbId: Int?, imdbId: String?, isShow: Bool) async -> String? {
        if let imdbId, imdbId.lowercased().hasPrefix("tt") { return imdbId }
        guard let tmdbId else { return nil }
        let key = "\(isShow ? "show" : "movie"):\(tmdbId)"
        if let cached = traktIds[key] { return cached }
        guard let result = try? await FlixorCore.shared.trakt.lookupByTmdb(tmdbId: tmdbId, type: isShow ? "show" : "movie") else {
            return nil
        }
        let ids = isShow ? result.show?.ids : result.movie?.ids
        guard let id = ids?.trakt.map(String.init) ?? ids?.slug else { return nil }
        traktIds[key] = id
        return id
    }

    enum CommentsError: LocalizedError {
        case unresolved
        var errorDescription: String? { "Couldn't find this title on Trakt" }
    }
}
