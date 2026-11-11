//
//  NewPopularViewModel.swift
//  FlixorMac
//
//  ViewModel for New & Popular screen
//

import Foundation
import SwiftUI

@MainActor
class NewPopularViewModel: ObservableObject {
    // MARK: - Tab Types

    enum Tab: String, CaseIterable, Identifiable {
        case trending = "Trending Now"
        case top10 = "Top 10"
        case comingSoon = "Coming Soon"
        case worthWait = "Worth the Wait"

        var id: String { rawValue }
    }

    // MARK: - Filter Types

    enum ContentType: String, CaseIterable, Identifiable {
        case all = "All"
        case movies = "Movies"
        case shows = "TV Shows"

        var id: String { rawValue }
    }

    enum Period: String, CaseIterable, Identifiable {
        case daily = "Today"
        case weekly = "This Week"
        case monthly = "This Month"

        var id: String { rawValue }

        // Map to API time window
        var timeWindow: String {
            switch self {
            case .daily: return "day"
            case .weekly, .monthly: return "week"
            }
        }

        // Map to Trakt period
        var traktPeriod: String {
            switch self {
            case .daily: return "daily"
            case .weekly: return "weekly"
            case .monthly: return "monthly"
            }
        }
    }

    // MARK: - Published State

    @Published var activeTab: Tab = .trending
    @Published var contentType: ContentType = .all
    @Published var period: Period = .weekly
    @Published var isLoading = false
    @Published var errorMessage: String?

    // Hero Data
    @Published var hero: HeroData?

    // Content Rows
    @Published var trendingMovies: [DisplayMediaItem] = []
    @Published var trendingShows: [DisplayMediaItem] = []
    @Published var recentlyAdded: [DisplayMediaItem] = []
    @Published var popularPlex: [DisplayMediaItem] = []
    @Published var top10: [DisplayMediaItem] = []
    @Published var upcoming: [DisplayMediaItem] = []
    @Published var anticipated: [DisplayMediaItem] = []

    // MARK: - Private Properties

    private let apiClient = APIClient.shared
    private let imageBaseURL = "https://image.tmdb.org/t/p/"

    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0
    /// When each sub-tab (with the period it was loaded for) last loaded successfully.
    private var loadedAt: [String: Date] = [:]
    /// Older content is refetched by loadIfNeeded, keeping it on screen meanwhile.
    private let freshnessWindow: TimeInterval = 15 * 60
    /// Concurrent TMDB detail requests for the Top 10 and Worth the Wait posters.
    private let detailsBatchSize = 10

    private func loadKey(for tab: Tab) -> String {
        switch tab {
        case .trending, .top10: return "\(tab.rawValue)|\(period.rawValue)"
        case .comingSoon, .worthWait: return tab.rawValue
        }
    }

    // MARK: - Public Methods

    /// Loads the active sub-tab unless it loaded for the current period within
    /// the freshness window.
    func loadIfNeeded() async {
        if let loaded = loadedAt[loadKey(for: activeTab)],
           Date().timeIntervalSince(loaded) < freshnessWindow {
            // Drop a load still running for another sub-tab.
            loadTask?.cancel()
            loadGeneration += 1
            isLoading = false
            errorMessage = nil
            return
        }
        await load()
    }

    /// Always refetches the active sub-tab. A newer load supersedes this one.
    func load() async {
        loadTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        let tab = activeTab
        let key = loadKey(for: tab)

        // A new period: don't show the previous period's rows meanwhile.
        // A refresh of loaded content keeps it on screen.
        if loadedAt[key] == nil {
            switch tab {
            case .trending:
                trendingMovies = []
                trendingShows = []
            case .top10:
                top10 = []
            case .comingSoon, .worthWait:
                break
            }
        }

        isLoading = true
        errorMessage = nil

        let task = Task { [weak self] in
            guard let self else { return }
            let succeeded: Bool
            switch tab {
            case .trending:
                succeeded = await self.loadTrendingContent(generation: generation)
            case .top10:
                succeeded = await self.loadTop10Content(generation: generation)
            case .comingSoon:
                succeeded = await self.loadComingSoonContent(generation: generation)
            case .worthWait:
                succeeded = await self.loadWorthWaitContent(generation: generation)
            }
            guard self.isCurrent(generation) else { return }
            if succeeded {
                self.loadedAt[key] = Date()
            }
            self.isLoading = false
        }
        loadTask = task
        await task.value
    }

