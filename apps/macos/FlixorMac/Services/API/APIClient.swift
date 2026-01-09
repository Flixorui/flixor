//
//  APIClient.swift
//  FlixorMac
//
//  API client - now routes through FlixorCore instead of localhost backend
//

import Foundation
import FlixorKit

@MainActor
class APIClient: ObservableObject {
    static let shared = APIClient()

    @Published var isAuthenticated = false

    var baseURL: URL
    private var session: URLSession
    private var token: String?

    init() {
        // Not used anymore - FlixorCore handles everything
        self.baseURL = URL(string: "http://localhost:3001")!

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)

        self.token = nil
        self.isAuthenticated = FlixorCore.shared.isPlexAuthenticated
    }

    // MARK: - Configuration

    func setBaseURL(_ urlString: String) {
        // No longer needed - FlixorCore handles server connections
    }

    func setToken(_ token: String?) {
        // No longer needed - FlixorCore manages tokens
    }

    // MARK: - Request Methods

    func get<T: Decodable>(_ path: String, queryItems: [URLQueryItem]? = nil, bypassCache: Bool = false) async throws -> T {
        // Route requests through FlixorCore instead of localhost
        return try await routeRequest(path: path, queryItems: queryItems)
    }

    // MARK: - FlixorCore Router

    private func routeRequest<T: Decodable>(path: String, queryItems: [URLQueryItem]?) async throws -> T {
        print("🔀 [APIClient] Routing: \(path)")

        // Parse query items into dictionary
        var params: [String: String] = [:]
        for item in queryItems ?? [] {
            if let value = item.value {
                params[item.name] = value
            }
        }

        // Route based on path prefix
        if path.hasPrefix("/api/plex/") {
            return try await routePlexRequest(path: path, params: params)
        } else if path.hasPrefix("/api/tmdb/") {
            return try await routeTMDBRequest(path: path, params: params)
        } else if path.hasPrefix("/api/trakt/") {
            return try await routeTraktRequest(path: path, params: params)
        } else if path.hasPrefix("/api/plextv/") {
            return try await routePlexTvRequest(path: path, params: params)
        } else {
            print("❌ [APIClient] Unknown route: \(path)")
            throw APIError.invalidURL
        }
    }

    // MARK: - Plex Routing

    private func routePlexRequest<T: Decodable>(path: String, params: [String: String]) async throws -> T {
        guard let plexServer = FlixorCore.shared.plexServer else {
            throw APIError.serverError("No Plex server connected")
        }

        let subpath = String(path.dropFirst("/api/plex/".count))

        // /api/plex/metadata/{ratingKey}
        if subpath.hasPrefix("metadata/") {
            let ratingKey = String(subpath.dropFirst("metadata/".count))
            let item = try await plexServer.getMetadata(ratingKey: ratingKey)
            return try encodeAndDecode(item)
        }

        // /api/plex/dir/library/metadata/{key}/children
        if subpath.hasPrefix("dir/library/metadata/") && subpath.contains("/children") {
            let parts = subpath.dropFirst("dir/library/metadata/".count).split(separator: "/")
            if let key = parts.first {
                let items = try await plexServer.getChildren(ratingKey: String(key))
                let response = PlexChildrenResponse(Metadata: items, size: items.count)
                return try encodeAndDecode(response)
            }
        }

        // /api/plex/dir/library/metadata/{key}/onDeck
        if subpath.hasPrefix("dir/library/metadata/") && subpath.contains("/onDeck") {
            let parts = subpath.dropFirst("dir/library/metadata/".count).split(separator: "/")
            if let key = parts.first {
                // Try to get on deck - this might not be directly available
                let items = try await plexServer.getOnDeck()
                let filtered = items.filter { $0.grandparentRatingKey == String(key) }
                let response = PlexChildrenResponse(Metadata: filtered, size: filtered.count)
                return try encodeAndDecode(response)
            }
        }

        // /api/plex/dir/{path}
        if subpath.hasPrefix("dir/") {
            let dirPath = String(subpath.dropFirst("dir/".count))

            // dir/library/sections/{key}/all - library items by section
            if dirPath.hasPrefix("library/sections/") && dirPath.contains("/all") {
                // Extract section key from path like "library/sections/2/all"
                let afterSections = String(dirPath.dropFirst("library/sections/".count))
                let key = String(afterSections.prefix(while: { $0 != "/" }))
                let type = params["type"].flatMap { Int($0) }
                let sort = params["sort"]
                let limit = params["limit"].flatMap { Int($0) } ?? params["X-Plex-Container-Size"].flatMap { Int($0) }
                let offset = params["offset"].flatMap { Int($0) } ?? params["X-Plex-Container-Start"].flatMap { Int($0) }
                let genre = params["genre"]
                let result = try await plexServer.getLibraryItemsWithPagination(key: key, type: type, sort: sort, limit: limit, offset: offset, genre: genre)
                let response = PlexDirResponse(MediaContainer: PlexDirContainer(Metadata: result.items))
                return try encodeAndDecode(response)
            }

            // Generic directory fetch - use children or library items
            if dirPath.hasPrefix("library/metadata/") {
                let key = String(dirPath.dropFirst("library/metadata/".count).prefix(while: { $0 != "/" }))
                let items = try await plexServer.getChildren(ratingKey: key)
                let response = PlexDirResponse(MediaContainer: PlexDirContainer(Metadata: items))
                return try encodeAndDecode(response)
            }
        }

        // /api/plex/search
        if subpath.hasPrefix("search") {
            let query = params["query"] ?? ""
            let type = params["type"].flatMap { Int($0) }
            let items = try await plexServer.search(query: query, type: type)
            // Return items array directly (not wrapped) - SearchViewModel expects [PlexSearchItem]
            return try encodeAndDecode(items)
        }

        // /api/plex/findByGuid
        if subpath.hasPrefix("findByGuid") {
            let guid = params["guid"] ?? ""
            let type = params["type"].flatMap { Int($0) }
            let items = try await plexServer.findByGuid(guid: guid, type: type)
            let response = PlexSearchResponse(MediaContainer: PlexSearchContainer(Metadata: items))
            return try encodeAndDecode(response)
        }

        // /api/plex/tmdb-match - Get TMDB backdrop for a Plex item
        if subpath.hasPrefix("tmdb-match") {
            let ratingKey = params["ratingKey"] ?? ""
            // Get Plex metadata to find TMDB GUID
            let meta = try await plexServer.getMetadata(ratingKey: ratingKey)
            let mediaType = (meta.type == "movie") ? "movie" : "tv"

            // Extract TMDB ID from guids
            var tmdbId: Int?
            for guid in meta.guids {
                if guid.contains("tmdb://") || guid.contains("themoviedb://") {
                    if let id = guid.components(separatedBy: "://").last, let intId = Int(id) {
                        tmdbId = intId
                        break
                    }
                }
            }

            // Fetch TMDB images if we have an ID
            var backdropUrl: String?
            var posterUrl: String?
            if let tmdbId = tmdbId {
                let images = try await FlixorCore.shared.tmdb.getImages(mediaType: mediaType, id: tmdbId)
                if let backdrop = images.backdrops.first {
                    backdropUrl = "https://image.tmdb.org/t/p/w1280\(backdrop.filePath)"
                }
                if let poster = images.posters.first {
                    posterUrl = "https://image.tmdb.org/t/p/w500\(poster.filePath)"
                }
            }

            let response = TMDBMatchResponse(
                tmdbId: tmdbId,
                backdropUrl: backdropUrl,
                posterUrl: posterUrl
            )
            return try encodeAndDecode(response)
        }

        // /api/plex/libraries
        if subpath == "libraries" {
            let libs = try await plexServer.getLibraries()
            return try encodeAndDecode(libs)
        }

        // /api/plex/library/{key}/genre
        if subpath.hasPrefix("library/") && subpath.contains("/genre") {
            let key = String(subpath.dropFirst("library/".count).prefix(while: { $0 != "/" }))
            let genres = try await plexServer.getLibraryGenres(key: key)
            // Map to DirectoryEntry format expected by LibraryViewModel
            let entries = genres.map { DirectoryEntry(key: $0.key, title: $0.title) }
            let response = DirectoryResponseWrapper(Directory: entries)
            return try encodeAndDecode(response)
        }

        // /api/plex/library/{key}/year
        if subpath.hasPrefix("library/") && subpath.contains("/year") {
            let key = String(subpath.dropFirst("library/".count).prefix(while: { $0 != "/" }))
            let years = try await plexServer.getLibraryYears(key: key)
            // Map to DirectoryEntry format expected by LibraryViewModel
            let entries = years.map { DirectoryEntry(key: $0.key, title: $0.title) }
            let response = DirectoryResponseWrapper(Directory: entries)
            return try encodeAndDecode(response)
        }

        // /api/plex/library/{key}/all
        if subpath.hasPrefix("library/") && subpath.contains("/all") {
            let key = String(subpath.dropFirst("library/".count).prefix(while: { $0 != "/" }))
            let type = params["type"].flatMap { Int($0) }
            let sort = params["sort"]
            let limit = params["limit"].flatMap { Int($0) } ?? params["X-Plex-Container-Size"].flatMap { Int($0) }
            let offset = params["offset"].flatMap { Int($0) } ?? params["X-Plex-Container-Start"].flatMap { Int($0) }
            let genre = params["genre"]
            let result = try await plexServer.getLibraryItemsWithPagination(key: key, type: type, sort: sort, limit: limit, offset: offset, genre: genre)
            // Wrap in response format expected by LibraryViewModel
            let response = LibraryItemsResponse(
                size: result.size,
                totalSize: result.totalSize,
                offset: result.offset,
                Metadata: result.items
            )
            return try encodeAndDecode(response)
        }

        // /api/plex/ratings/{ratingKey}
        if subpath.hasPrefix("ratings/") {
            // Ratings not directly available - return empty
            let emptyRatings = EmptyRatings()
            return try encodeAndDecode(emptyRatings)
        }

        // /api/plex/recent
        if subpath == "recent" {
            let items = try await plexServer.getRecentlyAdded()
            return try encodeAndDecode(items)
        }

        // /api/plex/servers
        if subpath == "servers" {
            let servers = try await FlixorCore.shared.getPlexServers()
            let currentServerId = FlixorCore.shared.currentServer?.id
            // Map to PlexServer format expected by app, marking active server
            let mappedServers = servers.map { server in
                PlexServer(
                    id: server.id,
                    name: server.name,
                    host: server.connections.first?.uri,
                    port: nil,
                    protocolName: server.connections.first?.protocol,
                    preferredUri: server.connections.first?.uri,
                    publicAddress: server.publicAddress,
                    localAddresses: nil,
                    machineIdentifier: server.id,
                    isActive: server.id == currentServerId,
                    owned: server.owned,
                    presence: server.presence
                )
            }
            return try encodeAndDecode(mappedServers)
        }

        print("❌ [APIClient] Unhandled Plex route: \(subpath)")
        throw APIError.invalidURL
    }

    // MARK: - TMDB Routing

    private func routeTMDBRequest<T: Decodable>(path: String, params: [String: String]) async throws -> T {
        let subpath = String(path.dropFirst("/api/tmdb/".count))
        let tmdb = FlixorCore.shared.tmdb

        // /api/tmdb/trending/{media}/{window}
        if subpath.hasPrefix("trending/") {
            let parts = subpath.dropFirst("trending/".count).split(separator: "/")
            if parts.count >= 2 {
                let media = String(parts[0])
                let window = String(parts[1])
                let page = params["page"].flatMap { Int($0) } ?? 1
                let result: TMDBResultsResponse
                if media == "movie" {
                    result = try await tmdb.getTrendingMovies(timeWindow: window, page: page)
                } else if media == "tv" {
                    result = try await tmdb.getTrendingTV(timeWindow: window, page: page)
                } else {
                    result = try await tmdb.getTrendingAll(timeWindow: window, page: page)
                }
                return try encodeAndDecode(result)
            }
        }

        // /api/tmdb/movie/upcoming - MUST be before movie/{id} handler
        if subpath == "movie/upcoming" {
            let page = params["page"].flatMap { Int($0) } ?? 1
            let region = params["region"]
            let result = try await tmdb.getUpcomingMovies(region: region, page: page)
            return try encodeAndDecode(result)
        }

        // /api/tmdb/movie/{id} or /api/tmdb/tv/{id}
        if subpath.hasPrefix("movie/") || subpath.hasPrefix("tv/") {
            let isMovie = subpath.hasPrefix("movie/")
            let rest = String(subpath.dropFirst(isMovie ? "movie/".count : "tv/".count))

            // Check for sub-endpoints
            if rest.contains("/") {
                let parts = rest.split(separator: "/", maxSplits: 1)
                let id = String(parts[0])
                let endpoint = String(parts[1])

                guard let tmdbId = Int(id) else {
                    throw APIError.invalidURL
                }

                // /images
                if endpoint == "images" || endpoint.hasPrefix("images") {
                    let result = isMovie ? try await tmdb.getMovieImages(id: tmdbId) : try await tmdb.getTVImages(id: tmdbId)
                    return try encodeAndDecode(result)
                }

                // /credits
                if endpoint == "credits" {
                    let result = isMovie ? try await tmdb.getMovieCredits(id: tmdbId) : try await tmdb.getTVCredits(id: tmdbId)
                    return try encodeAndDecode(result)
                }

                // /recommendations
                if endpoint == "recommendations" {
                    let page = params["page"].flatMap { Int($0) } ?? 1
                    let result = isMovie ? try await tmdb.getMovieRecommendations(id: tmdbId, page: page) : try await tmdb.getTVRecommendations(id: tmdbId, page: page)
                    return try encodeAndDecode(result)
                }

                // /similar
                if endpoint == "similar" {
                    let page = params["page"].flatMap { Int($0) } ?? 1
                    let result = isMovie ? try await tmdb.getSimilarMovies(id: tmdbId, page: page) : try await tmdb.getSimilarTV(id: tmdbId, page: page)
                    return try encodeAndDecode(result)
                }

                // /external_ids
                if endpoint == "external_ids" {
                    let result = isMovie ? try await tmdb.getMovieExternalIds(id: tmdbId) : try await tmdb.getTVExternalIds(id: tmdbId)
                    return try encodeAndDecode(result)
                }

                // /videos - get videos/trailers
                if endpoint == "videos" {
                    let result = isMovie ? try await tmdb.getMovieVideos(id: tmdbId) : try await tmdb.getTVVideos(id: tmdbId)
                    return try encodeAndDecode(result)
                }

                // /season/{num} or /season/{num}/episode/{num}
                if endpoint.hasPrefix("season/") {
                    let seasonPart = String(endpoint.dropFirst("season/".count))
                    // Check if it's an episode request: season/{num}/episode/{num}
                    if seasonPart.contains("/episode/") {
                        let parts = seasonPart.components(separatedBy: "/episode/")
                        let seasonNum = Int(parts[0]) ?? 1
                        let episodeNum = Int(parts.count > 1 ? parts[1] : "1") ?? 1
                        let result = try await tmdb.getEpisodeDetails(tvId: tmdbId, seasonNumber: seasonNum, episodeNumber: episodeNum)
                        return try encodeAndDecode(result)
                    } else {
                        let seasonNum = Int(seasonPart) ?? 1
                        let result = try await tmdb.getSeasonDetails(tvId: tmdbId, seasonNumber: seasonNum)
                        return try encodeAndDecode(result)
                    }
                }
            } else {
                // Just movie/tv details
                guard let tmdbId = Int(rest) else {
                    throw APIError.invalidURL
                }
                if isMovie {
                    let result = try await tmdb.getMovieDetails(id: tmdbId)
                    return try encodeAndDecode(result)
                } else {
                    let result = try await tmdb.getTVDetails(id: tmdbId)
                    return try encodeAndDecode(result)
                }
            }
        }

        // /api/tmdb/search/multi
        if subpath.hasPrefix("search/multi") {
            let query = params["query"] ?? ""
            let result = try await tmdb.searchMulti(query: query)
            return try encodeAndDecode(result)
        }

        // /api/tmdb/search/person - use searchMulti and filter
        if subpath.hasPrefix("search/person") {
            let query = params["query"] ?? ""
            let result = try await tmdb.searchMulti(query: query)
            return try encodeAndDecode(result)
        }

        // /api/tmdb/person/{id}/combined_credits
        if subpath.hasPrefix("person/") && subpath.contains("/combined_credits") {
            let id = String(subpath.dropFirst("person/".count).prefix(while: { $0 != "/" }))
            if let personId = Int(id) {
                let result = try await tmdb.getPersonCredits(id: personId)
                return try encodeAndDecode(result)
            }
        }

        // /api/tmdb/discover/movie
        if subpath == "discover/movie" || subpath.hasPrefix("discover/movie") {
            let genres = params["with_genres"]
            let sortBy = params["sort_by"] ?? "popularity.desc"
            let page = params["page"].flatMap { Int($0) } ?? 1
            let result = try await tmdb.discoverMovies(withGenres: genres, sortBy: sortBy, page: page)
            return try encodeAndDecode(result)
        }

        // /api/tmdb/discover/tv
        if subpath == "discover/tv" || subpath.hasPrefix("discover/tv") {
            let genres = params["with_genres"]
            let sortBy = params["sort_by"] ?? "popularity.desc"
            let page = params["page"].flatMap { Int($0) } ?? 1
            let result = try await tmdb.discoverTV(withGenres: genres, sortBy: sortBy, page: page)
            return try encodeAndDecode(result)
        }

        print("❌ [APIClient] Unhandled TMDB route: \(subpath)")
        throw APIError.invalidURL
    }

    // MARK: - Trakt Routing

    private func routeTraktRequest<T: Decodable>(path: String, params: [String: String]) async throws -> T {
        let subpath = String(path.dropFirst("/api/trakt/".count))
        let trakt = FlixorCore.shared.trakt

        // /api/trakt/trending/{media}
        if subpath.hasPrefix("trending/") {
            let media = String(subpath.dropFirst("trending/".count))
            if media == "movies" {
                let result = try await trakt.getTrendingMovies()
                return try encodeAndDecode(result)
            } else if media == "shows" {
                let result = try await trakt.getTrendingShows()
                return try encodeAndDecode(result)
            }
        }

        // /api/trakt/popular/{media}
        if subpath.hasPrefix("popular/") {
            let media = String(subpath.dropFirst("popular/".count))
            if media == "movies" {
                let result = try await trakt.getPopularMovies()
                return try encodeAndDecode(result)
            } else if media == "shows" {
                let result = try await trakt.getPopularShows()
                return try encodeAndDecode(result)
            }
        }

        // /api/trakt/recommendations/movies
        if subpath == "recommendations/movies" {
            let result = try await trakt.getRecommendedMovies()
            return try encodeAndDecode(result)
        }

        // /api/trakt/users/me (profile)
        if subpath == "users/me" {
            guard trakt.isAuthenticated else {
                throw APIError.serverError("Not authenticated with Trakt")
            }
            let result = try await trakt.getUserProfile()
            return try encodeAndDecode(result)
        }

        // /api/trakt/users/me/watchlist
        if subpath == "users/me/watchlist" {
            let result = try await trakt.getWatchlist()
            return try encodeAndDecode(result)
        }

        // /api/trakt/users/me/watchlist/movies
        if subpath == "users/me/watchlist/movies" {
            print("🎬 [Trakt] Fetching watchlist/movies, isAuthenticated: \(trakt.isAuthenticated)")
            // Return empty if not authenticated
            guard trakt.isAuthenticated else {
                let empty: [TraktWatchlistEntryWrapper] = []
                return try encodeAndDecode(empty)
            }
            do {
                let result = try await trakt.getWatchlist(type: "movies")
                print("🎬 [Trakt] Got \(result.count) watchlist movies")
                // Map FlixorKit types to wrapper types expected by MyListViewModel
                let mapped = result.map { item -> TraktWatchlistEntryWrapper in
                    let movieWrapper = item.movie.map { movie -> TraktMovieWrapper in
                        TraktMovieWrapper(
                            title: movie.title,
                            year: movie.year,
                            overview: movie.overview,
                            runtime: movie.runtime,
                            genres: movie.genres,
                            rating: movie.rating,
                            ids: TraktIDsWrapper(trakt: movie.ids.trakt, imdb: movie.ids.imdb, tmdb: movie.ids.tmdb)
                        )
                    }
                    return TraktWatchlistEntryWrapper(listed_at: item.listedAt, movie: movieWrapper, show: nil)
                }
                return try encodeAndDecode(mapped)
            } catch {
                print("⚠️ [APIClient] Trakt watchlist/movies error: \(error)")
                let empty: [TraktWatchlistEntryWrapper] = []
                return try encodeAndDecode(empty)
            }
        }

        // /api/trakt/users/me/watchlist/shows
        if subpath == "users/me/watchlist/shows" {
            print("🎬 [Trakt] Fetching watchlist/shows, isAuthenticated: \(trakt.isAuthenticated)")
            // Return empty if not authenticated
            guard trakt.isAuthenticated else {
                let empty: [TraktWatchlistEntryWrapper] = []
                return try encodeAndDecode(empty)
            }
            do {
                let result = try await trakt.getWatchlist(type: "shows")
                print("🎬 [Trakt] Got \(result.count) watchlist shows")
                // Map FlixorKit types to wrapper types expected by MyListViewModel
                let mapped = result.map { item -> TraktWatchlistEntryWrapper in
                    let showWrapper = item.show.map { show -> TraktShowWrapper in
                        TraktShowWrapper(
                            title: show.title,
                            year: show.year,
                            overview: show.overview,
                            runtime: show.runtime,
                            genres: show.genres,
                            rating: show.rating,
                            ids: TraktIDsWrapper(trakt: show.ids.trakt, imdb: show.ids.imdb, tmdb: show.ids.tmdb)
                        )
                    }
                    return TraktWatchlistEntryWrapper(listed_at: item.listedAt, movie: nil, show: showWrapper)
                }
                return try encodeAndDecode(mapped)
            } catch {
                print("⚠️ [APIClient] Trakt watchlist/shows error: \(error)")
                let empty: [TraktWatchlistEntryWrapper] = []
                return try encodeAndDecode(empty)
            }
        }

        // /api/trakt/users/me/history
        if subpath == "users/me/history" {
            let result = try await trakt.getHistory()
            return try encodeAndDecode(result)
        }

        // /api/trakt/{media}/watched/{period} - Most watched movies/shows
        if subpath.contains("/watched/") {
            // Format: movies/watched/weekly or shows/watched/weekly
            let parts = subpath.components(separatedBy: "/")
            if parts.count >= 3 {
                let media = parts[0]  // "movies" or "shows"
                let period = parts[2]  // "weekly", "monthly", "yearly", "all"
                let limit = params["limit"].flatMap { Int($0) } ?? 10

                if media == "movies" {
                    let result = try await trakt.getMostWatchedMovies(period: period, limit: limit)
                    // Map to wrapper types
                    let mapped = result.map { item -> TraktMostWatchedMovieWrapper in
                        TraktMostWatchedMovieWrapper(
                            watcher_count: item.watcherCount,
                            play_count: item.playCount,
                            collected_count: item.collectedCount,
                            movie: TraktMovieWrapper(
                                title: item.movie.title,
                                year: item.movie.year,
                                overview: item.movie.overview,
                                runtime: item.movie.runtime,
                                genres: item.movie.genres,
                                rating: item.movie.rating,
                                ids: TraktIDsWrapper(trakt: item.movie.ids.trakt, imdb: item.movie.ids.imdb, tmdb: item.movie.ids.tmdb)
                            )
                        )
                    }
                    return try encodeAndDecode(mapped)
                } else if media == "shows" {
                    let result = try await trakt.getMostWatchedShows(period: period, limit: limit)
                    // Map to wrapper types
                    let mapped = result.map { item -> TraktMostWatchedShowWrapper in
                        TraktMostWatchedShowWrapper(
                            watcher_count: item.watcherCount,
                            play_count: item.playCount,
                            collected_count: item.collectedCount,
                            show: TraktShowWrapper(
                                title: item.show.title,
                                year: item.show.year,
                                overview: item.show.overview,
                                runtime: item.show.runtime,
                                genres: item.show.genres,
                                rating: item.show.rating,
                                ids: TraktIDsWrapper(trakt: item.show.ids.trakt, imdb: item.show.ids.imdb, tmdb: item.show.ids.tmdb)
                            )
                        )
                    }
                    return try encodeAndDecode(mapped)
                }
            }
        }

        // /api/trakt/{media}/anticipated - Anticipated movies/shows
        if subpath.contains("/anticipated") {
            // Format: movies/anticipated or shows/anticipated
            let parts = subpath.components(separatedBy: "/")
            if parts.count >= 2 {
                let media = parts[0]  // "movies" or "shows"
                let limit = params["limit"].flatMap { Int($0) } ?? 20

                if media == "movies" {
                    let result = try await trakt.getAnticipatedMovies(limit: limit)
                    // Map to wrapper types
                    let mapped = result.map { item -> TraktAnticipatedMovieWrapper in
                        TraktAnticipatedMovieWrapper(
                            list_count: item.listCount,
                            movie: TraktMovieWrapper(
                                title: item.movie.title,
                                year: item.movie.year,
                                overview: item.movie.overview,
                                runtime: item.movie.runtime,
                                genres: item.movie.genres,
                                rating: item.movie.rating,
                                ids: TraktIDsWrapper(trakt: item.movie.ids.trakt, imdb: item.movie.ids.imdb, tmdb: item.movie.ids.tmdb)
                            )
                        )
                    }
                    return try encodeAndDecode(mapped)
                } else if media == "shows" {
                    let result = try await trakt.getAnticipatedShows(limit: limit)
                    // Map to wrapper types
                    let mapped = result.map { item -> TraktAnticipatedShowWrapper in
                        TraktAnticipatedShowWrapper(
                            list_count: item.listCount,
                            show: TraktShowWrapper(
                                title: item.show.title,
                                year: item.show.year,
                                overview: item.show.overview,
                                runtime: item.show.runtime,
                                genres: item.show.genres,
                                rating: item.show.rating,
                                ids: TraktIDsWrapper(trakt: item.show.ids.trakt, imdb: item.show.ids.imdb, tmdb: item.show.ids.tmdb)
                            )
                        )
                    }
                    return try encodeAndDecode(mapped)
                }
            }
        }

        print("❌ [APIClient] Unhandled Trakt route: \(subpath)")
        throw APIError.invalidURL
    }

    // MARK: - PlexTV Routing

    private func routePlexTvRequest<T: Decodable>(path: String, params: [String: String]) async throws -> T {
        let subpath = String(path.dropFirst("/api/plextv/".count))

        // /api/plextv/watchlist
        if subpath == "watchlist" {
            guard let plexTv = FlixorCore.shared.plexTv else {
                print("❌ [Watchlist] Not authenticated with Plex.tv")
                // Return empty watchlist instead of throwing
                let container = PlexWatchlistContainer(MediaContainer: PlexWatchlistMC(Metadata: []))
                return try encodeAndDecode(container)
            }
            print("✅ [Watchlist] Fetching Plex.tv watchlist...")
            do {
                let items = try await plexTv.getWatchlist()
                print("✅ [Watchlist] Got \(items.count) items from Plex.tv")

                // Enrich items with TMDB IDs by fetching full metadata for each
                var wrappedItems: [WatchlistItemWrapper] = []
                for item in items {
                    // Try to get TMDB ID from full metadata
                    let tmdbGuid = await plexTv.getTMDBIdForWatchlistItem(item)
                    if let tmdbGuid = tmdbGuid {
                        print("✅ [Watchlist] Enriched \(item.title) with TMDB: \(tmdbGuid)")
                    } else {
                        print("⚠️ [Watchlist] No TMDB ID for \(item.title)")
                    }

                    let guid = item.guids.first // Use first guid as primary

                    wrappedItems.append(WatchlistItemWrapper(
                        ratingKey: item.ratingKey,
                        guid: guid,
                        title: item.title,
                        type: item.type,
                        thumb: item.thumb,
                        art: item.art,
                        year: item.year,
                        rating: nil,
                        duration: item.duration,
                        summary: item.summary,
                        Genre: nil,
                        tmdbGuid: tmdbGuid
                    ))
                }

                let container = PlexWatchlistContainer(MediaContainer: PlexWatchlistMC(Metadata: wrappedItems))
                return try encodeAndDecode(container)
            } catch {
                print("⚠️ [Watchlist] Plex.tv watchlist error: \(error)")
                let container = PlexWatchlistContainer(MediaContainer: PlexWatchlistMC(Metadata: []))
                return try encodeAndDecode(container)
            }
        }

        print("❌ [APIClient] Unhandled PlexTV route: \(subpath)")
        throw APIError.invalidURL
    }

    // MARK: - Helpers

    private func encodeAndDecode<T: Decodable, U: Encodable>(_ value: U) throws -> T {
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }

    func post<T: Decodable>(_ path: String, body: Encodable? = nil) async throws -> T {
        print("🔀 [APIClient] POST Routing: \(path)")

        // Handle Plex progress reporting
        if path == "/api/plex/progress" {
            guard let plexServer = FlixorCore.shared.plexServer else {
                throw APIError.serverError("No Plex server connected")
            }

            // Decode the progress request body
            if let body = body {
                let encoder = JSONEncoder()
                let data = try encoder.encode(body)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let ratingKey = json["ratingKey"] as? String ?? ""
                    let time = json["time"] as? Int ?? 0
                    let duration = json["duration"] as? Int ?? 0
                    let state = json["state"] as? String ?? "stopped"

                    try await plexServer.reportProgress(ratingKey: ratingKey, time: time, duration: duration, state: state)
                }
            }

            // Return empty response
            let empty = EmptyResponse()
            return try encodeAndDecode(empty)
        }

        // POST /api/trakt/watchlist - Add to Trakt watchlist
        if path == "/api/trakt/watchlist" {
            print("🎬 [APIClient] Trakt watchlist add - isAuthenticated: \(FlixorCore.shared.trakt.isAuthenticated)")
            guard FlixorCore.shared.trakt.isAuthenticated else {
                print("❌ [APIClient] Trakt not authenticated")
                throw APIError.unauthorized
            }
            if let body = body {
                let encoder = JSONEncoder()
                let data = try encoder.encode(body)
                print("📦 [APIClient] Trakt request body: \(String(data: data, encoding: .utf8) ?? "nil")")
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    var tmdbId: Int?
                    var mediaType: String = "movie"

                    // Try direct tmdbId format first
                    if let directTmdbId = json["tmdbId"] as? Int {
                        tmdbId = directTmdbId
                        mediaType = json["mediaType"] as? String ?? "movie"
                    }
                    // Try movies array format: {"movies":[{"ids":{"tmdb":123}}]}
                    else if let movies = json["movies"] as? [[String: Any]],
                            let firstMovie = movies.first,
                            let ids = firstMovie["ids"] as? [String: Any],
                            let movieTmdbId = ids["tmdb"] as? Int {
                        tmdbId = movieTmdbId
                        mediaType = "movie"
                    }
                    // Try shows array format: {"shows":[{"ids":{"tmdb":123}}]}
                    else if let shows = json["shows"] as? [[String: Any]],
                            let firstShow = shows.first,
                            let ids = firstShow["ids"] as? [String: Any],
                            let showTmdbId = ids["tmdb"] as? Int {
                        tmdbId = showTmdbId
                        mediaType = "show"
                    }

                    if let tmdbId = tmdbId {
                        print("📝 [APIClient] Adding to Trakt watchlist: tmdbId=\(tmdbId), type=\(mediaType)")
                        do {
                            try await FlixorCore.shared.trakt.addToWatchlist(tmdbId: tmdbId, type: mediaType)
                            print("✅ [APIClient] Added to Trakt watchlist: \(tmdbId)")
                        } catch {
                            print("❌ [APIClient] Trakt addToWatchlist error: \(error)")
                            throw error
                        }
                    } else {
                        print("⚠️ [APIClient] No tmdbId found in request body")
                    }
                }
            } else {
                print("⚠️ [APIClient] No body in Trakt watchlist request")
            }
            let response = SimpleOkResponse(ok: true, message: "Added to watchlist")
            return try encodeAndDecode(response)
        }

        print("⚠️ [APIClient] POST not supported: \(path)")
        throw APIError.invalidURL
    }

    func put<T: Decodable>(_ path: String, body: Encodable? = nil) async throws -> T {
        print("🔀 [APIClient] PUT Routing: \(path)")

        // PUT /api/plextv/watchlist/:id - Add to Plex.tv watchlist
        if path.hasPrefix("/api/plextv/watchlist/") {
            guard let plexTv = FlixorCore.shared.plexTv else {
                throw APIError.serverError("Not authenticated with Plex.tv")
            }

            // Extract the ID from the path (URL decoded)
            let idPart = String(path.dropFirst("/api/plextv/watchlist/".count))
            let decodedId = idPart.removingPercentEncoding ?? idPart

            print("📝 [APIClient] Adding to Plex.tv watchlist: \(decodedId)")

            // The ID might be a TMDB ID like "tmdb://812583" or a Plex rating key
            // Plex.tv watchlist uses the discover API which can accept TMDB IDs
            try await plexTv.addToWatchlist(ratingKey: decodedId)

            let response = SimpleOkResponse(ok: true, message: "Added to Plex.tv watchlist")
            return try encodeAndDecode(response)
        }

        // PUT /api/trakt/watchlist - Alternative method for Trakt
        if path == "/api/trakt/watchlist" {
            guard FlixorCore.shared.trakt.isAuthenticated else {
                throw APIError.unauthorized
            }
            if let body = body {
                let encoder = JSONEncoder()
                let data = try encoder.encode(body)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let tmdbId = json["tmdbId"] as? Int
                    let mediaType = json["mediaType"] as? String ?? "movie"

                    if let tmdbId = tmdbId {
                        try await FlixorCore.shared.trakt.addToWatchlist(tmdbId: tmdbId, type: mediaType)
                        print("✅ [APIClient] Added to Trakt watchlist: \(tmdbId)")
                    }
                }
            }
            let response = SimpleOkResponse(ok: true, message: "Added to watchlist")
            return try encodeAndDecode(response)
        }

        print("⚠️ [APIClient] PUT not supported: \(path)")
        throw APIError.invalidURL
    }

    func delete<T: Decodable>(_ path: String) async throws -> T {
        print("🔀 [APIClient] DELETE Routing: \(path)")

        // DELETE /api/plextv/watchlist/:id - Remove from Plex.tv watchlist
        if path.hasPrefix("/api/plextv/watchlist/") {
            guard let plexTv = FlixorCore.shared.plexTv else {
                throw APIError.serverError("Not authenticated with Plex.tv")
            }

            let idPart = String(path.dropFirst("/api/plextv/watchlist/".count))
            let decodedId = idPart.removingPercentEncoding ?? idPart

            print("🗑️ [APIClient] Removing from Plex.tv watchlist: \(decodedId)")
            try await plexTv.removeFromWatchlist(ratingKey: decodedId)

            let response = SimpleOkResponse(ok: true, message: "Removed from Plex.tv watchlist")
            return try encodeAndDecode(response)
        }

        // DELETE /api/trakt/watchlist - Remove from Trakt watchlist
        if path == "/api/trakt/watchlist" {
            // Trakt watchlist removal needs body with item details
            // For now just return success
            let response = SimpleOkResponse(ok: true, message: "Removed from watchlist")
            return try encodeAndDecode(response)
        }

        print("⚠️ [APIClient] DELETE not supported: \(path)")
        throw APIError.invalidURL
    }

    func healthCheck() async throws -> [String: String] {
        // Health check not needed in standalone mode
        return ["status": "ok", "mode": "standalone"]
    }

    // Legacy methods that redirect through FlixorCore
    func getPlexServers() async throws -> [PlexServer] {
        return try await get("/api/plex/servers")
    }

    // Get Plex server connections (standalone implementation)
    func getPlexConnections(serverId: String) async throws -> PlexConnectionsResponse {
        // Get connections from FlixorCore servers
        let servers = try await FlixorCore.shared.getPlexServers()
        if let server = servers.first(where: { $0.id == serverId || $0.name == serverId }) {
            let connections = server.connections.map { conn in
                PlexConnection(
                    uri: conn.uri,
                    protocolName: conn.protocol,
                    local: conn.local,
                    relay: conn.relay,
                    IPv6: conn.IPv6,
                    isCurrent: nil,
                    isPreferred: nil
                )
            }
            return PlexConnectionsResponse(serverId: serverId, connections: connections)
        }
        return PlexConnectionsResponse(serverId: serverId, connections: [])
    }

    // Get Plex auth servers with tokens (standalone implementation)
    func getPlexAuthServers() async throws -> [PlexAuthServer] {
        guard FlixorCore.shared.plexToken != nil else {
            return []
        }
        let servers = try await FlixorCore.shared.getPlexServers()
        return servers.map { server in
            PlexAuthServer(
                clientIdentifier: server.id,
                token: server.accessToken,
                name: server.name
            )
        }
    }

    func traktUserProfile() async throws -> TraktUserProfile {
        return try await get("/api/trakt/users/me")
    }

    // MARK: - Trakt Device Auth (standalone implementation)

    func traktDeviceCode() async throws -> TraktDeviceCodeResponse {
        let code = try await FlixorCore.shared.trakt.generateDeviceCode()
        return TraktDeviceCodeResponse(
            device_code: code.deviceCode,
            user_code: code.userCode,
            verification_url: code.verificationUrl,
            expires_in: code.expiresIn,
            interval: code.interval
        )
    }

    func traktDeviceToken(code: String) async throws -> TraktTokenPollResponse {
        do {
            let tokens = try await FlixorCore.shared.trakt.pollDeviceCode(code)
            if let tokens = tokens {
                // Tokens are already set in trakt service by pollDeviceCode
                // But we need to persist them to storage
                do {
                    try await FlixorCore.shared.saveTraktTokens(tokens)
                    print("✅ [APIClient] Trakt tokens saved to storage successfully")
                } catch {
                    print("❌ [APIClient] Failed to save Trakt tokens: \(error)")
                }
                return TraktTokenPollResponse(
                    ok: true,
                    tokens: ["access_token": tokens.accessToken],
                    error: nil,
                    error_description: nil
                )
            } else {
                return TraktTokenPollResponse(
                    ok: false,
                    tokens: nil,
                    error: "pending",
                    error_description: "Waiting for authorization…"
                )
            }
        } catch {
            print("❌ [APIClient] Trakt pollDeviceCode error: \(error)")
            return TraktTokenPollResponse(
                ok: false,
                tokens: nil,
                error: "error",
                error_description: error.localizedDescription
            )
        }
    }

    func traktSignOut() async throws -> SimpleOkResponse {
        await FlixorCore.shared.trakt.signOut()
        return SimpleOkResponse(ok: true, message: "Signed out from Trakt")
    }

    // MARK: - Plex Server Management

    func setCurrentPlexServer(serverId: String) async throws -> SimpleMessageResponse {
        // Find the server in our list
        let servers = try await FlixorCore.shared.getPlexServers()
        guard let server = servers.first(where: { $0.id == serverId || $0.name == serverId }) else {
            throw APIError.serverError("Server not found")
        }

        // Connect to the server via FlixorCore
        _ = try await FlixorCore.shared.connectToPlexServer(server)

        return SimpleMessageResponse(message: "Connected to \(server.name)", serverId: serverId)
    }

    func setPlexServerEndpoint(serverId: String, uri: String, test: Bool = false) async throws -> PlexEndpointUpdateResponse {
        // Find the server
        let servers = try await FlixorCore.shared.getPlexServers()
        guard let server = servers.first(where: { $0.id == serverId || $0.name == serverId }) else {
            throw APIError.serverError("Server not found")
        }

        // Test the endpoint connectivity
        if test {
            var request = URLRequest(url: URL(string: uri)!)
            request.httpMethod = "HEAD"
            request.setValue(server.accessToken, forHTTPHeaderField: "X-Plex-Token")
            request.timeoutInterval = 10

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...399).contains(httpResponse.statusCode) else {
                    throw APIError.serverError("Endpoint unreachable")
                }
            } catch {
                throw APIError.serverError("Endpoint test failed: \(error.localizedDescription)")
            }
        }

        return PlexEndpointUpdateResponse(
            message: "Endpoint updated",
            server: PlexEndpointServer(
                id: serverId,
                host: nil,
                port: nil,
                protocolName: nil,
                preferredUri: uri
            )
        )
    }
}

