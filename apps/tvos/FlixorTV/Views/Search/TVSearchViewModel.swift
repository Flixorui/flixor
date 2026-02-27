import Foundation
import SwiftUI
import Combine
import FlixorKit

@MainActor
final class TVSearchViewModel: ObservableObject {
    enum SearchMode {
        case idle
        case searching
        case results
    }

    struct SearchResult: Identifiable, Hashable {
        enum MediaType: String {
            case movie
            case tv
            case collection
        }

        let id: String
        let title: String
        let type: MediaType
        let imageURL: URL?
        let logoURL: URL?
        let year: String?
        let overview: String?
        let available: Bool
        let genreIds: [Int]
        let editionTitle: String?
        let rawThumbPath: String?
        let rawArtPath: String?

        var mediaItem: MediaItem {
            MediaItem(
                id: id,
                title: title,
                type: type == .movie ? "movie" : "show",
                thumb: imageURL?.absoluteString ?? rawThumbPath,
                art: imageURL?.absoluteString ?? rawArtPath ?? rawThumbPath,
                logo: logoURL?.absoluteString,
                year: year.flatMap(Int.init),
                rating: nil,
                duration: nil,
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

    struct GenreRow: Identifiable {
        let id: String
        let title: String
        let items: [SearchResult]
    }

    static let genreMap: [Int: String] = [
        28: "Action", 12: "Adventure", 16: "Animation", 35: "Comedy", 80: "Crime",
        99: "Documentary", 18: "Drama", 10751: "Family", 14: "Fantasy", 36: "History",
        27: "Horror", 10402: "Music", 9648: "Mystery", 10749: "Romance", 878: "Sci-Fi",
        53: "Thriller", 10752: "War", 37: "Western", 10759: "Action & Adventure", 10764: "Reality"
    ]

    @Published var query: String = ""
    @Published var plexResults: [SearchResult] = []
    @Published var tmdbMovies: [SearchResult] = []
    @Published var tmdbShows: [SearchResult] = []
    @Published var genreRows: [GenreRow] = []
    @Published var popularItems: [SearchResult] = []
    @Published var trendingItems: [SearchResult] = []
    @Published var isLoading = false
    @Published var searchMode: SearchMode = .idle

    private let api = APIClient.shared
    private var searchTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private var includeTmdbInSearch: Bool {
        UserDefaults.standard.includeTmdbInSearch
    }

    init() {
        setupDebouncing()
    }

    private func setupDebouncing() {
        $query
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] text in
                guard let self else { return }
                Task { @MainActor in
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.searchMode = .idle
                        self.plexResults = []
                        self.tmdbMovies = []
                        self.tmdbShows = []
                        self.genreRows = []
                    } else {
                        self.searchMode = .searching
                        await self.performSearch(query: text)
                    }
                }
            }
            .store(in: &cancellables)
    }

