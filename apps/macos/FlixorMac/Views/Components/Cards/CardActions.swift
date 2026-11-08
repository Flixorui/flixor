//
//  CardActions.swift
//  FlixorMac
//
//  Actions shared by the card context menu and the hover preview: play, My List,
//  watched state and Trakt lists. Results are reported with ToastManager.
//
//  My List mirrors WatchlistButton (Plex.tv + Trakt in parallel, always a local
//  copy) so a title added from a card shows up exactly like one added from the
//  details screen.
//

import Foundation
import SwiftUI
import FlixorKit

@MainActor
enum CardActions {

    // MARK: - Capabilities

    /// Movies and episodes can be watched/unwatched directly. Shows and seasons
    /// affect every episode, so they get a confirmed "entire show" action.
    static func isWholeShowLike(_ item: MediaItem) -> Bool {
        let type = item.type.lowercased()
        return type == "show" || type == "season"
    }

    /// My List holds movies and shows only.
    static func supportsWatchlist(_ item: MediaItem) -> Bool {
        let type = item.type.lowercased()
        return type == "movie" || type == "show"
    }

    /// The existing direct play flow: Plex movies and episodes, never in
    /// Stremio-only mode (Stremio playback needs the details screen to pick a source).
    static func playDestination(for item: MediaItem) -> PlayerDestination? {
        guard !isStremioOnlyMode, item.id.hasPrefix("plex:") else { return nil }
        let type = item.type.lowercased()
        guard type == "movie" || type == "episode" else { return nil }
        return .plex(item)
    }

    // MARK: - My List

    /// Ids the watchlist may know this item by (Plex and TMDB forms).
    static func watchlistCandidateIds(for item: MediaItem, tmdbId: Int? = nil) -> [String] {
        var ids = [item.id]
        if let key = plexRatingKey(of: item) { ids.append("plex:\(key)") }
        let isShow = item.type.lowercased() != "movie"
        let tmdb = tmdbId ?? WatchStateTarget(item: item)?.tmdbId
        if let tmdb { ids.append("tmdb:\(isShow ? "tv" : "movie"):\(tmdb)") }
        return ids
    }

    static func isInWatchlist(_ item: MediaItem, controller: WatchlistController?, tmdbId: Int? = nil) -> Bool {
        guard let controller else { return false }
        return watchlistCandidateIds(for: item, tmdbId: tmdbId).contains { controller.contains($0) }
    }

    /// Adds or removes the item from My List. Returns the new membership.
    @discardableResult
    static func toggleWatchlist(_ item: MediaItem, controller: WatchlistController?) async -> Bool? {
        guard supportsWatchlist(item) else { return nil }
        let isShow = item.type.lowercased() == "show"
        let identity = await MediaIdentityResolver.shared.tmdbIdentity(for: item)
        let tmdbId = identity?.id
        let plexKey = plexRatingKey(of: item)
        let currentlyIn = isInWatchlist(item, controller: controller, tmdbId: tmdbId)

        let canonicalId: String
        if let plexKey {
            canonicalId = "plex:\(plexKey)"
        } else if let tmdbId {
            canonicalId = "tmdb:\(isShow ? "tv" : "movie"):\(tmdbId)"
        } else {
            canonicalId = item.id
        }
        let plexIdentifier = tmdbId.map { "tmdb://\($0)" } ?? plexKey
        let title = displayTitle(item)

        if currentlyIn {
            async let plexResult: Bool = removeFromPlexWatchlist(plexIdentifier)
            async let traktResult: Bool = postTraktWatchlist(tmdbId: tmdbId, isShow: isShow, title: nil, year: nil, remove: true)
            _ = await (plexResult, traktResult)
            for id in watchlistCandidateIds(for: item, tmdbId: tmdbId) {
                await LocalLibraryStore.shared.removeFromWatchlist(id: id)
                controller?.registerRemove(id: id)
            }
            ToastManager.shared.show("Removed \(title) from My List", type: .success)
            return false
        } else {
            async let plexResult: Bool = addToPlexWatchlist(plexIdentifier)
            async let traktResult: Bool = postTraktWatchlist(tmdbId: tmdbId, isShow: isShow, title: title, year: item.year, remove: false)
            _ = await (plexResult, traktResult)
            await LocalLibraryStore.shared.addToWatchlist(
                LocalWatchlistEntry(
                    id: canonicalId,
                    title: title,
                    type: isShow ? "show" : "movie",
                    posterURL: ImageService.shared.thumbURL(for: item)?.absoluteString,
                    backdropURL: nil,
                    year: item.year,
                    imdbId: WatchStateTarget(item: item)?.imdbId,
                    tmdbId: tmdbId,
                    addedAt: Date()
                )
            )
            controller?.registerAdd(id: canonicalId)
            ToastManager.shared.show("Added \(title) to My List", type: .success)
            return true
        }
    }

    // MARK: - Watched

