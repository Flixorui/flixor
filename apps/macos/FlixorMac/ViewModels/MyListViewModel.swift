//
//  MyListViewModel.swift
//  FlixorMac
//
//  Handles Plex + Trakt watchlist aggregation for the My List screen.
//

import Foundation
import SwiftUI

@MainActor
final class MyListViewModel: ObservableObject {
    enum Source: String {
        case plex
        case trakt
        case both
        /// Stored on this Mac. Used when neither Plex nor Trakt is connected.
        case local
    }

    enum MediaType: String {
        case movie
        case show
    }

    enum FilterType: String, CaseIterable, Identifiable {
        case all
        case movies
        case shows

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return String(localized: "All")
            case .movies: return String(localized: "Movies")
            case .shows: return String(localized: "TV Shows")
            }
        }
    }

    enum SortOption: String, CaseIterable, Identifiable {
        case dateAdded
        case title
        case year
        case rating

        var id: String { rawValue }

        var title: String {
            switch self {
            case .dateAdded: return String(localized: "Date Added")
            case .title: return String(localized: "Title")
            case .year: return String(localized: "Release Year")
            case .rating: return String(localized: "Rating")
            }
        }
    }

    struct WatchlistItem: Identifiable, Hashable {
        let id: String
        let title: String
        let year: String?
        let imageURL: URL?
        let plexThumb: String?
        let overview: String?
        let ratingText: String?
        let mediaType: MediaType
        var source: Source
        let dateAdded: Date?
        let runtimeMinutes: Int?
        let genres: [String]
        let plexRatingKey: String?
        let plexGuid: String?
        let tmdbId: String?
        let imdbId: String?

        var canonicalMediaItem: MediaItem {
            // Use the item's ID which already prefers TMDB format
            return MediaItem(
                id: id,
                title: title,
                type: mediaType == .movie ? "movie" : "show",
                thumb: plexThumb,
                art: nil,
                year: Int(year ?? ""),
                rating: nil,
                duration: runtimeMinutes.map { $0 * 60000 },
                viewOffset: nil,
                summary: overview,
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

        fileprivate func withImageURL(_ url: URL?) -> WatchlistItem {
            WatchlistItem(
                id: id, title: title, year: year, imageURL: url, plexThumb: plexThumb,
                overview: overview, ratingText: ratingText, mediaType: mediaType, source: source,
                dateAdded: dateAdded, runtimeMinutes: runtimeMinutes, genres: genres,
                plexRatingKey: plexRatingKey, plexGuid: plexGuid, tmdbId: tmdbId, imdbId: imdbId
            )
        }
    }

    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var items: [WatchlistItem] = []
    @Published private(set) var visibleItems: [WatchlistItem] = []
    @Published var filter: FilterType = .all {
        didSet { applyFilters() }
    }
    @Published var sort: SortOption = .dateAdded {
        didSet { applyFilters() }
    }
    @Published var searchQuery: String = "" {
        didSet { applyFilters() }
    }
    /// Quick chips on the My List header.
    @Published var recentOnly = false {
        didSet { applyFilters() }
    }
    @Published var inLibraryOnly = false {
        didSet { applyFilters() }
    }
    var movieCount: Int { items.filter { $0.mediaType == .movie }.count }
    var showCount: Int { items.filter { $0.mediaType == .show }.count }
    @Published var bulkMode = false
    @Published var selectedIDs: Set<String> = []
    @Published private(set) var traktAvailable = false

    private let api = APIClient.shared
    private weak var watchlistController: WatchlistController?
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0
    /// Last result from each source. A source that hasn't answered yet (or failed)
    /// keeps its previous items, so a reload never empties the grid.
    private var plexSource: [WatchlistItem] = []
    private var traktSource: [WatchlistItem] = []
    private var localSource: [WatchlistItem] = []
    /// TMDB poster URLs for Trakt items, keyed by "movie:123" / "show:123".
    private var traktPosterCache: [String: URL] = [:]
    private let posterBatchSize = 12
    /// watchlistDidChange notifications posted by this screen's own removals.
    private var pendingOwnChangeNotifications = 0
    private static let listedAtFormatter = ISO8601DateFormatter()

    private enum SourceResult {
        case plex([WatchlistItem])
        case trakt([WatchlistItem])
        case local([WatchlistItem])
        case failed(Error)
        case postersResolved
    }

    // MARK: - Trakt Types
    private struct TraktWatchlistEntry: Codable {
        let listedAt: String?  // ISO 8601 date string from Trakt API
        let movie: TraktMovie?
        let show: TraktShow?

        enum CodingKeys: String, CodingKey {
            case listedAt = "listed_at"
            case movie
            case show
        }
    }

    private struct TraktMovie: Codable {
        let title: String?
        let year: Int?
        let overview: String?
        let runtime: Int?
        let genres: [String]?
        let rating: Double?
        let ids: TraktIDs?
    }

    private struct TraktShow: Codable {
        let title: String?
        let year: Int?
        let overview: String?
        let runtime: Int?
        let genres: [String]?
        let rating: Double?
        let ids: TraktIDs?
    }

    private struct TraktIDs: Codable {
        let trakt: Int?
        let imdb: String?
        let tmdb: Int?
    }

    func attach(_ controller: WatchlistController) {
        watchlistController = controller
    }

    func load() async {
        guard !isLoading else { return }
        loadTask?.cancel()

        isLoading = true
        errorMessage = nil
        loadGeneration += 1
        let generation = loadGeneration

        // Each source is shown as soon as it answers; Trakt posters fill in afterwards.
        loadTask = Task { [weak self] in
            guard let self else { return }
            await withTaskGroup(of: SourceResult.self) { group in
                group.addTask {
                    do { return .plex(try await self.fetchPlexWatchlist()) } catch { return .failed(error) }
                }
                group.addTask {
                    do { return .trakt(try await self.fetchTraktWatchlist()) } catch { return .failed(error) }
                }
                group.addTask {
                    .local(await self.fetchLocalWatchlist())
                }

                var pendingSources = 3
                var failed = false
                while let result = await group.next() {
                    guard !Task.isCancelled, generation == self.loadGeneration else { continue }
                    switch result {
                    case .plex(let items):
                        pendingSources -= 1
                        self.plexSource = items
                        self.publishMerged()
                    case .trakt(let items):
                        pendingSources -= 1
                        self.traktSource = items
                        self.publishMerged()
                        group.addTask {
                            await self.resolveTraktPosters(generation: generation)
                            return .postersResolved
                        }
                    case .local(let items):
                        pendingSources -= 1
                        self.localSource = items
                        self.publishMerged()
                    case .failed(let error):
                        pendingSources -= 1
                        if !(error is CancellationError) {
                            failed = true
                            if self.errorMessage == nil {
                                self.errorMessage = error.localizedDescription
                            }
                        }
                    case .postersResolved:
                        continue
                    }
                    if pendingSources == 0 {
                        if !failed {
                            self.watchlistController?.synchronize(with: self.items)
                        }
                        self.isLoading = false
                    }
                }
            }
            if generation == self.loadGeneration {
                self.isLoading = false
            }
        }

        await loadTask?.value
    }

    func reload() async {
        await load()
    }

    /// Called for every watchlistDidChange. Skips the ones this screen posted
    /// itself (its own removals already updated the grid); other screens'
    /// changes still trigger a refetch.
    func handleWatchlistDidChange() async {
        if pendingOwnChangeNotifications > 0 {
            pendingOwnChangeNotifications -= 1
            return
        }
        await reload()
    }

    private func publishMerged() {
        var merged: [String: WatchlistItem] = [:]
        for item in plexSource {
            merged[item.id] = item
        }
        for item in traktSource {
            if var existing = merged[item.id] {
                existing.source = .both
                merged[item.id] = existing
            } else {
                merged[item.id] = item
            }
        }
        // Local entries only fill gaps - a remote source is authoritative when
        // it already has the title.
        for item in localSource where merged[item.id] == nil {
            merged[item.id] = item
        }

        // Ties broken by id so repeated publishes don't shuffle the grid.
        items = merged.values.sorted { lhs, rhs in
            let l = lhs.dateAdded ?? .distantPast
            let r = rhs.dateAdded ?? .distantPast
            return l == r ? lhs.id < rhs.id : l > r
        }
        applyFilters()
    }

    private func posterKey(_ mediaType: MediaType, _ tmdbId: String) -> String {
        "\(mediaType.rawValue):\(tmdbId)"
    }

    private func resolveTraktPosters(generation: Int) async {
        // Items Plex also has show the Plex poster, so they don't need one.
        let plexIds = Set(plexSource.map(\.id))
        var seen = Set<String>()
        var pending: [(key: String, mediaType: MediaType, tmdbId: String)] = []
        for item in traktSource where item.imageURL == nil && !plexIds.contains(item.id) {
            guard let tmdbId = item.tmdbId else { continue }
            let key = posterKey(item.mediaType, tmdbId)
            guard traktPosterCache[key] == nil, seen.insert(key).inserted else { continue }
            pending.append((key, item.mediaType, tmdbId))
        }
        guard !pending.isEmpty else { return }

        for start in stride(from: 0, to: pending.count, by: posterBatchSize) {
            let batch = pending[start..<min(start + posterBatchSize, pending.count)]
            let results = await withTaskGroup(of: (String, URL?).self) { group -> [(String, URL?)] in
                for entry in batch {
                    group.addTask { [weak self] in
                        (entry.key, await self?.tmdbPoster(for: entry.mediaType, tmdbId: entry.tmdbId))
                    }
                }
                var collected: [(String, URL?)] = []
                for await result in group {
                    collected.append(result)
                }
                return collected
            }
            guard !Task.isCancelled, generation == loadGeneration else { return }

            var found = false
            for case let (key, url?) in results {
                traktPosterCache[key] = url
                found = true
            }
            guard found else { continue }
            traktSource = traktSource.map { item in
                guard item.imageURL == nil, let tmdbId = item.tmdbId,
                      let url = traktPosterCache[posterKey(item.mediaType, tmdbId)] else { return item }
                return item.withImageURL(url)
            }
            publishMerged()
        }
    }

    func toggleSelection(for item: WatchlistItem) {
        let id = item.id
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    func clearSelection() {
        selectedIDs.removeAll()
    }

    func remove(item: WatchlistItem) async {
        await remove(ids: [item.id])
    }

    func removeSelected() async {
        let ids = Array(selectedIDs)
        selectedIDs.removeAll()
        await remove(ids: ids)
        bulkMode = false
    }

    private func remove(ids: [String]) async {
        guard !ids.isEmpty else { return }
        for id in ids {
            guard let item = items.first(where: { $0.id == id }) else { continue }
            await removeSingle(item: item)
        }
        let removed = Set(ids)
        items.removeAll { removed.contains($0.id) }
        plexSource.removeAll { removed.contains($0.id) }
        traktSource.removeAll { removed.contains($0.id) }
        localSource.removeAll { removed.contains($0.id) }
        applyFilters()
        watchlistController?.synchronize(with: items)
    }

    private func removeSingle(item: WatchlistItem) async {
        // Always clear the local copy - it may shadow a remote entry that was added
        // while offline.
        await LocalLibraryStore.shared.removeFromWatchlist(id: item.id)

        do {
            if item.source == .plex || item.source == .both, let identifier = item.plexGuid ?? item.plexRatingKey {
                let encoded = identifier.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? identifier
                struct Response: Codable { let ok: Bool? }
                let _: Response = try await api.delete("/api/plextv/watchlist/\(encoded)")
            }

            if (item.source == .trakt || item.source == .both), let tmdbId = item.tmdbId {
                struct TraktPayload: Codable {
                    struct IDs: Codable { let tmdb: Int? }
                    struct Entry: Codable { let ids: IDs }
                    let movies: [Entry]?
                    let shows: [Entry]?
                }
                let entry = TraktPayload.Entry(ids: .init(tmdb: Int(tmdbId)))
                let payload = item.mediaType == .movie
                    ? TraktPayload(movies: [entry], shows: nil)
                    : TraktPayload(movies: nil, shows: [entry])
                struct Response: Codable { let deleted: [String: Int]? }
                let _: Response = try await api.post("/api/trakt/watchlist/remove", body: payload)
            }

            if let controller = watchlistController {
                pendingOwnChangeNotifications += 1
                controller.registerRemove(id: item.id)
            }
        } catch {
            print("⚠️ Failed to remove \(item.title) from watchlist: \(error)")
        }
    }

    private func fetchLocalWatchlist() async -> [WatchlistItem] {
        let entries = await LocalLibraryStore.shared.watchlist()
        return entries.map { entry in
            WatchlistItem(
                id: entry.id,
                title: entry.title,
                year: entry.year.map(String.init),
                imageURL: entry.posterURL.flatMap { URL(string: $0) },
                plexThumb: entry.posterURL,
                overview: nil,
                ratingText: nil,
                mediaType: entry.type == "movie" ? .movie : .show,
                source: .local,
                dateAdded: entry.addedAt,
                runtimeMinutes: nil,
                genres: [],
                plexRatingKey: nil,
                plexGuid: nil,
                tmdbId: entry.tmdbId.map(String.init),
                imdbId: entry.imdbId
            )
        }
    }

    private func fetchPlexWatchlist() async throws -> [WatchlistItem] {
        // No Plex.tv token in Stremio-only mode - skip the request entirely.
        guard !AppModeStore.shared.isStremioOnly else { return [] }

        struct MediaContainer: Codable {
            let Metadata: [PlexMetadata]?
        }
        struct PlexResponse: Codable {
            let MediaContainer: MediaContainer?
        }
        struct PlexMetadata: Codable {
            let ratingKey: String?
            let guid: String?
            let type: String?
            let title: String?
            let summary: String?
            let year: Int?
            let thumb: String?
            let duration: Int?
            let contentRating: String?
            let addedAt: Int?
            let Genre: [PlexGenre]?
            let tmdbGuid: String? // Backend-enriched TMDB ID
        }
        struct PlexGenre: Codable { let tag: String? }

        let response: PlexResponse = try await api.get("/api/plextv/watchlist")
        let items = response.MediaContainer?.Metadata ?? []
        return items.compactMap { meta in
            guard let title = meta.title else { return nil }
            let image = ImageService.shared.plexImageURL(path: meta.thumb, width: 320, height: 480)
            let tmdbId = extractTMDBId(from: meta.guid)
            let imdbId = extractIMDBId(from: meta.guid)

            // Use backend-enriched tmdbGuid if available, fallback to Plex rating key
            let itemId: String
            if let tmdbGuid = meta.tmdbGuid {
                itemId = tmdbGuid
                print("✅ [MyList] Using backend-enriched TMDB ID for \(title): \(tmdbGuid)")
            } else if let ratingKey = meta.ratingKey {
                itemId = "plex:\(ratingKey)"
                print("⚠️ [MyList] No TMDB ID from backend for \(title), using Plex rating key")
            } else {
                itemId = UUID().uuidString
            }

            return WatchlistItem(
                id: itemId,
                title: title,
                year: meta.year.map { String($0) },
                imageURL: image,
                plexThumb: meta.thumb,
                overview: meta.summary,
                ratingText: meta.contentRating,
                mediaType: (meta.type == "show") ? .show : .movie,
                source: .plex,
                dateAdded: meta.addedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                runtimeMinutes: meta.duration.map { Int($0 / 60000) },
                genres: meta.Genre?.compactMap { $0.tag } ?? [],
                plexRatingKey: meta.ratingKey,
                plexGuid: meta.guid,
                tmdbId: tmdbId,
                imdbId: imdbId
            )
        }
    }

    private func fetchTraktWatchlist() async throws -> [WatchlistItem] {
        do {
            async let moviesRequest: [TraktWatchlistEntry] = api.get("/api/trakt/users/me/watchlist/movies")
            async let showsRequest: [TraktWatchlistEntry] = api.get("/api/trakt/users/me/watchlist/shows")
            let (movies, shows) = try await (moviesRequest, showsRequest)
            traktAvailable = true
            return mapTraktEntries(movies, mediaType: .movie) + mapTraktEntries(shows, mediaType: .show)
        } catch APIError.httpError(let status, _) where status == 401 || status == 403 {
            traktAvailable = false
            return []
        } catch APIError.unauthorized {
            traktAvailable = false
            return []
        } catch {
            traktAvailable = false
            throw error
        }
    }

    private func mapTraktEntries(_ entries: [TraktWatchlistEntry], mediaType: MediaType) -> [WatchlistItem] {
        var results: [WatchlistItem] = []

        for entry in entries {
            if mediaType == .movie, let movie = entry.movie {
                if let item = createTraktItem(movie: movie, listedAt: entry.listedAt, mediaType: .movie) {
                    results.append(item)
                }
            } else if mediaType == .show, let show = entry.show {
                if let item = createTraktItem(show: show, listedAt: entry.listedAt, mediaType: .show) {
                    results.append(item)
                }
            }
        }

        return results
    }

    private func createTraktItem(movie: TraktMovie, listedAt: String?, mediaType: MediaType) -> WatchlistItem? {
        guard let title = movie.title else { return nil }
        let tmdbId = movie.ids?.tmdb.map { String($0) }
        let imdbId = movie.ids?.imdb
        let traktId = movie.ids?.trakt

        let canonicalId: String
        if let tmdbId = tmdbId {
            canonicalId = "tmdb:\(mediaType == .movie ? "movie" : "tv"):\(tmdbId)"
        } else if let imdbId = imdbId {
            canonicalId = "imdb:\(imdbId)"
        } else if let traktId = traktId {
            canonicalId = "trakt:\(traktId)"
        } else {
            canonicalId = UUID().uuidString
        }

        // Parse ISO 8601 date string
        let dateAdded = listedAt.flatMap { Self.listedAtFormatter.date(from: $0) }

        // Poster comes from the cache, or is filled in later by resolveTraktPosters.
        let posterURL = tmdbId.flatMap { traktPosterCache[posterKey(mediaType, $0)] }

        return WatchlistItem(
            id: canonicalId,
            title: title,
            year: movie.year.map { String($0) },
                imageURL: posterURL,
                plexThumb: nil,
                overview: movie.overview,
                ratingText: movie.rating.map { "⭐️ \(String(format: "%.1f", $0))" },
                mediaType: mediaType,
                source: .trakt,
                dateAdded: dateAdded,
            runtimeMinutes: movie.runtime,
            genres: movie.genres ?? [],
            plexRatingKey: nil,
            plexGuid: nil,
            tmdbId: tmdbId,
            imdbId: imdbId
        )
    }

    private func createTraktItem(show: TraktShow, listedAt: String?, mediaType: MediaType) -> WatchlistItem? {
        guard let title = show.title else { return nil }
        let tmdbId = show.ids?.tmdb.map { String($0) }
        let imdbId = show.ids?.imdb
        let traktId = show.ids?.trakt

        let canonicalId: String
        if let tmdbId = tmdbId {
            canonicalId = "tmdb:\(mediaType == .movie ? "movie" : "tv"):\(tmdbId)"
        } else if let imdbId = imdbId {
            canonicalId = "imdb:\(imdbId)"
        } else if let traktId = traktId {
            canonicalId = "trakt:\(traktId)"
        } else {
            canonicalId = UUID().uuidString
        }

        // Parse ISO 8601 date string
        let dateAdded = listedAt.flatMap { Self.listedAtFormatter.date(from: $0) }

        // Poster comes from the cache, or is filled in later by resolveTraktPosters.
        let posterURL = tmdbId.flatMap { traktPosterCache[posterKey(mediaType, $0)] }

        return WatchlistItem(
            id: canonicalId,
            title: title,
            year: show.year.map { String($0) },
                imageURL: posterURL,
                plexThumb: nil,
                overview: show.overview,
                ratingText: show.rating.map { "⭐️ \(String(format: "%.1f", $0))" },
                mediaType: mediaType,
                source: .trakt,
                dateAdded: dateAdded,
            runtimeMinutes: show.runtime,
            genres: show.genres ?? [],
            plexRatingKey: nil,
            plexGuid: nil,
            tmdbId: tmdbId,
            imdbId: imdbId
        )
    }

    private func tmdbPoster(for mediaType: MediaType, tmdbId: String?) async -> URL? {
        guard let tmdbId = tmdbId else { return nil }
        struct TMDBDetails: Codable { let poster_path: String? }
        let path: String
        switch mediaType {
        case .movie:
            path = "/api/tmdb/movie/\(tmdbId)"
        case .show:
            path = "/api/tmdb/tv/\(tmdbId)"
        }
        do {
            let details: TMDBDetails = try await api.get(path)
            guard let poster = details.poster_path else { return nil }
            return ImageService.shared.proxyImageURL(url: "https://image.tmdb.org/t/p/w342\(poster)")
        } catch {
            print("⚠️ TMDB poster fetch failed: \(error)")
            return nil
        }
    }

    private func extractTMDBId(from guid: String?) -> String? {
        guard let guid = guid else { return nil }
        if let range = guid.range(of: "tmdb://") {
            return String(guid[range.upperBound...].prefix { $0.isNumber })
        }
        if let range = guid.range(of: "themoviedb://") {
            return String(guid[range.upperBound...].prefix { $0.isNumber })
        }
        return nil
    }

    private func extractIMDBId(from guid: String?) -> String? {
        guard let guid = guid else { return nil }
        if let range = guid.range(of: "imdb://") {
            return String(guid[range.upperBound...])
        }
        return nil
    }

    private func applyFilters() {
        var working = items

        switch filter {
        case .all:
            break
        case .movies:
            working = working.filter { $0.mediaType == .movie }
        case .shows:
            working = working.filter { $0.mediaType == .show }
        }

        if inLibraryOnly {
            working = working.filter { $0.source == .plex || $0.source == .both }
        }
        if recentOnly {
            let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
            working = working.filter { ($0.dateAdded ?? .distantPast) >= cutoff }
        }

        if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let term = searchQuery.lowercased()
            working = working.filter {
                $0.title.lowercased().contains(term) ||
                ($0.overview?.lowercased().contains(term) ?? false) ||
                ($0.genres.joined(separator: " ").lowercased().contains(term))
            }
        }

        switch sort {
        case .dateAdded:
            working.sort { ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast) }
        case .title:
            working.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .year:
            working.sort { ($0.year ?? "0") > ($1.year ?? "0") }
        case .rating:
            working.sort { ($0.ratingText ?? "") > ($1.ratingText ?? "") }
        }

        visibleItems = working
    }
}