    func loadInitialContent() async {
        guard includeTmdbInSearch else {
            popularItems = []
            trendingItems = []
            return
        }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadPopularItems() }
            group.addTask { await self.loadTrendingItems() }
        }
    }

    private func loadPopularItems() async {
        do {
            async let movies = api.getTMDBPopularMovies(page: 1)
            async let shows = api.getTMDBPopularTV(page: 1)
            let (movieResponse, showResponse) = try await (movies, shows)

            var combined: [SearchResult] = []
            for item in movieResponse.results.prefix(8) {
                let imageURL = ImageService.shared.proxyImageURL(
                    url: item.backdrop_path.flatMap { "https://image.tmdb.org/t/p/w780\($0)" }
                ) ?? ImageService.shared.proxyImageURL(
                    url: item.poster_path.flatMap { "https://image.tmdb.org/t/p/w500\($0)" }
                )

                combined.append(
                    SearchResult(
                        id: "tmdb:movie:\(item.id)",
                        title: item.title ?? "",
                        type: .movie,
                        imageURL: imageURL,
                        logoURL: await fetchTMDBLogo(mediaType: "movie", id: item.id),
                        year: item.release_date?.prefix(4).description,
                        overview: item.overview,
                        available: false,
                        genreIds: item.genre_ids ?? [],
                        editionTitle: nil,
                        rawThumbPath: nil,
                        rawArtPath: nil
                    )
                )
            }

            for item in showResponse.results.prefix(8) {
                let imageURL = ImageService.shared.proxyImageURL(
                    url: item.backdrop_path.flatMap { "https://image.tmdb.org/t/p/w780\($0)" }
                ) ?? ImageService.shared.proxyImageURL(
                    url: item.poster_path.flatMap { "https://image.tmdb.org/t/p/w500\($0)" }
                )

                combined.append(
                    SearchResult(
                        id: "tmdb:tv:\(item.id)",
                        title: item.name ?? "",
                        type: .tv,
                        imageURL: imageURL,
                        logoURL: await fetchTMDBLogo(mediaType: "tv", id: item.id),
                        year: item.first_air_date?.prefix(4).description,
                        overview: item.overview,
                        available: false,
                        genreIds: item.genre_ids ?? [],
                        editionTitle: nil,
                        rawThumbPath: nil,
                        rawArtPath: nil
                    )
                )
            }

            popularItems = Array(combined.prefix(12))
        } catch {
            #if DEBUG
            print("❌ [TVSearch] Failed loading popular: \(error)")
            #endif
        }
    }

    private func loadTrendingItems() async {
        do {
            async let movies = api.getTMDBTrending(mediaType: "movie", timeWindow: "week")
            async let shows = api.getTMDBTrending(mediaType: "tv", timeWindow: "week")
            let (movieResponse, showResponse) = try await (movies, shows)

            var movieItems: [SearchResult] = []
            for item in movieResponse.results.prefix(8) {
                let imageURL = ImageService.shared.proxyImageURL(
                    url: item.backdrop_path.flatMap { "https://image.tmdb.org/t/p/w780\($0)" }
                ) ?? ImageService.shared.proxyImageURL(
                    url: item.poster_path.flatMap { "https://image.tmdb.org/t/p/w500\($0)" }
                )

                movieItems.append(
                    SearchResult(
                        id: "tmdb:movie:\(item.id)",
                        title: item.title ?? "",
                        type: .movie,
                        imageURL: imageURL,
                        logoURL: await fetchTMDBLogo(mediaType: "movie", id: item.id),
                        year: item.release_date?.prefix(4).description,
                        overview: item.overview,
                        available: false,
                        genreIds: item.genre_ids ?? [],
                        editionTitle: nil,
                        rawThumbPath: nil,
                        rawArtPath: nil
                    )
                )
            }

            var showItems: [SearchResult] = []
            for item in showResponse.results.prefix(8) {
                let imageURL = ImageService.shared.proxyImageURL(
                    url: item.backdrop_path.flatMap { "https://image.tmdb.org/t/p/w780\($0)" }
                ) ?? ImageService.shared.proxyImageURL(
                    url: item.poster_path.flatMap { "https://image.tmdb.org/t/p/w500\($0)" }
                )

                showItems.append(
                    SearchResult(
                        id: "tmdb:tv:\(item.id)",
                        title: item.name ?? "",
                        type: .tv,
                        imageURL: imageURL,
                        logoURL: await fetchTMDBLogo(mediaType: "tv", id: item.id),
                        year: item.first_air_date?.prefix(4).description,
                        overview: item.overview,
                        available: false,
                        genreIds: item.genre_ids ?? [],
                        editionTitle: nil,
                        rawThumbPath: nil,
                        rawArtPath: nil
                    )
                )
            }

            var mixed: [SearchResult] = []
            for i in 0..<max(movieItems.count, showItems.count) {
                if i < showItems.count { mixed.append(showItems[i]) }
                if i < movieItems.count { mixed.append(movieItems[i]) }
            }
            trendingItems = mixed
        } catch {
            #if DEBUG
            print("❌ [TVSearch] Failed loading trending: \(error)")
            #endif
        }
    }

    private func performSearch(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            plexResults = []
            tmdbMovies = []
            tmdbShows = []
            genreRows = []
            searchMode = .idle
            return
        }

        searchTask?.cancel()

        searchTask = Task {
            isLoading = true
            defer { isLoading = false }

            var plex: [SearchResult] = []
            var movies: [SearchResult] = []
            var shows: [SearchResult] = []
            var genreIds = Set<Int>()

            await withTaskGroup(of: [SearchResult].self) { group in
                group.addTask { await self.searchPlex(query: trimmed, type: 1) }
                group.addTask { await self.searchPlex(query: trimmed, type: 2) }

                for await row in group {
                    plex.append(contentsOf: row)
                }
            }

            if includeTmdbInSearch {
                let (tmdbMovieResults, tmdbShowResults, allGenres) = await searchTMDBSeparate(query: trimmed)
                movies = tmdbMovieResults
                shows = tmdbShowResults
                genreIds = allGenres
            }

            guard !Task.isCancelled else { return }
            plexResults = plex
            tmdbMovies = movies
            tmdbShows = shows
            searchMode = .results

            if includeTmdbInSearch, !genreIds.isEmpty {
                await loadGenreRecommendations(genreIds: Array(genreIds).prefix(3))
            } else {
                genreRows = []
            }
        }

        await searchTask?.value
    }

    private func searchPlex(query: String, type: Int) async -> [SearchResult] {
        do {
            let response: [PlexSearchItem] = try await api.get(
                "/api/plex/search",
                queryItems: [
                    URLQueryItem(name: "query", value: query),
                    URLQueryItem(name: "type", value: String(type))
                ]
            )

            let items = response.prefix(20)
            return await withTaskGroup(of: (String, SearchResult).self) { group in
                for item in items {
                    let edition = extractEditionTitle(from: item.Media)
                    group.addTask {
                        let ratingKey = item.ratingKey
                        var imageURL: URL? = nil

                        do {
                            let tmdbMatch: TMDBMatchResponse = try await self.api.get(
                                "/api/plex/tmdb-match",
                                queryItems: [URLQueryItem(name: "ratingKey", value: ratingKey)]
                            )
                            if let backdrop = tmdbMatch.backdropUrl {
                                imageURL = await ImageService.shared.proxyImageURL(url: backdrop)
                            }
                            let logoURL = await ImageService.shared.proxyImageURL(url: tmdbMatch.logoUrl)
                            return (
                                ratingKey,
                                SearchResult(
                                    id: "plex:\(ratingKey)",
                                    title: item.title ?? "",
                                    type: type == 1 ? .movie : .tv,
                                    imageURL: imageURL,
                                    logoURL: logoURL,
                                    year: item.year.map(String.init),
                                    overview: item.summary,
                                    available: true,
                                    genreIds: [],
                                    editionTitle: edition,
                                    rawThumbPath: item.thumb ?? item.parentThumb ?? item.grandparentThumb,
                                    rawArtPath: item.art ?? item.grandparentArt ?? item.thumb ?? item.parentThumb ?? item.grandparentThumb
                                )
                            )
                        } catch {
                        }

                        if imageURL == nil {
                            let fallbackPath = item.art ?? item.grandparentArt ?? item.thumb ?? item.parentThumb ?? item.grandparentThumb
                            imageURL = await ImageService.shared.plexImageURL(path: fallbackPath, width: 780, height: 439)
                        }

                        let result = SearchResult(
                            id: "plex:\(ratingKey)",
                            title: item.title ?? "",
                            type: type == 1 ? .movie : .tv,
                            imageURL: imageURL,
                            logoURL: nil,
                            year: item.year.map(String.init),
                            overview: item.summary,
                            available: true,
                            genreIds: [],
                            editionTitle: edition,
                            rawThumbPath: item.thumb ?? item.parentThumb ?? item.grandparentThumb,
                            rawArtPath: item.art ?? item.grandparentArt ?? item.thumb ?? item.parentThumb ?? item.grandparentThumb
                        )
                        return (ratingKey, result)
                    }
                }

                var mapped: [(String, SearchResult)] = []
                for await result in group {
                    mapped.append(result)
                }

                let dictionary = Dictionary(uniqueKeysWithValues: mapped)
                return items.compactMap { dictionary[$0.ratingKey] }
            }
        } catch {
            return []
        }
    }

    private func searchTMDBSeparate(query: String) async -> ([SearchResult], [SearchResult], Set<Int>) {
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

        do {
            let response: TMDBSearchResponse = try await api.get(
                "/api/tmdb/search/multi",
                queryItems: [URLQueryItem(name: "query", value: query)]
            )

            var movies: [SearchResult] = []
            var shows: [SearchResult] = []
            var allGenres = Set<Int>()

            for item in response.results.prefix(24) {
                let genreIds = item.genre_ids ?? []
                genreIds.forEach { allGenres.insert($0) }

                let imageURL = ImageService.shared.proxyImageURL(
                    url: item.poster_path.flatMap { "https://image.tmdb.org/t/p/w500\($0)" }
                ) ?? ImageService.shared.proxyImageURL(
                    url: item.backdrop_path.flatMap { "https://image.tmdb.org/t/p/w780\($0)" }
                )

                let mediaType: SearchResult.MediaType = item.media_type == "movie" ? .movie : .tv
                let result = SearchResult(
                    id: "tmdb:\(item.media_type):\(item.id)",
                    title: item.title ?? item.name ?? "",
                    type: mediaType,
                    imageURL: imageURL,
                    logoURL: await fetchTMDBLogo(mediaType: item.media_type == "movie" ? "movie" : "tv", id: item.id),
                    year: (item.release_date ?? item.first_air_date)?.prefix(4).description,
                    overview: item.overview,
                    available: false,
                    genreIds: genreIds,
                    editionTitle: nil,
                    rawThumbPath: nil,
                    rawArtPath: nil
                )

                if mediaType == .movie {
                    movies.append(result)
                } else {
                    shows.append(result)
                }
            }

            return (movies, shows, allGenres)
        } catch {
            return ([], [], Set())
        }
    }

    private func loadGenreRecommendations(genreIds: ArraySlice<Int>) async {
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

        var rows: [GenreRow] = []

        for genreId in genreIds {
            guard let genreTitle = Self.genreMap[genreId] else { continue }
            do {
                async let moviesRes: DiscoverResponse = api.get(
                    "/api/tmdb/discover/movie",
                    queryItems: [
                        URLQueryItem(name: "with_genres", value: String(genreId)),
                        URLQueryItem(name: "sort_by", value: "popularity.desc"),
                        URLQueryItem(name: "page", value: "1")
                    ]
                )

                async let showsRes: DiscoverResponse = api.get(
                    "/api/tmdb/discover/tv",
                    queryItems: [
                        URLQueryItem(name: "with_genres", value: String(genreId)),
                        URLQueryItem(name: "sort_by", value: "popularity.desc"),
                        URLQueryItem(name: "page", value: "1")
                    ]
                )

                let (movieResult, showResult) = try await (moviesRes, showsRes)

                var movies: [SearchResult] = []
                for item in movieResult.results.prefix(8) {
                    movies.append(
                        SearchResult(
                            id: "tmdb:movie:\(item.id)",
                            title: item.title ?? "",
                            type: .movie,
                            imageURL: ImageService.shared.proxyImageURL(
                                url: item.poster_path.flatMap { "https://image.tmdb.org/t/p/w500\($0)" }
                            ),
                            logoURL: await fetchTMDBLogo(mediaType: "movie", id: item.id),
                            year: item.release_date?.prefix(4).description,
                            overview: nil,
                            available: false,
                            genreIds: [genreId],
                            editionTitle: nil,
                            rawThumbPath: nil,
                            rawArtPath: nil
                        )
                    )
                }

                var shows: [SearchResult] = []
                for item in showResult.results.prefix(8) {
                    shows.append(
                        SearchResult(
                            id: "tmdb:tv:\(item.id)",
                            title: item.name ?? "",
                            type: .tv,
                            imageURL: ImageService.shared.proxyImageURL(
                                url: item.poster_path.flatMap { "https://image.tmdb.org/t/p/w500\($0)" }
                            ),
                            logoURL: await fetchTMDBLogo(mediaType: "tv", id: item.id),
                            year: item.first_air_date?.prefix(4).description,
                            overview: nil,
                            available: false,
                            genreIds: [genreId],
                            editionTitle: nil,
                            rawThumbPath: nil,
                            rawArtPath: nil
                        )
                    )
                }

                let merged = Array((movies + shows).prefix(12))
                if !merged.isEmpty {
                    rows.append(GenreRow(id: "genre:\(genreId)", title: genreTitle, items: merged))
                }
            } catch {
            }
        }

        guard !Task.isCancelled else { return }
        genreRows = rows
    }

    private struct PlexSearchItem: Codable {
        let ratingKey: String
        let title: String?
        let year: Int?
        let summary: String?
        let art: String?
        let grandparentArt: String?
        let thumb: String?
        let parentThumb: String?
        let grandparentThumb: String?
        let Media: [PlexSearchMedia]?
    }

    private struct PlexSearchMedia: Codable {
        let editionTitle: String?
        let Part: [PlexSearchPart]?
    }

    private struct PlexSearchPart: Codable {
        let file: String?
    }

    private func extractEditionTitle(from media: [PlexSearchMedia]?) -> String? {
        guard let first = media?.first else { return nil }
        if let edition = first.editionTitle, !edition.isEmpty {
            return edition
        }

        if let filePath = first.Part?.first?.file,
           let match = filePath.range(of: #"\{edition-([^}]+)\}"#, options: .regularExpression) {
            let full = String(filePath[match])
            let start = full.index(full.startIndex, offsetBy: 9)
            let end = full.index(full.endIndex, offsetBy: -1)
            return String(full[start..<end])
        }

        return nil
    }

    private func fetchTMDBLogo(mediaType: String, id: Int) async -> URL? {
        do {
            let images = try await api.getTMDBImages(mediaType: mediaType, id: String(id))
            let logos = images.logos ?? []
            let picked = logos.first { $0.iso_639_1 == "en" }
                ?? logos.first { ($0.iso_639_1 ?? "").isEmpty }
                ?? logos.first
            guard let filePath = picked?.file_path else { return nil }
            return ImageService.shared.proxyImageURL(url: "https://image.tmdb.org/t/p/w500\(filePath)")
        } catch {
            return nil
        }
    }
}
