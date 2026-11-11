//
//  ContinueWatchingLandscapeRow.swift
//  FlixorMac
//
//  Continue Watching row with landscape cards showing time remaining and episode info
//

import SwiftUI
import FlixorKit

struct ContinueWatchingLandscapeRow: View {
    var title: String = String(localized: "Continue Watching")
    let items: [MediaItem]
    var itemsWithMultipleVersions: Set<String>? = nil
    /// Item ids with a watch-state action running (menus disabled).
    var busyItemIds: Set<String> = []
    var onTap: ((MediaItem) -> Void)?
    var onAction: ContinueWatchingActionHandler?

    private let cardWidth: CGFloat = 380
    private var cardHeight: CGFloat { cardWidth * 0.5625 } // 16:9 aspect ratio

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
                LazyHStack(spacing: DS.Space.s16) {
                    ForEach(items) { item in
                        let showVersion = itemsWithMultipleVersions?.contains(item.id) ?? false
                        ContinueWatchingLandscapeCard(
                            item: item,
                            width: cardWidth,
                            showVersion: showVersion,
                            isBusy: busyItemIds.contains(item.id),
                            onTap: { onTap?(item) },
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

// MARK: - Continue Watching Landscape Card

struct ContinueWatchingLandscapeCard: View {
    let item: MediaItem
    let width: CGFloat
    var showVersion: Bool = false
    var isBusy: Bool = false
    var onTap: (() -> Void)?
    var onAction: ContinueWatchingActionHandler?

    @State private var backdropURL: URL?

    private var height: CGFloat { width * 0.5625 } // 16:9

    /// Version info (e.g., "4K · Dolby Vision")
    private var versionText: String? {
        guard showVersion else { return nil }
        return getVersionString(item.media)
    }

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
            return String(localized: "\(totalMinutes)m")
        } else {
            let hours = totalMinutes / 60
            let mins = totalMinutes % 60
            if mins == 0 {
                return String(localized: "\(hours)h")
            }
            return String(localized: "\(hours)h \(mins)m")
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
            parts.append(String(localized: "\(mins)m"))
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
                CachedAsyncImage(url: imageURL, maxPixelSize: ImageCache.fillPixelSize(width: width, height: height))
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

                    HStack(spacing: DS.Space.s10) {
                        // Play icon
                        Image(systemName: "play.fill")
                            .font(.flixor(.caption, weight: .semibold))
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
                            .font(.flixor(.callout, weight: .medium))
                            .foregroundStyle(.white)

                        // Version info (only shown if multiple versions exist across libraries)
                        if let version = versionText {
                            Text("·")
                                .font(.flixor(.callout, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                            Text(version)
                                .font(.flixor(.footnote, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                        }

                        Spacer()

                        // Room for the "…" menu, which sits over the card
                        // (outside this Button) so it gets its own clicks.
                        Color.clear.frame(width: 16, height: 1)
                    }
                    .padding(.horizontal, DS.Space.s12)
                    .padding(.vertical, DS.Space.s10)
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
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.r14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .opacity(isBusy ? DS.Opacity.muted : 1)
        .overlay(alignment: .bottomTrailing) {
            if let onAction {
                ContinueWatchingMoreButton(item: item, isBusy: isBusy, onAction: onAction)
                    .padding(.trailing, DS.Space.s6)
                    .padding(.bottom, DS.Space.s4)
            }
        }
        .continueWatchingContextMenu(item: item, isBusy: isBusy, onAction: onAction)
        .task(id: item.id) {
            await loadBackdrop()
        }
    }

    /// Plex items that the Home view model already gave a TMDB backdrop (Continue
    /// Watching), picked by the same English-first rule, need no lookup.
    private var hasResolvedArt: Bool {
        !item.id.hasPrefix("tmdb:") && ImageService.isTMDBImageURL(item.art)
    }

    /// The looked-up TMDB backdrop (English, with title text, first), else the
    /// item's own artwork.
    private var imageURL: URL? {
        let size = ImageService.tmdbBackdropSize(forPointWidth: width)
        if hasResolvedArt, let art = item.art {
            return ImageService.tmdbImageURL(URL(string: art), downsizingOriginalTo: size)
        }
        if let resolved = backdropURL ?? ArtworkLookup.cachedURL(.backdrop, for: item) {
            return ImageService.tmdbImageURL(resolved, size: size)
        }
        return ImageService.tmdbImageURL(
            ImageService.shared.continueWatchingURL(for: item, width: Int(width * 2), height: Int(height * 2)),
            downsizingOriginalTo: size
        )
    }

    private func loadBackdrop() async {
        guard !hasResolvedArt else { return }
        let url = await ArtworkLookup.resolve(.backdrop, for: item)
        guard !Task.isCancelled, let url, url != backdropURL else { return }
        backdropURL = url
    }
}