    private func isCurrent(_ generation: Int) -> Bool {
        !Task.isCancelled && generation == loadGeneration
    }

    // MARK: - Private Loading Methods

    private enum TrendingPart {
        case movies(TMDBTrendingResponse)
        case shows(TMDBTrendingResponse)
        case recent([DisplayMediaItem])
        case popular([DisplayMediaItem])
        case failed(Error)
        case hero
    }

    /// Each row is shown as soon as its request returns; the hero loads alongside.
    private func loadTrendingContent(generation: Int) async -> Bool {
        let timeWindow = period.timeWindow
        let api = apiClient
        return await withTaskGroup(of: TrendingPart.self) { group -> Bool in
            group.addTask {
                do { return .movies(try await api.getTMDBTrending(mediaType: "movie", timeWindow: timeWindow)) } catch { return .failed(error) }
            }
            group.addTask {
                do { return .shows(try await api.getTMDBTrending(mediaType: "tv", timeWindow: timeWindow)) } catch { return .failed(error) }
            }
            group.addTask { [weak self] in
                .recent((try? await self?.fetchPlexRecentlyAdded()) ?? [])
            }
            group.addTask { [weak self] in
                .popular((try? await self?.fetchPlexPopular()) ?? [])
            }

            var failed = false
            while let part = await group.next() {
                guard isCurrent(generation) else { continue }
                switch part {
                case .movies(let moviesRes):
                    trendingMovies = moviesRes.results.prefix(20).map { item in
                        DisplayMediaItem(
                            id: "tmdb:movie:\(item.id)",
                            title: item.title ?? String(localized: "Unknown"),
                            imageURL: item.poster_path != nil ? URL(string: "\(imageBaseURL)w342\(item.poster_path!)") : nil,
                            subtitle: item.release_date?.split(separator: "-").first.map(String.init),
                            badge: item.vote_average.map { "⭐ \(String(format: "%.1f", $0))" },
                            rank: nil,
                            mediaType: "movie",
                            artPath: nil  // TMDB items use API for backdrop
                        )
                    }
                    // Load hero from top trending movie
                    if let topItem = moviesRes.results.first {
                        group.addTask { [weak self] in
                            await self?.loadHero(tmdbId: topItem.id, mediaType: "movie", topItem: topItem, generation: generation)
                            return .hero
                        }
                    }
                case .shows(let showsRes):
                    trendingShows = showsRes.results.prefix(20).map { item in
                        DisplayMediaItem(
                            id: "tmdb:tv:\(item.id)",
                            title: item.name ?? String(localized: "Unknown"),
                            imageURL: item.poster_path != nil ? URL(string: "\(imageBaseURL)w342\(item.poster_path!)") : nil,
                            subtitle: item.first_air_date?.split(separator: "-").first.map(String.init),
                            badge: item.vote_average.map { "⭐ \(String(format: "%.1f", $0))" },
                            rank: nil,
                            mediaType: "tv",
                            artPath: nil  // TMDB items use API for backdrop
                        )
                    }
                case .recent(let items):
                    recentlyAdded = items
                case .popular(let items):
                    popularPlex = items
                case .failed(let error):
                    guard !(error is CancellationError) else { continue }
                    failed = true
                    print("❌ [NewPopular] Error loading trending content: \(error)")
                    errorMessage = String(localized: "Failed to load trending content")
                case .hero:
                    continue
                }
            }
            return !failed
        }
    }

    /// TMDB poster URLs for the given ids, fetched in bounded parallel batches.
    private func fetchPosters(ids: [Int], isMovie: Bool) async -> [Int: URL] {
        let api = apiClient
        let base = imageBaseURL
        var posters: [Int: URL] = [:]
        for start in stride(from: 0, to: ids.count, by: detailsBatchSize) {
            if Task.isCancelled { break }
            let batch = ids[start..<min(start + detailsBatchSize, ids.count)]
            await withTaskGroup(of: (Int, URL?).self) { group in
                for id in Set(batch) {
                    group.addTask {
                        do {
                            let posterPath: String?
                            if isMovie {
                                posterPath = try await api.getTMDBMovieDetails(id: String(id)).poster_path
                            } else {
                                posterPath = try await api.getTMDBTVDetails(id: String(id)).poster_path
                            }
                            return (id, posterPath.flatMap { URL(string: "\(base)w342\($0)") })
                        } catch {
                            print("⚠️ [NewPopular] Failed to fetch \(isMovie ? "movie" : "TV") details for \(id)")
                            return (id, nil)
                        }
                    }
                }
                for await (id, url) in group {
                    if let url { posters[id] = url }
                }
            }
        }
        return posters
    }