// MARK: - Helper Response Structs for Routing

struct TMDBMatchResponse: Codable {
    let tmdbId: Int?
    let backdropUrl: String?
    let posterUrl: String?
}

struct PlexChildrenResponse: Codable {
    let Metadata: [FlixorKit.PlexMediaItem]?
    let size: Int?
}

struct PlexDirResponse: Codable {
    let MediaContainer: PlexDirContainer?
}

struct PlexDirContainer: Codable {
    let Metadata: [FlixorKit.PlexMediaItem]?
}

struct PlexSearchResponse: Codable {
    let MediaContainer: PlexSearchContainer?
}

struct PlexSearchContainer: Codable {
    let Metadata: [FlixorKit.PlexMediaItem]?
}

struct PlexFilterOptionsResponse: Codable {
    let Directory: [FlixorKit.PlexFilterOption]
}

// Directory response for library genre/year filters
struct DirectoryEntry: Codable {
    let key: String
    let title: String
}

struct DirectoryResponseWrapper: Codable {
    let Directory: [DirectoryEntry]
}

// Library items response
struct LibraryItemsResponse: Codable {
    let size: Int
    let totalSize: Int
    let offset: Int
    let Metadata: [FlixorKit.PlexMediaItem]
}

struct PlexWatchlistContainer: Codable {
    let MediaContainer: PlexWatchlistMC
}

