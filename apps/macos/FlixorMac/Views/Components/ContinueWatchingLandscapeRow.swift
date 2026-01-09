//
//  ContinueWatchingLandscapeRow.swift
//  FlixorMac
//
//  Continue Watching row with landscape cards showing time remaining and episode info
//

import SwiftUI

struct ContinueWatchingLandscapeRow: View {
    let items: [MediaItem]
    var onTap: ((MediaItem) -> Void)?

    private let cardWidth: CGFloat = 380
    private var cardHeight: CGFloat { cardWidth * 0.5625 } // 16:9 aspect ratio

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Continue Watching")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()
            }
            .padding(.horizontal, 20)

            // Horizontal scroll of cards
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(items) { item in
                        ContinueWatchingLandscapeCard(
                            item: item,
                            width: cardWidth,
                            onTap: { onTap?(item) }
                        )
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

// MARK: - Continue Watching Landscape Card

struct ContinueWatchingLandscapeCard: View {
    let item: MediaItem
    let width: CGFloat
    var onTap: (() -> Void)?

    @State private var backdropURL: URL?

    private var height: CGFloat { width * 0.5625 } // 16:9

    private var progressPercentage: Double {
        guard let duration = item.duration, duration > 0,
              let viewOffset = item.viewOffset else {
            return 0
        }
        return (Double(viewOffset) / Double(duration)) * 100.0
    }

    /// Format duration for display (e.g., "1h 11m" or "56m")
    private var durationText: String {
        guard let duration = item.duration else { return "" }
        let totalMinutes = duration / 60000

        if totalMinutes < 60 {
            return "\(totalMinutes)m"
        } else {
            let hours = totalMinutes / 60
            let mins = totalMinutes % 60
            if mins == 0 {
                return "\(hours)h"
            }
            return "\(hours)h \(mins)m"
        }
    }

    /// Episode info for TV shows (e.g., "S7, E8 · 40m")
    private var episodeInfoText: String? {
        guard item.type == "episode" else { return nil }

        var parts: [String] = []

        // Season and episode
        if let season = item.parentIndex, let episode = item.index {
            parts.append("S\(season), E\(episode)")
        }

        // Duration
        if let duration = item.duration {
            let mins = duration / 60000
            parts.append("\(mins)m")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Text to show in bottom overlay - episode info for TV, duration for movies
    private var bottomInfoText: String {
        if let episodeInfo = episodeInfoText {
            return episodeInfo
        }
        return durationText
    }

    var body: some View {
        Button(action: { onTap?() }) {
            ZStack(alignment: .bottom) {
                // Background Image
                CachedAsyncImage(
                    url: backdropURL ?? ImageService.shared.continueWatchingURL(
                        for: item,
                        width: Int(width * 2),
                        height: Int(height * 2)
                    )
                )
                .aspectRatio(contentMode: .fill)
                .frame(width: width, height: height)
                .clipped()
                .background(Color(white: 0.15))

                // Subtle bottom gradient for text readability
                LinearGradient(
                    colors: [
                        .clear,
                        .black.opacity(0.4),
                        .black.opacity(0.7)
                    ],
                    startPoint: .init(x: 0.5, y: 0.5),
                    endPoint: .bottom
                )

                // Bottom Info Bar - single row: Play icon | Progress bar | Duration | Menu
                VStack {
                    Spacer()

                    HStack(spacing: 10) {
                        // Play icon
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)

                        // Progress bar - fixed width, rounded, thicker
                        ZStack(alignment: .leading) {
                            // Background track
                            Capsule()
                                .fill(Color.white.opacity(0.3))
                                .frame(width: 50, height: 5)

                            // Progress fill
                            Capsule()
                                .fill(Color.white)
                                .frame(width: 50 * CGFloat(min(100, max(0, progressPercentage))) / 100.0, height: 5)
                        }

                        // Duration or episode info
                        Text(bottomInfoText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)

                        Spacer()

                        // Menu button (three dots)
                        Button(action: {
                            // TODO: Show context menu
                        }) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        Rectangle().fill(.ultraThinMaterial).opacity(0.3)
                    )
                    .mask(
                        VStack(spacing: 0) {
                            // Gradient mask for soft top edge
                            LinearGradient(
                                colors: [.clear, .black],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 12)

                            Rectangle()
                        }
                    )
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .task(id: item.id) {
            await loadBackdrop()
        }
    }

    private func loadBackdrop() async {
        // Try to get TMDB backdrop
        do {
            if let url = try await resolveTMDBBackdrop() {
                await MainActor.run {
                    self.backdropURL = url
                }
            }
        } catch {
            // Silent fallback to Plex image
        }
    }

    private func resolveTMDBBackdrop() async throws -> URL? {
        // For episodes, use the parent show's backdrop (grandparentRatingKey)
        if item.type == "episode", let showKey = item.grandparentRatingKey {
            return try await fetchPlexTMDBBackdrop(ratingKey: showKey, forceMediaType: "tv")
        }

        // For seasons, use the parent show's backdrop (parentRatingKey)
        if item.type == "season", let showKey = item.parentRatingKey {
            return try await fetchPlexTMDBBackdrop(ratingKey: showKey, forceMediaType: "tv")
        }

        // Handle tmdb: prefix
        if item.id.hasPrefix("tmdb:") {
            let parts = item.id.split(separator: ":")
            if parts.count == 3 {
                let media = (parts[1] == "movie") ? "movie" : "tv"
                let id = String(parts[2])
                return try await fetchTMDBBackdrop(mediaType: media, id: id)
            }
            return nil
        }

        // Handle plex: prefix
        if item.id.hasPrefix("plex:") {
            let rk = String(item.id.dropFirst(5))
            return try await fetchPlexTMDBBackdrop(ratingKey: rk)
        }

        // Handle raw numeric ID
        if item.id.allSatisfy({ $0.isNumber }) {
            return try await fetchPlexTMDBBackdrop(ratingKey: item.id)
        }

        return nil
    }

    private func fetchPlexTMDBBackdrop(ratingKey: String, forceMediaType: String? = nil) async throws -> URL? {
        struct PlexMeta: Codable { let type: String?; let Guid: [PlexGuid]? }
        struct PlexGuid: Codable { let id: String? }

        let meta: PlexMeta = try await APIClient.shared.get("/api/plex/metadata/\(ratingKey)")
        let mediaType = forceMediaType ?? ((meta.type == "movie") ? "movie" : "tv")

        if let guid = meta.Guid?.compactMap({ $0.id }).first(where: { $0.contains("tmdb://") || $0.contains("themoviedb://") }),
           let tid = guid.components(separatedBy: "://").last {
            return try await fetchTMDBBackdrop(mediaType: mediaType, id: tid)
        }
        return nil
    }

    private func fetchTMDBBackdrop(mediaType: String, id: String) async throws -> URL? {
        struct TMDBImages: Codable { let backdrops: [TMDBImage]? }
        struct TMDBImage: Codable { let file_path: String?; let vote_average: Double?; let iso_639_1: String? }

        let imgs: TMDBImages = try await APIClient.shared.get(
            "/api/tmdb/\(mediaType)/\(id)/images",
            queryItems: [URLQueryItem(name: "include_image_language", value: "en,null")]
        )

        let backs = imgs.backdrops ?? []

        // Priority 1: English backdrops (with title text burned in)
        let englishBackdrops = backs.filter { $0.iso_639_1 == "en" }
            .sorted { ($0.vote_average ?? 0) > ($1.vote_average ?? 0) }
        if let path = englishBackdrops.first?.file_path {
            return URL(string: "https://image.tmdb.org/t/p/original\(path)")
        }

        // Priority 2: Any language with title (iso_639_1 is not null)
        let withLanguage = backs.filter { $0.iso_639_1 != nil }
            .sorted { ($0.vote_average ?? 0) > ($1.vote_average ?? 0) }
        if let path = withLanguage.first?.file_path {
            return URL(string: "https://image.tmdb.org/t/p/original\(path)")
        }

        // Priority 3: Fallback to any backdrop (including textless)
        let sorted = backs.sorted { ($0.vote_average ?? 0) > ($1.vote_average ?? 0) }
        guard let path = sorted.first?.file_path else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/original\(path)")
    }
}

