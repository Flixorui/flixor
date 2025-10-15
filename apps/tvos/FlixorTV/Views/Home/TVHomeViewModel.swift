import Foundation
import FlixorKit

struct HomeSection: Identifiable {
    let id: String
    let title: String
    let items: [MediaItem]
}

// MARK: - Trakt Models
struct TraktIDs: Codable { let tmdb: Int?; let trakt: Int?; let imdb: String?; let tvdb: Int? }
struct TraktMedia: Codable { let title: String?; let year: Int?; let ids: TraktIDs }

@MainActor
final class TVHomeViewModel: ObservableObject {
    @Published var billboardItems: [MediaItem] = []
    @Published var continueWatching: [MediaItem] = []
    @Published var onDeck: [MediaItem] = []
    @Published var recentlyAdded: [MediaItem] = []
    @Published var additionalSections: [HomeSection] = []
    @Published var isLoading = true
    @Published var error: String?
    @Published var billboardUltraBlurColors: UltraBlurColors?

    private var loadTask: Task<Void, Never>?

    // Default colors for row sections
    static let defaultRowColors = UltraBlurColors(
        topLeft: "3d1813",
        topRight: "1c2628",
        bottomLeft: "4d1e1a",
        bottomRight: "55231f"
    )

    func load() async {
        // Prevent duplicate loads
        if loadTask != nil {
            print("⚠️ [TVHome] Already loading, skipping")
            return
        }

        loadTask = Task {}
        isLoading = true
        error = nil
        print("🏠 [TVHome] Starting home screen load...")

        // Fire parallel tasks for each section
        Task {
            do {
                let items = try await fetchContinueWatching()
                await MainActor.run {
                    self.continueWatching = Array(items.prefix(12))
                    if self.billboardItems.isEmpty && !items.isEmpty {
                        self.billboardItems = Array(items.prefix(5))
                    }
                }
            } catch {
                print("⚠️ [TVHome] Continue watching failed: \(error)")
            }
        }

        Task {
            do {
                let items = try await fetchOnDeck()
                await MainActor.run {
                    self.onDeck = Array(items.prefix(12))
                    if self.billboardItems.isEmpty && !items.isEmpty {
                        self.billboardItems = Array(items.prefix(5))
                    }
                }
            } catch {
                print("⚠️ [TVHome] On deck failed: \(error)")
            }
        }

        Task {
            do {
                let items = try await fetchRecentlyAdded()
                await MainActor.run {
                    self.recentlyAdded = Array(items.prefix(12))
                    if self.billboardItems.isEmpty && !items.isEmpty {
                        self.billboardItems = Array(items.prefix(5))
                    }
                }
            } catch {
                print("⚠️ [TVHome] Recently added failed: \(error)")
            }
        }

        // Load additional sections (TMDB, Plex.tv watchlist)
        Task {
            await loadAdditionalSections()
        }

        // Wait a bit for initial data then mark done loading
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        isLoading = false
        loadTask = nil
        print("✅ [TVHome] Home screen load complete")
    }

    private func loadAdditionalSections() async {
        var sections: [HomeSection] = []

        // TMDB sections
        if let tmdbSection = await fetchTMDBTrendingSection() { sections.append(tmdbSection) }
        if let watchlistSection = await fetchPlexWatchlistSection() { sections.append(watchlistSection) }
        if let popularMoviesSection = await fetchTMDBPopularMoviesSection() { sections.append(popularMoviesSection) }

        // Genre sections
        do {
            let genreSections = try await fetchGenreSections()
            sections.append(contentsOf: genreSections)
        } catch {
            print("⚠️ [TVHome] Genre sections failed: \(error)")
        }

        // Trakt sections
        do {
            let traktSections = try await fetchTraktSections()
            sections.append(contentsOf: traktSections)
        } catch {
            print("⚠️ [TVHome] Trakt sections failed: \(error)")
        }

        await MainActor.run {
            self.additionalSections = sections

            // If main sections are empty, use fallbacks for billboard
            if billboardItems.isEmpty && !sections.isEmpty {
                if let firstNonEmpty = sections.first(where: { !$0.items.isEmpty }) {
                    self.billboardItems = Array(firstNonEmpty.items.prefix(3))
                }
            }
        }
    }

    // MARK: - Fetch Methods

