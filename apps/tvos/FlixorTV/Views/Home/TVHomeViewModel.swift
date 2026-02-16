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
    private var additionalSectionsTask: Task<Void, Never>?
    private var logoEnrichmentTask: Task<Void, Never>?
    private var ultraBlurTask: Task<Void, Never>?
    private var ultraBlurColorCache: [String: UltraBlurColors] = [:]
    private var hasLoadedOnce = false

    // Default colors for row sections
    static let defaultRowColors = UltraBlurColors(
        topLeft: "3d1813",
        topRight: "1c2628",
        bottomRight: "55231f",
        bottomLeft: "4d1e1a"
    )

    func loadIfNeeded() async {
        if hasLoadedOnce,
           (!continueWatching.isEmpty || !onDeck.isEmpty || !recentlyAdded.isEmpty || !additionalSections.isEmpty) {
            return
        }
        await load()
    }

    func load() async {
        // Prevent duplicate loads and await the in-flight refresh.
        if let inFlight = loadTask {
            await inFlight.value
            return
        }

        additionalSectionsTask?.cancel()
        logoEnrichmentTask?.cancel()

        isLoading = true
        error = nil

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performLoad()
        }
        loadTask = task
        await task.value
    }

    private func performLoad() async {
        defer {
            isLoading = false
            loadTask = nil
        }

        async let continueWatchingResult = fetchContinueWatchingSafe()
        async let onDeckResult = fetchOnDeckSafe()
        async let recentlyAddedResult = fetchRecentlyAddedSafe()

        let (continueItems, onDeckItems, recentlyAddedItems) = await (
            continueWatchingResult,
            onDeckResult,
            recentlyAddedResult
        )

        continueWatching = Array(continueItems.prefix(12))
        onDeck = Array(onDeckItems.prefix(12))
        recentlyAdded = Array(recentlyAddedItems.prefix(12))

        if billboardItems.isEmpty {
            if !continueItems.isEmpty {
                billboardItems = Array(continueItems.prefix(5))
            } else if !onDeckItems.isEmpty {
                billboardItems = Array(onDeckItems.prefix(5))
            } else if !recentlyAddedItems.isEmpty {
                billboardItems = Array(recentlyAddedItems.prefix(5))
            }
        }

        hasLoadedOnce = true
        scheduleDeferredLogoEnrichment()

        additionalSectionsTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let sections = await self.fetchAdditionalSections()
            guard !Task.isCancelled else { return }
            self.additionalSections = sections
            if self.billboardItems.isEmpty,
               let firstNonEmpty = sections.first(where: { !$0.items.isEmpty }) {
                self.billboardItems = Array(firstNonEmpty.items.prefix(3))
            }
        }
    }

    private func fetchContinueWatchingSafe() async -> [MediaItem] {
        do {
            return try await fetchContinueWatching()
        } catch {
            return []
        }
    }

    private func fetchOnDeckSafe() async -> [MediaItem] {
        do {
            return try await fetchOnDeck()
        } catch {
            return []
        }
    }

    private func fetchRecentlyAddedSafe() async -> [MediaItem] {
        do {
            return try await fetchRecentlyAdded()
        } catch {
            return []
        }
    }

    private func fetchAdditionalSections() async -> [HomeSection] {
        var sections: [HomeSection] = []

        // TMDB sections
        if let tmdbSection = await fetchTMDBTrendingSection() { sections.append(tmdbSection) }
        if let watchlistSection = await fetchPlexWatchlistSection() { sections.append(watchlistSection) }
        if let popularMoviesSection = await fetchTMDBPopularMoviesSection() { sections.append(popularMoviesSection) }

        // Genre sections
        do {
            let genreSections = try await fetchGenreSections()
            sections.append(contentsOf: genreSections)
        } catch {}

        // Trakt sections
        do {
            let traktSections = try await fetchTraktSections()
            sections.append(contentsOf: traktSections)
        } catch {}

        return sections
    }

    // MARK: - Fetch Methods

    private func fetchContinueWatching() async throws -> [MediaItem] {
        let items = try await APIClient.shared.getPlexContinueList()
        return items.map { $0.toMediaItem() }
    }

    private func fetchOnDeck() async throws -> [MediaItem] {
        let items = try await APIClient.shared.getPlexOnDeckList()
        return items.map { $0.toMediaItem() }
    }

    private func fetchRecentlyAdded() async throws -> [MediaItem] {
        let items = try await APIClient.shared.getPlexRecentList()
        return items.map { $0.toMediaItem() }
    }

    // MARK: - Additional Sections

    private func fetchTMDBTrendingSection() async -> HomeSection? {
        do {
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
                            thumb: await ImageService.shared.tmdbImageURL(path: result.poster_path, size: .w500)?.absoluteString,
                            art: await ImageService.shared.tmdbImageURL(path: result.backdrop_path, size: .original)?.absoluteString,
                            logo: logo,
                            year: nil, rating: nil, duration: nil, viewOffset: nil, summary: nil,
                            grandparentTitle: nil, grandparentThumb: nil, grandparentArt: nil,
                            parentIndex: nil, index: nil
                        )
                    }
                }
                for await maybe in group { if let m = maybe { items.append(m) } }
            }

            return HomeSection(id: "tmdb-trending", title: "Trending Now", items: items)
        } catch { return nil }
    }

    private func fetchTMDBPopularMoviesSection() async -> HomeSection? {
        do {
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
                            thumb: await ImageService.shared.tmdbImageURL(path: result.poster_path, size: .w500)?.absoluteString,
                            art: await ImageService.shared.tmdbImageURL(path: result.backdrop_path, size: .original)?.absoluteString,
                            logo: logo,
                            year: nil, rating: nil, duration: nil, viewOffset: nil, summary: nil,
                            grandparentTitle: nil, grandparentThumb: nil, grandparentArt: nil,
                            parentIndex: nil, index: nil
                        )
                    }
                }
                for await maybe in group { if let m = maybe { items.append(m) } }
            }

            return HomeSection(id: "tmdb-popular-movies", title: "Popular on Plex", items: items)
        } catch { return nil }
    }

    private func fetchPlexWatchlistSection() async -> HomeSection? {
        do {
            let envelope = try await APIClient.shared.getPlexTvWatchlist()
            let metadata = envelope.MediaContainer.Metadata ?? []

            let items: [MediaItem] = metadata.prefix(12).map { m in
                let baseItem = m.toMediaItem()
                let outId = m.tmdbGuid ?? baseItem.id
                return copy(baseItem, id: outId)
            }
            if items.isEmpty { return nil }
            return HomeSection(id: "plex-watchlist", title: "My List", items: Array(items.prefix(12)))
        } catch { return nil }
    }

    private func scheduleDeferredLogoEnrichment() {
        logoEnrichmentTask?.cancel()
        let continueSnapshot = continueWatching
        let onDeckSnapshot = onDeck
        let recentSnapshot = recentlyAdded

        logoEnrichmentTask = Task { @MainActor [weak self] in
            guard let self else { return }
            async let continueTask = self.enrichVisibleLogos(in: continueSnapshot, eagerCount: 5)
            async let onDeckTask = self.enrichVisibleLogos(in: onDeckSnapshot, eagerCount: 5)
            async let recentTask = self.enrichVisibleLogos(in: recentSnapshot, eagerCount: 5)
            let (enrichedContinue, enrichedOnDeck, enrichedRecent) = await (continueTask, onDeckTask, recentTask)
            guard !Task.isCancelled else { return }
            continueWatching = enrichedContinue
            onDeck = enrichedOnDeck
            recentlyAdded = enrichedRecent

            if let currentBillboard = billboardItems.first {
                if let fromContinue = enrichedContinue.first(where: { $0.id == currentBillboard.id }) {
                    billboardItems[0] = fromContinue
                } else if let fromOnDeck = enrichedOnDeck.first(where: { $0.id == currentBillboard.id }) {
                    billboardItems[0] = fromOnDeck
                } else if let fromRecent = enrichedRecent.first(where: { $0.id == currentBillboard.id }) {
                    billboardItems[0] = fromRecent
                }
            }
        }
    }

    private func enrichVisibleLogos(in items: [MediaItem], eagerCount: Int) async -> [MediaItem] {
        guard !items.isEmpty else { return items }
        let limit = min(eagerCount, items.count)
        var updated = items

        await withTaskGroup(of: (Int, String?).self) { group in
            for idx in 0..<limit {
                let item = items[idx]
                guard item.logo == nil else { continue }
                group.addTask {
                    let logo = try? await self.resolveTMDBLogoForPlexItem(item)
                    return (idx, logo)
                }
            }

            for await (idx, logo) in group {
                guard let logo else { continue }
                updated[idx] = copy(updated[idx], logo: logo)
            }
        }

        return updated
    }

    private func copy(_ item: MediaItem, id: String? = nil, logo: String? = nil) -> MediaItem {
        MediaItem(
            id: id ?? item.id,
            title: item.title,
            type: item.type,
            thumb: item.thumb,
            art: item.art,
            logo: logo ?? item.logo,
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
    }

    // MARK: - UltraBlur Colors

    func fetchUltraBlurColors(for item: MediaItem) async {
        if let cached = ultraBlurColorCache[item.id] {
            billboardUltraBlurColors = cached
            return
        }

        let resolvedURL = ImageService.shared.continueWatchingURL(for: item, width: 1920, height: 1080)?.absoluteString
            ?? ImageService.shared.artURL(for: item, width: 1920, height: 1080)?.absoluteString
            ?? ImageService.shared.thumbURL(for: item, width: 1920, height: 1080)?.absoluteString

        guard let resolvedURL else { return }
        ultraBlurTask?.cancel()
        ultraBlurTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard !Task.isCancelled else { return }
            if let colors = try? await APIClient.shared.getUltraBlurColors(imageUrl: resolvedURL) {
                guard !Task.isCancelled else { return }
                ultraBlurColorCache[item.id] = colors
                billboardUltraBlurColors = colors
            }
        }
    }

    // MARK: - Plex Genre Sections

    private func fetchGenreSections() async throws -> [HomeSection] {
        struct DirectoryEntry: Codable { let key: String?; let title: String? }
        struct DirectoryContainer: Codable { let Directory: [DirectoryEntry]? }
        struct DirectoryResponse: Codable {
            let MediaContainer: DirectoryContainer?
            let Directory: [DirectoryEntry]?
        }
        struct LibraryResponse: Codable {
            let Metadata: [MediaItemFull]?
        }

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

        let libraries = try await APIClient.shared.getPlexLibraries()
        let movieLib = libraries.first { $0.type == "movie" }
        let showLib = libraries.first { $0.type == "show" }

        var out: [HomeSection] = []
        for spec in genreRows {
            let lib = (spec.type == "movie") ? movieLib : showLib
            guard let libKey = lib?.key else { continue }
            do {
                let dirs: DirectoryResponse = try await APIClient.shared.get("/api/plex/library/\(libKey)/genre")
                let entries = dirs.MediaContainer?.Directory ?? dirs.Directory ?? []
                guard let genreEntry = entries.first(where: {
                    ($0.title ?? "").lowercased() == spec.genre.lowercased()
                }), let genreKey = genreEntry.key else {
                    continue
                }

                let type = spec.type == "movie" ? 1 : 2
                let response: LibraryResponse = try await APIClient.shared.get(
                    "/api/plex/library/\(libKey)/all",
                    queryItems: [
                        URLQueryItem(name: "type", value: String(type)),
                        URLQueryItem(name: "sort", value: "addedAt:desc"),
                        URLQueryItem(name: "offset", value: "0"),
                        URLQueryItem(name: "limit", value: "24"),
                        URLQueryItem(name: "genre", value: genreKey),
                    ]
                )
                let items = (response.Metadata ?? []).map { $0.toMediaItem() }
                if !items.isEmpty {
                    out.append(HomeSection(
                        id: "genre-\(spec.genre.lowercased())",
                        title: spec.label,
                        items: Array(items.prefix(12))
                    ))
                }
            } catch {}
        }
        return out
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
        } catch {}

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
        } catch {}

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
        } catch {}

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

    private func resolveTMDBLogoForPlexItem(_ item: MediaItem) async throws -> String? {
        if item.id.hasPrefix("tmdb:") || item.id.hasPrefix("trakt:") {
            return nil
        }

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
                let showItem: MediaItemFull = try await APIClient.shared.get("/api/plex/metadata/\(parentRatingKey)")

                // Extract TMDB ID from parent show's Guid array
                if let tmdbId = extractTMDBIdFromGuidArray(showItem.Guid) ?? extractTMDBIdFromString(showItem.guid) {
                    let logo = try await fetchTMDBLogo(mediaType: "tv", id: tmdbId)
                    return logo
                }
            }

            // For TV episodes, fetch the parent series metadata instead
            if fullItem.type == "episode", let grandparentRatingKey = fullItem.grandparentRatingKey {
                let seriesItem: MediaItemFull = try await APIClient.shared.get("/api/plex/metadata/\(grandparentRatingKey)")

                // Extract TMDB ID from series Guid array
                if let tmdbId = extractTMDBIdFromGuidArray(seriesItem.Guid) ?? extractTMDBIdFromString(seriesItem.guid) {
                    let logo = try await fetchTMDBLogo(mediaType: "tv", id: tmdbId)
                    return logo
                }
            }

            // For movies and shows, extract TMDB ID from Guid array
            if let tmdbId = extractTMDBIdFromGuidArray(fullItem.Guid) ?? extractTMDBIdFromString(fullItem.guid) {
                let mediaType = (fullItem.type == "movie") ? "movie" : "tv"
                let logo = try await fetchTMDBLogo(mediaType: mediaType, id: tmdbId)
                return logo
            }
        } catch {}

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
