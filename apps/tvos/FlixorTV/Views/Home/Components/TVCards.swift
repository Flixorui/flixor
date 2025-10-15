import SwiftUI
import FlixorKit

// MARK: - Image helper
struct TVImage: View {
    enum Layout { case aspect(CGFloat), heightFixed(CGFloat) }

    let url: URL?
    let corner: CGFloat
    let layout: Layout

    init(url: URL?, corner: CGFloat = 14, aspect: CGFloat) {
        self.url = url
        self.corner = corner
        self.layout = .aspect(aspect)
    }

    init(url: URL?, corner: CGFloat = 14, height: CGFloat) {
        self.url = url
        self.corner = corner
        self.layout = .heightFixed(height)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        ZStack {
            shape
                .fill(Color.white.opacity(0.06))
                .overlay(
                    LinearGradient(colors: [Color.black.opacity(0.2), Color.black.opacity(0.0)], startPoint: .bottom, endPoint: .top)
                        .clipShape(shape)
                )
            // Use AsyncImage when URL is provided; otherwise keep placeholder
            if let url = url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        Color.white.opacity(0.04)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Color.white.opacity(0.04)
                    @unknown default:
                        Color.white.opacity(0.04)
                    }
                }
                .clipShape(shape)
            }
        }
        .modifier(LayoutModifier(layout: layout))
        .clipShape(shape)
        .overlay(shape.stroke(Color.white.opacity(0.12), lineWidth: 1))
        .contentShape(shape)
    }
}

private struct LayoutModifier: ViewModifier {
    let layout: TVImage.Layout
    func body(content: Content) -> some View {
        switch layout {
        case .aspect(let ar):
            content.aspectRatio(ar, contentMode: .fit)
        case .heightFixed(let h):
            content
                .frame(maxWidth: .infinity)
                .frame(height: h)
        }
    }
}

// MARK: - Poster (2:3)
struct TVPosterCard: View {
    let item: MediaItem
    let isFocused: Bool
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            TVImage(url: ImageService.shared.thumbURL(for: item, width: 360, height: 540), corner: UX.posterRadius, aspect: 2/3)
            if isFocused {
                LinearGradient(colors: [Color.black.opacity(0.6), .clear], startPoint: .bottom, endPoint: .top)
                    .clipShape(RoundedRectangle(cornerRadius: UX.posterRadius, style: .continuous))
                Text(item.title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(12)
            }

            // Progress overlay for Continue Watching items
            if let viewOffset = item.viewOffset, let duration = item.duration, duration > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.25))
                        Capsule().fill(Color.white)
                            .frame(width: max(2, geo.size.width * CGFloat(viewOffset) / CGFloat(duration)))
                    }
                    .frame(height: 6)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
        }
        // scale/shadow handled by row wrapper for consistent neighbor treatment
    }
}

// MARK: - Landscape (16:9)
struct TVLandscapeCard: View {
    let item: MediaItem
    let showBadges: Bool
    var isFocused: Bool = false
    var outlined: Bool = false
    var heightOverride: CGFloat? = nil
    var overrideURL: URL? = nil

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                let imgURL = overrideURL ?? ImageService.shared.continueWatchingURL(for: item, width: 960, height: 540)
                if let h = heightOverride {
                    TVImage(url: imgURL, corner: UX.landscapeRadius, height: h)
                } else {
                    TVImage(url: imgURL, corner: UX.landscapeRadius, aspect: 16/9)
                }
            }
            LinearGradient(colors: [Color.black.opacity(0.65), Color.black.opacity(0.0)], startPoint: .bottom, endPoint: .top)
                .clipShape(RoundedRectangle(cornerRadius: UX.landscapeRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.system(size: 28, weight: .semibold))
                    .lineLimit(1)
                if showBadges {
                    HStack(spacing: 6) {
                        Text("HD").font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.white.opacity(0.18)).clipShape(Capsule())
                        Text("5.1").font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.white.opacity(0.18)).clipShape(Capsule())
                    }
                }

                if let viewOffset = item.viewOffset, let duration = item.duration, duration > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.25))
                            Capsule().fill(Color.white)
                                .frame(width: max(2, geo.size.width * CGFloat(viewOffset) / CGFloat(duration)))
                        }
                    }
                    .frame(height: 6)
                    .padding(.top, 6)

                    // time-left pill overlay for Continue Watching parity
                    if duration > viewOffset {
                        let remaining = max(0, (duration - viewOffset) / 60000)
                        Text("\(remaining)m left")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.18))
                            .clipShape(Capsule())
                            .padding(.top, 6)
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(18)
            .shadow(color: .black.opacity(0.6), radius: 12, y: 4)
            .overlay(
                Group {
                    if outlined {
                        RoundedRectangle(cornerRadius: UX.landscapeRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.85), lineWidth: 2)
                    }
                }
            )
        }
    }
}

// MARK: - Expanded Preview (morph target)
struct TVExpandedPreviewCard: View {
    let item: MediaItem
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TVLandscapeCard(item: item, showBadges: true, outlined: true)
            TVHoverMeta(item: item)
        }
        .padding(.horizontal, 12)
    }
}

// Hover metadata block used under expanded preview
struct TVHoverMeta: View {
    let item: MediaItem
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TVMetaLine(item: item)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white)
                .opacity(0.9)
            if let summary = item.summary, !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
            }
        }
    }
}

// Local meta line (year • runtime • ★ rating)
struct TVMetaLine: View {
    let item: MediaItem

    enum Segment: Hashable { case year(Int), duration(Int), rating(Double) }

    var segments: [Segment] {
        var s: [Segment] = []
        if let y = item.year { s.append(.year(y)) }
        if let d = item.duration, d > 0 { s.append(.duration(d)) }
        if let r = item.rating, r > 0 { s.append(.rating(r)) }
        return s
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(segments.enumerated()), id: \.offset) { idx, seg in
                HStack(spacing: 6) {
                    switch seg {
                    case .year(let y): Text(String(y))
                    case .duration(let d): Text("\(d / 60000)m")
                    case .rating(let r): HStack(spacing: 4) {
                        Image(systemName: "star.fill").font(.system(size: 16))
                        Text(String(format: "%.1f", r))
                    }
                    }
                    if idx < segments.count - 1 { Text("•").opacity(0.7) }
                }
            }
        }
    }
}
