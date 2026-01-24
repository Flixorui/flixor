//
//  HomeViewModel.swift
//  FlixorMac
//
//  View model for home screen using FlixorCore
//

import Foundation
import SwiftUI
import FlixorKit

// Use types from FlixorKit directly

// MARK: - Section Load State

enum SectionLoadState: Equatable {
    case idle
    case loading
    case loaded
    case empty
    case error(String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

@MainActor
class HomeViewModel: ObservableObject {
    // MARK: - Settings (Profile-Scoped)
    private var enabledLibraryKeys: Set<String> {
        Set(UserDefaults.standard.enabledLibraryKeys)
    }

    private func isLibraryEnabled(_ key: String) -> Bool {
        // Empty means all libraries are enabled
        return enabledLibraryKeys.isEmpty || enabledLibraryKeys.contains(key)
    }

    // MARK: - Global State
    @Published var isLoading = false  // Initial full-page loading
    @Published var error: String?

    // MARK: - Per-Section Loading States
    @Published var continueWatchingState: SectionLoadState = .idle
    @Published var onDeckState: SectionLoadState = .idle
    @Published var recentlyAddedState: SectionLoadState = .idle
    @Published var librariesState: SectionLoadState = .idle
    @Published var extraSectionsState: SectionLoadState = .idle
    @Published var collectionSectionsState: SectionLoadState = .idle

    // Expected number of extra section rows (for skeleton placeholders)
    let expectedExtraSectionCount = 8

    // MARK: - Data
    @Published var billboardItems: [MediaItem] = []
    @Published var continueWatchingItems: [MediaItem] = []
    @Published var continueWatchingVersions: Set<String> = []  // ratingKeys with multiple versions across libraries
    @Published var onDeckItems: [MediaItem] = []
    @Published var recentlyAddedItems: [MediaItem] = []
    @Published var librarySections: [LibrarySection] = []
    @Published var extraSections: [LibrarySection] = [] // TMDB/Trakt/Watchlist/Genres
    @Published var collectionSections: [LibrarySection] = [] // Plex Collections

    @Published var currentBillboardIndex = 0
    @Published var pendingAction: HomeAction?

    // MARK: - UltraBlur Colors
    @Published var heroColors: PlexUltraBlurColors?
    private var ultraBlurCache: [String: PlexUltraBlurColors] = [:]
    private var lastHeroColorKey: String?

    private var billboardTimer: Timer?
    private var loadTask: Task<Void, Never>?

    // MARK: - Load Data

    func loadHomeScreen() async {
        // Guard against duplicate loads
        if isLoading || loadTask != nil {
            print("⚠️ [Home] Already loading, skipping duplicate request")
            return
        }
        loadTask = Task {} // mark in-progress

        print("🏠 [Home] Starting home screen load...")
        isLoading = true
        error = nil

        // Set all sections to loading state
        continueWatchingState = .loading
        onDeckState = .loading
        recentlyAddedState = .loading
        librariesState = .loading
        extraSectionsState = .loading
        collectionSectionsState = .loading

        // Fire-and-forget each section; update UI as each finishes
        Task { @MainActor in
            do {
                let data = try await self.fetchContinueWatching()
                self.continueWatchingItems = data
                self.continueWatchingState = data.isEmpty ? .empty : .loaded
                if self.billboardItems.isEmpty, !data.isEmpty {
                    self.billboardItems = self.normalizeForHero(Array(data.prefix(5)))
                    self.startBillboardRotation()
                }
                print("✅ [Home] Continue Watching loaded: \(data.count) items")
            } catch {
                print("⚠️ [Home] Continue Watching failed: \(error)")
                self.continueWatchingState = .error(error.localizedDescription)
            }
            // Mark initial loading complete after first section
            self.isLoading = false
        }

        Task { @MainActor in
            do {
                let data = try await self.fetchOnDeck()
                self.onDeckItems = data
                self.onDeckState = data.isEmpty ? .empty : .loaded
                if self.billboardItems.isEmpty, !data.isEmpty {
                    self.billboardItems = self.normalizeForHero(Array(data.prefix(5)))
                    self.startBillboardRotation()
                }
                print("✅ [Home] On Deck loaded: \(data.count) items")
            } catch {
                print("⚠️ [Home] On Deck failed: \(error)")
                self.onDeckState = .error(error.localizedDescription)
            }
        }

        Task { @MainActor in
            do {
                let data = try await self.fetchRecentlyAdded()
                self.recentlyAddedItems = data
                self.recentlyAddedState = data.isEmpty ? .empty : .loaded
                if self.billboardItems.isEmpty, !data.isEmpty {
                    self.billboardItems = self.normalizeForHero(Array(data.prefix(5)))
                    self.startBillboardRotation()
                }
                print("✅ [Home] Recently Added loaded: \(data.count) items")
            } catch {
                print("⚠️ [Home] Recently Added failed: \(error)")
                self.recentlyAddedState = .error(error.localizedDescription)
            }
        }

        Task { @MainActor in
            do {
                let libs = try await self.fetchLibrarySections()
                self.librarySections = libs
                self.librariesState = libs.isEmpty ? .empty : .loaded
                print("✅ [Home] Libraries loaded: \(libs.count) sections")
            } catch {
                print("⚠️ [Home] Libraries failed: \(error)")
                self.librariesState = .error(error.localizedDescription)
            }
        }

        // Load additional content sections (TMDB/Trakt/Genres/Watchlist) without blocking
        Task { @MainActor in
            await self.loadAdditionalRows()
        }

        // Load collection sections (Plex Collections) without blocking
        Task { @MainActor in
            await self.loadCollectionRows()
        }

        loadTask = nil
    }

    // MARK: - Refresh

    func refresh() async {
        await loadHomeScreen()
    }

    // MARK: - Additional Sections

    private func loadAdditionalRows() async {
        // Gather
        var all: [String: LibrarySection] = [:]
        var genres: [LibrarySection] = []
        var trakt: [String: LibrarySection] = [:]

        // TMDB: Popular on Plex / Trending Now
        do {
            let (popular, trending) = try await fetchTMDBTrendingTVSections()
            if let p = popular.first { all["Popular on Plex"] = p }
            if let t = trending.first { all["Trending Now"] = t }
        } catch { print("⚠️ [Home] TMDB trending failed: \(error)") }

        // Plex.tv Watchlist
        if let wl = await fetchPlexTvWatchlistSection() { all["Watchlist"] = wl }

        // Genres
        do { genres = try await fetchGenreSections() } catch { print("⚠️ [Home] Genre sections failed: \(error)") }

        // Trakt
        do {
            let t = try await fetchTraktSections()
            for s in t { trakt[s.title] = s }
        } catch { print("⚠️ [Home] Trakt sections failed: \(error)") }

        // Order exactly as requested
        var ordered: [LibrarySection] = []
        func push(_ title: String) { if let s = all[title] { ordered.append(s) } }
        push("Popular on Plex")
        // Continue Watching is rendered separately with its own card style
        push("Trending Now")
        push("Watchlist")

        // Specific genre labels in desired order
        let desiredGenres = [
            "TV Shows - Children",
            "Movie - Music",
            "Movies - Documentary",
            "Movies - History",
            "TV Shows - Reality",
            "Movies - Drama",
            "TV Shows - Suspense",
            "Movies - Animation",
        ]
        for label in desiredGenres {
            if let g = genres.first(where: { $0.title == label }) { ordered.append(g) }
        }

        // Trakt: Trending Movies, Trending TV Shows, Your Watchlist, Recently Watched, Recommended, Popular TV Shows
        let desiredTrakt = [
            "Trending Movies on Trakt",
            "Trending TV Shows on Trakt",
            "Your Trakt Watchlist",
            "Recently Watched",
            "Recommended for You",
            "Popular TV Shows on Trakt",
        ]
        for label in desiredTrakt { if let s = trakt[label] { ordered.append(s) } }

        await MainActor.run {
            print("✅ [Home] Extra sections prepared: \(ordered.map { $0.title }.joined(separator: ", "))")
            self.extraSections = ordered
            self.extraSectionsState = ordered.isEmpty ? .empty : .loaded
        }
    }

    // MARK: - Collection Rows

    private func loadCollectionRows() async {
        // Check if collections are enabled in settings
        guard UserDefaults.standard.showCollectionRows else {
            await MainActor.run {
                self.collectionSections = []
                self.collectionSectionsState = .empty
            }
            return
        }

        guard let plexServer = FlixorCore.shared.plexServer else {
            await MainActor.run {
                self.collectionSections = []
                self.collectionSectionsState = .empty
            }
            return
        }

        do {
            let collections = try await plexServer.getAllCollections()

            // Get hidden collection keys from settings
            let hiddenKeys = Set(UserDefaults.standard.hiddenCollectionKeys)

            // Sort by childCount descending and filter out hidden collections
            let sortedCollections = collections
                .filter { !hiddenKeys.contains($0.ratingKey) }
                .sorted { ($0.childCount ?? 0) > ($1.childCount ?? 0) }

            // Fetch 10 collections but only show 5 (in case some are hidden)
            let limitedCollections = Array(sortedCollections.prefix(10))

            var sections: [LibrarySection] = []

            for collection in limitedCollections.prefix(5) {
                do {
                    let items = try await plexServer.getCollectionItems(ratingKey: collection.ratingKey, size: 15)
                    if !items.isEmpty {
                        let mediaItems = items.map { toMediaItem($0) }
                        sections.append(LibrarySection(
                            id: "collection-\(collection.ratingKey)",
                            title: collection.title ?? "Untitled Collection",
                            items: mediaItems,
                            totalCount: collection.childCount ?? items.count,
                            libraryKey: nil,
                            browseContext: .plexCollection(ratingKey: collection.ratingKey, title: collection.title ?? "Collection"),
                            isCollection: true
                        ))
                    }
                } catch {
                    // Continue with other collections
                }
            }

            await MainActor.run {
                self.collectionSections = sections
                self.collectionSectionsState = sections.isEmpty ? .empty : .loaded
            }
        } catch {
            await MainActor.run {
                self.collectionSections = []
                self.collectionSectionsState = .error(error.localizedDescription)
            }
        }
    }

    // MARK: - Helpers

    private func normalizeForHero(_ items: [MediaItem]) -> [MediaItem] {
        return items.map { m in
            if m.id.hasPrefix("plex:") || m.id.hasPrefix("tmdb:") { return m }
            return MediaItem(
                id: "plex:\(m.id)",
                title: m.title,
                type: m.type,
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
        }
    }

    // MARK: - Convert PlexMediaItem to MediaItem

    private func toMediaItem(_ plex: FlixorKit.PlexMediaItem) -> MediaItem {
        return MediaItem(
            id: plex.ratingKey ?? plex.key ?? "",
            title: plex.title ?? "Unknown",
            type: plex.type ?? "unknown",
            thumb: plex.thumb,
            art: plex.art,
            year: plex.year,
            rating: plex.viewCount.map { Double($0) },
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
            viewedLeafCount: plex.viewedLeafCount,
            media: plex.Media
        )
    }

    // MARK: - TMDB Trending (TV)

    private func fetchTMDBTrendingTVSections() async throws -> ([LibrarySection], [LibrarySection]) {
        print("📦 [Home] Fetching TMDB trending TV (week)...")
        let response = try await FlixorCore.shared.tmdb.getTrendingTV(timeWindow: "week")
        let items = response.results.prefix(16)

        var mapped: [MediaItem] = []
        for r in items {
            let title = r.name ?? r.title ?? ""
            let art = FlixorCore.shared.tmdb.getBackdropUrl(path: r.backdropPath, size: "original")
            let thumb = FlixorCore.shared.tmdb.getPosterUrl(path: r.posterPath, size: "w500")
            let m = MediaItem(
                id: "tmdb:tv:\(r.id)",
                title: title,
                type: "show",
                thumb: thumb,
                art: art,
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
            mapped.append(m)
        }
        let first = Array(mapped.prefix(8))
        let second = Array(mapped.dropFirst(8).prefix(8))
        let popular = LibrarySection(
            id: "tmdb-popular",
            title: "Popular on Plex",
            items: first,
            totalCount: first.count,
            libraryKey: nil,
            browseContext: .tmdb(kind: .trending, media: .tv, id: nil, displayTitle: "Popular on Plex")
        )
        let trending = LibrarySection(
            id: "tmdb-trending",
            title: "Trending Now",
            items: second,
            totalCount: second.count,
            libraryKey: nil,
            browseContext: .tmdb(kind: .trending, media: .tv, id: nil, displayTitle: "Trending Now")
        )
        return ([popular], [trending])
    }

    // MARK: - Combined Watchlist (Plex + Trakt)

    private func fetchPlexTvWatchlistSection() async -> LibrarySection? {
        var allItems: [String: MediaItem] = [:] // Use dict to dedupe by ID

        // Fetch Plex.tv watchlist
        if let plexTv = FlixorCore.shared.plexTv {
            do {
                print("📦 [Home] Fetching Plex.tv watchlist...")
                let meta = try await plexTv.getWatchlist()

                for m in meta.prefix(20) {
                    let mediaType = (m.type ?? "show") == "movie" ? "movie" : "show"

                    // Try to extract TMDB ID from Plex GUIDs array
                    var itemId: String
                    var tmdbIdFound: String?
                    for guidStr in m.guids {
                        if let tmdbId = extractTMDBId(from: guidStr) {
                            tmdbIdFound = tmdbId
                            break
                        }
                    }

                    if let tmdbId = tmdbIdFound {
                        itemId = "tmdb:\(mediaType):\(tmdbId)"
                        print("✅ [Home Watchlist] Plex item \(m.title ?? "Unknown") using TMDB ID: \(itemId)")
                    } else if m.key != nil {
                        // Fallback: try to resolve TMDB ID via PlexTv metadata lookup
                        // Note: getTMDBIdForWatchlistItem returns full ID like "tmdb:movie:123"
                        if let fullTmdbId = await plexTv.getTMDBIdForWatchlistItem(m) {
                            itemId = fullTmdbId
                            print("✅ [Home Watchlist] Plex item \(m.title ?? "Unknown") resolved TMDB ID via metadata: \(itemId)")
                        } else if let ratingKey = m.ratingKey {
                            itemId = "plex:\(ratingKey)"
                            print("⚠️ [Home Watchlist] Plex item \(m.title ?? "Unknown") using Plex rating key")
                        } else {
                            continue
                        }
                    } else if let ratingKey = m.ratingKey {
                        itemId = "plex:\(ratingKey)"
                        print("⚠️ [Home Watchlist] Plex item \(m.title ?? "Unknown") using Plex rating key (no key)")
                    } else {
                        continue
                    }

                    let item = MediaItem(
                        id: itemId,
                        title: m.title ?? "Unknown",
                        type: mediaType,
                        thumb: m.thumb,
                        art: m.art,
                        year: m.year,
                        rating: nil,
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
                    allItems[itemId] = item
                }
                print("✅ [Home] Plex watchlist loaded: \(meta.count) items")
            } catch {
                print("⚠️ [Home] Plex.tv watchlist failed: \(error)")
            }
        }

        // Fetch Trakt watchlist if authenticated
        let trakt = FlixorCore.shared.trakt
        if trakt.isAuthenticated {
            do {
                print("📦 [Home] Fetching Trakt watchlist...")
                let watchlist = try await trakt.getWatchlist()

                for wlItem in watchlist.prefix(20) {
                    if let movie = wlItem.movie, let tmdbId = movie.ids.tmdb {
                        let itemId = "tmdb:movie:\(tmdbId)"
                        if allItems[itemId] == nil { // Don't overwrite Plex items (they may have more metadata)
                            let backdrop = await fetchTMDBBackdrop(mediaType: "movie", id: tmdbId)
                            let poster = await fetchTMDBPoster(mediaType: "movie", id: tmdbId)
                            let item = MediaItem(
                                id: itemId,
                                title: movie.title,
                                type: "movie",
                                thumb: poster,
                                art: backdrop,
                                year: movie.year,
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
                            allItems[itemId] = item
                            print("✅ [Home Watchlist] Trakt movie \(movie.title) added: \(itemId)")
                        }
                    } else if let show = wlItem.show, let tmdbId = show.ids.tmdb {
                        let itemId = "tmdb:tv:\(tmdbId)"
                        if allItems[itemId] == nil {
                            let backdrop = await fetchTMDBBackdrop(mediaType: "tv", id: tmdbId)
                            let poster = await fetchTMDBPoster(mediaType: "tv", id: tmdbId)
                            let item = MediaItem(
                                id: itemId,
                                title: show.title,
                                type: "show",
                                thumb: poster,
                                art: backdrop,
                                year: show.year,
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
                            allItems[itemId] = item
                            print("✅ [Home Watchlist] Trakt show \(show.title) added: \(itemId)")
                        }
                    }
                }
                print("✅ [Home] Trakt watchlist loaded")
            } catch {
                print("⚠️ [Home] Trakt watchlist failed: \(error)")
            }
        }

        let items = Array(allItems.values)
        if items.isEmpty { return nil }

        return LibrarySection(
            id: "combined-watchlist",
            title: "Watchlist",
            items: Array(items.prefix(12)),
            totalCount: items.count,
            libraryKey: nil,
            browseContext: .plexWatchlist
        )
    }

    private func fetchTMDBPoster(mediaType: String, id: Int) async -> String? {
        do {
            if mediaType == "movie" {
                let detail = try await FlixorCore.shared.tmdb.getMovieDetails(id: id)
                return FlixorCore.shared.tmdb.getPosterUrl(path: detail.posterPath, size: "w500")
            } else {
                let detail = try await FlixorCore.shared.tmdb.getTVDetails(id: id)
                return FlixorCore.shared.tmdb.getPosterUrl(path: detail.posterPath, size: "w500")
            }
        } catch {
            return nil
        }
    }

    private func extractTMDBId(from guid: String) -> String? {
        // Extract digits from tmdb://... or themoviedb://...
        let prefixes = ["tmdb://", "themoviedb://"]
        for p in prefixes {
            if let range = guid.range(of: p) {
                let tail = String(guid[range.upperBound...])
                let digits = String(tail.filter { $0.isNumber })
                if digits.count >= 3 { return digits }
            }
        }
        return nil
    }

    // MARK: - Plex Genre Sections

    private func fetchGenreSections() async throws -> [LibrarySection] {
        guard let plexServer = FlixorCore.shared.plexServer else { return [] }

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

        print("📦 [Home] Fetching libraries for genre rows...")
        let libraries = try await plexServer.getLibraries()

        // Only use libraries that are enabled in settings
        let enabledLibs = libraries.filter { isLibraryEnabled($0.key) }
        let movieLib = enabledLibs.first { $0.type == "movie" }
        let showLib = enabledLibs.first { $0.type == "show" }

        var out: [LibrarySection] = []
        for spec in genreRows {
            let lib = (spec.type == "movie") ? movieLib : showLib
            guard let libKey = lib?.key else { continue }
            do {
                // Fetch items with genre filter
                let plexItems = try await plexServer.getLibraryItems(key: libKey, limit: 20, genre: spec.genre)
                let items = plexItems.map { toMediaItem($0) }
                if !items.isEmpty {
                    out.append(LibrarySection(
                        id: "genre-\(spec.genre.lowercased())",
                        title: spec.label,
                        items: Array(items.prefix(12)),
                        totalCount: items.count,
                        libraryKey: libKey,
                        browseContext: .plexDirectory(path: "/library/sections/\(libKey)/all?genre=\(spec.genre)", title: spec.label)
                    ))
                }
            } catch {
                print("⚠️ [Home] Genre fetch failed for \(spec.label): \(error)")
            }
        }
        return out
    }

    // MARK: - Trakt Sections

    private func fetchTraktSections() async throws -> [LibrarySection] {
        var sections: [LibrarySection] = []
        let trakt = FlixorCore.shared.trakt

        // Trending Movies (public)
        do {
            let trendingMovies = try await trakt.getTrendingMovies(limit: 12)
            let items = await mapTraktMoviesToMediaItems(trendingMovies.map { $0.movie })
            if !items.isEmpty {
                sections.append(LibrarySection(
                    id: "trakt-trending-movies",
                    title: "Trending Movies on Trakt",
                    items: items,
                    totalCount: items.count,
                    libraryKey: nil,
                    browseContext: .trakt(kind: .trendingMovies)
                ))
            }
        } catch { print("⚠️ [Home] Trakt trending movies failed: \(error)") }

        // Trending TV Shows (public)
        do {
            let trendingShows = try await trakt.getTrendingShows(limit: 12)
            let items = await mapTraktShowsToMediaItems(trendingShows.map { $0.show })
            if !items.isEmpty {
                sections.append(LibrarySection(
                    id: "trakt-trending-shows",
                    title: "Trending TV Shows on Trakt",
                    items: items,
                    totalCount: items.count,
                    libraryKey: nil,
                    browseContext: .trakt(kind: .trendingShows)
                ))
            }
        } catch { print("⚠️ [Home] Trakt trending shows failed: \(error)") }

        // Your Trakt Watchlist (auth)
        if trakt.isAuthenticated {
            do {
                let watchlist = try await trakt.getWatchlist()
                var items: [MediaItem] = []
                for wlItem in watchlist.prefix(12) {
                    if let movie = wlItem.movie {
                        if let item = await mapTraktMovieToMediaItem(movie) {
                            items.append(item)
                        }
                    } else if let show = wlItem.show {
                        if let item = await mapTraktShowToMediaItem(show) {
                            items.append(item)
                        }
                    }
                }
                if !items.isEmpty {
                    sections.append(LibrarySection(
                        id: "trakt-watchlist",
                        title: "Your Trakt Watchlist",
                        items: items,
                        totalCount: items.count,
                        libraryKey: nil,
                        browseContext: .trakt(kind: .watchlist)
                    ))
                }
            } catch { print("⚠️ [Home] Trakt watchlist failed: \(error)") }

            // Recently Watched (auth) - fetch movies and shows separately like mobile
            do {
                async let moviesTask = trakt.getHistory(type: "movies", page: 1, limit: 20)
                async let showsTask = trakt.getHistory(type: "shows", page: 1, limit: 20)
                let (moviesHistory, showsHistory) = try await (moviesTask, showsTask)

                // Combine and deduplicate by TMDB ID
                var seenIds = Set<String>()
                var items: [MediaItem] = []

                // Process movies
                for histItem in moviesHistory {
                    if let movie = histItem.movie, let tmdbId = movie.ids.tmdb {
                        let id = "tmdb:movie:\(tmdbId)"
                        if !seenIds.contains(id) {
                            seenIds.insert(id)
                            if let item = await mapTraktMovieToMediaItem(movie) {
                                items.append(item)
                            }
                        }
                    }
                }

                // Process shows
                for histItem in showsHistory {
                    if let show = histItem.show, let tmdbId = show.ids.tmdb {
                        let id = "tmdb:tv:\(tmdbId)"
                        if !seenIds.contains(id) {
                            seenIds.insert(id)
                            if let item = await mapTraktShowToMediaItem(show) {
                                items.append(item)
                            }
                        }
                    }
                }

                // Limit to 12 items
                let limitedItems = Array(items.prefix(12))

                if !limitedItems.isEmpty {
                    sections.append(LibrarySection(
                        id: "trakt-history",
                        title: "Recently Watched",
                        items: limitedItems,
                        totalCount: limitedItems.count,
                        libraryKey: nil,
                        browseContext: .trakt(kind: .history)
                    ))
                }
            } catch { print("⚠️ [Home] Trakt history failed: \(error)") }

            // Recommended for You (auth)
            do {
                let recommended = try await trakt.getRecommendedMovies(limit: 12)
                let items = await mapTraktMoviesToMediaItems(recommended)
                if !items.isEmpty {
                    sections.append(LibrarySection(
                        id: "trakt-recs",
                        title: "Recommended for You",
                        items: items,
                        totalCount: items.count,
                        libraryKey: nil,
                        browseContext: .trakt(kind: .recommendations)
                    ))
                }
            } catch { print("⚠️ [Home] Trakt recommendations failed: \(error)") }
        }

        // Popular TV Shows on Trakt (public)
        do {
            let popularShows = try await trakt.getPopularShows(limit: 12)
            let items = await mapTraktShowsToMediaItems(popularShows)
            if !items.isEmpty {
                sections.append(LibrarySection(
                    id: "trakt-popular-shows",
                    title: "Popular TV Shows on Trakt",
                    items: items,
                    totalCount: items.count,
                    libraryKey: nil,
                    browseContext: .trakt(kind: .popularShows)
                ))
            }
        } catch { print("⚠️ [Home] Trakt popular shows failed: \(error)") }

        return sections
    }

    // Helpers: Trakt mappers
    private func mapTraktMoviesToMediaItems(_ movies: [FlixorKit.TraktMovie]) async -> [MediaItem] {
        var out: [MediaItem] = []
        await withTaskGroup(of: MediaItem?.self) { group in
            for movie in movies {
                group.addTask {
                    return await self.mapTraktMovieToMediaItem(movie)
                }
            }
            for await maybe in group {
                if let m = maybe { out.append(m) }
            }
        }
        return out
    }

    private func mapTraktMovieToMediaItem(_ movie: FlixorKit.TraktMovie) async -> MediaItem? {
        guard let tmdb = movie.ids.tmdb else { return nil }
        async let backdropTask = fetchTMDBBackdrop(mediaType: "movie", id: tmdb)
        async let posterTask = fetchTMDBPoster(mediaType: "movie", id: tmdb)
        let (backdrop, poster) = await (backdropTask, posterTask)
        return MediaItem(
            id: "tmdb:movie:\(tmdb)",
            title: movie.title,
            type: "movie",
            thumb: poster,
            art: backdrop,
            year: movie.year,
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

    private func mapTraktShowsToMediaItems(_ shows: [FlixorKit.TraktShow]) async -> [MediaItem] {
        var out: [MediaItem] = []
        await withTaskGroup(of: MediaItem?.self) { group in
            for show in shows {
                group.addTask {
                    return await self.mapTraktShowToMediaItem(show)
                }
            }
            for await maybe in group {
                if let m = maybe { out.append(m) }
            }
        }
        return out
    }

    private func mapTraktShowToMediaItem(_ show: FlixorKit.TraktShow) async -> MediaItem? {
        guard let tmdb = show.ids.tmdb else { return nil }
        async let backdropTask = fetchTMDBBackdrop(mediaType: "tv", id: tmdb)
        async let posterTask = fetchTMDBPoster(mediaType: "tv", id: tmdb)
        let (backdrop, poster) = await (backdropTask, posterTask)
        return MediaItem(
            id: "tmdb:tv:\(tmdb)",
            title: show.title,
            type: "show",
            thumb: poster,
            art: backdrop,
            year: show.year,
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

    private func fetchTMDBBackdrop(mediaType: String, id: Int) async -> String? {
        do {
            if mediaType == "movie" {
                let detail = try await FlixorCore.shared.tmdb.getMovieDetails(id: id)
                return FlixorCore.shared.tmdb.getBackdropUrl(path: detail.backdropPath, size: "original")
            } else {
                let detail = try await FlixorCore.shared.tmdb.getTVDetails(id: id)
                return FlixorCore.shared.tmdb.getBackdropUrl(path: detail.backdropPath, size: "original")
            }
        } catch {
            return nil
        }
    }

    // MARK: - Fetch Methods

    private func fetchOnDeck() async throws -> [MediaItem] {
        guard let plexServer = FlixorCore.shared.plexServer else { return [] }
        print("📦 [Home] Fetching on deck items...")
        let items = try await plexServer.getOnDeck()
        print("✅ [Home] Received \(items.count) on deck items")
        return items.map { toMediaItem($0) }
    }

    private func fetchContinueWatching() async throws -> [MediaItem] {
        guard let plexServer = FlixorCore.shared.plexServer else { return [] }
        print("📦 [Home] Fetching continue watching items...")
        let result = try await plexServer.getContinueWatching()
        print("✅ [Home] Received \(result.items.count) continue watching items (deduplicated)")

        // Store which items have multiple editions
        self.continueWatchingVersions = result.itemsWithMultipleVersions

        // Enrich with TMDB backdrop URLs before returning
        let baseItems = result.items.map { toMediaItem($0) }
        return await enrichWithTMDBBackdrops(baseItems)
    }

    private func enrichWithTMDBBackdrops(_ items: [MediaItem]) async -> [MediaItem] {
        print("🎨 [Home] Enriching \(items.count) items with TMDB backdrops...")

        return await withTaskGroup(of: (Int, MediaItem).self) { group in
            for (index, item) in items.enumerated() {
                group.addTask {
                    // Try to fetch TMDB backdrop
                    if let backdropURL = try? await self.resolveTMDBBackdropForItem(item) {
                        // Create new MediaItem with TMDB backdrop
                        let enriched = MediaItem(
                            id: item.id,
                            title: item.title,
                            type: item.type,
                            thumb: item.thumb,
                            art: backdropURL, // Replace with TMDB backdrop
                            year: item.year,
                            rating: item.rating,
                            duration: item.duration,
                            viewOffset: item.viewOffset,
                            summary: item.summary,
                            grandparentTitle: item.grandparentTitle,
                            grandparentThumb: item.grandparentThumb,
                            grandparentArt: item.grandparentArt,
                            grandparentRatingKey: item.grandparentRatingKey,
                            parentIndex: item.parentIndex,
                            index: item.index,
                            parentRatingKey: item.parentRatingKey,
                            parentTitle: item.parentTitle,
                            leafCount: item.leafCount,
                            viewedLeafCount: item.viewedLeafCount
                        )
                        return (index, enriched)
                    }
                    // Return original item if TMDB fetch fails
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
            print("✅ [Home] Enriched \(sorted.count) items with TMDB backdrops")
            return sorted
        }
    }

    private func resolveTMDBBackdropForItem(_ item: MediaItem) async throws -> String? {
        guard let plexServer = FlixorCore.shared.plexServer else { return nil }

        print("🔍 [Home] Resolving TMDB backdrop for: \(item.title) (id: \(item.id), type: \(item.type))")

        // Handle plain numeric IDs (assume they're Plex rating keys)
        let normalizedId: String
        if item.id.hasPrefix("plex:") || item.id.hasPrefix("tmdb:") {
            normalizedId = item.id
        } else {
            // Plain numeric ID - treat as Plex rating key
            normalizedId = "plex:\(item.id)"
        }

        if normalizedId.hasPrefix("tmdb:") {
            let parts = normalizedId.split(separator: ":")
            if parts.count == 3 {
                let media = (parts[1] == "movie") ? "movie" : "tv"
                let id = String(parts[2])
                let url = try await fetchTMDBBestBackdropURLString(mediaType: media, id: id)
                print("✅ [Home] TMDB backdrop resolved for \(item.title): \(url ?? "nil")")
                return url
            }
        }

        if normalizedId.hasPrefix("plex:") {
            let rk = String(normalizedId.dropFirst(5))

            do {
                let fullItem = try await plexServer.getMetadata(ratingKey: rk)

                // For TV episodes, fetch the parent series metadata instead
                if fullItem.type == "episode", let grandparentRatingKey = fullItem.grandparentRatingKey {
                    print("📺 [Home] Episode detected, fetching parent series metadata for \(item.title)")
                    let seriesItem = try await plexServer.getMetadata(ratingKey: grandparentRatingKey)

                    // Extract TMDB ID from series Guid array
                    for guidId in seriesItem.guids {
                        if guidId.contains("tmdb://") || guidId.contains("themoviedb://") {
                            if let tmdbId = extractTMDBId(from: guidId) {
                                let url = try await fetchTMDBBestBackdropURLString(mediaType: "tv", id: tmdbId)
                                print("✅ [Home] TMDB backdrop resolved for \(item.title) from series Guid array: \(url ?? "nil")")
                                return url
                            }
                        }
                    }
                    print("⚠️ [Home] No TMDB ID found in series metadata for \(item.title)")
                    return nil
                }

                // For movies and shows, extract TMDB ID from Guid array
                for guidId in fullItem.guids {
                    if guidId.contains("tmdb://") || guidId.contains("themoviedb://") {
                        if let tmdbId = extractTMDBId(from: guidId) {
                            let mediaType = (fullItem.type == "movie") ? "movie" : "tv"
                            let url = try await fetchTMDBBestBackdropURLString(mediaType: mediaType, id: tmdbId)
                            print("✅ [Home] TMDB backdrop resolved for \(item.title) from Guid array: \(url ?? "nil")")
                            return url
                        }
                    }
                }
                print("⚠️ [Home] No TMDB ID found in Guid array for \(item.title)")
            } catch {
                print("❌ [Home] Failed to fetch metadata for \(item.title): \(error)")
            }
        }

        return nil
    }

    private func fetchTMDBBestBackdropURLString(mediaType: String, id: String) async throws -> String? {
        guard let tmdbId = Int(id) else { return nil }

        let imgs = try await FlixorCore.shared.tmdb.getImages(mediaType: mediaType, id: tmdbId)
        let backs = imgs.backdrops
        if backs.isEmpty { return nil }

        let pick: ([FlixorKit.TMDBImage]) -> FlixorKit.TMDBImage? = { arr in
            return arr.sorted(by: { ($0.voteAverage ?? 0) > ($1.voteAverage ?? 0) }).first
        }

        // Priority 1: English backdrops (with title text burned in)
        if let en = pick(backs.filter { $0.iso6391 == "en" }), let path = en.filePath {
            return FlixorCore.shared.tmdb.getBackdropUrl(path: path, size: "original")
        }

        // Priority 2: Any language with title (iso_639_1 is not null)
        if let withLang = pick(backs.filter { $0.iso6391 != nil }), let path = withLang.filePath {
            return FlixorCore.shared.tmdb.getBackdropUrl(path: path, size: "original")
        }

        // Priority 3: Fallback to any backdrop (including textless)
        guard let any = pick(backs), let path = any.filePath else { return nil }
        return FlixorCore.shared.tmdb.getBackdropUrl(path: path, size: "original")
    }

    private func fetchRecentlyAdded() async throws -> [MediaItem] {
        guard let plexServer = FlixorCore.shared.plexServer else { return [] }
        print("📦 [Home] Fetching recently added items...")
        let items = try await plexServer.getRecentlyAdded()
        print("✅ [Home] Received \(items.count) recently added items")
        return items.map { toMediaItem($0) }
    }

    private func fetchLibrarySections() async throws -> [LibrarySection] {
        guard let plexServer = FlixorCore.shared.plexServer else { return [] }

        print("📦 [Home] Fetching libraries...")
        let libraries = try await plexServer.getLibraries()
        print("✅ [Home] Received \(libraries.count) libraries")

        // Filter libraries based on enabled settings
        let filteredLibraries = libraries.filter { isLibraryEnabled($0.key) }
        print("📋 [Home] Enabled libraries: \(filteredLibraries.count) of \(libraries.count)")

        // Fetch items for each enabled library (limit to first 20)
        var sections: [LibrarySection] = []

        for library in filteredLibraries {
            do {
                print("📦 [Home] Fetching items for library: \(library.title)")
                let items = try await plexServer.getLibraryItems(key: library.key, limit: 20)

                if !items.isEmpty {
                    print("✅ [Home] Received \(items.count) items for \(library.title)")
                    sections.append(LibrarySection(
                        id: library.key,
                        title: library.title,
                        items: items.map { toMediaItem($0) },
                        totalCount: items.count,
                        libraryKey: library.key,
                        browseContext: .plexLibrary(key: library.key, title: library.title)
                    ))
                }
            } catch {
                print("⚠️ [Home] Failed to load library \(library.title): \(error)")
                // Continue with other libraries
            }
        }

        return sections
    }

    // MARK: - Billboard Rotation

    private var heroAutoRotate: Bool {
        UserDefaults.standard.heroAutoRotate
    }

    private func startBillboardRotation() {
        guard !billboardItems.isEmpty else { return }

        // Fetch colors for initial item
        Task {
            await fetchHeroColors(for: currentBillboardIndex)
        }

        // Only start timer if auto-rotate is enabled
        guard heroAutoRotate else { return }

        billboardTimer?.invalidate()
        billboardTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                let newIndex = (self.currentBillboardIndex + 1) % self.billboardItems.count
                withAnimation {
                    self.currentBillboardIndex = newIndex
                }
                await self.fetchHeroColors(for: newIndex)
            }
        }
    }

    func stopBillboardRotation() {
        billboardTimer?.invalidate()
        billboardTimer = nil
    }

    func resumeBillboardRotation() {
        guard heroAutoRotate, !billboardItems.isEmpty else { return }

        billboardTimer?.invalidate()
        billboardTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                let newIndex = (self.currentBillboardIndex + 1) % self.billboardItems.count
                withAnimation {
                    self.currentBillboardIndex = newIndex
                }
                await self.fetchHeroColors(for: newIndex)
            }
        }
    }

    // MARK: - UltraBlur Colors

    /// Fetch UltraBlur colors for the current hero/billboard item
    func fetchHeroColors(for index: Int) async {
        guard index >= 0 && index < billboardItems.count else { return }
        let item = billboardItems[index]

        // Get the backdrop URL for this item
        guard let backdropUrl = await resolveHeroBackdropURL(for: item) else {
            print("⚠️ [Home] No backdrop URL for hero colors: \(item.title)")
            return
        }

        let colorKey = "hero:\(backdropUrl)"

        // Skip if already showing colors for this item
        if colorKey == lastHeroColorKey && heroColors != nil {
            return
        }

        // Check cache first
        if let cached = ultraBlurCache[colorKey] {
            lastHeroColorKey = colorKey
            withAnimation(.easeInOut(duration: 0.8)) {
                self.heroColors = cached
            }
            return
        }

        // Fetch from Plex server
        guard let plexServer = FlixorCore.shared.plexServer else { return }

        do {
            if let colors = try await plexServer.getUltraBlurColors(imageUrl: backdropUrl) {
                ultraBlurCache[colorKey] = colors
                lastHeroColorKey = colorKey
                withAnimation(.easeInOut(duration: 0.8)) {
                    self.heroColors = colors
                }
                print("✅ [Home] UltraBlur colors fetched for: \(item.title)")
            }
        } catch {
            print("❌ [Home] Failed to fetch UltraBlur colors: \(error)")
        }
    }

    /// Manually trigger color update (e.g., when user changes billboard)
    func updateHeroColorsForCurrentItem() {
        Task {
            await fetchHeroColors(for: currentBillboardIndex)
        }
    }

    /// Resolve backdrop URL for hero/billboard item (for UltraBlur)
    /// Prefers TMDB backdrop (matches displayed hero image) over Plex art
    private func resolveHeroBackdropURL(for item: MediaItem) async -> String? {
        // Determine cache key (same logic as BillboardView)
        let cacheKey: String
        if item.type == "episode", let seriesKey = item.grandparentRatingKey {
            cacheKey = "series:\(seriesKey)"
        } else if item.type == "season", let seriesKey = item.parentRatingKey {
            cacheKey = "series:\(seriesKey)"
        } else {
            cacheKey = item.id
        }

        // Check BillboardImageCache for TMDB backdrop (matches what hero displays)
        if let cached = BillboardImageCache.shared.get(itemId: cacheKey),
           let tmdbBackdrop = cached.0 {
            print("🎨 [Home] Using cached TMDB backdrop for UltraBlur: \(tmdbBackdrop.absoluteString)")
            return tmdbBackdrop.absoluteString
        }

        // Fall back to Plex art if no TMDB cached
        if let art = item.art {
            if art.hasPrefix("http") {
                return art
            }
            if let plexServer = FlixorCore.shared.plexServer {
                return plexServer.getImageUrl(path: art, width: 1920)
            }
        }

        // For episodes, try grandparent art (show backdrop)
        if item.type == "episode", let grandparentArt = item.grandparentArt {
            if grandparentArt.hasPrefix("http") {
                return grandparentArt
            }
            if let plexServer = FlixorCore.shared.plexServer {
                return plexServer.getImageUrl(path: grandparentArt, width: 1920)
            }
        }

        // Try thumb as fallback
        if let thumb = item.thumb {
            if thumb.hasPrefix("http") {
                return thumb
            }
            if let plexServer = FlixorCore.shared.plexServer {
                return plexServer.getImageUrl(path: thumb, width: 1920)
            }
        }

        return nil
    }

    // MARK: - Navigation

    func playItem(_ item: MediaItem) {
        pendingAction = .play(item)
    }

    func showItemDetails(_ item: MediaItem) {
        pendingAction = .details(item)
    }

    func toggleMyList(_ item: MediaItem) {
        // TODO: Add/remove from watchlist
        print("Toggle My List: \(item.title)")
    }

    // MARK: - Cleanup

    deinit {
        billboardTimer?.invalidate()
    }
}

// MARK: - Navigation Actions

enum HomeAction {
    case play(MediaItem)
    case details(MediaItem)
}

extension HomeAction: Equatable {
    static func == (lhs: HomeAction, rhs: HomeAction) -> Bool {
        switch (lhs, rhs) {
        case (.play(let a), .play(let b)): return a.id == b.id
        case (.details(let a), .details(let b)): return a.id == b.id
        default: return false
        }
    }
}