struct PlexWatchlistMC: Codable {
    let Metadata: [WatchlistItemWrapper]?
}

struct WatchlistItemWrapper: Codable {
    let ratingKey: String?
    let guid: String?
    let title: String?
    let type: String?
    let thumb: String?
    let art: String?
    let year: Int?
    let rating: Double?
    let duration: Int?
    let summary: String?
    let Genre: [PlexGenreTag]?
    let tmdbGuid: String?
}

struct PlexGenreTag: Codable {
    let tag: String?
}

// MARK: - Trakt Watchlist Wrappers (matches MyListViewModel expectations)

struct TraktWatchlistEntryWrapper: Codable {
    let listed_at: String?
    let movie: TraktMovieWrapper?
    let show: TraktShowWrapper?
}

struct TraktMovieWrapper: Codable {
    let title: String?
    let year: Int?
    let overview: String?
    let runtime: Int?
    let genres: [String]?
    let rating: Double?
    let ids: TraktIDsWrapper?
}

struct TraktShowWrapper: Codable {
    let title: String?
    let year: Int?
    let overview: String?
    let runtime: Int?
    let genres: [String]?
    let rating: Double?
    let ids: TraktIDsWrapper?
}

struct TraktIDsWrapper: Codable {
    let trakt: Int?
    let imdb: String?
    let tmdb: Int?
}

