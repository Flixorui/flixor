//
//  PosterCard.swift
//  FlixorMac
//
//  Vertical poster card for movies/shows
//

import SwiftUI

struct PosterCard: View {
    let item: MediaItem
    let width: CGFloat
    var showTitle: Bool = true
    var showProgress: Bool = false
    var badge: AnyView? = nil
    var topTrailingOverlay: AnyView? = nil
    var isSelected: Bool = false
    var customImageURL: URL? = nil
    var onTap: (() -> Void)?

    @State private var isHovered = false

    private var height: CGFloat {
        width * 1.5 // 2:3 aspect ratio
    }

    private var progressPercentage: Double {
        guard let duration = item.duration, duration > 0,
              let viewOffset = item.viewOffset else {
            return 0
        }
        return Double(viewOffset) / Double(duration)
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
        VStack(alignment: .leading, spacing: 8) {
            // Poster Image
            Button(action: {
                onTap?()
            }) {
                ZStack(alignment: .bottom) {
                    CachedAsyncImage(
                        url: customImageURL ?? ImageService.shared.thumbURL(for: item, width: Int(width * 2), height: Int(height * 2))
                    )
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipped()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(isSelected ? 1.0 : (isHovered ? 0.9 : 0.15)),
                                   lineWidth: isSelected ? 2 : (isHovered ? 2 : 1))
                    )
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                    .overlay(alignment: .topLeading) {
                        // Badge overlay (e.g., source badges)
                        if let badge = badge {
                            badge.padding(8)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        // Top trailing overlay (e.g., watchlist button)
                        if let overlay = topTrailingOverlay {
                            overlay.padding(10)
                        }
                    }

                    // Progress bar
                    if showProgress && progressPercentage > 0 {
                        GeometryReader { geometry in
                            VStack(spacing: 0) {
                                Spacer()

                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.3))
                                        .frame(height: 4)

                                    Rectangle()
                                        .fill(Color.red)
                                        .frame(width: geometry.size.width * progressPercentage, height: 4)
                                }
                            }
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }

            // Title
            if showTitle {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .frame(width: width, alignment: .leading)

                    if item.year != nil || item.editionTitle != nil {
                        Text(yearEditionText)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(width: width)
    }
}
#if DEBUG && canImport(PreviewsMacros)
#Preview {
    HStack(spacing: 12) {
        PosterCard(
            item: MediaItem(
                id: "1",
                title: "The Matrix",
                type: "movie",
                thumb: "/library/metadata/1/thumb/123456",
                art: nil,
                year: 1999,
                rating: 8.7,
                duration: 8100000,
                viewOffset: nil,
                summary: "A computer hacker learns about the true nature of reality.",
                grandparentTitle: nil,
                grandparentThumb: nil,
                grandparentArt: nil,
                grandparentRatingKey: nil,
                parentIndex: nil,
                index: nil,
                parentRatingKey: nil,
                parentTitle: nil,
                leafCount: nil,
                viewedLeafCount: nil,
                editionTitle: "Theatrical Cut"
            ),
            width: 150
        )

        PosterCard(
            item: MediaItem(
                id: "2",
                title: "Inception",
                type: "movie",
                thumb: "/library/metadata/2/thumb/123457",
                art: nil,
                year: 2010,
                rating: 8.8,
                duration: 8880000,
                viewOffset: 4440000,
                summary: nil,
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
            ),
            width: 150,
            showProgress: true
        )
    }
    .padding()
    .background(Color.black)
}
#endif