    private func fetchContinueWatching() async throws -> [MediaItem] {
        print("📦 [TVHome] Fetching continue watching...")
        let items = try await APIClient.shared.getPlexContinueList()
        print("✅ [TVHome] Received \(items.count) continue watching items")
        let baseItems = items.map { $0.toMediaItem() }
        return await enrichPlexItemsWithLogos(baseItems)
    }

    private func fetchOnDeck() async throws -> [MediaItem] {
        print("📦 [TVHome] Fetching on deck...")
        let items = try await APIClient.shared.getPlexOnDeckList()
        print("✅ [TVHome] Received \(items.count) on deck items")
        let baseItems = items.map { $0.toMediaItem() }
        return await enrichPlexItemsWithLogos(baseItems)
    }

    private func fetchRecentlyAdded() async throws -> [MediaItem] {
        print("📦 [TVHome] Fetching recently added...")
        let items = try await APIClient.shared.getPlexRecentList()
        print("✅ [TVHome] Received \(items.count) recently added items")
        let baseItems = items.map { $0.toMediaItem() }
        return await enrichPlexItemsWithLogos(baseItems)
    }

    // MARK: - Additional Sections

    private func fetchTMDBTrendingSection() async -> HomeSection? {
        do {
            print("📦 [TVHome] Fetching TMDB trending TV...")
            let response = try await APIClient.shared.getTMDBTrending(mediaType: "tv", timeWindow: "week")

            // Fetch items with logos
            var items: [MediaItem] = []
            await withTaskGroup(of: MediaItem?.self) { group in
                for result in response.results.prefix(12) {
                    group.addTask {
                        let logo = try? await self.fetchTMDBLogo(mediaType: "tv", id: result.id)
                        return MediaItem(
                            id: "tmdb:tv:\(result.id)",
                            title: result.name ?? result.title ?? "Untitled",
                            type: "show",
                            thumb: ImageService.shared.tmdbImageURL(path: result.poster_path, size: .w500)?.absoluteString,
                            art: ImageService.shared.tmdbImageURL(path: result.backdrop_path, size: .original)?.absoluteString,
                            logo: logo,
                            year: nil, rating: nil, duration: nil, viewOffset: nil, summary: nil,
                            grandparentTitle: nil, grandparentThumb: nil, grandparentArt: nil,
                            parentIndex: nil, index: nil
                        )
                    }
                }
                for await maybe in group { if let m = maybe { items.append(m) } }
            }

            print("✅ [TVHome] TMDB trending: \(items.count) items")
            return HomeSection(id: "tmdb-trending", title: "Trending Now", items: items)
        } catch {
            print("⚠️ [TVHome] TMDB trending failed: \(error)")
            return nil
        }
    }

    private func fetchTMDBPopularMoviesSection() async -> HomeSection? {
        do {
            print("📦 [TVHome] Fetching TMDB trending movies...")
            let response = try await APIClient.shared.getTMDBTrending(mediaType: "movie", timeWindow: "week")

            // Fetch items with logos
            var items: [MediaItem] = []
            await withTaskGroup(of: MediaItem?.self) { group in
                for result in response.results.prefix(12) {
                    group.addTask {
                        let logo = try? await self.fetchTMDBLogo(mediaType: "movie", id: result.id)
                        return MediaItem(
                            id: "tmdb:movie:\(result.id)",
                            title: result.title ?? result.name ?? "Untitled",
                            type: "movie",
                            thumb: ImageService.shared.tmdbImageURL(path: result.poster_path, size: .w500)?.absoluteString,
                            art: ImageService.shared.tmdbImageURL(path: result.backdrop_path, size: .original)?.absoluteString,
                            logo: logo,
                            year: nil, rating: nil, duration: nil, viewOffset: nil, summary: nil,
                            grandparentTitle: nil, grandparentThumb: nil, grandparentArt: nil,
                            parentIndex: nil, index: nil
                        )
                    }
                }
                for await maybe in group { if let m = maybe { items.append(m) } }
            }

            print("✅ [TVHome] TMDB popular movies: \(items.count) items")
            return HomeSection(id: "tmdb-popular-movies", title: "Popular on Plex", items: items)
        } catch {
            print("⚠️ [TVHome] TMDB popular movies failed: \(error)")
            return nil
        }
    }