// MARK: - Trakt Most Watched Wrappers

struct TraktMostWatchedMovieWrapper: Codable {
    let watcher_count: Int?
    let play_count: Int?
    let collected_count: Int?
    let movie: TraktMovieWrapper?
}

struct TraktMostWatchedShowWrapper: Codable {
    let watcher_count: Int?
    let play_count: Int?
    let collected_count: Int?
    let show: TraktShowWrapper?
}

// MARK: - Trakt Anticipated Wrappers

struct TraktAnticipatedMovieWrapper: Codable {
    let list_count: Int?
    let movie: TraktMovieWrapper?
}

struct TraktAnticipatedShowWrapper: Codable {
    let list_count: Int?
    let show: TraktShowWrapper?
}

struct TMDBVideosResult: Codable {
    let results: [TMDBVideoItem]
}

struct TMDBVideoItem: Codable {
    let key: String?
    let site: String?
    let type: String?
    let name: String?
}

struct EmptyRatings: Codable {
    let imdb: EmptyIMDb?
    let rottenTomatoes: EmptyRT?

    init() {
        imdb = nil
        rottenTomatoes = nil
    }
}

struct EmptyIMDb: Codable {
    let rating: Double?
    let votes: Int?
}

struct EmptyRT: Codable {
    let critic: Int?
    let audience: Int?
}

