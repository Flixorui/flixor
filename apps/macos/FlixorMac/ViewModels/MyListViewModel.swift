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
            case .all: return "All"
            case .movies: return "Movies"
            case .shows: return "TV Shows"
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
            case .dateAdded: return "Date Added"
            case .title: return "Title"
            case .year: return "Release Year"
            case .rating: return "Rating"
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
                parentIndex: nil,
                index: nil,
                parentRatingKey: nil,
                parentTitle: nil,
                leafCount: nil,
                viewedLeafCount: nil
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
    @Published var bulkMode = false
    @Published var selectedIDs: Set<String> = []
    @Published private(set) var traktAvailable = false

    private let api = APIClient.shared
    private weak var watchlistController: WatchlistController?
    private var loadTask: Task<Void, Never>?

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

        loadTask = Task {
            do {
                async let plexItems = fetchPlexWatchlist()
                async let traktItems = fetchTraktWatchlist()

                let (plex, trakt) = try await (plexItems, traktItems)

                var merged: [String: WatchlistItem] = [:]
                for item in plex {
                    merged[item.id] = item
                }
                for item in trakt {
                    if var existing = merged[item.id] {
                        existing.source = .both
                        merged[item.id] = existing
                    } else {
                        merged[item.id] = item
                    }
                }

                items = merged.values.sorted { lhs, rhs in
                    (lhs.dateAdded ?? .distantPast) > (rhs.dateAdded ?? .distantPast)
                }

                watchlistController?.synchronize(with: items)
                applyFilters()
            } catch is CancellationError {
                // Ignore
            } catch {
                errorMessage = error.localizedDescription
            }

            isLoading = false
        }

        await loadTask?.value
    }

    func reload() async {
        await load()
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
        items.removeAll { ids.contains($0.id) }
        applyFilters()
        watchlistController?.synchronize(with: items)
    }

    private func removeSingle(item: WatchlistItem) async {
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

            watchlistController?.registerRemove(id: item.id)
        } catch {
            print("⚠️ Failed to remove \(item.title) from watchlist: \(error)")
        }
    }

    private func fetchPlexWatchlist() async throws -> [WatchlistItem] {
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
            let movies: [TraktWatchlistEntry] = try await api.get("/api/trakt/users/me/watchlist/movies")
            let shows: [TraktWatchlistEntry] = try await api.get("/api/trakt/users/me/watchlist/shows")
            traktAvailable = true
            let movieItems = try await mapTraktEntries(movies, mediaType: .movie)
            let showItems = try await mapTraktEntries(shows, mediaType: .show)
            return movieItems + showItems
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

    private func mapTraktEntries(_ entries: [TraktWatchlistEntry], mediaType: MediaType) async throws -> [WatchlistItem] {
        var results: [WatchlistItem] = []

        for entry in entries {
            if mediaType == .movie, let movie = entry.movie {
                if let item = try await createTraktItem(movie: movie, listedAt: entry.listedAt, mediaType: .movie) {
                    results.append(item)
                }
            } else if mediaType == .show, let show = entry.show {
                if let item = try await createTraktItem(show: show, listedAt: entry.listedAt, mediaType: .show) {
                    results.append(item)
                }
            }
        }

        return results
    }

    private func createTraktItem(movie: TraktMovie, listedAt: String?, mediaType: MediaType) async throws -> WatchlistItem? {
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
        let dateAdded = listedAt.flatMap { ISO8601DateFormatter().date(from: $0) }

        let posterURL = try await tmdbPoster(for: mediaType, tmdbId: tmdbId)

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

    private func createTraktItem(show: TraktShow, listedAt: String?, mediaType: MediaType) async throws -> WatchlistItem? {
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
        let dateAdded = listedAt.flatMap { ISO8601DateFormatter().date(from: $0) }

        let posterURL = try await tmdbPoster(for: mediaType, tmdbId: tmdbId)

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

    private func tmdbPoster(for mediaType: MediaType, tmdbId: String?) async throws -> URL? {
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
