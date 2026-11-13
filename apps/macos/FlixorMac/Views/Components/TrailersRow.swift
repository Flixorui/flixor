//
//  TrailersRow.swift
//  FlixorMac
//
//  Horizontal row of video trailers with YouTube thumbnail previews
//

import SwiftUI

// MARK: - Trailer Model

struct Trailer: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let key: String  // YouTube video ID; the provider's own id for direct streams
    let site: String // "YouTube", or "Apple TV" for direct streams
    let type: String // "Trailer", "Teaser", "Featurette", etc.
    let official: Bool?
    let publishedAt: String?
    /// Direct HLS or MP4 stream (Apple TV trailers from MyBluray). Played in
    /// AVPlayer instead of YouTube when set.
    var streamURL: URL? = nil
    /// Artwork for direct streams; YouTube trailers use YouTube's thumbnail.
    var imageURL: URL? = nil
    var durationSeconds: Double? = nil
    /// A YouTube trailer for the same title, played if the direct stream fails.
    var fallbackYouTubeKey: String? = nil

    var isDirect: Bool { streamURL != nil }

    /// The type label, unless the name already says it ("Trailer" / "Trailer").
    var typeLabel: String? {
        let name = self.name.trimmingCharacters(in: .whitespaces).lowercased()
        let kind = type.trimmingCharacters(in: .whitespaces).lowercased()
        guard !kind.isEmpty, name != kind else { return nil }
        return type
    }

    var thumbnailURL: URL? {
        if let imageURL { return imageURL }
        guard site.lowercased() == "youtube" else { return nil }
        return URL(string: "https://img.youtube.com/vi/\(key)/mqdefault.jpg")
    }

    /// The YouTube video to play: this trailer's own, or the fallback for a
    /// direct stream.
    var youtubeKey: String? {
        site.lowercased() == "youtube" ? key : fallbackYouTubeKey
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
    var title: String = String(localized: "Videos")
    var onPlay: ((Trailer) -> Void)?

    private let cardWidth: CGFloat = 320
    private var cardHeight: CGFloat { cardWidth * 0.5625 } // 16:9

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s12) {
            // Header - styled like DetailsSectionHeader
            Text(title)
                .font(.flixor(.title3, weight: .bold))
                .foregroundStyle(.white.opacity(0.95))
                .padding(.horizontal, DS.Space.s24)

            // Horizontal scroll of trailer cards
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: DS.Space.s16) {
                    ForEach(trailers) { trailer in
                        TrailerCard(
                            trailer: trailer,
                            width: cardWidth,
                            onPlay: { onPlay?(trailer) }
                        )
                    }
                }
                .padding(.leading, DS.Space.s24)
                .padding(.trailing, DS.Space.s60)
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
                VStack(alignment: .leading, spacing: DS.Space.s4) {
                    Spacer()

                    // Quiet type label (red is kept for "on" and progress).
                    if let label = trailer.typeLabel {
                        TrailerTypeLabel(text: label)
                    }

                    // Title
                    Text(trailer.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.7), radius: 4)
                }
                .padding(DS.Space.s12)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.r12, style: .continuous)
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

}

/// "Teaser", "Featurette"…: a small frosted label on the trailer art.
struct TrailerTypeLabel: View {
    let text: String
    var compact = false

    var body: some View {
        Text(compact ? text.uppercased() : text)
            .font(.flixor(compact ? .nano : .micro, weight: .semibold))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, compact ? DS.Space.s6 : DS.Space.s8)
            .padding(.vertical, compact ? DS.Space.s2 : 3)
            .background(Capsule().fill(.ultraThinMaterial))
            .background(Capsule().fill(Color.black.opacity(0.35)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: DS.Border.thin))
    }
}
