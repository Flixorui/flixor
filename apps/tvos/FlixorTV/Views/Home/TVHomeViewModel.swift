import Foundation
import FlixorKit

struct HomeSection: Identifiable {
    let id: String
    let title: String
    let items: [MediaItem]
}

@MainActor
final class TVHomeViewModel: ObservableObject {
    @Published var billboardItems: [MediaItem] = []
    @Published var continueWatching: [MediaItem] = []
    @Published var onDeck: [MediaItem] = []
    @Published var recentlyAdded: [MediaItem] = []
    @Published var additionalSections: [HomeSection] = []
    @Published var isLoading = true
    @Published var error: String?

    private var loadTask: Task<Void, Never>?

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

        // TMDB Trending TV
        if let tmdbSection = await fetchTMDBTrendingSection() {
            sections.append(tmdbSection)
        }

        // Plex.tv Watchlist
        if let watchlistSection = await fetchPlexWatchlistSection() {
            sections.append(watchlistSection)
        }

        // TMDB Popular Movies
        if let popularMoviesSection = await fetchTMDBPopularMoviesSection() {
            sections.append(popularMoviesSection)
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
        return items.map { $0.toMediaItem() }
    }

    private func fetchOnDeck() async throws -> [MediaItem] {
        print("📦 [TVHome] Fetching on deck...")
        let items = try await APIClient.shared.getPlexOnDeckList()
        print("✅ [TVHome] Received \(items.count) on deck items")
        return items.map { $0.toMediaItem() }
    }

    private func fetchRecentlyAdded() async throws -> [MediaItem] {
        print("📦 [TVHome] Fetching recently added...")
        let items = try await APIClient.shared.getPlexRecentList()
        print("✅ [TVHome] Received \(items.count) recently added items")
        return items.map { $0.toMediaItem() }
    }

    // MARK: - Additional Sections

    private func fetchTMDBTrendingSection() async -> HomeSection? {
        do {
            print("📦 [TVHome] Fetching TMDB trending TV...")
            let response = try await APIClient.shared.getTMDBTrending(mediaType: "tv", timeWindow: "week")
            let items = response.results.prefix(12).map { result in
                MediaItem(
                    id: "tmdb:tv:\(result.id)",
                    title: result.name ?? result.title ?? "Untitled",
                    type: "show",
                    thumb: ImageService.shared.tmdbImageURL(path: result.poster_path, size: .w500)?.absoluteString,
                    art: ImageService.shared.tmdbImageURL(path: result.backdrop_path, size: .original)?.absoluteString,
                    year: nil, rating: nil, duration: nil, viewOffset: nil, summary: nil,
                    grandparentTitle: nil, grandparentThumb: nil, grandparentArt: nil,
                    parentIndex: nil, index: nil
                )
            }
            print("✅ [TVHome] TMDB trending: \(items.count) items")
            return HomeSection(id: "tmdb-trending", title: "Trending Now", items: Array(items))
        } catch {
            print("⚠️ [TVHome] TMDB trending failed: \(error)")
            return nil
        }
    }

    private func fetchTMDBPopularMoviesSection() async -> HomeSection? {
        do {
            print("📦 [TVHome] Fetching TMDB trending movies...")
            let response = try await APIClient.shared.getTMDBTrending(mediaType: "movie", timeWindow: "week")
            let items = response.results.prefix(12).map { result in
                MediaItem(
                    id: "tmdb:movie:\(result.id)",
                    title: result.title ?? result.name ?? "Untitled",
                    type: "movie",
                    thumb: ImageService.shared.tmdbImageURL(path: result.poster_path, size: .w500)?.absoluteString,
                    art: ImageService.shared.tmdbImageURL(path: result.backdrop_path, size: .original)?.absoluteString,
                    year: nil, rating: nil, duration: nil, viewOffset: nil, summary: nil,
                    grandparentTitle: nil, grandparentThumb: nil, grandparentArt: nil,
                    parentIndex: nil, index: nil
                )
            }
            print("✅ [TVHome] TMDB popular movies: \(items.count) items")
            return HomeSection(id: "tmdb-popular-movies", title: "Popular on Plex", items: Array(items))
        } catch {
            print("⚠️ [TVHome] TMDB popular movies failed: \(error)")
            return nil
        }
    }

    private func fetchPlexWatchlistSection() async -> HomeSection? {
        do {
            print("📦 [TVHome] Fetching Plex.tv watchlist...")
            let envelope = try await APIClient.shared.getPlexTvWatchlist()
            let items = (envelope.MediaContainer.Metadata ?? []).map { $0.toMediaItem() }
            print("✅ [TVHome] Plex.tv watchlist: \(items.count) items")
            if items.isEmpty { return nil }
            return HomeSection(id: "plex-watchlist", title: "My List", items: Array(items.prefix(12)))
        } catch {
            print("⚠️ [TVHome] Plex.tv watchlist failed: \(error)")
            return nil
        }
    }
}
