//
//  WatchlistButton.swift
//  FlixorMac
//
//  Toggle control to add/remove items from My List (Plex + Trakt).
//

import SwiftUI

struct WatchlistButton: View {
    enum Style {
        case icon
        case pill
    }

    let canonicalId: String
    let mediaType: MyListViewModel.MediaType
    let plexRatingKey: String?
    let plexGuid: String?
    let tmdbId: String?
    let imdbId: String?
    let title: String?
    let year: Int?
    var style: Style = .pill

    @EnvironmentObject private var watchlistController: WatchlistController
    @State private var isInWatchlist = false
    @State private var isLoading = false

    var body: some View {
        Group {
            switch style {
            case .icon:
                iconButton
            case .pill:
                pillButton
            }
        }
        .task(id: canonicalId) {
            // Refresh state whenever canonicalId changes
            isInWatchlist = watchlistController.contains(canonicalId)
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchlistDidChange)) { _ in
            // Update state when watchlist changes from anywhere
            isInWatchlist = watchlistController.contains(canonicalId)
        }
    }

    private var pillButton: some View {
        Button {
            Task { await toggle() }
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                } else {
                    Image(systemName: isInWatchlist ? "checkmark" : "plus")
                        .font(.system(size: 14, weight: .bold))
                }
                Text(isInWatchlist ? "My List" : "Watchlist")
                    .font(.system(size: 15, weight: .semibold))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isInWatchlist ? Color.white.opacity(0.22) : Color.white.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private var iconButton: some View {
        Button {
            Task { await toggle() }
        } label: {
            Group {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.mini)
                } else {
                    Image(systemName: isInWatchlist ? "checkmark" : "plus")
                        .font(.system(size: 14, weight: .bold))
                }
            }
            .frame(width: 32, height: 32)
            .background(Color.black.opacity(0.65))
            .foregroundStyle(Color.white)
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private func toggle() async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }

        if isInWatchlist {
            await removeFromWatchlist()
        } else {
            await addToWatchlist()
        }
    }

    private func addToWatchlist() async {
        // Run both operations in parallel using unstructured tasks
        // so one failure doesn't cancel the other
        let plexTask = Task {
            do {
                try await addToPlex()
                return true
            } catch {
                print("⚠️ Plex watchlist add failed: \(error)")
                return false
            }
        }

        let traktTask = Task {
            do {
                try await addToTrakt()
                return true
            } catch {
                print("⚠️ Trakt watchlist add failed: \(error)")
                return false
            }
        }

        let plexSuccess = await plexTask.value
        let traktSuccess = await traktTask.value

        // Consider successful if at least one service succeeded
        if plexSuccess || traktSuccess {
            watchlistController.registerAdd(id: canonicalId)
            isInWatchlist = true
        } else {
            print("⚠️ Failed to add to watchlist on both services")
        }
    }

    private func removeFromWatchlist() async {
        // Run both operations in parallel using unstructured tasks
        // so one failure doesn't cancel the other
        let plexTask = Task {
            do {
                try await removeFromPlex()
                return true
            } catch {
                print("⚠️ Plex watchlist remove failed: \(error)")
                return false
            }
        }

        let traktTask = Task {
            do {
                try await removeFromTrakt()
                return true
            } catch {
                print("⚠️ Trakt watchlist remove failed: \(error)")
                return false
            }
        }

        let plexSuccess = await plexTask.value
        let traktSuccess = await traktTask.value

        // Consider successful if at least one service succeeded
        if plexSuccess || traktSuccess {
            watchlistController.registerRemove(id: canonicalId)
            isInWatchlist = false
        } else {
            print("⚠️ Failed to remove from watchlist on both services")
        }
    }

    private func addToPlex() async throws {
        guard let identifier = plexGuid ?? plexRatingKey else { return }
        struct Response: Codable { let ok: Bool? }
        let encoded = identifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? identifier
        let _: Response = try await APIClient.shared.put("/api/plextv/watchlist/\(encoded)")
    }

    private func removeFromPlex() async throws {
        guard let identifier = plexGuid ?? plexRatingKey else { return }
        struct Response: Codable { let ok: Bool? }
        let encoded = identifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? identifier
        let _: Response = try await APIClient.shared.delete("/api/plextv/watchlist/\(encoded)")
    }

    private func addToTrakt() async throws {
        guard let tmdbId = tmdbId else { return }
        struct TraktPayload: Codable {
            struct IDs: Codable { let tmdb: Int? }
            struct Entry: Codable { let ids: IDs; let title: String?; let year: Int? }
            let movies: [Entry]?
            let shows: [Entry]?
        }
        struct Response: Codable { let added: [String: Int]? }
        let entry = TraktPayload.Entry(ids: .init(tmdb: Int(tmdbId)), title: title, year: year)
        let payload = mediaType == .movie
            ? TraktPayload(movies: [entry], shows: nil)
            : TraktPayload(movies: nil, shows: [entry])
        let _: Response = try await APIClient.shared.post("/api/trakt/watchlist", body: payload)
    }

    private func removeFromTrakt() async throws {
        guard let tmdbId = tmdbId else { return }
        struct TraktPayload: Codable {
            struct IDs: Codable { let tmdb: Int? }
            struct Entry: Codable { let ids: IDs }
            let movies: [Entry]?
            let shows: [Entry]?
        }
        struct Response: Codable { let deleted: [String: Int]? }
        let entry = TraktPayload.Entry(ids: .init(tmdb: Int(tmdbId)))
        let payload = mediaType == .movie
            ? TraktPayload(movies: [entry], shows: nil)
            : TraktPayload(movies: nil, shows: [entry])
        let _: Response = try await APIClient.shared.post("/api/trakt/watchlist/remove", body: payload)
    }
}
#if DEBUG && canImport(PreviewsMacros)
#Preview {
    WatchlistButton(
        canonicalId: "tmdb:movie:1234",
        mediaType: .movie,
        plexRatingKey: nil,
        plexGuid: "tmdb://1234",
        tmdbId: "1234",
        imdbId: nil,
        title: "Sample",
        year: 2024,
        style: .pill
    )
    .environmentObject(WatchlistController())
}
#endif