    private func fetchPlexWatchlistSection() async -> HomeSection? {
        do {
            print("📦 [TVHome] Fetching Plex.tv watchlist...")
            let envelope = try await APIClient.shared.getPlexTvWatchlist()
            let metadata = envelope.MediaContainer.Metadata ?? []

            // Fetch items with logos using task group
            var items: [MediaItem] = []
            await withTaskGroup(of: MediaItem?.self) { group in
                for m in metadata.prefix(20) {
                    group.addTask {
                        let baseItem = m.toMediaItem()

                        // Use backend-enriched tmdbGuid if available, otherwise use original Plex ID
                        var outId = baseItem.id
                        var logo: String? = nil

                        if let tmdbGuid = m.tmdbGuid {
                            // Backend already formatted as "tmdb:movie:123" or "tmdb:tv:456"
                            outId = tmdbGuid
                            print("✅ [TVHome] Using backend-enriched TMDB ID for \(m.title): \(tmdbGuid)")

                            // Extract TMDB ID and media type from tmdbGuid
                            if let (mediaType, tmdbId) = self.extractTMDBInfoFromGuid(tmdbGuid) {
                                logo = try? await self.fetchTMDBLogo(mediaType: mediaType, id: tmdbId)
                                print("🎨 [TVHome] Fetched logo for \(m.title): \(logo != nil ? "✅" : "❌")")
                            }
                        } else {
                            print("⚠️ [TVHome] No TMDB ID available for \(m.title), using Plex enrichment")
                            // Try to fetch logo via Plex metadata path
                            logo = try? await self.resolveTMDBLogoForPlexItem(baseItem)
                        }

                        // Create MediaItem with logo
                        return MediaItem(
                            id: outId,
                            title: baseItem.title,
                            type: baseItem.type,
                            thumb: baseItem.thumb,
                            art: baseItem.art,
                            logo: logo,
                            year: baseItem.year,
                            rating: baseItem.rating,
                            duration: baseItem.duration,
                            viewOffset: baseItem.viewOffset,
                            summary: baseItem.summary,
                            grandparentTitle: baseItem.grandparentTitle,
                            grandparentThumb: baseItem.grandparentThumb,
                            grandparentArt: baseItem.grandparentArt,
                            parentIndex: baseItem.parentIndex,
                            index: baseItem.index,
                            parentRatingKey: baseItem.parentRatingKey,
                            parentTitle: baseItem.parentTitle,
                            leafCount: baseItem.leafCount,
                            viewedLeafCount: baseItem.viewedLeafCount
                        )
                    }
                }
                for await maybe in group { if let m = maybe { items.append(m) } }
            }

            print("✅ [TVHome] Plex.tv watchlist: \(items.count) items with logos enriched")
            if items.isEmpty { return nil }
            return HomeSection(id: "plex-watchlist", title: "My List", items: Array(items.prefix(12)))
        } catch {
            print("⚠️ [TVHome] Plex.tv watchlist failed: \(error)")
            return nil
        }
    }

    // Helper to extract media type and TMDB ID from "tmdb:movie:123" or "tmdb:tv:456" format
    nonisolated private func extractTMDBInfoFromGuid(_ guid: String) -> (mediaType: String, tmdbId: Int)? {
        let components = guid.split(separator: ":")
        guard components.count == 3,
              components[0] == "tmdb",
              let tmdbId = Int(components[2]) else {
            return nil
        }
        let mediaType = String(components[1]) // "movie" or "tv"
        return (mediaType, tmdbId)
    }

    // MARK: - UltraBlur Colors

    func fetchUltraBlurColors(for item: MediaItem) async {
        guard let artURL = item.art ?? item.thumb else {
            print("⚠️ [TVHome] No art URL for ultrablur colors")
            return
        }

        do {
            print("🎨 [TVHome] Fetching ultrablur colors for: \(artURL)")
            let colors = try await APIClient.shared.getUltraBlurColors(imageUrl: artURL)
            await MainActor.run {
                self.billboardUltraBlurColors = colors
            }
            print("✅ [TVHome] UltraBlur colors fetched: TL=\(colors.topLeft) TR=\(colors.topRight)")
        } catch {
            print("⚠️ [TVHome] Failed to fetch ultrablur colors: \(error)")
        }
    }

    // MARK: - Plex Genre Sections