// MARK: - Plex Markers (intro/credits)

struct PlexMarkersEnvelope: Decodable {
    let MediaContainer: PlexMarkersContainer?
}

struct PlexMarkersContainer: Decodable {
    let Metadata: [PlexMarkersMetadata]?
}

struct PlexMarkersMetadata: Decodable {
    let Marker: [PlexMarker]?
}

struct PlexMarker: Decodable {
    let id: String?
    let type: String?
    let startTimeOffset: Int?
    let endTimeOffset: Int?
}

extension APIClient {
    /// Fetch Plex intro/credits markers for a ratingKey.
    func getPlexMarkers(ratingKey: String) async throws -> [PlexMarker] {
        let encoded = ratingKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ratingKey
        let path = "/api/plex/dir/library/metadata/\(encoded)"
        let env: PlexMarkersEnvelope = try await get(path, queryItems: [URLQueryItem(name: "includeMarkers", value: "1")])
        let list = env.MediaContainer?.Metadata?.first?.Marker ?? []
        return list
    }
}

// MARK: - Supporting Models

struct SimpleMessageResponse: Decodable {
    let message: String?
    let serverId: String?
}

struct SimpleOkResponse: Codable {
    let ok: Bool
    let message: String?
}

struct PlexEndpointUpdateResponse: Decodable {
    let message: String?
    let server: PlexEndpointServer?
}

