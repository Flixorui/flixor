//
//  BrowseModalViewModel.swift
//  FlixorMac
//
//  Drives the Netflix-style Browse overlay on macOS.
//

import Foundation

// Local types for Trakt API responses (used with backend)
private struct TraktIDs: Codable { let tmdb: Int?; let trakt: Int?; let imdb: String?; let tvdb: Int? }
private struct TraktMedia: Codable { let title: String?; let year: Int?; let ids: TraktIDs }

@MainActor
class BrowseModalViewModel: ObservableObject {
    enum ViewState: Equatable {
        case idle
        case loading
        case loaded
        case empty
        case error(String)
    }

    @Published var state: ViewState = .idle
    @Published var items: [MediaItem] = []
    @Published var title: String = ""
    @Published var subtitle: String?
    @Published var isLoadingMore = false
    @Published var canLoadMore = false

    private let api = APIClient.shared
    private let imageService = ImageService.shared

    private var context: BrowseContext?
    private var tmdbPage = 1
    private var tmdbTotalPages = 1

    // Reset state when modal is dismissed
    func reset() {
        state = .idle
        items = []
        title = ""
        subtitle = nil
        canLoadMore = false
        isLoadingMore = false
        context = nil
        tmdbPage = 1
        tmdbTotalPages = 1
    }

