//
//  HoverPreviewModel.swift
//  FlixorMac
//
//  Data for one hover preview. Starts from what the card's MediaItem already
//  has, then (only once the preview is on screen) fills in TMDB details, logo,
//  backdrop and, after the preview settles, a trailer key. `cancel()` stops all
//  work; the controller calls it on dismiss.
//

import Foundation
import SwiftUI
import FlixorKit

@MainActor
final class HoverPreviewModel: ObservableObject {
    let item: MediaItem
    let trailerMode: HoverTrailerMode

    @Published private(set) var title: String
    @Published private(set) var subtitle: String?
    @Published private(set) var year: String?
    @Published private(set) var runtime: String?
    @Published private(set) var rating: Double?
    @Published private(set) var genres: [String] = []
    @Published private(set) var overview: String?
    @Published private(set) var backdropURL: URL?
    @Published private(set) var logoURL: URL?
    @Published private(set) var tmdbId: Int?
    @Published private(set) var trailer: Trailer?
    @Published var isWatched = false

    /// Delay after the preview appears before a trailer is looked up and started.
    private let trailerSettleDelay: UInt64 = 900_000_000
    private var task: Task<Void, Never>?

    init(item: MediaItem, trailerMode: HoverTrailerMode) {
        self.item = item
        self.trailerMode = trailerMode

        let type = item.type.lowercased()
        title = CardActions.displayTitle(item)
        if type == "episode" {
            var parts: [String] = []
            if let season = item.parentIndex, let episode = item.index { parts.append("S\(season) E\(episode)") }
            if item.grandparentTitle != nil { parts.append(item.title) }
            subtitle = parts.isEmpty ? nil : parts.joined(separator: " · ")
        } else if type == "season" {
            subtitle = item.parentTitle.map { _ in item.title }
        }
        year = item.year.map(String.init)
        runtime = Self.formatRuntime(minutes: item.duration.map { $0 / 60_000 })
        rating = item.rating.flatMap { $0 > 0 ? $0 : nil }
        overview = item.summary.flatMap { $0.isEmpty || item.isGroupedRecentlyAddedShow ? nil : $0 }
        backdropURL = ImageService.shared.continueWatchingURL(for: item, width: 960, height: 540)
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            await self?.load()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    // MARK: - Loading

    private func load() async {
        if let target = WatchStateTarget(item: item), item.type.lowercased() != "show" {
            isWatched = await WatchStateService.shared.isWatchedLocally(target)
        }

        guard !Task.isCancelled,
              let identity = await MediaIdentityResolver.shared.tmdbIdentity(for: item),
              !Task.isCancelled else { return }
        tmdbId = identity.id

        async let details: Void = loadDetails(identity.id, mediaType: identity.mediaType)
        async let images: Void = loadImages(identity.id, mediaType: identity.mediaType)
        _ = await (details, images)

        guard trailerMode != .off, !Task.isCancelled else { return }
        try? await Task.sleep(nanoseconds: trailerSettleDelay)
        guard !Task.isCancelled else { return }
        let best = await TrailerService.shared.bestTrailer(tmdbId: identity.id, mediaType: identity.mediaType)
        guard !Task.isCancelled else { return }
        trailer = best
    }

    private func loadDetails(_ id: Int, mediaType: TMDBMediaType) async {
        let tmdb = FlixorCore.shared.tmdb
        // Episodes and seasons keep their own overview/runtime; only borrow genres.
        let keepOwnText = ["episode", "season"].contains(item.type.lowercased())
        do {
            switch mediaType {
            case .movie:
                let details = try await tmdb.getMovieDetails(id: id)
                guard !Task.isCancelled else { return }
                apply(genres: details.genres.map(\.name),
                      overview: keepOwnText ? nil : details.overview,
                      runtimeMinutes: details.runtime,
                      rating: details.voteAverage,
                      date: details.releaseDate,
                      backdropPath: details.backdropPath)
            case .tv:
                let details = try await tmdb.getTVDetails(id: id)
                guard !Task.isCancelled else { return }
                apply(genres: details.genres.map(\.name),
                      overview: keepOwnText ? nil : details.overview,
                      runtimeMinutes: keepOwnText ? nil : details.episodeRunTime?.first,
                      rating: details.voteAverage,
                      date: details.firstAirDate,
                      backdropPath: details.backdropPath)
            }
        } catch {
            // Keep what the card already had.
        }
    }

    private func apply(genres: [String], overview: String?, runtimeMinutes: Int?, rating: Double?, date: String?, backdropPath: String?) {
        self.genres = Array(genres.prefix(3))
        if let overview, !overview.isEmpty, self.overview == nil || item.type.lowercased() != "episode" {
            self.overview = overview
        }
        if runtime == nil, let text = Self.formatRuntime(minutes: runtimeMinutes) { runtime = text }
        if self.rating == nil, let rating, rating > 0 { self.rating = rating }
        if year == nil, let date, date.count >= 4 { year = String(date.prefix(4)) }
        if backdropURL == nil, let backdropPath {
            backdropURL = URL(string: "https://image.tmdb.org/t/p/w1280\(backdropPath)")
        }
    }

    private func loadImages(_ id: Int, mediaType: TMDBMediaType) async {
        guard let images = try? await FlixorCore.shared.tmdb.getImages(mediaType: mediaType.rawValue, id: id),
              !Task.isCancelled else { return }
        let logos = images.logos.filter { $0.filePath != nil }
        let preferred = logos.first { $0.iso6391 == "en" } ?? logos.first { $0.iso6391 == nil } ?? logos.first
        if let path = preferred?.filePath {
            logoURL = URL(string: "https://image.tmdb.org/t/p/w500\(path)")
        }
    }

    // MARK: - Formatting

    static func formatRuntime(minutes: Int?) -> String? {
        guard let minutes, minutes > 0 else { return nil }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return String(localized: "\(rest)m") }
        return rest == 0 ? String(localized: "\(hours)h") : String(localized: "\(hours)h \(rest)m")
    }
}