struct PlexEndpointServer: Decodable {
    let id: String?
    let host: String?
    let port: Int?
    let protocolName: String?
    let preferredUri: String?

    enum CodingKeys: String, CodingKey {
        case id
        case host
        case port
        case preferredUri
        case protocolName = "protocol"
    }
}

struct TraktDeviceCodeResponse: Decodable {
    let device_code: String
    let user_code: String
    let verification_url: String
    let expires_in: Int
    let interval: Int?
}

struct TraktTokenPollResponse: Decodable {
    let ok: Bool
    let tokens: [String: String]?
    let error: String?
    let error_description: String?
}

struct TraktUserProfile: Decodable {
    struct IDs: Decodable { let slug: String? }
    let username: String?
    let name: String?
    let ids: IDs?
}

struct TMDBPersonSearchResponse: Codable {
    struct Result: Codable {
        let id: Int?
        let name: String?
        let profile_path: String?
        let known_for_department: String?
    }
    let results: [Result]?
}

struct TMDBPersonCombinedResponse: Codable {
    struct Credit: Codable, Identifiable {
        let id: Int?
        let media_type: String?
        let title: String?
        let name: String?
        let character: String?
        let job: String?
        let overview: String?
        let popularity: Double?
        let release_date: String?
        let first_air_date: String?
        let poster_path: String?
        let backdrop_path: String?