    private func loadTop10Content(generation: Int) async -> Bool {
        do {
            // Fetch top 10 from Trakt
            let traktPeriod = period.traktPeriod
            async let moviesTask = apiClient.getTraktMostWatched(media: "movies", period: traktPeriod, limit: 10)
            async let showsTask = apiClient.getTraktMostWatched(media: "shows", period: traktPeriod, limit: 10)

            let (moviesRes, showsRes) = try await (moviesTask, showsTask)

            // Fetch TMDB details for images
            async let moviePostersTask = fetchPosters(ids: moviesRes.prefix(10).compactMap { $0.movie?.ids.tmdb }, isMovie: true)
            async let showPostersTask = fetchPosters(ids: showsRes.prefix(10).compactMap { $0.show?.ids.tmdb }, isMovie: false)
            let (moviePosters, showPosters) = await (moviePostersTask, showPostersTask)
            guard isCurrent(generation) else { return false }

            var items: [DisplayMediaItem] = []

            // Process movies
            for (index, item) in moviesRes.prefix(10).enumerated() {
                guard let movie = item.movie, let tmdbId = movie.ids.tmdb else { continue }
                items.append(DisplayMediaItem(
                    id: "tmdb:movie:\(tmdbId)",
                    title: movie.title,
                    imageURL: moviePosters[tmdbId],
                    subtitle: movie.year.map(String.init),
                    badge: "#\(index + 1)",
                    rank: index + 1,
                    mediaType: "movie",
                    artPath: nil
                ))
            }

            // Process shows
            for (index, item) in showsRes.prefix(10).enumerated() {
                guard let show = item.show, let tmdbId = show.ids.tmdb else { continue }
                items.append(DisplayMediaItem(
                    id: "tmdb:tv:\(tmdbId)",
                    title: show.title,
                    imageURL: showPosters[tmdbId],
                    subtitle: show.year.map(String.init),
                    badge: "#\(index + 1 + items.count)",
                    rank: index + 1 + items.count,
                    mediaType: "tv",
                    artPath: nil
                ))
            }

            // Combine and sort by rank
            top10 = items.sorted { ($0.rank ?? 0) < ($1.rank ?? 0) }.prefix(10).map { $0 }
            return true

        } catch {
            guard isCurrent(generation), !(error is CancellationError) else { return false }
            print("❌ [NewPopular] Error loading top 10 content: \(error)")
            errorMessage = String(localized: "Failed to load top 10 content")
            return false
        }
    }

    private func loadComingSoonContent(generation: Int) async -> Bool {
        do {
            let upcomingRes = try await apiClient.getTMDBUpcoming(region: "US", page: 1)
            guard isCurrent(generation) else { return false }

            upcoming = upcomingRes.results.map { item in
                DisplayMediaItem(
                    id: "tmdb:movie:\(item.id)",
                    title: item.title ?? String(localized: "Unknown"),
                    imageURL: item.poster_path != nil ? URL(string: "\(imageBaseURL)w342\(item.poster_path!)") : nil,
                    subtitle: item.release_date.map { formatReleaseDate($0) },
                    badge: String(localized: "Coming Soon"),
                    rank: nil,
                    mediaType: "movie",
                    artPath: nil
                )
            }
            return true

        } catch {
            guard isCurrent(generation), !(error is CancellationError) else { return false }
            print("❌ [NewPopular] Error loading upcoming content: \(error)")
            errorMessage = String(localized: "Failed to load upcoming content")
            return false
        }
    }