    /// Marks watched or unwatched through WatchStateService and toasts the result.
    @discardableResult
    static func setWatched(_ item: MediaItem, watched: Bool) async -> WatchStateResult {
        let service = WatchStateService.shared
        let result = watched ? await service.markWatched(item) : await service.markUnwatched(item)
        let type: ToastView.ToastType = result.isSuccess ? .success : (result.isPartialSuccess ? .info : .error)
        ToastManager.shared.show(result.message, type: type)
        return result
    }

    // MARK: - Trakt lists

    static func addToTraktList(_ item: MediaItem, list: TraktUserList) async {
        do {
            let result = try await TraktListsService.shared.add(item, toList: list.id)
            if result.addedCount == 0 && result.existingCount > 0 {
                ToastManager.shared.show("Already on \(list.name)", type: .info)
            } else {
                ToastManager.shared.show("Added to \(list.name)", type: .success)
            }
        } catch {
            ToastManager.shared.show("Couldn't add to \(list.name): \(error.localizedDescription)", type: .error)
        }
    }

    // MARK: - Helpers

    /// Show title for episodes, otherwise the item's own title.
    static func displayTitle(_ item: MediaItem) -> String {
        if item.type.lowercased() == "episode", let show = item.grandparentTitle, !show.isEmpty {
            return show
        }
        return item.title
    }

    static func plexRatingKey(of item: MediaItem) -> String? {
        if item.id.hasPrefix("plex:") { return String(item.id.dropFirst(5)) }
        if !item.id.isEmpty, item.id.allSatisfy(\.isNumber) { return item.id }
        return nil
    }

    private static func addToPlexWatchlist(_ identifier: String?) async -> Bool {
        guard let identifier, !isStremioOnlyMode else { return false }
        struct Response: Codable { let ok: Bool? }
        let encoded = identifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? identifier
        do {
            let _: Response = try await APIClient.shared.put("/api/plextv/watchlist/\(encoded)")
            return true
        } catch {
            AppLogger.shared.warn("[Cards] Plex watchlist add failed", data: ["error": error.localizedDescription])
            return false
        }
    }

    private static func removeFromPlexWatchlist(_ identifier: String?) async -> Bool {
        guard let identifier, !isStremioOnlyMode else { return false }
        struct Response: Codable { let ok: Bool? }
        let encoded = identifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? identifier
        do {
            let _: Response = try await APIClient.shared.delete("/api/plextv/watchlist/\(encoded)")
            return true
        } catch {
            AppLogger.shared.warn("[Cards] Plex watchlist remove failed", data: ["error": error.localizedDescription])
            return false
        }
    }

    private static func postTraktWatchlist(tmdbId: Int?, isShow: Bool, title: String?, year: Int?, remove: Bool) async -> Bool {
        guard let tmdbId, FlixorCore.shared.isTraktAuthenticated else { return false }
        struct Payload: Codable {
            struct IDs: Codable { let tmdb: Int? }
            struct Entry: Codable { let ids: IDs; let title: String?; let year: Int? }
            let movies: [Entry]?
            let shows: [Entry]?
        }
        struct Response: Codable { let added: [String: Int]?; let deleted: [String: Int]? }
        let entry = Payload.Entry(ids: .init(tmdb: tmdbId), title: title, year: year)
        let payload = isShow ? Payload(movies: nil, shows: [entry]) : Payload(movies: [entry], shows: nil)
        do {
            let _: Response = try await APIClient.shared.post(remove ? "/api/trakt/watchlist/remove" : "/api/trakt/watchlist", body: payload)
            return true
        } catch {
            AppLogger.shared.warn("[Cards] Trakt watchlist update failed", data: ["error": error.localizedDescription])
            return false
        }
    }
}

// MARK: - Trakt lists cache

/// The user's Trakt lists for the "Add to Trakt list" submenu. Loaded lazily the
/// first time a card menu opens, refreshed after list changes.
@MainActor
final class CardTraktListsCache: ObservableObject {
    static let shared = CardTraktListsCache()

    enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed
    }

    @Published private(set) var lists: [TraktUserList] = []
    @Published private(set) var state: State = .idle

    private var observer: NSObjectProtocol?
    private var loadTask: Task<Void, Never>?
    private var loadedAt: Date = .distantPast
    /// Loaded lists are refreshed in the background when older than this.
    private let refreshInterval: TimeInterval = 60

    private init() {
        observer = NotificationCenter.default.addObserver(forName: .traktListsDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                // Next menu open reloads (item counts and names may have changed).
                if self?.state != .loading { self?.state = .idle }
            }
        }
    }

    var isAvailable: Bool { TraktListsService.shared.isAvailable }

    func loadIfNeeded() {
        guard isAvailable, loadTask == nil else { return }
        let isStale = Date().timeIntervalSince(loadedAt) > refreshInterval
        guard state == .idle || state == .failed || (state == .loaded && isStale) else { return }
        // A background refresh keeps showing the current lists.
        let isRefresh = state == .loaded
        if !isRefresh { state = .loading }
        loadTask = Task { [weak self] in
            do {
                let lists = try await TraktListsService.shared.myLists()
                self?.lists = lists.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                self?.loadedAt = Date()
                self?.state = .loaded
            } catch {
                if !isRefresh { self?.state = .failed }
            }
            self?.loadTask = nil
        }
    }
}
