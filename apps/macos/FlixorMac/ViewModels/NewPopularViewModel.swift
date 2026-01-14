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

    // MARK: - Public Methods

    func load() async {
        isLoading = true
        errorMessage = nil

        do {
            switch activeTab {
            case .trending:
                await loadTrendingContent()
            case .top10:
                await loadTop10Content()
            case .comingSoon:
                await loadComingSoonContent()
            case .worthWait:
                await loadWorthWaitContent()
            }
        } catch {
            print("❌ [NewPopular] Error loading content: \(error)")
            errorMessage = "Failed to load content. Please try again."
        }

        isLoading = false
    }

    // MARK: - Private Loading Methods

    private func loadTrendingContent() async {
        do {
            // Fetch all data in parallel
            async let moviesTask = apiClient.getTMDBTrending(mediaType: "movie", timeWindow: period.timeWindow)
            async let showsTask = apiClient.getTMDBTrending(mediaType: "tv", timeWindow: period.timeWindow)
            async let recentTask = fetchPlexRecentlyAdded()
            async let popularTask = fetchPlexPopular()

            let (moviesRes, showsRes, recentRes, popularRes) = try await (moviesTask, showsTask, recentTask, popularTask)

            // Map trending movies
            trendingMovies = moviesRes.results.prefix(20).map { item in
                DisplayMediaItem(
                    id: "tmdb:movie:\(item.id)",
                    title: item.title ?? "Unknown",
                    imageURL: item.poster_path != nil ? URL(string: "\(imageBaseURL)w342\(item.poster_path!)") : nil,
                    subtitle: item.release_date?.split(separator: "-").first.map(String.init),
                    badge: item.vote_average.map { "⭐ \(String(format: "%.1f", $0))" },
                    rank: nil,
                    mediaType: "movie",
                    artPath: nil  // TMDB items use API for backdrop
                )
            }

            // Map trending shows
            trendingShows = showsRes.results.prefix(20).map { item in
                DisplayMediaItem(
                    id: "tmdb:tv:\(item.id)",
                    title: item.name ?? "Unknown",
                    imageURL: item.poster_path != nil ? URL(string: "\(imageBaseURL)w342\(item.poster_path!)") : nil,
                    subtitle: item.first_air_date?.split(separator: "-").first.map(String.init),
                    badge: item.vote_average.map { "⭐ \(String(format: "%.1f", $0))" },
                    rank: nil,
                    mediaType: "tv",
                    artPath: nil  // TMDB items use API for backdrop
                )
            }

            recentlyAdded = recentRes
            popularPlex = popularRes

            // Load hero from top trending movie
            if let topItem = moviesRes.results.first {
                await loadHero(tmdbId: topItem.id, mediaType: "movie", topItem: topItem)
            }

        } catch {
            print("❌ [NewPopular] Error loading trending content: \(error)")
            errorMessage = "Failed to load trending content"
        }
    }

    private func loadTop10Content() async {
        do {
            // Fetch top 10 from Trakt
            let traktPeriod = period.traktPeriod
            async let moviesTask = apiClient.getTraktMostWatched(media: "movies", period: traktPeriod, limit: 10)
            async let showsTask = apiClient.getTraktMostWatched(media: "shows", period: traktPeriod, limit: 10)

            let (moviesRes, showsRes) = try await (moviesTask, showsTask)

            // Fetch TMDB details for images
            var items: [DisplayMediaItem] = []

            // Process movies
            for (index, item) in moviesRes.prefix(10).enumerated() {
                guard let movie = item.movie, let tmdbId = movie.ids.tmdb else { continue }

                var imageURL: URL?
                do {
                    let details = try await apiClient.getTMDBMovieDetails(id: String(tmdbId))
                    if let posterPath = details.poster_path {
                        imageURL = URL(string: "\(imageBaseURL)w342\(posterPath)")
                    }
                } catch {
                    print("⚠️ [NewPopular] Failed to fetch movie details for \(movie.title)")
                }

                items.append(DisplayMediaItem(
                    id: "tmdb:movie:\(tmdbId)",
                    title: movie.title,
                    imageURL: imageURL,
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

                var imageURL: URL?
                do {
                    let details = try await apiClient.getTMDBTVDetails(id: String(tmdbId))
                    if let posterPath = details.poster_path {
                        imageURL = URL(string: "\(imageBaseURL)w342\(posterPath)")
                    }
                } catch {
                    print("⚠️ [NewPopular] Failed to fetch TV details for \(show.title)")
                }

                items.append(DisplayMediaItem(
                    id: "tmdb:tv:\(tmdbId)",
                    title: show.title,
                    imageURL: imageURL,
                    subtitle: show.year.map(String.init),
                    badge: "#\(index + 1 + items.count)",
                    rank: index + 1 + items.count,
                    mediaType: "tv",
                    artPath: nil
                ))
            }

            // Combine and sort by rank
            top10 = items.sorted { ($0.rank ?? 0) < ($1.rank ?? 0) }.prefix(10).map { $0 }

        } catch {
            print("❌ [NewPopular] Error loading top 10 content: \(error)")
            errorMessage = "Failed to load top 10 content"
        }
    }

    private func loadComingSoonContent() async {
        do {
            let upcomingRes = try await apiClient.getTMDBUpcoming(region: "US", page: 1)

            upcoming = upcomingRes.results.map { item in
                DisplayMediaItem(
                    id: "tmdb:movie:\(item.id)",
                    title: item.title ?? "Unknown",
                    imageURL: item.poster_path != nil ? URL(string: "\(imageBaseURL)w342\(item.poster_path!)") : nil,
                    subtitle: item.release_date.map { formatReleaseDate($0) },
                    badge: "Coming Soon",
                    rank: nil,
                    mediaType: "movie",
                    artPath: nil
                )
            }

        } catch {
            print("❌ [NewPopular] Error loading upcoming content: \(error)")
            errorMessage = "Failed to load upcoming content"
        }
    }

    private func loadWorthWaitContent() async {
        do {
            let anticipatedRes = try await apiClient.getTraktAnticipated(media: "movies", limit: 20)

            // Fetch TMDB details for images
            var items: [DisplayMediaItem] = []

            for item in anticipatedRes {
                guard let movie = item.movie, let tmdbId = movie.ids.tmdb else { continue }

                var imageURL: URL?
                do {
                    let details = try await apiClient.getTMDBMovieDetails(id: String(tmdbId))
                    if let posterPath = details.poster_path {
                        imageURL = URL(string: "\(imageBaseURL)w342\(posterPath)")
                    }
                } catch {
                    print("⚠️ [NewPopular] Failed to fetch movie details for \(movie.title)")
                }

                items.append(DisplayMediaItem(
                    id: "tmdb:movie:\(tmdbId)",
                    title: movie.title,
                    imageURL: imageURL,
                    subtitle: movie.year.map(String.init),
                    badge: "\(item.list_count) lists",
                    rank: nil,
                    mediaType: "movie",
                    artPath: nil
                ))
            }

            anticipated = items

        } catch {
            print("❌ [NewPopular] Error loading anticipated content: \(error)")
            errorMessage = "Failed to load anticipated content"
        }
    }

    private func loadHero(tmdbId: Int, mediaType: String, topItem: TMDBMediaItem) async {
        do {
            // Fetch details, videos, and images in parallel
            async let videosTask = apiClient.getTMDBVideos(mediaType: mediaType, id: String(tmdbId))
            async let imagesTask = apiClient.getTMDBImages(mediaType: mediaType, id: String(tmdbId))

            let (videos, images) = try await (videosTask, imagesTask)

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
            var runtime: Int?
            var genres: [String] = []

            if mediaType == "movie" {
                let details = try await apiClient.getTMDBMovieDetails(id: String(tmdbId))
                runtime = details.runtime
                genres = details.genres?.map { $0.name } ?? []
            } else {
                let details = try await apiClient.getTMDBTVDetails(id: String(tmdbId))
                runtime = details.episode_run_time?.first
                genres = details.genres?.map { $0.name } ?? []
            }

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
                title: topItem.title ?? topItem.name ?? "Unknown",
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
        do {
            let items = try await apiClient.getPlexRecentlyAdded(days: 7)

            return items.prefix(20).map { item in
                // Use art field for backdrop fallback
                return DisplayMediaItem(
                    id: "plex:\(item.ratingKey)",
                    title: item.title ?? item.grandparentTitle ?? "Unknown",
                    imageURL: ImageService.shared.plexImageURL(path: item.thumb, width: 342),
                    subtitle: item.year.map(String.init),
                    badge: "New",
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

            var allItems: [PlexMediaItem] = []

            // Fetch from each movie/show library
            for library in dirs where library.type == "movie" || library.type == "show" {
                print("📁 [NewPopular] Processing library: \(library.title ?? library.key) (type: \(library.type))")
                let typeNum = library.type == "movie" ? 1 : 2

                // Try lastViewedAt first
                var response: PlexLibraryResponse? = nil
                do {
                    response = try await apiClient.getPlexLibraryAll(
                        sectionKey: library.key,
                        type: typeNum,
                        sort: "lastViewedAt:desc",
                        limit: 50
                    )
                    print("✅ [NewPopular] Got lastViewedAt response with \(response?.Metadata?.count ?? 0) items")
                } catch {
                    print("⚠️ [NewPopular] lastViewedAt failed for \(library.key): \(error), trying viewCount")
                    do {
                        response = try await apiClient.getPlexLibraryAll(
                            sectionKey: library.key,
                            type: typeNum,
                            sort: "viewCount:desc",
                            limit: 50
                        )
                        print("✅ [NewPopular] Got viewCount response with \(response?.Metadata?.count ?? 0) items")
                    } catch {
                        print("❌ [NewPopular] viewCount also failed for \(library.key): \(error)")
                    }
                }

                if let items = response?.Metadata {
                    print("📊 [NewPopular] Adding \(items.count) items from library \(library.key)")
                    allItems.append(contentsOf: items)
                }
            }

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
                    title: item.title ?? item.grandparentTitle ?? "Unknown",
                    imageURL: ImageService.shared.plexImageURL(path: thumb, width: 342),
                    subtitle: item.year.map(String.init),
                    badge: "Popular",
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
