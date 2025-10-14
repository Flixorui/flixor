import Foundation
import FlixorKit

@MainActor
final class TVHomeViewModel: ObservableObject {
    @Published var billboardItems: [MediaItem] = []
    @Published var continueWatching: [MediaItem] = []
    @Published var trending: [MediaItem] = []
    @Published var recentlyAdded: [MediaItem] = []
    @Published var isLoading = true
    @Published var debugMessage: String?

    func load() async {
        isLoading = true
        defer { isLoading = false }
        debugMessage = "Loading Home…"

        // Optional: ensure a current server is set
        do {
            let servers = try await APIClient.shared.getPlexServers()
            if let first = servers.first {
                _ = try? await APIClient.shared.setCurrentPlexServer(serverId: first.id)
            }
        } catch {
            debugMessage = "Servers error: \(error.localizedDescription)"
        }

        // Parallel fetches
        async let cont: [MediaItem] = fetchCW()
        async let recent: [MediaItem] = fetchRecent()
        async let ondeck: [MediaItem] = fetchOnDeck()

        let cw = await cont
        let ra = await recent
        let od = await ondeck

        self.continueWatching = Array(cw.prefix(12))
        self.recentlyAdded = Array(ra.prefix(12))
        self.trending = Array(od.prefix(12))

        if continueWatching.isEmpty && trending.isEmpty && recentlyAdded.isEmpty {
            // Try Plex.tv watchlist
            do {
                let env = try await APIClient.shared.getPlexTvWatchlist()
                let wl = (env.MediaContainer.Metadata ?? []).map { $0.toMediaItem() }
                self.trending = Array(wl.prefix(12))
                debugMessage = wl.isEmpty ? "Watchlist empty; trying TMDB…" : nil
            } catch {
                debugMessage = "Watchlist error: \(error.localizedDescription)"
            }
        }

        if continueWatching.isEmpty && trending.isEmpty && recentlyAdded.isEmpty {
            // Try TMDB trending TV week
            do {
                let tm = try await APIClient.shared.getTMDBTrending(mediaType: "tv", timeWindow: "week")
                let mapped: [MediaItem] = tm.results.prefix(16).map { r in
                    MediaItem(
                        id: "tmdb:tv:\(r.id)",
                        title: r.name ?? r.title ?? "",
                        type: "show",
                        thumb: ImageService.shared.tmdbImageURL(path: r.poster_path, size: .w500)?.absoluteString,
                        art: ImageService.shared.tmdbImageURL(path: r.backdrop_path, size: .original)?.absoluteString,
                        year: nil, rating: nil, duration: nil, viewOffset: nil, summary: nil,
                        grandparentTitle: nil, grandparentThumb: nil, grandparentArt: nil,
                        parentIndex: nil, index: nil
                    )
                }
                self.trending = Array(mapped.prefix(12))
                debugMessage = nil
            } catch {
                debugMessage = "TMDB error: \(error.localizedDescription)"
            }
        }

        // Billboard choose available source
        let heroSource = !continueWatching.isEmpty ? continueWatching : (!trending.isEmpty ? trending : recentlyAdded)
        self.billboardItems = Array(heroSource.prefix(1))
    }

    // MARK: - helpers
    private func fetchCW() async -> [MediaItem] {
        do { return try await APIClient.shared.getPlexContinueList().map { $0.toMediaItem() } } catch { return [] }
    }
    private func fetchRecent() async -> [MediaItem] {
        do { return try await APIClient.shared.getPlexRecentList().map { $0.toMediaItem() } } catch { return [] }
    }
    private func fetchOnDeck() async -> [MediaItem] {
        do { return try await APIClient.shared.getPlexOnDeckList().map { $0.toMediaItem() } } catch { return [] }
    }
}
