//
//  ContinueWatchingPosterRow.swift
//  FlixorMac
//
//  Continue Watching row with poster cards showing progress ring
//

import SwiftUI

struct ContinueWatchingPosterRow: View {
    let items: [MediaItem]
    var onTap: ((MediaItem) -> Void)?

    private let cardWidth: CGFloat = 160

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
                LazyHStack(spacing: 14) {
                    ForEach(items) { item in
                        ContinueWatchingPosterCard(
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

// MARK: - Continue Watching Poster Card

struct ContinueWatchingPosterCard: View {
    let item: MediaItem
    let width: CGFloat
    var onTap: (() -> Void)?

    @State private var isHovered = false
    @State private var posterURL: URL?

    private var height: CGFloat { width * 1.5 } // 2:3 aspect ratio

    // For episodes, use the show poster; for movies, use the movie poster
    private var defaultPosterURL: URL? {
        if item.type == "episode", let grandparentThumb = item.grandparentThumb {
            // Use show poster for episodes
            return ImageService.shared.plexImageURL(path: grandparentThumb, width: Int(width * 2), height: Int(height * 2))
        }
        return ImageService.shared.thumbURL(for: item, width: Int(width * 2), height: Int(height * 2))
    }

    private var progressPercentage: Double {
        guard let duration = item.duration, duration > 0,
              let viewOffset = item.viewOffset else {
            return 0
        }
        return (Double(viewOffset) / Double(duration))
    }

    var body: some View {
        Button(action: { onTap?() }) {
            ZStack(alignment: .bottom) {
                // Poster Image (show poster for episodes, movie poster for movies)
                CachedAsyncImage(url: posterURL ?? defaultPosterURL)
                .aspectRatio(contentMode: .fill)
                .frame(width: width, height: height)
                .clipped()
                .background(Color.gray.opacity(0.2))

                // Gradient overlay (only on hover)
                if isHovered {
                    LinearGradient(
                        colors: [
                            .black.opacity(0.0),
                            .black.opacity(0.75)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: width, height: height)
                    .transition(.opacity)
                }

                // Title overlay (only on hover)
                if isHovered {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.type == "episode" ? (item.grandparentTitle ?? item.title) : item.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        if item.type == "episode", let label = item.episodeLabel {
                            Text(label)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                        }
                    }
                    .frame(width: width - 16, alignment: .leading)
                    .padding(8)
                    .transition(.opacity)
                }

                // Progress Ring (top trailing, always visible)
                if progressPercentage > 0 {
                    VStack {
                        HStack {
                            Spacer()
                            ProgressRing(progress: progressPercentage)
                                .frame(width: 36, height: 36)
                                .padding(8)
                        }
                        Spacer()
                    }
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(isHovered ? 0.6 : 0.1), lineWidth: isHovered ? 2 : 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .task(id: item.id) {
            await loadPoster()
        }
    }

    private func loadPoster() async {
        // Try to get TMDB poster
        do {
            if let url = try await resolveTMDBPoster() {
                await MainActor.run {
                    self.posterURL = url
                }
            }
        } catch {
            // Silent fallback to Plex image
        }
    }

    private func resolveTMDBPoster() async throws -> URL? {
        // Handle tmdb: prefix
        if item.id.hasPrefix("tmdb:") {
            let parts = item.id.split(separator: ":")
            if parts.count == 3 {
                let media = (parts[1] == "movie") ? "movie" : "tv"
                let id = String(parts[2])
                return try await fetchTMDBPoster(mediaType: media, id: id)
            }
            return nil
        }

        // Handle plex: prefix
        if item.id.hasPrefix("plex:") {
            let rk = String(item.id.dropFirst(5))
            return try await fetchPlexTMDBPoster(ratingKey: rk)
        }

        // Handle raw numeric ID
        if item.id.allSatisfy({ $0.isNumber }) {
            return try await fetchPlexTMDBPoster(ratingKey: item.id)
        }

        return nil
    }

    private func fetchPlexTMDBPoster(ratingKey: String) async throws -> URL? {
        struct PlexMeta: Codable {
            let type: String?
            let Guid: [PlexGuid]?
            let grandparentRatingKey: String?
        }
        struct PlexGuid: Codable { let id: String? }

        let meta: PlexMeta = try await APIClient.shared.get("/api/plex/metadata/\(ratingKey)")

        // For episodes, fetch the show's poster instead
        if meta.type == "episode", let parentKey = meta.grandparentRatingKey {
            return try await fetchPlexTMDBPoster(ratingKey: parentKey)
        }

        let mediaType = (meta.type == "movie") ? "movie" : "tv"

        if let guid = meta.Guid?.compactMap({ $0.id }).first(where: { $0.contains("tmdb://") || $0.contains("themoviedb://") }),
           let tid = guid.components(separatedBy: "://").last {
            return try await fetchTMDBPoster(mediaType: mediaType, id: tid)
        }
        return nil
    }

    private func fetchTMDBPoster(mediaType: String, id: String) async throws -> URL? {
        struct TMDBImages: Codable { let posters: [TMDBImage]? }
        struct TMDBImage: Codable { let file_path: String?; let iso_639_1: String?; let vote_average: Double? }

        let imgs: TMDBImages = try await APIClient.shared.get(
            "/api/tmdb/\(mediaType)/\(id)/images",
            queryItems: [URLQueryItem(name: "language", value: "en,null")]
        )

        let posters = imgs.posters ?? []
        // Prefer English posters
        let english = posters.filter { $0.iso_639_1 == "en" }
        let sorted = (english.isEmpty ? posters : english).sorted { ($0.vote_average ?? 0) > ($1.vote_average ?? 0) }

        guard let path = sorted.first?.file_path else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(path)")
    }
}

// MARK: - Progress Ring

struct ProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color.white.opacity(0.3), lineWidth: 3)

            // Progress arc
            Circle()
                .trim(from: 0, to: CGFloat(min(1, max(0, progress))))
                .stroke(Color.red, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))

            // Play icon in center
            Image(systemName: "play.fill")
                .font(.system(size: 10))
                .foregroundStyle(.white)
        }
        .background(Color.black.opacity(0.6))
        .clipShape(Circle())
    }
}