    private func fetchGenreSections() async throws -> [HomeSection] {
        struct DirContainer: Codable { let MediaContainer: DirMC }
        struct DirMC: Codable { let Directory: [DirEntry]? }
        struct DirTop: Codable { let Directory: [DirEntry]? }
        struct DirEntry: Codable { let key: String; let title: String; let fastKey: String? }
        struct MetaResponse: Codable {
            let MediaContainer: MetaMC?
            let Metadata: [MediaItemFull]?
        }
        struct MetaMC: Codable { let Metadata: [MediaItemFull]? }

        let genreRows: [(label: String, type: String, genre: String)] = [
            ("TV Shows - Children", "show", "Children"),
            ("Movie - Music", "movie", "Music"),
            ("Movies - Documentary", "movie", "Documentary"),
            ("Movies - History", "movie", "History"),
            ("TV Shows - Reality", "show", "Reality"),
            ("Movies - Drama", "movie", "Drama"),
            ("TV Shows - Suspense", "show", "Suspense"),
            ("Movies - Animation", "movie", "Animation"),
        ]

        print("📦 [TVHome] Fetching libraries for genre rows...")
        let libraries = try await APIClient.shared.getPlexLibraries()
        let movieLib = libraries.first { $0.type == "movie" }
        let showLib = libraries.first { $0.type == "show" }

        var out: [HomeSection] = []
        for spec in genreRows {
            let lib = (spec.type == "movie") ? movieLib : showLib
            guard let libKey = lib?.key else { continue }
            do {
                // Try top-level Directory first
                if let top: DirTop = try? await APIClient.shared.get("/api/plex/library/\(libKey)/genre"),
                   let dir = top.Directory?.first(where: { $0.title.lowercased() == spec.genre.lowercased() }) {
                    let target = normalizedGenreRequest(dir.fastKey, libKey: libKey, rawKey: dir.key)
                    let meta: MetaResponse = try await APIClient.shared.get("/api/plex/dir\(target.path)", queryItems: target.queryItems)
                    let items = (meta.MediaContainer?.Metadata ?? meta.Metadata ?? []).map { $0.toMediaItem() }
                    if !items.isEmpty {
                        out.append(HomeSection(
                            id: "genre-\(spec.genre.lowercased())",
                            title: spec.label,
                            items: Array(items.prefix(12))
                        ))
                    }
                    continue
                }
                // Fallback to MediaContainer.Directory
                let dirs: DirContainer = try await APIClient.shared.get("/api/plex/library/\(libKey)/genre")
                guard let dir = dirs.MediaContainer.Directory?.first(where: { $0.title.lowercased() == spec.genre.lowercased() }) else { continue }
                let target = normalizedGenreRequest(dir.fastKey, libKey: libKey, rawKey: dir.key)
                let meta: MetaResponse = try await APIClient.shared.get("/api/plex/dir\(target.path)", queryItems: target.queryItems)
                let items = (meta.MediaContainer?.Metadata ?? meta.Metadata ?? []).map { $0.toMediaItem() }
                if !items.isEmpty {
                    out.append(HomeSection(
                        id: "genre-\(spec.genre.lowercased())",
                        title: spec.label,
                        items: Array(items.prefix(12))
                    ))
                }
            } catch {
                print("⚠️ [TVHome] Genre fetch failed for \(spec.label): \(error)")
            }
        }
        return out
    }

    private func normalizedGenreRequest(_ fastKey: String?, libKey: String, rawKey: String) -> (path: String, queryItems: [URLQueryItem]?) {
        var key = fastKey ?? "/library/sections/\(libKey)/all?genre=\(rawKey)"
        if !key.hasPrefix("/") { key = "/\(key)" }

        if let questionIndex = key.firstIndex(of: "?") {
            let path = String(key[..<questionIndex])
            let query = String(key[key.index(after: questionIndex)...])
            let components = query.split(separator: "&").map { pair -> URLQueryItem in
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                let name = parts.first ?? ""
                let value = parts.count > 1 ? parts[1] : nil
                return URLQueryItem(name: name, value: value)
            }
            return (path, components)
        }
        return (key, nil)
    }

    // MARK: - Trakt Sections