    private func loadWorthWaitContent(generation: Int) async -> Bool {
        do {
            let anticipatedRes = try await apiClient.getTraktAnticipated(media: "movies", limit: 20)

            // Fetch TMDB details for images
            let posters = await fetchPosters(ids: anticipatedRes.compactMap { $0.movie?.ids.tmdb }, isMovie: true)
            guard isCurrent(generation) else { return false }

            var items: [DisplayMediaItem] = []
            for item in anticipatedRes {
                guard let movie = item.movie, let tmdbId = movie.ids.tmdb else { continue }
                items.append(DisplayMediaItem(
                    id: "tmdb:movie:\(tmdbId)",
                    title: movie.title,
                    imageURL: posters[tmdbId],
                    subtitle: movie.year.map(String.init),
                    badge: String(localized: "\(item.list_count) lists"),
                    rank: nil,
                    mediaType: "movie",
                    artPath: nil
                ))
            }

            anticipated = items
            return true

        } catch {
            guard isCurrent(generation), !(error is CancellationError) else { return false }
            print("❌ [NewPopular] Error loading anticipated content: \(error)")
            errorMessage = String(localized: "Failed to load anticipated content")
            return false
        }
    }

    private func fetchHeroDetails(mediaType: String, tmdbId: Int) async throws -> (runtime: Int?, genres: [String]) {
        if mediaType == "movie" {
            let details = try await apiClient.getTMDBMovieDetails(id: String(tmdbId))
            return (details.runtime, details.genres?.map { $0.name } ?? [])
        } else {
            let details = try await apiClient.getTMDBTVDetails(id: String(tmdbId))
            return (details.episode_run_time?.first, details.genres?.map { $0.name } ?? [])
        }
    }

    private func loadHero(tmdbId: Int, mediaType: String, topItem: TMDBMediaItem, generation: Int) async {
        do {
            // Fetch details, videos, and images in parallel
            async let videosTask = apiClient.getTMDBVideos(mediaType: mediaType, id: String(tmdbId))
            async let imagesTask = apiClient.getTMDBImages(mediaType: mediaType, id: String(tmdbId))
            async let detailsTask = fetchHeroDetails(mediaType: mediaType, tmdbId: tmdbId)

            let (videos, images, details) = try await (videosTask, imagesTask, detailsTask)
            guard isCurrent(generation) else { return }

            // Find trailer
            let trailer = videos.results.first { $0.type == "Trailer" && $0.site == "YouTube" }

            // Find logo with priority: English > null language > any
            let logos = images.logos ?? []
            let logo = logos.first { $0.iso_639_1 == "en" }
                ?? logos.first { $0.iso_639_1 == nil }
                ?? logos.first

            // Find backdrop with priority: Textless (null) preferred for hero since we overlay title/logo
            let backdrops = images.backdrops ?? []
            func pickBestBackdrop(_ arr: [TMDBImage]) -> TMDBImage? {
                arr.sorted(by: { (a: TMDBImage, b: TMDBImage) in (a.vote_average ?? 0) > (b.vote_average ?? 0) }).first
            }
            let bestBackdrop = pickBestBackdrop(backdrops.filter { $0.iso_639_1 == nil })
                ?? pickBestBackdrop(backdrops)

            // Get detailed info
            let runtime = details.runtime
            let genres = details.genres

            // Check if available on Plex
            let heroId = "tmdb:\(mediaType):\(tmdbId)"
            let canPlay = false // TODO: Implement Plex availability check

            // Use best backdrop from images API, fallback to trending item backdrop
            let backdropURL: URL?
            if let backdropPath = bestBackdrop?.file_path {
                backdropURL = URL(string: "\(imageBaseURL)original\(backdropPath)")
            } else if let path = topItem.backdrop_path {
                backdropURL = URL(string: "\(imageBaseURL)original\(path)")
            } else {
                backdropURL = nil
            }

            hero = HeroData(
                id: heroId,
                title: topItem.title ?? topItem.name ?? String(localized: "Unknown"),
                overview: topItem.overview ?? "",
                backdropURL: backdropURL,
                posterURL: topItem.poster_path != nil ? URL(string: "\(imageBaseURL)w500\(topItem.poster_path!)") : nil,
                rating: topItem.vote_average.map { "⭐ \(String(format: "%.1f", $0))" },
                year: (topItem.release_date ?? topItem.first_air_date)?.split(separator: "-").first.map(String.init),
                runtime: runtime,
                genres: genres,
                ytKey: trailer?.key,
                logoURL: logo?.file_path != nil ? URL(string: "\(imageBaseURL)w500\(logo!.file_path)") : nil,
                canPlay: canPlay,
                mediaType: mediaType
            )

        } catch {
            print("❌ [NewPopular] Error loading hero: \(error)")
        }
    }

    // MARK: - Helper Methods

