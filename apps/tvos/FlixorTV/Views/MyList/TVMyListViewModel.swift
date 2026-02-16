import Foundation
import SwiftUI
import FlixorKit

@MainActor
final class TVMyListViewModel: ObservableObject {
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

        var id: String { rawValue }

        var title: String {
            switch self {
            case .dateAdded: return "Date Added"
            case .title: return "Title"
            case .year: return "Release Year"
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
        let mediaType: MediaType
        var source: Source
        let dateAdded: Date?
        let runtimeMinutes: Int?
        let genres: [String]
        let plexRatingKey: String?
        let plexGuid: String?
        let tmdbId: String?
        let imdbId: String?

        var mediaItem: MediaItem {
            MediaItem(
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
                index: nil
            )
        }
    }

    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var items: [WatchlistItem] = []
    @Published private(set) var visibleItems: [WatchlistItem] = []
    @Published private(set) var traktAvailable = false
    @Published var filter: FilterType = .all {
        didSet { applyFilters() }
    }
    @Published var sort: SortOption = .dateAdded {
        didSet { applyFilters() }
    }
    @Published var searchQuery: String = "" {
        didSet { applyFilters() }
    }

    private let api = APIClient.shared
    private weak var watchlistController: TVWatchlistController?
    private var loadTask: Task<Void, Never>?

    func attach(_ controller: TVWatchlistController) {
        watchlistController = controller
    }

    func load() async {
        guard !isLoading else { return }
        loadTask?.cancel()

        isLoading = true
        errorMessage = nil

        loadTask = Task { [weak self] in
            guard let self else { return }
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

                watchlistController?.synchronize(with: items.map(\.id))
                applyFilters()
            } catch is CancellationError {
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

    func remove(item: WatchlistItem) async {
        await remove(items: [item])
    }

    private func remove(items: [WatchlistItem]) async {
        guard !items.isEmpty else { return }

        for item in items {
            await removeSingle(item: item)
        }

        let idsToDelete = Set(items.map(\.id))
        self.items.removeAll { idsToDelete.contains($0.id) }
        applyFilters()
        watchlistController?.synchronize(with: self.items.map(\.id))
    }

    private func removeSingle(item: WatchlistItem) async {
        do {
            if item.source == .plex || item.source == .both,
               let identifier = item.plexGuid ?? item.plexRatingKey {
                let encoded = identifier.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? identifier
                let _: SimpleOkResponse = try await api.delete("/api/plextv/watchlist/\(encoded)")
            }

            if (item.source == .trakt || item.source == .both),
               let tmdbId = item.tmdbId {
                struct TraktRemovePayload: Codable {
                    struct IDs: Codable { let tmdb: Int? }
                    struct Entry: Codable { let ids: IDs }
                    let movies: [Entry]?
                    let shows: [Entry]?
                }

                let entry = TraktRemovePayload.Entry(ids: .init(tmdb: Int(tmdbId)))
                let payload = item.mediaType == .movie
                    ? TraktRemovePayload(movies: [entry], shows: nil)
                    : TraktRemovePayload(movies: nil, shows: [entry])

                let _: SimpleOkResponse = try await api.post("/api/trakt/watchlist/remove", body: payload)
            }

            watchlistController?.registerRemove(id: item.id)
        } catch {
            #if DEBUG
            print("⚠️ [TVMyList] Failed to remove \(item.title): \(error)")
            #endif
        }
    }

    private func fetchPlexWatchlist() async throws -> [WatchlistItem] {
        let response: PlexWatchlistContainer = try await api.get("/api/plextv/watchlist")
        let metadata = response.MediaContainer.Metadata ?? []

        return metadata.compactMap { meta in
            guard let title = meta.title else { return nil }
            let tmdbId = extractTMDBId(from: meta.guid)
            let imdbId = extractIMDBId(from: meta.guid)

            let canonicalId = canonicalIdForPlexItem(tmdbGuid: meta.tmdbGuid, tmdbId: tmdbId, type: meta.type, ratingKey: meta.ratingKey)
            let image = ImageService.shared.plexImageURL(path: meta.thumb, width: 320, height: 480)

            return WatchlistItem(
                id: canonicalId,
                title: title,
                year: meta.year.map(String.init),
                imageURL: image,
                plexThumb: meta.thumb,
                overview: meta.summary,
                mediaType: (meta.type == "show") ? .show : .movie,
                source: .plex,
                dateAdded: nil,
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
            let movies: [TraktWatchlistEntryWrapper] = try await api.get("/api/trakt/users/me/watchlist/movies")
            let shows: [TraktWatchlistEntryWrapper] = try await api.get("/api/trakt/users/me/watchlist/shows")
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

    private func mapTraktEntries(_ entries: [TraktWatchlistEntryWrapper], mediaType: MediaType) async throws -> [WatchlistItem] {
        var results: [WatchlistItem] = []

        for entry in entries {
            if mediaType == .movie, let movie = entry.movie {
                if let item = try await createTraktItem(movie: movie, listedAt: entry.listed_at, mediaType: .movie) {
                    results.append(item)
                }
            } else if mediaType == .show, let show = entry.show {
                if let item = try await createTraktItem(show: show, listedAt: entry.listed_at, mediaType: .show) {
                    results.append(item)
                }
            }
        }

        return results
    }

    private func createTraktItem(movie: TraktMovieWrapper, listedAt: String?, mediaType: MediaType) async throws -> WatchlistItem? {
        guard let title = movie.title else { return nil }
        let tmdbId = movie.ids?.tmdb.map(String.init)
        let imdbId = movie.ids?.imdb
        let traktId = movie.ids?.trakt

        let canonicalId = canonicalIdForTrakt(tmdbId: tmdbId, imdbId: imdbId, traktId: traktId, mediaType: mediaType)
        let dateAdded = listedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
        let posterURL = try await tmdbPoster(for: mediaType, tmdbId: tmdbId)

        return WatchlistItem(
            id: canonicalId,
            title: title,
            year: movie.year.map(String.init),
            imageURL: posterURL,
            plexThumb: nil,
            overview: movie.overview,
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

    private func createTraktItem(show: TraktShowWrapper, listedAt: String?, mediaType: MediaType) async throws -> WatchlistItem? {
        guard let title = show.title else { return nil }
        let tmdbId = show.ids?.tmdb.map(String.init)
        let imdbId = show.ids?.imdb
        let traktId = show.ids?.trakt

        let canonicalId = canonicalIdForTrakt(tmdbId: tmdbId, imdbId: imdbId, traktId: traktId, mediaType: mediaType)
        let dateAdded = listedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
        let posterURL = try await tmdbPoster(for: mediaType, tmdbId: tmdbId)

        return WatchlistItem(
            id: canonicalId,
            title: title,
            year: show.year.map(String.init),
            imageURL: posterURL,
            plexThumb: nil,
            overview: show.overview,
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

        struct TMDBPosterDetails: Codable {
            let poster_path: String?
        }

        let path: String
        switch mediaType {
        case .movie:
            path = "/api/tmdb/movie/\(tmdbId)"
        case .show:
            path = "/api/tmdb/tv/\(tmdbId)"
        }

        do {
            let details: TMDBPosterDetails = try await api.get(path)
            guard let poster = details.poster_path else { return nil }
            return ImageService.shared.proxyImageURL(url: "https://image.tmdb.org/t/p/w342\(poster)")
        } catch {
            return nil
        }
    }

    private func canonicalIdForPlexItem(tmdbGuid: String?, tmdbId: String?, type: String?, ratingKey: String?) -> String {
        if let tmdbGuid, !tmdbGuid.isEmpty {
            if tmdbGuid.hasPrefix("tmdb:") {
                return tmdbGuid
            }
            if let parsed = Int(tmdbGuid) {
                let media = (type == "show") ? "tv" : "movie"
                return "tmdb:\(media):\(parsed)"
            }
        }

        if let tmdbId, let parsed = Int(tmdbId) {
            let media = (type == "show") ? "tv" : "movie"
            return "tmdb:\(media):\(parsed)"
        }

        if let ratingKey, !ratingKey.isEmpty {
            return ratingKey.hasPrefix("plex:") ? ratingKey : "plex:\(ratingKey)"
        }

        return UUID().uuidString
    }

    private func canonicalIdForTrakt(tmdbId: String?, imdbId: String?, traktId: Int?, mediaType: MediaType) -> String {
        if let tmdbId {
            return "tmdb:\(mediaType == .movie ? "movie" : "tv"):\(tmdbId)"
        }
        if let imdbId {
            return "imdb:\(imdbId)"
        }
        if let traktId {
            return "trakt:\(traktId)"
        }
        return UUID().uuidString
    }

    private func extractTMDBId(from guid: String?) -> String? {
        guard let guid else { return nil }
        if let range = guid.range(of: "tmdb://") {
            return String(guid[range.upperBound...].prefix { $0.isNumber })
        }
        if let range = guid.range(of: "themoviedb://") {
            return String(guid[range.upperBound...].prefix { $0.isNumber })
        }
        return nil
    }

    private func extractIMDBId(from guid: String?) -> String? {
        guard let guid else { return nil }
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

        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let term = trimmed.lowercased()
            working = working.filter {
                $0.title.lowercased().contains(term)
                    || ($0.overview?.lowercased().contains(term) ?? false)
                    || $0.genres.joined(separator: " ").lowercased().contains(term)
            }
        }

        switch sort {
        case .dateAdded:
            working.sort { ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast) }
        case .title:
            working.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .year:
            working.sort { ($0.year ?? "0") > ($1.year ?? "0") }
        }

        visibleItems = working
    }
}