    private func fetchTraktSections() async throws -> [HomeSection] {
        var sections: [HomeSection] = []

        // Trending Movies
        do {
            let items = try await fetchTraktTrending(media: "movies")
            if !items.isEmpty {
                sections.append(HomeSection(
                    id: "trakt-trending-movies",
                    title: "Trending Movies on Trakt",
                    items: items
                ))
            }
        } catch { print("⚠️ [TVHome] Trakt trending movies failed: \(error)") }

        // Trending TV Shows
        do {
            let items = try await fetchTraktTrending(media: "shows")
            if !items.isEmpty {
                sections.append(HomeSection(
                    id: "trakt-trending-shows",
                    title: "Trending TV Shows on Trakt",
                    items: items
                ))
            }
        } catch { print("⚠️ [TVHome] Trakt trending shows failed: \(error)") }

        // Your Trakt Watchlist
        if let wl = try? await fetchTraktWatchlist() {
            if !wl.isEmpty {
                sections.append(HomeSection(
                    id: "trakt-watchlist",
                    title: "Your Trakt Watchlist",
                    items: wl
                ))
            }
        }

        // Recently Watched
        if let hist = try? await fetchTraktHistory() {
            if !hist.isEmpty {
                sections.append(HomeSection(
                    id: "trakt-history",
                    title: "Recently Watched",
                    items: hist
                ))
            }
        }

        // Recommended for You
        if let rec = try? await fetchTraktRecommendations() {
            if !rec.isEmpty {
                sections.append(HomeSection(
                    id: "trakt-recs",
                    title: "Recommended for You",
                    items: rec
                ))
            }
        }

        // Popular TV Shows on Trakt
        do {
            let items = try await fetchTraktPopular(media: "shows")
            if !items.isEmpty {
                sections.append(HomeSection(
                    id: "trakt-popular-shows",
                    title: "Popular TV Shows on Trakt",
                    items: items
                ))
            }
        } catch { print("⚠️ [TVHome] Trakt popular shows failed: \(error)") }

        return sections
    }

    private func fetchTraktTrending(media: String) async throws -> [MediaItem] {
        struct TraktTrendingItem: Codable { let watchers: Int?; let movie: TraktMedia?; let show: TraktMedia? }
        let arr: [TraktTrendingItem] = try await APIClient.shared.get("/api/trakt/trending/\(media)")
        let mediaType = (media == "movies") ? "movie" : "tv"
        let limited = Array(arr.prefix(12))
        let list: [TraktMedia] = limited.compactMap { $0.movie ?? $0.show }
        return await mapTraktMediaListToMediaItems(list, mediaType: mediaType)
    }

    private func fetchTraktPopular(media: String) async throws -> [MediaItem] {
        let arr: [TraktMedia] = try await APIClient.shared.get("/api/trakt/popular/\(media)")
        let mediaType = (media == "movies") ? "movie" : "tv"
        let limited = Array(arr.prefix(12))
        return await mapTraktMediaListToMediaItems(limited, mediaType: mediaType)
    }

    private func fetchTraktWatchlist() async throws -> [MediaItem]? {
        struct TraktItem: Codable { let movie: TraktMedia?; let show: TraktMedia? }
        do {
            let arr: [TraktItem] = try await APIClient.shared.get("/api/trakt/users/me/watchlist")
            let mediaList: [TraktMedia] = arr.compactMap { $0.movie ?? $0.show }
            let items = await mapTraktMediaListToMediaItems(Array(mediaList.prefix(12)), mediaType: nil)
            return items
        } catch {
            return nil
        }
    }

    private func fetchTraktHistory() async throws -> [MediaItem]? {
        struct TraktItem: Codable { let movie: TraktMedia?; let show: TraktMedia? }
        do {
            let arr: [TraktItem] = try await APIClient.shared.get("/api/trakt/users/me/history")
            let mediaList: [TraktMedia] = arr.compactMap { $0.movie ?? $0.show }
            let items = await mapTraktMediaListToMediaItems(Array(mediaList.prefix(12)), mediaType: nil)
            return items
        } catch { return nil }
    }

    private func fetchTraktRecommendations() async throws -> [MediaItem]? {
        do {
            let arr: [TraktMedia] = try await APIClient.shared.get("/api/trakt/recommendations/movies")
            let items = await mapTraktMediaListToMediaItems(Array(arr.prefix(12)), mediaType: "movie")
            return items
        } catch { return nil }
    }

