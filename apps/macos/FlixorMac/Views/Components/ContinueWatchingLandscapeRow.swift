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

    @State private var isHovered = false
    @State private var backdropURL: URL?

    private var height: CGFloat { width * 0.5625 } // 16:9

    private var progressPercentage: Double {
        guard let duration = item.duration, duration > 0,
              let viewOffset = item.viewOffset else {
            return 0
        }
        return (Double(viewOffset) / Double(duration)) * 100.0
    }

    private var timeRemaining: String? {
        guard let duration = item.duration,
              let viewOffset = item.viewOffset else {
            return nil
        }
        let remainingMs = max(0, duration - viewOffset)
        let remainingMin = remainingMs / 60000

        if remainingMin < 60 {
            return "\(remainingMin)m left"
        } else {
            let hours = remainingMin / 60
            let mins = remainingMin % 60
            return "\(hours)h \(mins)m left"
        }
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
                .background(Color.gray.opacity(0.2))

                // Gradient Overlay
                LinearGradient(
                    colors: [
                        .black.opacity(0.0),
                        .black.opacity(0.6),
                        .black.opacity(0.85)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Content Overlay
                VStack(alignment: .leading, spacing: 8) {
                    Spacer()

                    // Title and Episode Info
                    VStack(alignment: .leading, spacing: 4) {
                        // Show title for episodes, movie title for movies
                        Text(item.type == "episode" ? (item.grandparentTitle ?? item.title) : item.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        // Episode label (S1:E2 - Episode Title)
                        if let label = item.episodeLabel {
                            Text(label)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                        }

                        // Time remaining
                        if let remaining = timeRemaining {
                            Text(remaining)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)

                    // Progress Bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.white.opacity(0.3))
                                .frame(height: 4)

                            Rectangle()
                                .fill(Color.red)
                                .frame(
                                    width: geometry.size.width * CGFloat(min(100, max(0, progressPercentage))) / 100.0,
                                    height: 4
                                )
                        }
                    }
                    .frame(height: 4)
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(isHovered ? 0.6 : 0.1), lineWidth: isHovered ? 2 : 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
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

    private func fetchPlexTMDBBackdrop(ratingKey: String) async throws -> URL? {
        struct PlexMeta: Codable { let type: String?; let Guid: [PlexGuid]? }
        struct PlexGuid: Codable { let id: String? }

        let meta: PlexMeta = try await APIClient.shared.get("/api/plex/metadata/\(ratingKey)")
        let mediaType = (meta.type == "movie") ? "movie" : "tv"

        if let guid = meta.Guid?.compactMap({ $0.id }).first(where: { $0.contains("tmdb://") || $0.contains("themoviedb://") }),
           let tid = guid.components(separatedBy: "://").last {
            return try await fetchTMDBBackdrop(mediaType: mediaType, id: tid)
        }
        return nil
    }

    private func fetchTMDBBackdrop(mediaType: String, id: String) async throws -> URL? {
        struct TMDBImages: Codable { let backdrops: [TMDBImage]? }
        struct TMDBImage: Codable { let file_path: String?; let vote_average: Double? }

        let imgs: TMDBImages = try await APIClient.shared.get(
            "/api/tmdb/\(mediaType)/\(id)/images",
            queryItems: [URLQueryItem(name: "language", value: "en,null")]
        )

        let backs = imgs.backdrops ?? []
        let sorted = backs.sorted { ($0.vote_average ?? 0) > ($1.vote_average ?? 0) }

        guard let path = sorted.first?.file_path else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/original\(path)")
    }
}

