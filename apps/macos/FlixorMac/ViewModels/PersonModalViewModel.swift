//
//  PersonModalViewModel.swift
//  FlixorMac
//
//  Provides TMDB-driven filmography data for cast/crew modal.
//

import Foundation
import SwiftUI

@MainActor
class PersonModalViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var error: String?
    @Published var name: String = ""
    @Published var subtitle: String?
    @Published var profileURL: URL?
    @Published var movies: [MediaItem] = []
    @Published var shows: [MediaItem] = []
    @Published var isLoadingMoreMovies = false
    @Published var isLoadingMoreShows = false

    private var combinedCast: [TMDBPersonCombinedResponse.Credit] = []
    private var tmdbPersonId: String?

    private let chunkSize = 12
    private let api = APIClient.shared
    private let imageService = ImageService.shared

    func reset() {
        isLoading = false
        error = nil
        name = ""
        subtitle = nil
        profileURL = nil
        movies = []
        shows = []
        isLoadingMoreMovies = false
        isLoadingMoreShows = false
        combinedCast = []
        tmdbPersonId = nil
    }

    func load(personId: String?, name: String, profilePath: URL?) async {
        reset()
        self.name = name
        self.profileURL = profilePath

        isLoading = true
        defer { isLoading = false }

        do {
            let tmdbId = try await resolveTMDBId(personId: personId, name: name)
            guard let tmdbId else {
                error = "Unable to locate TMDB profile for \(name)."
                return
            }
            self.tmdbPersonId = tmdbId

            let combined = try await api.getTMDBPersonCombinedCredits(id: tmdbId)
            let credits = sanitizeCredits(combined)
            combinedCast = credits

            let movieCredits = credits.filter { $0.media_type == "movie" }
            let showCredits = credits.filter { $0.media_type == "tv" }

            subtitle = buildSubtitle(from: credits)

            movies = Array(movieCredits.prefix(chunkSize)).map { mapCreditToMediaItem($0, mediaType: "movie") }
            shows = Array(showCredits.prefix(chunkSize)).map { mapCreditToMediaItem($0, mediaType: "tv") }
        } catch {
            self.error = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
    }

    func loadMoreMoviesIfNeeded(currentItem item: MediaItem) async {
        guard !isLoadingMoreMovies else { return }
        guard let idx = movies.firstIndex(where: { $0.id == item.id }) else { return }
        let triggerIndex = max(movies.count - 4, 0)
        guard idx >= triggerIndex else { return }
        await appendNextChunk(for: "movie")
    }

    func loadMoreShowsIfNeeded(currentItem item: MediaItem) async {
        guard !isLoadingMoreShows else { return }
        guard let idx = shows.firstIndex(where: { $0.id == item.id }) else { return }
        let triggerIndex = max(shows.count - 4, 0)
        guard idx >= triggerIndex else { return }
        await appendNextChunk(for: "tv")
    }

    private func appendNextChunk(for mediaType: String) async {
        let source = combinedCast.filter { $0.media_type == mediaType }
        var current = mediaType == "movie" ? movies : shows
        guard current.count < source.count else { return }

        if mediaType == "movie" { isLoadingMoreMovies = true } else { isLoadingMoreShows = true }
        defer {
            if mediaType == "movie" { isLoadingMoreMovies = false } else { isLoadingMoreShows = false }
        }

        let nextRange = current.count ..< min(current.count + chunkSize, source.count)
        let newItems = source[nextRange].map { mapCreditToMediaItem($0, mediaType: mediaType) }
        if mediaType == "movie" {
            movies.append(contentsOf: newItems)
        } else {
            shows.append(contentsOf: newItems)
        }
    }

    private func resolveTMDBId(personId: String?, name: String) async throws -> String? {
        if let pid = personId, !pid.isEmpty {
            return pid
        }
        let search = try await api.searchTMDBPerson(name: name)
        return search.results?.first?.id.map(String.init)
    }

    private func sanitizeCredits(_ response: TMDBPersonCombinedResponse) -> [TMDBPersonCombinedResponse.Credit] {
        let combined = (response.cast ?? []) + (response.crew ?? [])
        var seen = Set<Int>()
        var filtered: [TMDBPersonCombinedResponse.Credit] = []
        for credit in combined {
            guard let id = credit.id else { continue }
            if seen.insert(id).inserted {
                filtered.append(credit)
            }
        }
        return filtered.sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
    }

    private func buildSubtitle(from credits: [TMDBPersonCombinedResponse.Credit]) -> String? {
        guard !credits.isEmpty else { return nil }
        let movieCount = credits.filter { $0.media_type == "movie" }.count
        let showCount = credits.filter { $0.media_type == "tv" }.count
        switch (movieCount, showCount) {
        case (0, 0): return nil
        case (let m, 0):
            return "\(m) movie\(m == 1 ? "" : "s")"
        case (0, let s):
            return "\(s) TV show\(s == 1 ? "" : "s")"
        default:
            return "\(movieCount) movie\(movieCount == 1 ? "" : "s") • \(showCount) TV show\(showCount == 1 ? "" : "s")"
        }
    }

    private func mapCreditToMediaItem(_ credit: TMDBPersonCombinedResponse.Credit, mediaType: String) -> MediaItem {
        let artPath = credit.backdrop_path ?? credit.poster_path
        let artURL = imageService.tmdbImageURL(path: artPath, size: .w780)?.absoluteString
        let thumbURL = imageService.tmdbImageURL(path: credit.poster_path, size: .w500)?.absoluteString
        return MediaItem(
            id: "tmdb:\(mediaType):\(credit.id ?? 0)",
            title: credit.displayTitle,
            type: mediaType == "movie" ? "movie" : "show",
            thumb: thumbURL,
            art: artURL,
            year: extractYear(from: credit.release_date ?? credit.first_air_date),
            rating: nil,
            duration: nil,
            viewOffset: nil,
            summary: credit.overview,
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

    private func extractYear(from dateString: String?) -> Int? {
        guard let dateString, dateString.count >= 4 else { return nil }
        return Int(dateString.prefix(4))
    }
}