        var displayTitle: String { title ?? name ?? "Untitled" }
    }

    let cast: [Credit]?
    let crew: [Credit]?
}

// MARK: - New & Popular API Methods

extension APIClient {
    // MARK: - TMDB Methods

    /// Get trending content from TMDB
    /// - Parameters:
    ///   - mediaType: "all", "movie", or "tv"
    ///   - timeWindow: "day" or "week"
    ///   - page: Page number for pagination
    func getTMDBTrending(mediaType: String, timeWindow: String, page: Int = 1) async throws -> TMDBTrendingResponse {
        return try await get("/api/tmdb/trending/\(mediaType)/\(timeWindow)", queryItems: [
            URLQueryItem(name: "page", value: String(page))
        ])
    }

    /// Get upcoming movies from TMDB
    /// - Parameters:
    ///   - region: Country code (e.g., "US")
    ///   - page: Page number for pagination
    func getTMDBUpcoming(region: String = "US", page: Int = 1) async throws -> TMDBMoviesResponse {
        return try await get("/api/tmdb/movie/upcoming", queryItems: [
            URLQueryItem(name: "region", value: region),
            URLQueryItem(name: "page", value: String(page))
        ])
    }

    /// Get movie details from TMDB
    /// - Parameter id: TMDB movie ID
    func getTMDBMovieDetails(id: String) async throws -> TMDBMovieDetails {
        return try await get("/api/tmdb/movie/\(id)")
    }