    private func mapTraktMediaListToMediaItems(_ list: [TraktMedia], mediaType: String?) async -> [MediaItem] {
        var out: [MediaItem] = []
        await withTaskGroup(of: MediaItem?.self) { group in
            for media in list {
                group.addTask {
                    guard let tmdb = media.ids.tmdb else { return nil }
                    let inferredType: String = mediaType ?? "movie"
                    let title = media.title ?? ""
                    do {
                        // Fetch backdrop, poster, and logo from TMDB
                        async let backdropTask = self.fetchTMDBBackdrop(mediaType: inferredType, id: tmdb)
                        async let posterTask = self.fetchTMDBPoster(mediaType: inferredType, id: tmdb)
                        async let logoTask = try? await self.fetchTMDBLogo(mediaType: inferredType, id: tmdb)

                        let (backdrop, poster) = try await (backdropTask, posterTask)
                        let logo = await logoTask

                        let m = MediaItem(
                            id: "tmdb:\(inferredType):\(tmdb)",
                            title: title,
                            type: inferredType == "movie" ? "movie" : "show",
                            thumb: poster,
                            art: backdrop,
                            logo: logo,
                            year: media.year,
                            rating: nil,
                            duration: nil,
                            viewOffset: nil,
                            summary: nil,
                            grandparentTitle: nil,
                            grandparentThumb: nil,
                            grandparentArt: nil,
                            parentIndex: nil,
                            index: nil
                        )
                        return m
                    } catch { return nil }
                }
            }
            for await maybe in group { if let m = maybe { out.append(m) } }
        }
        return out
    }

    private func fetchTMDBBackdrop(mediaType: String, id: Int) async throws -> String? {
        struct TMDBTitle: Codable { let backdrop_path: String? }
        let path = "/api/tmdb/\(mediaType)/\(id)"
        let detail: TMDBTitle = try await APIClient.shared.get(path)
        if let p = detail.backdrop_path {
            return ImageService.shared.tmdbImageURL(path: p, size: .original)?.absoluteString
        }
        return nil
    }

    private func fetchTMDBPoster(mediaType: String, id: Int) async throws -> String? {
        struct TMDBTitle: Codable { let poster_path: String? }
        let path = "/api/tmdb/\(mediaType)/\(id)"
        let detail: TMDBTitle = try await APIClient.shared.get(path)
        if let p = detail.poster_path {
            return ImageService.shared.tmdbImageURL(path: p, size: .w500)?.absoluteString
        }
        return nil
    }

    private func fetchTMDBLogo(mediaType: String, id: Int) async throws -> String? {
        struct TMDBImage: Codable { let file_path: String?; let iso_639_1: String?; let vote_average: Double? }
        struct TMDBImages: Codable { let logos: [TMDBImage]? }

        let imgs: TMDBImages = try await APIClient.shared.get("/api/tmdb/\(mediaType)/\(id)/images", queryItems: [URLQueryItem(name: "language", value: "en,hi,null")])

        // Priority: English > Hindi > any language > no language
        if let logo = (imgs.logos ?? []).first(where: { $0.iso_639_1 == "en" || $0.iso_639_1 == "hi" }) ?? imgs.logos?.first,
           let p = logo.file_path {
            return "https://image.tmdb.org/t/p/w500\(p)"
        }
        return nil
    }

    // MARK: - Plex Item Logo Enrichment

    private func enrichPlexItemsWithLogos(_ items: [MediaItem]) async -> [MediaItem] {
        print("🎨 [TVHome] Enriching \(items.count) Plex items with TMDB logos...")

        return await withTaskGroup(of: (Int, MediaItem).self) { group in
            for (index, item) in items.enumerated() {
                group.addTask {
                    if let logoURL = try? await self.resolveTMDBLogoForPlexItem(item) {
                        // Create new MediaItem with logo
                        let enriched = MediaItem(
                            id: item.id,
                            title: item.title,
                            type: item.type,
                            thumb: item.thumb,
                            art: item.art,
                            logo: logoURL,
                            year: item.year,
                            rating: item.rating,
                            duration: item.duration,
                            viewOffset: item.viewOffset,
                            summary: item.summary,
                            grandparentTitle: item.grandparentTitle,
                            grandparentThumb: item.grandparentThumb,
                            grandparentArt: item.grandparentArt,
                            parentIndex: item.parentIndex,
                            index: item.index,
                            parentRatingKey: item.parentRatingKey,
                            parentTitle: item.parentTitle,
                            leafCount: item.leafCount,
                            viewedLeafCount: item.viewedLeafCount
                        )
                        return (index, enriched)
                    }
                    // Return original item if logo fetch fails
                    return (index, item)
                }
            }

            // Collect results and maintain order
            var enrichedItems: [(Int, MediaItem)] = []
            for await result in group {
                enrichedItems.append(result)
            }

            // Sort by original index and return just the items
            let sorted = enrichedItems.sorted { $0.0 < $1.0 }.map { $0.1 }
            print("✅ [TVHome] Enriched \(sorted.count) items with TMDB logos")
            return sorted
        }
    }

