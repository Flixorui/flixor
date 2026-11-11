//
//  BrowseModalViewModel.swift
//  FlixorMac
//
//  Drives the Netflix-style Browse overlay on macOS.
//

import Foundation
import FlixorKit

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
    /// Unique by id (sources sometimes repeat a title on a later page, and a
    /// repeated id leaves an empty cell in a lazy grid).
    @Published var items: [MediaItem] = [] {
        didSet { recount() }
    }
    /// Movies and shows in `items`, kept in step with it.
    private(set) var movieCount = 0
    private(set) var showCount = 0
    @Published var title: String = ""
    @Published var subtitle: String?
    @Published var isLoadingMore = false
    @Published var canLoadMore = false

    private let api = APIClient.shared
    private let imageService = ImageService.shared

    private var context: BrowseContext?
    private var tmdbPage = 1
    private var tmdbTotalPages = 1
    private var traktPage = 1
    private let pageSize = 20
    /// Next `skip` value for an addon catalog, and what it has returned so far.
    private var stremioSkip = 0
    private var stremioSeenIds: Set<String> = []
    private var itemIds: Set<String> = []

    nonisolated static func isShow(_ item: MediaItem) -> Bool {
        item.type == "show" || item.type == "tv" || item.type == "episode"
    }

    private func recount() {
        let shows = items.reduce(0) { $0 + (Self.isShow($1) ? 1 : 0) }
        showCount = shows
        movieCount = items.count - shows
    }

    /// Keeps the first of each id, across pages.
    private func uniqueNewItems(_ incoming: [MediaItem]) -> [MediaItem] {
        incoming.filter { itemIds.insert($0.id).inserted }
    }

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
        traktPage = 1
        stremioSkip = 0
        stremioSeenIds = []
        itemIds = []
    }

    /// Loads once per context: coming back to the page keeps the loaded pages
    /// (and the scroll position). A failed or interrupted load runs again.
    func loadIfNeeded(context: BrowseContext) async {
        if self.context == context {
            switch state {
            case .loading, .loaded, .empty:
                return
            case .idle, .error:
                break
            }
        }
        await load(context: context)
    }

    func load(context: BrowseContext) async {
        self.context = context
        tmdbPage = 1
        tmdbTotalPages = 1
        traktPage = 1
        stremioSkip = 0
        stremioSeenIds = []
        canLoadMore = false
        isLoadingMore = false

        let header = headerText(for: context)
        title = header.title
        subtitle = header.subtitle

        state = .loading
        itemIds = []
        items = []

        do {
            let data = uniqueNewItems(try await fetchItems(for: context, page: 1, append: false))
            if Task.isCancelled {
                // Left before it finished (lookups may have been cut short); load again on return.
                state = .idle
                return
            }
            items = data
            state = data.isEmpty ? .empty : .loaded
        } catch {
            if Task.isCancelled {
                state = .idle
                return
            }
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
            // Determine next page based on context type
            let nextPage: Int
            switch context {
            case .trakt:
                nextPage = traktPage + 1
            case .tmdb:
                nextPage = tmdbPage + 1
            default:
                nextPage = 1
            }

            let more = uniqueNewItems(try await fetchItems(for: context, page: nextPage, append: true))
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
        case .plexCollection(let ratingKey, _):
            canLoadMore = false
            return try await fetchPlexCollection(ratingKey: ratingKey)
        case .tmdb(let kind, let media, let id, let display):
            return try await fetchTMDB(kind: kind, media: media, identifier: id, displayTitle: display, page: page, append: append)
        case .trakt(let kind):
            return try await fetchTrakt(kind: kind, page: page, append: append)
        case .stremioCatalog(let catalog):
            return try await fetchStremioCatalog(catalog)
        }
    }

    /// Addons don't report totals, so paging stops when a page brings nothing new.
    /// That also ends the list for an addon that ignores `skip`.
    private func fetchStremioCatalog(_ catalog: StremioCatalogBrowse) async throws -> [MediaItem] {
        let previews = try await StremioService.shared.fetchCatalog(
            installationId: catalog.installationId,
            type: catalog.type,
            catalogId: catalog.catalogId,
            extras: stremioSkip > 0 ? ["skip": String(stremioSkip)] : [:],
            limit: 100
        )
        let items = await StremioCatalogMapper.shared.mediaItems(from: previews)
        let fresh = items.filter { stremioSeenIds.insert($0.id).inserted }
        stremioSkip += previews.count
        canLoadMore = catalog.supportsPaging && !fresh.isEmpty
        return fresh
    }

    // MARK: - Header Helpers

    private func headerText(for context: BrowseContext) -> (title: String, subtitle: String?) {
        switch context {
        case .plexDirectory(_, let customTitle):
            return (customTitle ?? String(localized: "Browse"), nil)
        case .plexLibrary(_, let libraryTitle):
            return (libraryTitle ?? String(localized: "Library"), String(localized: "All titles"))
        case .plexWatchlist:
            return (String(localized: "Watchlist"), "Plex.tv")
        case .plexCollection(_, let collectionTitle):
            return (collectionTitle, String(localized: "Collection"))
        case .stremioCatalog(let catalog):
            return (catalog.title, catalog.addonName)
        case .tmdb(let kind, let media, _, let display):
            switch kind {
            case .trending:
                return (String(localized: "Trending"), "TMDB")
            case .recommendations:
                return (String(localized: "Recommendations"), display)
            case .similar:
                return (String(localized: "More Like This"), display)
            case .popular:
                return (display ?? (media == .movie ? String(localized: "Popular Movies") : String(localized: "Popular TV Shows")), "TMDB")
            case .topRated:
                return (display ?? (media == .movie ? String(localized: "Top Rated Movies") : String(localized: "Top Rated TV Shows")), "TMDB")
            case .upcoming:
                return (display ?? String(localized: "Coming Soon"), "TMDB")
            case .genre:
                return (display ?? String(localized: "Browse"), "TMDB")
            }
        case .trakt(let kind):
            switch kind {
            case .trendingMovies:
                return (String(localized: "Trending Movies"), "Trakt")
            case .trendingShows:
                return (String(localized: "Trending TV Shows"), "Trakt")
            case .watchlist:
                return (String(localized: "Your Trakt Watchlist"), nil)
            case .history:
                return (String(localized: "Recently Watched"), "Trakt")
            case .recommendations:
                return (String(localized: "Recommended for You"), "Trakt")
            case .popularShows:
                return (String(localized: "Popular TV Shows"), "Trakt")
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

    private func fetchPlexCollection(ratingKey: String) async throws -> [MediaItem] {
        guard let plexServer = FlixorCore.shared.plexServer else { return [] }
        let items = try await plexServer.getCollectionItems(ratingKey: ratingKey, size: nil)
        return items.map { plex in
            MediaItem(
                id: plex.ratingKey ?? plex.key ?? "",
                title: plex.title ?? String(localized: "Unknown"),
                type: plex.type ?? "unknown",
                thumb: plex.thumb,
                art: plex.art,
                year: plex.year,
                rating: nil,
                duration: plex.duration,
                viewOffset: plex.viewOffset,
                summary: plex.summary,
                grandparentTitle: plex.grandparentTitle,
                grandparentThumb: plex.grandparentThumb,
                grandparentArt: plex.grandparentArt,
                grandparentRatingKey: plex.grandparentRatingKey,
                parentIndex: plex.parentIndex,
                index: plex.index,
                parentRatingKey: plex.parentRatingKey,
                parentTitle: plex.parentTitle,
                leafCount: plex.leafCount,
                viewedLeafCount: plex.viewedLeafCount
            )
        }
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
        var query: [URLQueryItem] = []

        switch kind {
        case .trending:
            endpoint = "/api/tmdb/trending/\(media.rawValue)/week"
        case .recommendations:
            guard let identifier else { return [] }
            endpoint = "/api/tmdb/\(media.rawValue)/\(identifier)/recommendations"
        case .similar:
            guard let identifier else { return [] }
            endpoint = "/api/tmdb/\(media.rawValue)/\(identifier)/similar"
        case .popular:
            endpoint = "/api/tmdb/\(media.rawValue)/popular"
        case .topRated:
            endpoint = "/api/tmdb/\(media.rawValue)/top_rated"
        case .upcoming:
            endpoint = "/api/tmdb/movie/upcoming"
        case .genre:
            guard let identifier else { return [] }
            endpoint = "/api/tmdb/discover/\(media.rawValue)"
            query.append(URLQueryItem(name: "with_genres", value: identifier))
        }

        if kind != .trending || page > 1 {
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

    private func fetchTrakt(kind: TraktBrowseKind, page: Int, append: Bool) async throws -> [MediaItem] {
        switch kind {
        case .trendingMovies:
            return try await fetchTraktTrending(media: "movies", page: page)
        case .trendingShows:
            return try await fetchTraktTrending(media: "shows", page: page)
        case .watchlist:
            return try await fetchTraktWatchlist(page: page)
        case .history:
            return try await fetchTraktHistory(page: page)
        case .recommendations:
            return try await fetchTraktRecommendations(page: page)
        case .popularShows:
            return try await fetchTraktPopular(media: "shows", page: page)
        }
    }

    private func fetchTraktTrending(media: String, page: Int) async throws -> [MediaItem] {
        struct TraktTrendingItem: Codable { let watchers: Int?; let movie: TraktMedia?; let show: TraktMedia? }
        let arr: [TraktTrendingItem] = try await api.get(
            "/api/trakt/trending/\(media)",
            queryItems: [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "limit", value: String(pageSize))]
        )
        let mediaType = (media == "movies") ? "movie" : "tv"
        let list: [TraktMedia] = arr.map { $0.movie ?? $0.show }.compactMap { $0 }
        canLoadMore = list.count == pageSize
        traktPage = page
        return await mapTraktMedia(list, mediaType: mediaType)
    }

    private func fetchTraktPopular(media: String, page: Int) async throws -> [MediaItem] {
        let arr: [TraktMedia] = try await api.get(
            "/api/trakt/popular/\(media)",
            queryItems: [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "limit", value: String(pageSize))]
        )
        let mediaType = (media == "movies") ? "movie" : "tv"
        canLoadMore = arr.count == pageSize
        traktPage = page
        return await mapTraktMedia(arr, mediaType: mediaType)
    }

    private func fetchTraktWatchlist(page: Int) async throws -> [MediaItem] {
        struct TraktItem: Codable { let movie: TraktMedia?; let show: TraktMedia? }
        let arr: [TraktItem] = try await api.get(
            "/api/trakt/users/me/watchlist",
            queryItems: [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "limit", value: String(pageSize))]
        )
        let mediaList: [TraktMedia] = arr.compactMap { $0.movie ?? $0.show }
        canLoadMore = mediaList.count == pageSize
        traktPage = page
        return await mapTraktMedia(mediaList, mediaType: nil)
    }

    private func fetchTraktHistory(page: Int) async throws -> [MediaItem] {
        struct TraktItem: Codable { let movie: TraktMedia?; let show: TraktMedia? }
        // Fetch movies and shows history separately like mobile does
        async let moviesTask: [TraktItem] = api.get(
            "/api/trakt/users/me/history/movies",
            queryItems: [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "limit", value: String(pageSize))]
        )
        async let showsTask: [TraktItem] = api.get(
            "/api/trakt/users/me/history/shows",
            queryItems: [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "limit", value: String(pageSize))]
        )
        let (moviesArr, showsArr) = try await (moviesTask, showsTask)

        // Combine and deduplicate by TMDB ID
        var seenIds = Set<String>()
        var mediaList: [TraktMedia] = []

        for item in moviesArr {
            if let movie = item.movie, let tmdbId = movie.ids.tmdb {
                let id = "tmdb:movie:\(tmdbId)"
                if !seenIds.contains(id) {
                    seenIds.insert(id)
                    mediaList.append(movie)
                }
            }
        }

        for item in showsArr {
            if let show = item.show, let tmdbId = show.ids.tmdb {
                let id = "tmdb:tv:\(tmdbId)"
                if !seenIds.contains(id) {
                    seenIds.insert(id)
                    mediaList.append(show)
                }
            }
        }

        canLoadMore = moviesArr.count == pageSize || showsArr.count == pageSize
        traktPage = page
        return await mapTraktMedia(mediaList, mediaType: nil)
    }

    private func fetchTraktRecommendations(page: Int) async throws -> [MediaItem] {
        let arr: [TraktMedia] = try await api.get(
            "/api/trakt/recommendations/movies",
            queryItems: [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "limit", value: String(pageSize))]
        )
        canLoadMore = arr.count == pageSize
        traktPage = page
        return await mapTraktMedia(arr, mediaType: "movie")
    }

    /// One TMDB request per title for both poster and backdrop. Keeps the list's order.
    private func mapTraktMedia(_ list: [TraktMedia], mediaType: String?) async -> [MediaItem] {
        guard !list.isEmpty else { return [] }
        let mapped = await withTaskGroup(of: (Int, MediaItem?).self) { group -> [MediaItem?] in
            for (index, media) in list.enumerated() {
                group.addTask {
                    guard let tmdb = media.ids.tmdb else { return (index, nil) }
                    let type = mediaType ?? (media.ids.tmdb != nil ? self.inferType(from: media) : "movie")
                    let title = media.title ?? ""
                    do {
                        let art = try await self.fetchTMDBArt(mediaType: type, id: tmdb)

                        return (index, MediaItem(
                            id: "tmdb:\(type == "movie" ? "movie" : "tv"):\(tmdb)",
                            title: title,
                            type: type == "movie" ? "movie" : "show",
                            thumb: art.poster,
                            art: art.backdrop,
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
                        ))
                    } catch {
                        return (index, nil)
                    }
                }
            }
            var ordered = [MediaItem?](repeating: nil, count: list.count)
            for await (index, item) in group {
                ordered[index] = item
            }
            return ordered
        }
        return mapped.compactMap { $0 }
    }

    private nonisolated func inferType(from media: TraktMedia) -> String {
        if media.ids.tmdb != nil, media.ids.trakt != nil {
            // Heuristic: use movie when year present, otherwise tv
            return (media.year != nil) ? "movie" : "tv"
        }
        return "movie"
    }

    private func fetchTMDBArt(mediaType: String, id: Int) async throws -> (poster: String?, backdrop: String?) {
        struct TMDBTitle: Codable { let poster_path: String?; let backdrop_path: String? }
        let detail: TMDBTitle = try await api.get("/api/tmdb/\(mediaType)/\(id)")
        let poster = detail.poster_path.flatMap { imageService.tmdbImageURL(path: $0, size: .w500)?.absoluteString }
        let backdrop = detail.backdrop_path.flatMap { imageService.tmdbImageURL(path: $0, size: .w780)?.absoluteString }
        return (poster, backdrop)
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
