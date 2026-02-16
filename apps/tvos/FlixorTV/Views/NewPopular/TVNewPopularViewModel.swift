import Foundation
import SwiftUI
import FlixorKit

@MainActor
final class TVNewPopularViewModel: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case trending = "Trending"
        case top10 = "Top 10"
        case comingSoon = "Coming Soon"
        case worthWait = "Worth the Wait"

        var id: String { rawValue }
    }

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

        var timeWindow: String {
            switch self {
            case .daily: return "day"
            case .weekly, .monthly: return "week"
            }
        }

        var traktPeriod: String {
            switch self {
            case .daily: return "daily"
            case .weekly: return "weekly"
            case .monthly: return "monthly"
            }
        }
    }

    struct HeroData {
        let id: String
        let title: String
        let overview: String
        let backdropURL: URL?
        let posterURL: URL?
        let rating: String?
        let year: String?
        let runtime: Int?
        let genres: [String]
        let ytKey: String?
        let logoURL: URL?
        let canPlay: Bool
        let mediaType: String
    }

    struct DisplayMediaItem: Identifiable {
        let id: String
        let title: String
        let imageURL: URL?
        let subtitle: String?
        let badge: String?
        let rank: Int?
        let mediaType: String
        let artPath: String?

        func toMediaItem() -> MediaItem {
            MediaItem(
                id: id,
                title: title,
                type: mediaType == "tv" ? "show" : "movie",
                thumb: imageURL?.absoluteString,
                art: artPath,
                year: subtitle.flatMap(Int.init),
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
        }
    }

    @Published var activeTab: Tab = .trending
    @Published var contentType: ContentType = .all
    @Published var period: Period = .weekly
    @Published var isLoading = false
    @Published var errorMessage: String?

    @Published var hero: HeroData?
    @Published var trendingMovies: [DisplayMediaItem] = []
    @Published var trendingShows: [DisplayMediaItem] = []
    @Published var recentlyAdded: [DisplayMediaItem] = []
    @Published var popularPlex: [DisplayMediaItem] = []
    @Published var top10: [DisplayMediaItem] = []
    @Published var upcoming: [DisplayMediaItem] = []
    @Published var anticipated: [DisplayMediaItem] = []

    private let apiClient = APIClient.shared
    private let imageBaseURL = "https://image.tmdb.org/t/p/"

    func load() async {
        isLoading = true
        errorMessage = nil

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

        isLoading = false
    }

    private func loadTrendingContent() async {
        do {
            async let moviesTask = apiClient.getTMDBTrending(mediaType: "movie", timeWindow: period.timeWindow)
            async let showsTask = apiClient.getTMDBTrending(mediaType: "tv", timeWindow: period.timeWindow)
            async let recentTask = fetchPlexRecentlyAdded()
            async let popularTask = fetchPlexPopular()

            let (moviesRes, showsRes, recentRes, popularRes) = try await (moviesTask, showsTask, recentTask, popularTask)

            trendingMovies = moviesRes.results.prefix(20).map { item in
                DisplayMediaItem(
                    id: "tmdb:movie:\(item.id)",
                    title: item.title ?? "Unknown",
                    imageURL: item.poster_path != nil ? URL(string: "\(imageBaseURL)w342\(item.poster_path!)") : nil,
                    subtitle: item.release_date?.split(separator: "-").first.map(String.init),
                    badge: item.vote_average.map { "⭐ \(String(format: "%.1f", $0))" },
                    rank: nil,
                    mediaType: "movie",
                    artPath: nil
                )
            }

            trendingShows = showsRes.results.prefix(20).map { item in
                DisplayMediaItem(
                    id: "tmdb:tv:\(item.id)",
                    title: item.name ?? "Unknown",
                    imageURL: item.poster_path != nil ? URL(string: "\(imageBaseURL)w342\(item.poster_path!)") : nil,
                    subtitle: item.first_air_date?.split(separator: "-").first.map(String.init),
                    badge: item.vote_average.map { "⭐ \(String(format: "%.1f", $0))" },
                    rank: nil,
                    mediaType: "tv",
                    artPath: nil
                )
            }

            recentlyAdded = recentRes
            popularPlex = popularRes

            if let topMovie = moviesRes.results.first {
                await loadHero(tmdbId: topMovie.id, mediaType: "movie", topItem: topMovie)
            }
        } catch {
            errorMessage = "Failed to load trending content"
            #if DEBUG
            print("❌ [TVNewPopular] loadTrendingContent: \(error)")
            #endif
        }
    }

    private func loadTop10Content() async {
        do {
            let traktPeriod = period.traktPeriod
            async let moviesTask = apiClient.getTraktMostWatched(media: "movies", period: traktPeriod, limit: 10)
            async let showsTask = apiClient.getTraktMostWatched(media: "shows", period: traktPeriod, limit: 10)

            let (moviesRes, showsRes) = try await (moviesTask, showsTask)
            var items: [DisplayMediaItem] = []
            var rank = 1

            for item in moviesRes.prefix(10) {
                guard let movie = item.movie, let tmdbId = movie.ids?.tmdb else { continue }
                let imageURL = await tmdbPosterURL(mediaType: "movie", tmdbId: tmdbId)
                items.append(
                    DisplayMediaItem(
                        id: "tmdb:movie:\(tmdbId)",
                        title: movie.title ?? "Unknown",
                        imageURL: imageURL,
                        subtitle: movie.year.map(String.init),
                        badge: "#\(rank)",
                        rank: rank,
                        mediaType: "movie",
                        artPath: nil
                    )
                )
                rank += 1
            }

            for item in showsRes.prefix(10) {
                guard let show = item.show, let tmdbId = show.ids?.tmdb else { continue }
                let imageURL = await tmdbPosterURL(mediaType: "tv", tmdbId: tmdbId)
                items.append(
                    DisplayMediaItem(
                        id: "tmdb:tv:\(tmdbId)",
                        title: show.title ?? "Unknown",
                        imageURL: imageURL,
                        subtitle: show.year.map(String.init),
                        badge: "#\(rank)",
                        rank: rank,
                        mediaType: "tv",
                        artPath: nil
                    )
                )
                rank += 1
            }

            top10 = Array(items.sorted { ($0.rank ?? 0) < ($1.rank ?? 0) }.prefix(10))
        } catch {
            errorMessage = "Failed to load top 10 content"
        }
    }

    private func loadComingSoonContent() async {
        do {
            let response = try await apiClient.getTMDBUpcoming(region: "US", page: 1)
            upcoming = response.results.map { item in
                DisplayMediaItem(
                    id: "tmdb:movie:\(item.id)",
                    title: item.title ?? "Unknown",
                    imageURL: item.poster_path != nil ? URL(string: "\(imageBaseURL)w342\(item.poster_path!)") : nil,
                    subtitle: item.release_date.map(formatReleaseDate),
                    badge: "Coming Soon",
                    rank: nil,
                    mediaType: "movie",
                    artPath: nil
                )
            }
        } catch {
            errorMessage = "Failed to load upcoming content"
        }
    }

    private func loadWorthWaitContent() async {
        do {
            let response = try await apiClient.getTraktAnticipated(media: "movies", limit: 20)
            var items: [DisplayMediaItem] = []

            for item in response {
                guard let movie = item.movie, let tmdbId = movie.ids?.tmdb else { continue }
                let imageURL = await tmdbPosterURL(mediaType: "movie", tmdbId: tmdbId)
                items.append(
                    DisplayMediaItem(
                        id: "tmdb:movie:\(tmdbId)",
                        title: movie.title ?? "Unknown",
                        imageURL: imageURL,
                        subtitle: movie.year.map(String.init),
                        badge: "\(item.list_count ?? 0) lists",
                        rank: nil,
                        mediaType: "movie",
                        artPath: nil
                    )
                )
            }

            anticipated = items
        } catch {
            errorMessage = "Failed to load anticipated content"
        }
    }

    private func loadHero(tmdbId: Int, mediaType: String, topItem: TMDBMediaItem) async {
        do {
            async let videosTask = apiClient.getTMDBVideos(mediaType: mediaType, id: String(tmdbId))
            async let imagesTask = apiClient.getTMDBImages(mediaType: mediaType, id: String(tmdbId))
            let (videos, images) = try await (videosTask, imagesTask)

            let trailer = videos.results.first { $0.type == "Trailer" && $0.site == "YouTube" }
            let logos = images.logos ?? []
            let logo = logos.first { $0.iso_639_1 == "en" }
                ?? logos.first { ($0.iso_639_1 ?? "").isEmpty }
                ?? logos.first

            let backdrops = images.backdrops ?? []
            let bestBackdrop = backdrops
                .sorted { ($0.vote_average ?? 0) > ($1.vote_average ?? 0) }
                .first

            var runtime: Int?
            var genres: [String] = []

            if mediaType == "movie" {
                let details = try await apiClient.getTMDBMovieDetails(id: String(tmdbId))
                runtime = details.runtime
                genres = details.genres.map { $0.name }
            } else {
                let details = try await apiClient.getTMDBTVDetails(id: String(tmdbId))
                runtime = details.episodeRunTime?.first
                genres = details.genres.map { $0.name }
            }

            let backdropURL: URL?
            if let backdropPath = bestBackdrop?.file_path {
                backdropURL = URL(string: "\(imageBaseURL)original\(backdropPath)")
            } else if let fallbackBackdrop = topItem.backdrop_path {
                backdropURL = URL(string: "\(imageBaseURL)original\(fallbackBackdrop)")
            } else {
                backdropURL = nil
            }

            hero = HeroData(
                id: "tmdb:\(mediaType):\(tmdbId)",
                title: topItem.title ?? topItem.name ?? "Unknown",
                overview: topItem.overview ?? "",
                backdropURL: backdropURL,
                posterURL: topItem.poster_path != nil ? URL(string: "\(imageBaseURL)w500\(topItem.poster_path!)") : nil,
                rating: topItem.vote_average.map { "⭐ \(String(format: "%.1f", $0))" },
                year: (topItem.release_date ?? topItem.first_air_date)?.split(separator: "-").first.map(String.init),
                runtime: runtime,
                genres: genres,
                ytKey: trailer?.key,
                logoURL: logo.flatMap { URL(string: "\(imageBaseURL)w500\($0.file_path)") },
                canPlay: false,
                mediaType: mediaType
            )
        } catch {
            #if DEBUG
            print("⚠️ [TVNewPopular] Hero load failed: \(error)")
            #endif
        }
    }

    private func fetchPlexRecentlyAdded() async throws -> [DisplayMediaItem] {
        do {
            let items = try await apiClient.getPlexRecentlyAdded(days: 7)
            return items.prefix(20).map { item in
                DisplayMediaItem(
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
            return []
        }
    }

    private func fetchPlexPopular() async throws -> [DisplayMediaItem] {
        do {
            let libraries = try await apiClient.getPlexLibraries()
            var allItems: [PlexMediaItem] = []

            for library in libraries where library.type == "movie" || library.type == "show" {
                let typeNum = library.type == "movie" ? 1 : 2

                if let viewed = try? await apiClient.getPlexLibraryAll(
                    sectionKey: library.key,
                    type: typeNum,
                    sort: "lastViewedAt:desc",
                    offset: 0,
                    limit: 12
                ) {
                    allItems.append(contentsOf: viewed.Metadata ?? [])
                }

                if allItems.count < 20,
                   let rated = try? await apiClient.getPlexLibraryAll(
                    sectionKey: library.key,
                    type: typeNum,
                    sort: "rating:desc",
                    offset: 0,
                    limit: 8
                   ) {
                    allItems.append(contentsOf: rated.Metadata ?? [])
                }
            }

            var unique: [String: PlexMediaItem] = [:]
            for item in allItems {
                unique[item.ratingKey] = item
            }

            return Array(unique.values.prefix(20)).map { item in
                DisplayMediaItem(
                    id: "plex:\(item.ratingKey)",
                    title: item.title ?? item.grandparentTitle ?? "Unknown",
                    imageURL: ImageService.shared.plexImageURL(path: item.thumb, width: 342),
                    subtitle: item.year.map(String.init),
                    badge: nil,
                    rank: nil,
                    mediaType: item.type == "movie" ? "movie" : "tv",
                    artPath: item.art
                )
            }
        } catch {
            return []
        }
    }

    private func tmdbPosterURL(mediaType: String, tmdbId: Int) async -> URL? {
        do {
            if mediaType == "movie" {
                let details = try await apiClient.getTMDBMovieDetails(id: String(tmdbId))
                if let posterPath = details.posterPath {
                    return URL(string: "\(imageBaseURL)w342\(posterPath)")
                }
            } else {
                let details = try await apiClient.getTMDBTVDetails(id: String(tmdbId))
                if let posterPath = details.posterPath {
                    return URL(string: "\(imageBaseURL)w342\(posterPath)")
                }
            }
        } catch {
        }
        return nil
    }

    private func formatReleaseDate(_ dateString: String) -> String {
        let input = DateFormatter()
        input.dateFormat = "yyyy-MM-dd"
        let output = DateFormatter()
        output.dateFormat = "MMM d, yyyy"

        if let date = input.date(from: dateString) {
            return output.string(from: date)
        }
        return dateString
    }
}