    private func resolveTMDBLogoForPlexItem(_ item: MediaItem) async throws -> String? {
        print("🔍 [TVHome] Resolving TMDB logo for: \(item.title) (id: \(item.id), type: \(item.type))")

        // Extract rating key from plex: prefix or use raw ID
        let normalizedId: String
        if item.id.hasPrefix("plex:") {
            normalizedId = item.id
        } else {
            normalizedId = "plex:\(item.id)"
        }

        guard normalizedId.hasPrefix("plex:") else { return nil }

        let rk = String(normalizedId.dropFirst(5))

        // Fetch full Plex metadata to get TMDB GUID
        do {
            let fullItem: MediaItemFull = try await APIClient.shared.get("/api/plex/metadata/\(rk)")

            // For seasons, fetch the parent show's logo instead
            if fullItem.type == "season", let parentRatingKey = fullItem.parentRatingKey {
                print("📺 [TVHome] Season detected, fetching parent show logo (parentKey: \(parentRatingKey))")
                let showItem: MediaItemFull = try await APIClient.shared.get("/api/plex/metadata/\(parentRatingKey)")

                // Extract TMDB ID from parent show's Guid array
                if let tmdbId = extractTMDBIdFromGuidArray(showItem.Guid) ?? extractTMDBIdFromString(showItem.guid) {
                    let logo = try await fetchTMDBLogo(mediaType: "tv", id: tmdbId)
                    print("✅ [TVHome] TMDB logo resolved for season \(item.title) from parent show: \(logo ?? "nil")")
                    return logo
                }
            }

            // For TV episodes, fetch the parent series metadata instead
            if fullItem.type == "episode", let grandparentRatingKey = fullItem.grandparentRatingKey {
                print("📺 [TVHome] Episode detected, fetching parent series metadata for \(item.title)")
                let seriesItem: MediaItemFull = try await APIClient.shared.get("/api/plex/metadata/\(grandparentRatingKey)")

                // Extract TMDB ID from series Guid array
                if let tmdbId = extractTMDBIdFromGuidArray(seriesItem.Guid) ?? extractTMDBIdFromString(seriesItem.guid) {
                    let logo = try await fetchTMDBLogo(mediaType: "tv", id: tmdbId)
                    print("✅ [TVHome] TMDB logo resolved for \(item.title) from series: \(logo ?? "nil")")
                    return logo
                }
            }

            // For movies and shows, extract TMDB ID from Guid array
            if let tmdbId = extractTMDBIdFromGuidArray(fullItem.Guid) ?? extractTMDBIdFromString(fullItem.guid) {
                let mediaType = (fullItem.type == "movie") ? "movie" : "tv"
                let logo = try await fetchTMDBLogo(mediaType: mediaType, id: tmdbId)
                print("✅ [TVHome] TMDB logo resolved for \(item.title): \(logo ?? "nil")")
                return logo
            }

            print("⚠️ [TVHome] No TMDB ID found for \(item.title)")
        } catch {
            print("❌ [TVHome] Failed to fetch metadata for \(item.title): \(error)")
        }

        return nil
    }

    private func extractTMDBIdFromGuidArray(_ guidArray: [MediaItemFull.GuidEntry]?) -> Int? {
        guard let guidArray = guidArray else { return nil }
        for guidEntry in guidArray {
            if guidEntry.id.contains("tmdb://") || guidEntry.id.contains("themoviedb://") {
                if let tmdbIdString = extractTMDBIdFromString(guidEntry.id) {
                    return tmdbIdString
                }
            }
        }
        return nil
    }

    private func extractTMDBIdFromString(_ guid: String?) -> Int? {
        guard let guid = guid else { return nil }
        let prefixes = ["tmdb://", "themoviedb://"]
        for p in prefixes {
            if let range = guid.range(of: p) {
                let tail = String(guid[range.upperBound...])
                let digits = String(tail.filter { $0.isNumber })
                if digits.count >= 3, let id = Int(digits) {
                    return id
                }
            }
        }
        return nil
    }
}
