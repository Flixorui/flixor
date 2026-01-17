//
//  SearchViewModel.swift
//  FlixorMac
//
//  ViewModel for Search screen with Popular/Trending/Live results
//

import Foundation
import SwiftUI
import Combine

@MainActor
class SearchViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var query: String = ""
    @Published var plexResults: [SearchResult] = []
    @Published var tmdbMovies: [SearchResult] = []
    @Published var tmdbShows: [SearchResult] = []
    @Published var genreRows: [GenreRow] = []
    @Published var popularItems: [SearchResult] = []
    @Published var trendingItems: [SearchResult] = []
    @Published var isLoading = false
    @Published var searchMode: SearchMode = .idle

    enum SearchMode {
        case idle          // Show Popular/Trending
        case searching     // Actively searching
        case results       // Showing results
    }

    struct SearchResult: Identifiable, Hashable {
        let id: String
        let title: String
        let type: MediaType
        let imageURL: URL?
        let year: String?
        let overview: String?
        let available: Bool  // true if in Plex library
        let genreIds: [Int]  // TMDB genre IDs

        enum MediaType: String {
            case movie, tv, collection
        }
    }

    struct GenreRow: Identifiable {
        let id: String
        let title: String
        let items: [SearchResult]
    }

    // TMDB Genre mapping
    static let genreMap: [Int: String] = [
        28: "Action", 12: "Adventure", 16: "Animation", 35: "Comedy", 80: "Crime",
        99: "Documentary", 18: "Drama", 10751: "Family", 14: "Fantasy", 36: "History",
        27: "Horror", 10402: "Music", 9648: "Mystery", 10749: "Romance", 878: "Sci-Fi",
        10770: "TV Movie", 53: "Thriller", 10752: "War", 37: "Western",
        10759: "Action & Adventure", 10762: "Kids", 10763: "News", 10764: "Reality",
        10765: "Sci-Fi & Fantasy", 10766: "Soap", 10767: "Talk", 10768: "War & Politics"
    ]

    private let api = APIClient.shared
    private var searchTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    /// Whether to include TMDB results in search (from settings)
    private var includeTmdbInSearch: Bool {
        UserDefaults.standard.includeTmdbInSearch
    }

    init() {
        setupSearchDebouncing()
    }

    // MARK: - Setup

    private func setupSearchDebouncing() {
        // Debounce search input (300ms)
        $query
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] newQuery in
                guard let self = self else { return }
                Task { @MainActor in
                    if newQuery.isEmpty {
                        self.searchMode = .idle
                        self.plexResults = []
                        self.tmdbMovies = []
                        self.tmdbShows = []
                        self.genreRows = []
                    } else {
                        self.searchMode = .searching
                        await self.performSearch(query: newQuery)
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Load Initial Content

    func loadInitialContent() async {
        // Only load TMDB content if the setting is enabled
        guard includeTmdbInSearch else {
            popularItems = []
            trendingItems = []
            return
        }

        await withTaskGroup(of: Void.self) { group in
            // Load popular items
            group.addTask { await self.loadPopularItems() }
            // Load trending items
            group.addTask { await self.loadTrendingItems() }
        }
    }

    private func loadPopularItems() async {
        do {
            // Fetch popular movies and TV shows from TMDB
            struct PopularResponse: Codable {
                let results: [PopularItem]
            }
            struct PopularItem: Codable {
                let id: Int
                let title: String?
                let name: String?
                let backdrop_path: String?
                let poster_path: String?
                let release_date: String?
                let first_air_date: String?
            }

            async let movies: PopularResponse = api.get("/api/tmdb/movie/popular")
            async let shows: PopularResponse = api.get("/api/tmdb/tv/popular")

            let (movieResults, showResults) = try await (movies, shows)

            var popular: [SearchResult] = []

            // Add popular movies (first 6)
            for item in movieResults.results.prefix(6) {
                let imageURL = ImageService.shared.proxyImageURL(
                    url: item.backdrop_path.flatMap { "https://image.tmdb.org/t/p/w780\($0)" }
                ) ?? ImageService.shared.proxyImageURL(
                    url: item.poster_path.flatMap { "https://image.tmdb.org/t/p/w500\($0)" }
                )

                popular.append(SearchResult(
                    id: "tmdb:movie:\(item.id)",
                    title: item.title ?? "",
                    type: .movie,
                    imageURL: imageURL,
                    year: item.release_date?.prefix(4).description,
                    overview: nil,
                    available: false,
                    genreIds: []
                ))
            }

            // Add popular TV shows (first 6)
            for item in showResults.results.prefix(6) {
                let imageURL = ImageService.shared.proxyImageURL(
                    url: item.backdrop_path.flatMap { "https://image.tmdb.org/t/p/w780\($0)" }
                ) ?? ImageService.shared.proxyImageURL(
                    url: item.poster_path.flatMap { "https://image.tmdb.org/t/p/w500\($0)" }
                )

                popular.append(SearchResult(
                    id: "tmdb:tv:\(item.id)",
                    title: item.name ?? "",
                    type: .tv,
                    imageURL: imageURL,
                    year: item.first_air_date?.prefix(4).description,
                    overview: nil,
                    available: false,
                    genreIds: []
                ))
            }

            self.popularItems = Array(popular.prefix(10))
            print("📊 [Search] Loaded \(self.popularItems.count) popular items")
        } catch {
            print("❌ [Search] Failed to load popular items: \(error)")
        }
    }

    private func loadTrendingItems() async {
        do {
            // Fetch trending movies and shows separately, then interleave for variety
            struct TrendingResponse: Codable {
                let results: [TrendingItem]
            }
            struct TrendingItem: Codable {
                let id: Int
                let title: String?
                let name: String?
                let release_date: String?
                let first_air_date: String?
            }

            async let moviesRes: TrendingResponse = api.get("/api/tmdb/trending/movie/week")
            async let showsRes: TrendingResponse = api.get("/api/tmdb/trending/tv/week")

            let (movieResults, showResults) = try await (moviesRes, showsRes)

            // Fetch backdrop images with non-null iso_639_1 in parallel
            let movies: [SearchResult] = await withTaskGroup(of: SearchResult?.self) { group in
                for item in movieResults.results.prefix(6) {
                    group.addTask {
                        let imageURL = try? await self.fetchTMDBBackdropURL(mediaType: "movie", id: item.id, width: 780, height: 439)
                        return SearchResult(
                            id: "tmdb:movie:\(item.id)",
                            title: item.title ?? "",
                            type: .movie,
                            imageURL: imageURL,
                            year: item.release_date?.prefix(4).description,
                            overview: nil,
                            available: false,
                            genreIds: []
                        )
                    }
                }
                var results: [SearchResult] = []
                for await result in group {
                    if let result = result {
                        results.append(result)
                    }
                }
                return results
            }

            let shows: [SearchResult] = await withTaskGroup(of: SearchResult?.self) { group in
                for item in showResults.results.prefix(6) {
                    group.addTask {
                        let imageURL = try? await self.fetchTMDBBackdropURL(mediaType: "tv", id: item.id, width: 780, height: 439)
                        return SearchResult(
                            id: "tmdb:tv:\(item.id)",
                            title: item.name ?? "",
                            type: .tv,
                            imageURL: imageURL,
                            year: item.first_air_date?.prefix(4).description,
                            overview: nil,
                            available: false,
                            genreIds: []
                        )
                    }
                }
                var results: [SearchResult] = []
                for await result in group {
                    if let result = result {
                        results.append(result)
                    }
                }
                return results
            }

            // Interleave shows and movies for variety
            var combined: [SearchResult] = []
            for i in 0..<max(movies.count, shows.count) {
                if i < shows.count { combined.append(shows[i]) }
                if i < movies.count { combined.append(movies[i]) }
            }

            self.trendingItems = combined
            print("🔥 [Search] Loaded \(self.trendingItems.count) trending items")
        } catch {
            print("❌ [Search] Failed to load trending items: \(error)")
        }
    }

    // MARK: - TMDB Backdrop Helper

    private func fetchTMDBBackdropURL(mediaType: String, id: Int, width: Int, height: Int) async throws -> URL? {
        struct TMDBImages: Codable { let backdrops: [TMDBImage]? }
        struct TMDBImage: Codable { let file_path: String?; let iso_639_1: String?; let vote_average: Double? }

        let imgs: TMDBImages = try await api.get("/api/tmdb/\(mediaType)/\(id)/images", queryItems: [URLQueryItem(name: "include_image_language", value: "en,null")])
        let backdrops = imgs.backdrops ?? []
        if backdrops.isEmpty { return nil }

        let pick: ([TMDBImage]) -> TMDBImage? = { arr in
            return arr.sorted { ($0.vote_average ?? 0) > ($1.vote_average ?? 0) }.first
        }

        // Priority 1: English backdrops (with title text burned in)
        if let en = pick(backdrops.filter { $0.iso_639_1 == "en" }), let path = en.file_path {
            return ImageService.shared.proxyImageURL(url: "https://image.tmdb.org/t/p/original\(path)", width: width, height: height)
        }

        // Priority 2: Any language with title (iso_639_1 is not null)
        if let withLang = pick(backdrops.filter { $0.iso_639_1 != nil }), let path = withLang.file_path {
            return ImageService.shared.proxyImageURL(url: "https://image.tmdb.org/t/p/original\(path)", width: width, height: height)
        }

        // Priority 3: Fallback to any backdrop (including textless)
        guard let any = pick(backdrops), let path = any.file_path else { return nil }
        return ImageService.shared.proxyImageURL(url: "https://image.tmdb.org/t/p/original\(path)", width: width, height: height)
    }

    // MARK: - Search

    private func performSearch(query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            plexResults = []
            tmdbMovies = []
            tmdbShows = []
            genreRows = []
            searchMode = .idle
            return
        }

        // Cancel previous search task
        searchTask?.cancel()

        searchTask = Task {
            isLoading = true
            defer { isLoading = false }

            print("🔍 [Search] Searching for: \(query)")

            var plexRes: [SearchResult] = []
            var tmdbMovieRes: [SearchResult] = []
            var tmdbShowRes: [SearchResult] = []
            var allGenreIds = Set<Int>()

            // Search Plex
            await withTaskGroup(of: [SearchResult].self) { group in
                // Search Plex movies
                group.addTask { await self.searchPlex(query: query, type: 1) }
                // Search Plex TV shows
                group.addTask { await self.searchPlex(query: query, type: 2) }

                for await results in group {
                    plexRes.append(contentsOf: results)
                }
            }

            // Search TMDB (only if enabled in settings)
            if self.includeTmdbInSearch {
                let (movies, shows, genres) = await searchTMDBSeparate(query: query)
                tmdbMovieRes = movies
                tmdbShowRes = shows
                allGenreIds = genres
            }

            guard !Task.isCancelled else { return }

            self.plexResults = plexRes
            self.tmdbMovies = tmdbMovieRes
            self.tmdbShows = tmdbShowRes
            self.searchMode = .results

            print("✅ [Search] Found \(plexRes.count) Plex, \(tmdbMovieRes.count) TMDB movies, \(tmdbShowRes.count) TMDB shows")

            // Fetch genre-based recommendations (top 3 genres) - only if TMDB is enabled
            if self.includeTmdbInSearch && !allGenreIds.isEmpty {
                await loadGenreRecommendations(genreIds: Array(allGenreIds).prefix(3))
            }
        }
    }

    private func searchPlex(query: String, type: Int) async -> [SearchResult] {
        do {
            // type: 1 = movies, 2 = tv shows
            let response: [PlexSearchItem] = try await api.get(
                "/api/plex/search",
                queryItems: [
                    URLQueryItem(name: "query", value: query),
                    URLQueryItem(name: "type", value: String(type))
                ]
            )

            // Fetch TMDB images for all items in parallel
            let items = response.prefix(20)
            return await withTaskGroup(of: (String, SearchResult).self) { group in
                for item in items {
                    group.addTask {
                        let ratingKey = item.ratingKey

                        // Try to get TMDB backdrop
                        var imageURL: URL? = nil
                        do {
                            struct TMDBMatchResponse: Codable {
                                let tmdbId: String?
                                let backdropUrl: String?
                            }

                            let tmdbMatch: TMDBMatchResponse = try await self.api.get(
                                "/api/plex/tmdb-match",
                                queryItems: [URLQueryItem(name: "ratingKey", value: ratingKey)]
                            )

                            if let backdropUrl = tmdbMatch.backdropUrl {
                                imageURL = await ImageService.shared.proxyImageURL(url: backdropUrl)
                            }
                        } catch {
                            // Silently fail - will use Plex image
                        }

                        // Fallback to Plex image if no TMDB image
                        if imageURL == nil {
                            let fallbackPath = item.art ?? item.thumb ?? item.parentThumb ?? item.grandparentThumb ?? ""
                            imageURL = await ImageService.shared.plexImageURL(path: fallbackPath, width: 780, height: 439)
                        }

                        let result = SearchResult(
                            id: "plex:\(ratingKey)",
                            title: item.title ?? "",
                            type: type == 1 ? .movie : .tv,
                            imageURL: imageURL,
                            year: item.year.map(String.init),
                            overview: item.summary,
                            available: true,
                            genreIds: []
                        )

                        return (ratingKey, result)
                    }
                }

                var results: [(String, SearchResult)] = []
                for await result in group {
                    results.append(result)
                }

                // Preserve original order
                let resultMap = Dictionary(uniqueKeysWithValues: results)
                return items.compactMap { resultMap[$0.ratingKey] }
            }
        } catch {
            print("❌ [Search] Plex search failed (type=\(type)): \(error)")
            return []
        }
    }

    private func searchTMDBSeparate(query: String) async -> ([SearchResult], [SearchResult], Set<Int>) {
        do {
            struct TMDBSearchResponse: Codable {
                let results: [TMDBSearchItem]
            }
            struct TMDBSearchItem: Codable {
                let id: Int
                let title: String?
                let name: String?
                let media_type: String
                let backdrop_path: String?
                let poster_path: String?
                let release_date: String?
                let first_air_date: String?
                let overview: String?
                let genre_ids: [Int]?
            }

            let response: TMDBSearchResponse = try await api.get(
                "/api/tmdb/search/multi",
                queryItems: [URLQueryItem(name: "query", value: query)]
            )

            var movies: [SearchResult] = []
            var shows: [SearchResult] = []
            var allGenreIds = Set<Int>()

            for item in response.results.prefix(20) {
                let genreIds = item.genre_ids ?? []
                genreIds.forEach { allGenreIds.insert($0) }

                let imageURL = ImageService.shared.proxyImageURL(
                    url: item.poster_path.flatMap { "https://image.tmdb.org/t/p/w500\($0)" }
                ) ?? ImageService.shared.proxyImageURL(
                    url: item.backdrop_path.flatMap { "https://image.tmdb.org/t/p/w780\($0)" }
                )

                let result = SearchResult(
                    id: "tmdb:\(item.media_type):\(item.id)",
                    title: item.title ?? item.name ?? "",
                    type: item.media_type == "movie" ? .movie : .tv,
                    imageURL: imageURL,
                    year: (item.release_date ?? item.first_air_date)?.prefix(4).description,
                    overview: item.overview,
                    available: false,
                    genreIds: genreIds
                )

                if item.media_type == "movie" {
                    movies.append(result)
                } else if item.media_type == "tv" {
                    shows.append(result)
                }
            }

            return (movies, shows, allGenreIds)
        } catch {
            print("❌ [Search] TMDB search failed: \(error)")
            return ([], [], Set())
        }
    }

    private func loadGenreRecommendations(genreIds: ArraySlice<Int>) async {
        var genreRowsData: [GenreRow] = []

        for genreId in genreIds {
            guard let genreName = Self.genreMap[genreId] else { continue }

            do {
                // Fetch movies and TV shows for this genre in parallel
                struct DiscoverResponse: Codable {
                    let results: [DiscoverItem]
                }
                struct DiscoverItem: Codable {
                    let id: Int
                    let title: String?
                    let name: String?
                    let poster_path: String?
                    let release_date: String?
                    let first_air_date: String?
                }

                async let movieRes: DiscoverResponse = api.get(
                    "/api/tmdb/discover/movie",
                    queryItems: [
                        URLQueryItem(name: "with_genres", value: String(genreId)),
                        URLQueryItem(name: "sort_by", value: "popularity.desc"),
                        URLQueryItem(name: "page", value: "1")
                    ]
                )

                async let tvRes: DiscoverResponse = api.get(
                    "/api/tmdb/discover/tv",
                    queryItems: [
                        URLQueryItem(name: "with_genres", value: String(genreId)),
                        URLQueryItem(name: "sort_by", value: "popularity.desc"),
                        URLQueryItem(name: "page", value: "1")
                    ]
                )

                let (movieResults, tvResults) = try await (movieRes, tvRes)

                let movies: [SearchResult] = movieResults.results.prefix(10).map { item in
                    let imageURL = ImageService.shared.proxyImageURL(
                        url: item.poster_path.flatMap { "https://image.tmdb.org/t/p/w500\($0)" }
                    )
                    return SearchResult(
                        id: "tmdb:movie:\(item.id)",
                        title: item.title ?? "",
                        type: .movie,
                        imageURL: imageURL,
                        year: item.release_date?.prefix(4).description,
                        overview: nil,
                        available: false,
                        genreIds: [genreId]
                    )
                }

                let shows: [SearchResult] = tvResults.results.prefix(10).map { item in
                    let imageURL = ImageService.shared.proxyImageURL(
                        url: item.poster_path.flatMap { "https://image.tmdb.org/t/p/w500\($0)" }
                    )
                    return SearchResult(
                        id: "tmdb:tv:\(item.id)",
                        title: item.name ?? "",
                        type: .tv,
                        imageURL: imageURL,
                        year: item.first_air_date?.prefix(4).description,
                        overview: nil,
                        available: false,
                        genreIds: [genreId]
                    )
                }

                // Combine movies and shows (up to 15 items)
                let combined = Array((movies + shows).prefix(15))

                if !combined.isEmpty {
                    genreRowsData.append(GenreRow(
                        id: "genre:\(genreId)",
                        title: genreName,
                        items: combined
                    ))
                }

                print("🎬 [Search] Loaded \(combined.count) items for genre '\(genreName)'")
            } catch {
                print("❌ [Search] Failed to fetch genre '\(genreName)': \(error)")
            }
        }

        guard !Task.isCancelled else { return }
        self.genreRows = genreRowsData
    }

    // MARK: - Helper Structs

    private struct PlexSearchItem: Codable {
        let ratingKey: String
        let title: String?
        let year: Int?
        let summary: String?
        let art: String?
        let thumb: String?
        let parentThumb: String?
        let grandparentThumb: String?
    }
}