    /// Get TV show details from TMDB
    /// - Parameter id: TMDB TV show ID
    func getTMDBTVDetails(id: String) async throws -> TMDBTVDetails {
        return try await get("/api/tmdb/tv/\(id)")
    }

    /// Get videos (trailers) for a movie or TV show
    /// - Parameters:
    ///   - mediaType: "movie" or "tv"
    ///   - id: TMDB ID
    func getTMDBVideos(mediaType: String, id: String) async throws -> TMDBVideosResponse {
        return try await get("/api/tmdb/\(mediaType)/\(id)/videos")
    }

    /// Get images (logos, backdrops, posters) for a movie or TV show
    /// - Parameters:
    ///   - mediaType: "movie" or "tv"
    ///   - id: TMDB ID
    func getTMDBImages(mediaType: String, id: String) async throws -> TMDBImagesResponse {
        return try await get("/api/tmdb/\(mediaType)/\(id)/images")
    }

    /// Search for a person on TMDB by name
    func searchTMDBPerson(name: String) async throws -> TMDBPersonSearchResponse {
        return try await get("/api/tmdb/search/person", queryItems: [
            URLQueryItem(name: "query", value: name)
        ])
    }

    /// Fetch combined movie and TV credits for a TMDB person id
    func getTMDBPersonCombinedCredits(id: String) async throws -> TMDBPersonCombinedResponse {
        return try await get("/api/tmdb/person/\(id)/combined_credits")
    }

    // MARK: - Trakt Methods

    /// Get most watched content from Trakt
    /// - Parameters:
    ///   - media: "movies" or "shows"
    ///   - period: "daily", "weekly", "monthly", "yearly", or "all"
    ///   - limit: Optional limit on number of results
    func getTraktMostWatched(media: String, period: String, limit: Int? = nil) async throws -> TraktWatchedResponse {
        var queryItems: [URLQueryItem] = []
        if let limit = limit {
            queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        return try await get("/api/trakt/\(media)/watched/\(period)", queryItems: queryItems.isEmpty ? nil : queryItems)
    }

    /// Get most anticipated content from Trakt
    /// - Parameters:
    ///   - media: "movies" or "shows"
    ///   - limit: Optional limit on number of results
    func getTraktAnticipated(media: String, limit: Int? = nil) async throws -> TraktAnticipatedResponse {
        var queryItems: [URLQueryItem] = []
        if let limit = limit {
            queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        return try await get("/api/trakt/\(media)/anticipated", queryItems: queryItems.isEmpty ? nil : queryItems)
    }

    // MARK: - Plex Content Methods

    /// Get Plex libraries
    func getPlexLibraries() async throws -> [PlexLibrary] {
        return try await get("/api/plex/libraries")
    }

    /// Get all items from a Plex library section
    /// - Parameters:
    ///   - sectionKey: Library section ID
    ///   - type: Media type (1 for movies, 2 for shows)
    ///   - sort: Sort order (e.g., "addedAt:desc", "lastViewedAt:desc", "viewCount:desc")
    ///   - offset: Pagination offset
    ///   - limit: Number of items to fetch
    func getPlexLibraryAll(sectionKey: String, type: Int, sort: String, offset: Int = 0, limit: Int = 50) async throws -> PlexLibraryResponse {
        return try await get("/api/plex/library/\(sectionKey)/all", queryItems: [
            URLQueryItem(name: "type", value: String(type)),
            URLQueryItem(name: "sort", value: sort),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "limit", value: String(limit))
        ])
    }

    /// Get recently added items from Plex (last N days)
    /// - Parameter days: Number of days to look back (optional)
    func getPlexRecentlyAdded(days: Int? = nil) async throws -> [PlexMediaItem] {
        var queryItems: [URLQueryItem] = []
        if let days = days {
            queryItems.append(URLQueryItem(name: "days", value: String(days)))
        }
        return try await get("/api/plex/recent", queryItems: queryItems.isEmpty ? nil : queryItems)
    }
}

// MARK: - Plex Models

struct PlexLibrary: Decodable {
    let key: String
    let title: String?
    let type: String // "movie" or "show"
}

struct PlexLibraryResponse: Decodable {
    let size: Int?
    let totalSize: Int?
    let offset: Int?
    let Metadata: [PlexMediaItem]?
}

struct PlexMediaItem: Decodable {
    let ratingKey: String
    let title: String?
    let type: String?
    let thumb: String?
    let art: String?
    let year: Int?
    let addedAt: Int?
    let lastViewedAt: Int?
    let viewCount: Int?
    let grandparentTitle: String?
    let grandparentThumb: String?
    let parentThumb: String?
}