    private func fetchPlexRecentlyAdded() async throws -> [DisplayMediaItem] {
        // No Plex server in Stremio-only mode - skip instead of failing per load.
        guard !AppModeStore.shared.isStremioOnly else { return [] }
        do {
            let items = try await apiClient.getPlexRecentlyAdded(days: 7)

            return items.prefix(20).map { item in
                // Use art field for backdrop fallback
                return DisplayMediaItem(
                    id: "plex:\(item.ratingKey)",
                    title: item.title ?? item.grandparentTitle ?? String(localized: "Unknown"),
                    imageURL: ImageService.shared.plexImageURL(path: item.thumb, width: 342),
                    subtitle: item.year.map(String.init),
                    badge: String(localized: "New"),
                    rank: nil,
                    mediaType: item.type == "movie" ? "movie" : "tv",
                    artPath: item.art
                )
            }
        } catch {
            print("⚠️ [NewPopular] Failed to fetch Plex recently added: \(error)")
            return []
        }
    }

    private func fetchPlexPopular() async throws -> [DisplayMediaItem] {
        guard !AppModeStore.shared.isStremioOnly else { return [] }
        print("🔍 [NewPopular] Starting fetchPlexPopular")
        do {
            // Fetch libraries
            let libraries = try await apiClient.getPlexLibraries()
            print("📚 [NewPopular] Got libraries: \(libraries.count) directories")
            guard !libraries.isEmpty else {
                print("⚠️ [NewPopular] No directories found")
                return []
            }
            let dirs = libraries

            // Fetch from each movie/show library in parallel, keeping library order
            let mediaLibraries = dirs.filter { $0.type == "movie" || $0.type == "show" }
            let api = apiClient
            let perLibrary = await withTaskGroup(of: (Int, [PlexMediaItem]).self) { group -> [[PlexMediaItem]] in
                for (index, library) in mediaLibraries.enumerated() {
                    let key = library.key
                    let typeNum = library.type == "movie" ? 1 : 2
                    group.addTask {
                        // Try lastViewedAt first
                        var response: PlexLibraryResponse? = nil
                        do {
                            response = try await api.getPlexLibraryAll(
                                sectionKey: key,
                                type: typeNum,
                                sort: "lastViewedAt:desc",
                                limit: 50
                            )
                        } catch {
                            print("⚠️ [NewPopular] lastViewedAt failed for \(key): \(error), trying viewCount")
                            do {
                                response = try await api.getPlexLibraryAll(
                                    sectionKey: key,
                                    type: typeNum,
                                    sort: "viewCount:desc",
                                    limit: 50
                                )
                            } catch {
                                print("❌ [NewPopular] viewCount also failed for \(key): \(error)")
                            }
                        }
                        return (index, response?.Metadata ?? [])
                    }
                }
                var results = Array(repeating: [PlexMediaItem](), count: mediaLibraries.count)
                for await (index, items) in group {
                    results[index] = items
                }
                return results
            }
            let allItems = perLibrary.flatMap { $0 }

            print("📊 [NewPopular] Total items collected: \(allItems.count)")

            // Score items based on lastViewedAt and viewCount
            let scored = allItems.map { item -> (item: PlexMediaItem, score: Int) in
                let lv = item.lastViewedAt ?? 0
                let vc = item.viewCount ?? 0
                let score = lv * 10 + vc
                return (item, score)
            }

            // Sort by score and take top 20
            let topItems = scored.sorted { $0.score > $1.score }.prefix(20)
            print("🏆 [NewPopular] Top 20 items selected, scores range: \(topItems.first?.score ?? 0) to \(topItems.last?.score ?? 0)")

            let result = topItems.map { tuple in
                let item = tuple.item
                let thumb = item.thumb ?? item.parentThumb ?? item.grandparentThumb

                return DisplayMediaItem(
                    id: "plex:\(item.ratingKey)",
                    title: item.title ?? item.grandparentTitle ?? String(localized: "Unknown"),
                    imageURL: ImageService.shared.plexImageURL(path: thumb, width: 342),
                    subtitle: item.year.map(String.init),
                    badge: String(localized: "Popular"),
                    rank: nil,
                    mediaType: item.type == "movie" ? "movie" : "tv",
                    artPath: item.art
                )
            }

            print("✅ [NewPopular] Returning \(result.count) popular items")
            return result

        } catch {
            print("❌ [NewPopular] Failed to fetch Plex popular: \(error)")
            return []
        }
    }

    private func formatReleaseDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else {
            return dateString
        }

        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}
