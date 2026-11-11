//
//  ContinueWatchingPosterRow.swift
//  FlixorMac
//
//  Continue Watching row with poster cards showing progress ring
//

import SwiftUI
import FlixorKit

struct ContinueWatchingPosterRow: View {
    var title: String = String(localized: "Continue Watching")
    let items: [MediaItem]
    var itemsWithMultipleVersions: Set<String>? = nil
    /// Item ids with a watch-state action running (menus disabled).
    var busyItemIds: Set<String> = []
    var onTap: ((MediaItem) -> Void)?
    var onAction: ContinueWatchingActionHandler?

    @ObservedObject private var profileSettings = ProfileSettings.shared
    @Environment(\.windowMetrics) private var metrics

    private var cardWidth: CGFloat {
        metrics.posterWidth(designWidth: 160, storedSize: profileSettings.posterSize)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s12) {
            // Header
            HStack {
                Text(title)
                    .font(.flixor(.title2, weight: .bold))

                Spacer()
            }
            .padding(.horizontal, DS.Space.s20)

            // Horizontal scroll of cards
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: DS.Space.s14) {
                    ForEach(items) { item in
                        let showVersion = itemsWithMultipleVersions?.contains(item.id) ?? false
                        ContinueWatchingPosterCard(
                            item: item,
                            width: cardWidth,
                            showVersion: showVersion,
                            onTap: { onTap?(item) }
                        )
                        .opacity(busyItemIds.contains(item.id) ? DS.Opacity.muted : 1)
                        .continueWatchingContextMenu(
                            item: item,
                            isBusy: busyItemIds.contains(item.id),
                            onAction: onAction
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                }
                .padding(.horizontal, DS.Space.s20)
            }
        }
    }
}

// MARK: - Continue Watching Poster Card

struct ContinueWatchingPosterCard: View {
    let item: MediaItem
    let width: CGFloat
    var showVersion: Bool = false
    var onTap: (() -> Void)?

    @State private var isHovered = false
    @State private var posterURL: URL?

    private var height: CGFloat { width * 1.5 } // 2:3 aspect ratio

    /// Version info (e.g., "4K · Dolby Vision")
    private var versionText: String? {
        guard showVersion else { return nil }
        return getVersionString(item.media)
    }

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
                CachedAsyncImage(url: imageURL, maxPixelSize: ImageCache.fillPixelSize(width: width, height: height))
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
                    VStack(alignment: .leading, spacing: DS.Space.s4) {
                        Text(item.type == "episode" ? (item.grandparentTitle ?? item.title) : item.title)
                            .font(.flixor(.callout, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        if item.type == "episode", let label = item.episodeLabel {
                            Text(label)
                                .font(.flixor(.caption))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                        }

                        if let version = versionText {
                            Text(version)
                                .font(.flixor(.micro))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                    .frame(width: width - 16, alignment: .leading)
                    .padding(DS.Space.s8)
                    .transition(.opacity)
                }

                // Progress Ring (top trailing, always visible)
                if progressPercentage > 0 {
                    VStack {
                        HStack {
                            Spacer()
                            ProgressRing(progress: progressPercentage)
                                .frame(width: 36, height: 36)
                                .padding(DS.Space.s8)
                        }
                        Spacer()
                    }
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.r10, style: .continuous)
                    .strokeBorder(Color.white.opacity(isHovered ? 0.6 : 0.1), lineWidth: isHovered ? 2 : 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DS.Motion.quick) {
                isHovered = hovering
            }
        }
        .task(id: item.id) {
            await loadPoster()
        }
    }

    /// Path of the item's own poster (the show's for episodes).
    private var ownPosterPath: String? {
        if item.type == "episode", let grandparentThumb = item.grandparentThumb { return grandparentThumb }
        return item.thumb
    }

    /// The item's own TMDB poster, else the looked-up one, else the Plex poster.
    private var imageURL: URL? {
        if !ImageService.isTMDBImageURL(ownPosterPath),
           let resolved = posterURL ?? ArtworkLookup.cachedURL(.imagesPoster, for: item) {
            return ImageService.tmdbImageURL(resolved, size: ImageService.tmdbPosterSize(forPointWidth: width))
        }
        return ImageService.tmdbImageURL(defaultPosterURL, downsizingOriginalTo: "w780")
    }

    private func loadPoster() async {
        guard !ImageService.isTMDBImageURL(ownPosterPath) else { return }
        let url = await ArtworkLookup.resolve(.imagesPoster, for: item)
        guard !Task.isCancelled, let url, url != posterURL else { return }
        posterURL = url
    }
}

// MARK: - Progress Ring

struct ProgressRing: View {
    let progress: Double

    @Environment(\.flixorTheme) private var theme

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color.white.opacity(0.3), lineWidth: 3)

            // Progress arc
            Circle()
                .trim(from: 0, to: CGFloat(min(1, max(0, progress))))
                .stroke(theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))

            // Play icon in center
            Image(systemName: "play.fill")
                .font(.flixor(.micro))
                .foregroundStyle(.white)
        }
        .background(Color.black.opacity(0.6))
        .clipShape(Circle())
    }
}