    func load(context: BrowseContext) async {
        self.context = context
        tmdbPage = 1
        tmdbTotalPages = 1
        canLoadMore = false
        isLoadingMore = false

        let header = headerText(for: context)
        title = header.title
        subtitle = header.subtitle

        state = .loading
        items = []

        do {
            let data = try await fetchItems(for: context, page: 1, append: false)
            items = data
            state = data.isEmpty ? .empty : .loaded
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func reload() async {
        guard let context else { return }
        await load(context: context)
    }

    func loadMore() async {
        guard let context, canLoadMore, !isLoadingMore else { return }
        isLoadingMore = true
        do {
            let nextPage = tmdbPage + 1
            let more = try await fetchItems(for: context, page: nextPage, append: true)
            items.append(contentsOf: more)
            if items.isEmpty {
                state = .empty
            } else {
                state = .loaded
            }
        } catch {
            state = .error(error.localizedDescription)
        }
        isLoadingMore = false
    }

    // MARK: - Fetchers

    private func fetchItems(for context: BrowseContext, page: Int, append: Bool) async throws -> [MediaItem] {
        switch context {
        case .plexDirectory(let path, _):
            canLoadMore = false
            return try await fetchPlexDirectory(path: path)
        case .plexLibrary(let key, _):
            canLoadMore = false
            return try await fetchPlexLibrary(key: key)
        case .plexWatchlist:
            canLoadMore = false
            return try await fetchPlexWatchlist()
        case .tmdb(let kind, let media, let id, let display):
            return try await fetchTMDB(kind: kind, media: media, identifier: id, displayTitle: display, page: page, append: append)
        case .trakt(let kind):
            canLoadMore = false
            return try await fetchTrakt(kind: kind)
        }
    }

    // MARK: - Header Helpers

    private func headerText(for context: BrowseContext) -> (title: String, subtitle: String?) {
        switch context {
        case .plexDirectory(_, let customTitle):
            return (customTitle ?? "Browse", nil)
        case .plexLibrary(_, let libraryTitle):
            return (libraryTitle ?? "Library", "All titles")
        case .plexWatchlist:
            return ("Watchlist", "Plex.tv")
        case .tmdb(let kind, _, _, let display):
            switch kind {
            case .trending:
                return ("Trending", "TMDB")
            case .recommendations:
                return ("Recommendations", display)
            case .similar:
                return ("More Like This", display)
            }
        case .trakt(let kind):
            switch kind {
            case .trendingMovies:
                return ("Trending Movies", "Trakt")
            case .trendingShows:
                return ("Trending TV Shows", "Trakt")
            case .watchlist:
                return ("Your Trakt Watchlist", nil)
            case .history:
                return ("Recently Watched", "Trakt")
            case .recommendations:
                return ("Recommended for You", "Trakt")
            case .popularShows:
                return ("Popular TV Shows", "Trakt")
            }
        }
    }

    // MARK: - Plex Fetchers

    private func fetchPlexDirectory(path: String) async throws -> [MediaItem] {
        struct MetaResponse: Codable {
            let MediaContainer: MetaContainer?
            let Metadata: [MediaItemFull]?

            struct MetaContainer: Codable {
                let Metadata: [MediaItemFull]?
            }
        }

        let split = splitPathAndQuery(path)
        let response: MetaResponse = try await api.get("/api/plex/dir\(split.path)", queryItems: split.query)
        let data = response.MediaContainer?.Metadata ?? response.Metadata ?? []
        return data.map { $0.toMediaItem() }
    }

    private func fetchPlexLibrary(key: String) async throws -> [MediaItem] {
        let query = [
            URLQueryItem(name: "offset", value: "0"),
            URLQueryItem(name: "limit", value: "60")
        ]
        let items: [MediaItemFull] = try await api.get("/api/plex/library/\(key)/all", queryItems: query)
        return items.map { $0.toMediaItem() }
    }

    private func fetchPlexWatchlist() async throws -> [MediaItem] {
        struct PlexContainer: Codable { let MediaContainer: PlexMC }
        struct PlexMC: Codable { let Metadata: [MediaItemFull]? }

        let container: PlexContainer = try await api.get("/api/plextv/watchlist")
        let meta = container.MediaContainer.Metadata ?? []

        var items: [MediaItem] = []
        for m in meta {
            var identifier = m.id
            if let tmdbGuid = m.tmdbGuid {
                identifier = tmdbGuid
            }

            let entry = MediaItem(
                id: identifier,
                title: m.title,
                type: (m.type == "movie") ? "movie" : (m.type == "show" ? "show" : m.type),
                thumb: m.thumb,
                art: m.art,
                year: m.year,
                rating: m.rating,
                duration: m.duration,
                viewOffset: m.viewOffset,
                summary: m.summary,
                grandparentTitle: m.grandparentTitle,
                grandparentThumb: m.grandparentThumb,
                grandparentArt: m.grandparentArt,
                grandparentRatingKey: m.grandparentRatingKey,
                parentIndex: m.parentIndex,
                index: m.index,
                parentRatingKey: m.parentRatingKey,
                parentTitle: m.parentTitle,
                leafCount: m.leafCount,
                viewedLeafCount: m.viewedLeafCount
            )
            items.append(entry)
        }
        return items
    }

    // MARK: - TMDB Fetchers

    private func fetchTMDB(kind: TMDBBrowseKind, media: TMDBMediaType, identifier: String?, displayTitle: String?, page: Int, append: Bool) async throws -> [MediaItem] {
        struct TMDBResponse: Codable {
            let page: Int?
            let total_pages: Int?
            let results: [TMDBItem]?
        }
        struct TMDBItem: Codable {
            let id: Int?
            let title: String?
            let name: String?
            let backdrop_path: String?
            let poster_path: String?
        }

        let endpoint: String
        switch kind {
        case .trending:
            endpoint = "/api/tmdb/trending/\(media.rawValue)/week"
        case .recommendations:
            guard let identifier else { return [] }
            endpoint = "/api/tmdb/\(media.rawValue)/\(identifier)/recommendations"
        case .similar:
            guard let identifier else { return [] }
            endpoint = "/api/tmdb/\(media.rawValue)/\(identifier)/similar"
        }

        var query: [URLQueryItem] = []
        if kind != .trending {
            query.append(URLQueryItem(name: "page", value: String(page)))
        } else if page > 1 {
            query.append(URLQueryItem(name: "page", value: String(page)))
        }

        let response: TMDBResponse = try await api.get(endpoint, queryItems: query)
        tmdbPage = response.page ?? page
        tmdbTotalPages = response.total_pages ?? tmdbPage
        canLoadMore = tmdbPage < tmdbTotalPages

        let results = response.results ?? []
        return results.compactMap { item in
            guard let id = item.id else { return nil }
            return makeTMDBMediaItem(id: id, title: item.title ?? item.name ?? "", media: media, backdropPath: item.backdrop_path, posterPath: item.poster_path)
        }
    }

    private func makeTMDBMediaItem(id: Int, title: String, media: TMDBMediaType, backdropPath: String?, posterPath: String?) -> MediaItem {
        let artURL = imageService.tmdbImageURL(path: backdropPath, size: .w780)?.absoluteString
        let posterURL = imageService.tmdbImageURL(path: posterPath, size: .w500)?.absoluteString

        return MediaItem(
            id: "tmdb:\(media.rawValue):\(id)",
            title: title,
            type: media == .movie ? "movie" : "show",
            thumb: posterURL,
            art: artURL,
            year: nil,
            rating: nil,
            duration: nil,
            viewOffset: nil,
            summary: nil,
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

    // MARK: - Trakt Fetchers

    private func fetchTrakt(kind: TraktBrowseKind) async throws -> [MediaItem] {
        switch kind {
        case .trendingMovies:
            return try await fetchTraktTrending(media: "movies")
        case .trendingShows:
            return try await fetchTraktTrending(media: "shows")
        case .watchlist:
            return try await fetchTraktWatchlist()
        case .history:
            return try await fetchTraktHistory()
        case .recommendations:
            return try await fetchTraktRecommendations()
        case .popularShows:
            return try await fetchTraktPopular(media: "shows")
        }
    }

    private func fetchTraktTrending(media: String) async throws -> [MediaItem] {
        struct TraktTrendingItem: Codable { let watchers: Int?; let movie: TraktMedia?; let show: TraktMedia? }
        let arr: [TraktTrendingItem] = try await api.get("/api/trakt/trending/\(media)")
        let mediaType = (media == "movies") ? "movie" : "tv"
        let list: [TraktMedia] = arr.map { $0.movie ?? $0.show }.compactMap { $0 }
        return await mapTraktMedia(list, mediaType: mediaType)
    }

    private func fetchTraktPopular(media: String) async throws -> [MediaItem] {
        let arr: [TraktMedia] = try await api.get("/api/trakt/popular/\(media)")
        let mediaType = (media == "movies") ? "movie" : "tv"
        return await mapTraktMedia(arr, mediaType: mediaType)
    }

    private func fetchTraktWatchlist() async throws -> [MediaItem] {
        struct TraktItem: Codable { let movie: TraktMedia?; let show: TraktMedia? }
        let arr: [TraktItem] = try await api.get("/api/trakt/users/me/watchlist")
        let mediaList: [TraktMedia] = arr.compactMap { $0.movie ?? $0.show }
        return await mapTraktMedia(mediaList, mediaType: nil)
    }

    private func fetchTraktHistory() async throws -> [MediaItem] {
        struct TraktItem: Codable { let movie: TraktMedia?; let show: TraktMedia? }
        let arr: [TraktItem] = try await api.get("/api/trakt/users/me/history")
        let mediaList: [TraktMedia] = arr.compactMap { $0.movie ?? $0.show }
        return await mapTraktMedia(mediaList, mediaType: nil)
    }

    private func fetchTraktRecommendations() async throws -> [MediaItem] {
        let arr: [TraktMedia] = try await api.get("/api/trakt/recommendations/movies")
        return await mapTraktMedia(arr, mediaType: "movie")
    }

    private func mapTraktMedia(_ list: [TraktMedia], mediaType: String?) async -> [MediaItem] {
        guard !list.isEmpty else { return [] }
        var results: [MediaItem] = []
        await withTaskGroup(of: MediaItem?.self) { group in
            for media in list {
                group.addTask {
                    guard let tmdb = media.ids.tmdb else { return nil }
                    let type = mediaType ?? (media.ids.tmdb != nil ? self.inferType(from: media) : "movie")
                    let title = media.title ?? ""
                    do {
                        let backdrop = try await self.fetchTMDBBackdrop(mediaType: type, id: tmdb)
                        return MediaItem(
                            id: "tmdb:\(type == "movie" ? "movie" : "tv"):\(tmdb)",
                            title: title,
                            type: type == "movie" ? "movie" : "show",
                            thumb: nil,
                            art: backdrop,
                            year: media.year,
                            rating: nil,
                            duration: nil,
                            viewOffset: nil,
                            summary: nil,
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
                    } catch {
                        return nil
                    }
                }
            }
            for await item in group {
                if let item { results.append(item) }
            }
        }
        return results
    }

    private nonisolated func inferType(from media: TraktMedia) -> String {
        if media.ids.tmdb != nil, media.ids.trakt != nil {
            // Heuristic: use movie when year present, otherwise tv
            return (media.year != nil) ? "movie" : "tv"
        }
        return "movie"
    }

    private func fetchTMDBBackdrop(mediaType: String, id: Int) async throws -> String? {
        struct TMDBTitle: Codable { let backdrop_path: String? }
        let detail: TMDBTitle = try await api.get("/api/tmdb/\(mediaType)/\(id)")
        if let path = detail.backdrop_path {
            return imageService.tmdbImageURL(path: path, size: .w780)?.absoluteString
        }
        return nil
    }

    // MARK: - Helpers

    private func splitPathAndQuery(_ raw: String) -> (path: String, query: [URLQueryItem]?) {
        guard let question = raw.firstIndex(of: "?") else {
            return (raw, nil)
        }
        let path = String(raw[..<question])
        let queryString = String(raw[raw.index(after: question)...])
        let components = queryString.split(separator: "&").map { part -> URLQueryItem in
            let pieces = part.split(separator: "=", maxSplits: 1).map(String.init)
            let name = pieces.first ?? ""
            let value = pieces.count > 1 ? pieces[1] : nil
            return URLQueryItem(name: name, value: value)
        }
        return (path, components)
    }

    func shouldPrefetchItem(at index: Int) -> Bool {
        guard state == .loaded, canLoadMore, !isLoadingMore else { return false }
        let triggerIndex = max(items.count - 4, 0)
        return index >= triggerIndex
    }
}
