//
//  TrailersRow.swift
//  FlixorMac
//
//  Horizontal row of video trailers with YouTube thumbnail previews
//

import SwiftUI

// MARK: - Trailer Model

struct Trailer: Identifiable, Codable {
    let id: String
    let name: String
    let key: String  // YouTube video ID
    let site: String // Usually "YouTube"
    let type: String // "Trailer", "Teaser", "Featurette", etc.
    let official: Bool?
    let publishedAt: String?

    var thumbnailURL: URL? {
        guard site.lowercased() == "youtube" else { return nil }
        return URL(string: "https://img.youtube.com/vi/\(key)/mqdefault.jpg")
    }

    var youtubeURL: URL? {
        guard site.lowercased() == "youtube" else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(key)")
    }

    var embedURL: URL? {
        guard site.lowercased() == "youtube" else { return nil }
        // Use youtube-nocookie for better embed support in WKWebView
        return URL(string: "https://www.youtube-nocookie.com/embed/\(key)?autoplay=1&rel=0&modestbranding=1&playsinline=1")
    }
}

// MARK: - Trailers Row

struct TrailersRow: View {
    let trailers: [Trailer]
    var title: String = "Videos"
    var onPlay: ((Trailer) -> Void)?

    private let cardWidth: CGFloat = 320
    private var cardHeight: CGFloat { cardWidth * 0.5625 } // 16:9

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header - styled like DetailsSectionHeader
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white.opacity(0.95))
                .padding(.horizontal, 24)

            // Horizontal scroll of trailer cards
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(trailers) { trailer in
                        TrailerCard(
                            trailer: trailer,
                            width: cardWidth,
                            onPlay: { onPlay?(trailer) }
                        )
                    }
                }
                .padding(.leading, 24)
                .padding(.trailing, 60)
            }
        }
    }
}

// MARK: - Trailer Card

struct TrailerCard: View {
    let trailer: Trailer
    let width: CGFloat
    var onPlay: (() -> Void)?

    @State private var isHovered = false

    private var height: CGFloat { width * 0.5625 } // 16:9

    var body: some View {
        Button(action: { onPlay?() }) {
            ZStack(alignment: .bottomLeading) {
                // Thumbnail
                CachedAsyncImage(url: trailer.thumbnailURL)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipped()
                    .background(Color.gray.opacity(0.2))

                // Play overlay
                ZStack {
                    Color.black.opacity(isHovered ? 0.5 : 0.3)

                    Image(systemName: "play.circle.fill")
                        .font(.system(size: isHovered ? 56 : 48))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 10)
                        .scaleEffect(isHovered ? 1.1 : 1.0)
                }

                // Gradient overlay for text
                LinearGradient(
                    colors: [.clear, .black.opacity(0.8)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Spacer()

                    // Type badge
                    Text(trailer.type)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(badgeColor(for: trailer.type))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.white)

                    // Title
                    Text(trailer.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.7), radius: 4)
                }
                .padding(12)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(isHovered ? 0.6 : 0.1), lineWidth: isHovered ? 2 : 1)
            )
            .shadow(color: .black.opacity(isHovered ? 0.5 : 0.3), radius: isHovered ? 16 : 8, y: isHovered ? 8 : 4)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func badgeColor(for type: String) -> Color {
        switch type.lowercased() {
        case "trailer":
            return Color.red.opacity(0.8)
        case "teaser":
            return Color.orange.opacity(0.8)
        case "featurette":
            return Color.purple.opacity(0.8)
        case "behind the scenes":
            return Color.blue.opacity(0.8)
        case "clip":
            return Color.green.opacity(0.8)
        default:
            return Color.gray.opacity(0.8)
        }
    }
}
