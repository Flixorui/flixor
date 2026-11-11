//
//  LandscapeCard.swift
//  FlixorMac
//
//  Generic landscape (backdrop) card used for rows like On Deck and Recently Added
//

import SwiftUI
import FlixorKit

struct LandscapeCard: View {
    let item: MediaItem
    let width: CGFloat
    var onTap: (() -> Void)?
    var showProgressBar: Bool = false // Optional progress bar overlay

    @State private var isHovered = false
    @State private var altURL: URL? = nil
    @ObservedObject private var cardStyle = CardStyleStore.shared
    @Environment(\.flixorTheme) private var theme

    private var height: CGFloat {
        width * 0.5 // 2:1 aspect to match web rows
    }

    private var cornerRadius: CGFloat { cardStyle.cornerStyle.landscapeRadius }

    private var ratingBadgeValue: Double? {
        guard cardStyle.showRatingBadges, let rating = item.rating, rating > 0 else { return nil }
        return rating
    }

    private var progressPercentage: Double {
        guard showProgressBar,
              let duration = item.duration, duration > 0,
              let viewOffset = item.viewOffset else {
            return 0
        }
        return (Double(viewOffset) / Double(duration)) * 100.0
    }

    private var yearEditionText: String {
        var parts: [String] = []
        if let year = item.year {
            parts.append(String(year))
        }
        if let edition = item.editionTitle {
            parts.append(edition)
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Button(action: { onTap?() }) {
            ZStack(alignment: .bottomLeading) {
                // Backdrop image
                CachedAsyncImage(url: imageURL, maxPixelSize: ImageCache.fillPixelSize(width: width, height: height))
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipped()
                    .background(Color.white.opacity(0.05))
                    .accessibilityHidden(true)

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
                        // For episodes, show the show name (grandparentTitle)
                        // For movies, show the movie title
                        Text(item.type == "episode" ? (item.grandparentTitle ?? item.title) : item.title)
                            .font(.flixor(.bodyLarge, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if let label = item.episodeLabel {
                            Text(label)
                                .font(.flixor(.footnote))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                        } else if item.year != nil || item.editionTitle != nil {
                            // For movies/shows, show year and edition
                            Text(yearEditionText)
                                .font(.flixor(.footnote))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                        }
                    }
                    .padding(DS.Space.s12)
                    .transition(.opacity)
                }

                // Progress bar overlay (optional)
                if progressPercentage > 0 {
                    VStack {
                        Spacer()
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.2))
                                    .frame(height: 6)

                                Rectangle()
                                    .fill(theme.accent)
                                    .frame(width: geometry.size.width * CGFloat(min(100, max(0, progressPercentage))) / 100.0, height: 6)
                            }
                        }
                        .frame(height: 6)
                    }
                }
            }
            .frame(width: width, height: height)
            .overlay(alignment: .topLeading) {
                if let rating = ratingBadgeValue {
                    CardRatingBadge(rating: rating).padding(DS.Space.s8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(isHovered ? 0.9 : 0.15), lineWidth: isHovered ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .cardInteractions(item: item, cornerRadius: cornerRadius, isHovered: $isHovered, onOpen: onTap)
        .task(id: item.id) {
            await fetchTMDBBackdrop()
        }
    }

    // MARK: - TMDB Backdrop Upgrade

    /// The looked-up TMDB backdrop (English, with title text, first), else the
    /// item's own artwork. Any TMDB URL is sized to the card (w780 at 420 pt).
    private var imageURL: URL? {
        let url: URL?
        if let resolved = altURL ?? ArtworkLookup.cachedURL(.backdrop, for: item) {
            url = resolved
        } else if ImageService.isTMDBImageURL(item.art), let art = item.art {
            url = URL(string: art)
        } else {
            url = ImageService.shared.continueWatchingURL(for: item, width: Int(width * 2), height: Int(height * 2))
        }
        return ImageService.tmdbImageURL(url, size: ImageService.tmdbBackdropSize(forPointWidth: width))
    }

    private func fetchTMDBBackdrop() async {
        let url = await ArtworkLookup.resolve(.backdrop, for: item)
        guard !Task.isCancelled, let url, url != altURL else { return }
        altURL = url
    }
}
#if DEBUG && canImport(PreviewsMacros)
#Preview {
    HStack(spacing: DS.Space.s20) {
        LandscapeCard(
            item: MediaItem(
                id: "1",
                title: "The Matrix",
                type: "movie",
                thumb: nil,
                art: "/library/metadata/1/art/123456",
                year: 1999,
                rating: 8.7,
                duration: 8100000,
                viewOffset: nil,
                summary: nil,
                grandparentTitle: nil,
                grandparentThumb: nil,
                grandparentArt: nil,
                parentIndex: nil,
                index: nil
            ),
            width: 420
        )

        LandscapeCard(
            item: MediaItem(
                id: "2",
                title: "Breaking Bad - S1:E2",
                type: "episode",
                thumb: nil,
                art: "/library/metadata/2/art/123457",
                year: nil,
                rating: nil,
                duration: nil,
                viewOffset: nil,
                summary: nil,
                grandparentTitle: "Breaking Bad",
                grandparentThumb: nil,
                grandparentArt: "/library/metadata/show1/art/123",
                parentIndex: 1,
                index: 2
            ),
            width: 420
        )
    }
    .padding()
    .background(Color.black)
}
#endif
