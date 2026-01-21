//
//  PosterSectionRow.swift
//  FlixorMac
//
//  Generic poster section row for displaying any content as poster cards
//

import SwiftUI

struct PosterSectionRow: View {
    let section: LibrarySection
    var onTap: (MediaItem) -> Void
    var onBrowse: ((BrowseContext) -> Void)?

    @ObservedObject private var profileSettings = ProfileSettings.shared

    private var posterWidth: CGFloat {
        switch profileSettings.posterSize {
        case "small": return 130
        case "large": return 190
        default: return 160
        }
    }

    private var posterHeight: CGFloat {
        posterWidth * 1.5 // Standard 2:3 poster ratio
    }

    var body: some View {
        CarouselRow(
            title: section.title,
            items: section.items,
            itemWidth: posterWidth,
            spacing: 14,
            rowHeight: posterHeight + 16,
            browseAction: section.browseContext.map { context in
                { onBrowse?(context) }
            }
        ) { item in
            PosterSectionCard(
                item: item,
                width: posterWidth,
                onTap: { onTap(item) }
            )
        }
    }
}

// MARK: - Poster Section Card

struct PosterSectionCard: View {
    let item: MediaItem
    let width: CGFloat
    var onTap: (() -> Void)?

    @State private var isHovered = false
    @State private var posterURL: URL?

    private var height: CGFloat { width * 1.5 }

    var body: some View {
        Button(action: { onTap?() }) {
            ZStack(alignment: .bottom) {
                // Poster Image
                CachedAsyncImage(
                    url: posterURL ?? ImageService.shared.thumbURL(
                        for: item,
                        width: Int(width * 2),
                        height: Int(height * 2)
                    )
                )
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
                        Text(item.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        HStack(spacing: 6) {
                            if let year = item.year {
                                Text(String(year))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.85))
                            }

                            if let rating = item.rating {
                                HStack(spacing: 2) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 9))
                                    Text(String(format: "%.1f", rating))
                                        .font(.system(size: 11))
                                }
                                .foregroundStyle(.yellow.opacity(0.9))
                            }
                        }
                    }
                    .frame(width: width - 16, alignment: .leading)
                    .padding(8)
                    .transition(.opacity)
                }

                // Type badge (top trailing)
                if item.type == "show" || item.type == "episode" {
                    VStack {
                        HStack {
                            Spacer()
                            Text("TV")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.blue.opacity(0.8))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .padding(6)
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
        struct PlexMeta: Codable { let type: String?; let Guid: [PlexGuid]? }
        struct PlexGuid: Codable { let id: String? }

        let meta: PlexMeta = try await APIClient.shared.get("/api/plex/metadata/\(ratingKey)")
        let mediaType = (meta.type == "movie") ? "movie" : "tv"

        if let guid = meta.Guid?.compactMap({ $0.id }).first(where: { $0.contains("tmdb://") || $0.contains("themoviedb://") }),
           let tid = guid.components(separatedBy: "://").last {
            return try await fetchTMDBPoster(mediaType: mediaType, id: tid)
        }
        return nil
    }

    private func fetchTMDBPoster(mediaType: String, id: String) async throws -> URL? {
        struct TMDBDetails: Codable { let poster_path: String? }

        let details: TMDBDetails = try await APIClient.shared.get("/api/tmdb/\(mediaType)/\(id)")

        guard let path = details.poster_path else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(path)")
    }
}
