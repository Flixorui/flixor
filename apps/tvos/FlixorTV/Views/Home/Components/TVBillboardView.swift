import SwiftUI
import FlixorKit

struct TVBillboardView: View {
    let item: MediaItem
    var focusNS: Namespace.ID? = nil
    var defaultFocus: Bool = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Backdrop
            TVImage(
                url: ImageService.shared.artURL(for: item, width: 1920, height: 1080),
                corner: UX.billboardRadius,
                height: 800
            )
            .overlay(
                // 3-stop gradient per spec: 0.55 → 0.1 → 0 alpha
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color.black.opacity(0.65), location: 0.0),
                        .init(color: Color.black.opacity(0.18), location: 0.55),
                        .init(color: .clear, location: 1.0)
                    ]),
                    startPoint: .bottom,
                    endPoint: .top
                )
                .clipShape(RoundedRectangle(cornerRadius: UX.billboardRadius, style: .continuous))
            )
            .overlay(
                // Subtle outer stroke to lift the billboard
                RoundedRectangle(cornerRadius: UX.billboardRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 18, y: 8)

            // Text + actions
            VStack(alignment: .leading, spacing: 14) {
                // Display clear logo if available, otherwise fallback to text title
                if let logoURL = item.logo, let url = URL(string: logoURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 500, maxHeight: 140, alignment: .leading)
                                .shadow(color: .black.opacity(0.8), radius: 12, x: 0, y: 4)
                        case .failure, .empty:
                            // Fallback to text if logo fails to load
                            Text(item.title)
                                .font(.system(size: 56, weight: .bold))
                                .lineLimit(2)
                        @unknown default:
                            Text(item.title)
                                .font(.system(size: 56, weight: .bold))
                                .lineLimit(2)
                        }
                    }
                } else {
                    // No logo available, use text title
                    Text(item.title)
                        .font(.system(size: 56, weight: .bold))
                        .lineLimit(2)
                }

                MetaLine(item: item)
                    .font(.system(size: 22, weight: .medium))
                    .opacity(0.9)

                if let summary = item.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 22))
                        .opacity(0.85)
                        .lineLimit(3)
                        .frame(maxWidth: 1000, alignment: .leading)
                }

                HStack(spacing: 16) {
                    CTAButton(title: item.viewOffset != nil ? "Resume" : "Play", systemName: "play.fill", style: .primary)
                        .applyDefaultBillboardFocus(ns: focusNS, enabled: defaultFocus)

                    NavigationLink(value: item) {
                        HStack(spacing: 10) {
                            Image(systemName: "info.circle")
                            Text("More Info")
                        }
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.18))
                        )
                    }
                    .buttonStyle(.plain)

                    CTAButton(title: "My List", systemName: "plus", style: .secondary)
                }
                .focusSection()
                .padding(.top, 8)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 20)
        }
        .padding(.horizontal, UX.billboardSide)
        .frame(height: 820)
    }
}

// MARK: - Metadata line with separators
private struct MetaLine: View {
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

private struct CTAButton: View {
    enum Style { case primary, secondary }
    let title: String
    let systemName: String
    let style: Style

    @State private var focused = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemName)
            Text(title)
        }
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(style == .primary ? Color.black : Color.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(style == .primary ? Color.white : Color.white.opacity(focused ? 0.18 : 0.10))
        )
        .overlay(
            Capsule().stroke(Color.white.opacity(style == .secondary && focused ? 0.35 : 0.0), lineWidth: 1)
        )
        .focusable(true) { focused in self.focused = focused }
        .scaleEffect(focused ? UX.focusScale : 1.0)
        .animation(.easeOut(duration: 0.18), value: focused)
    }
}

private extension View {
    @ViewBuilder
    func applyDefaultBillboardFocus(ns: Namespace.ID?, enabled: Bool) -> some View {
        if let ns, enabled {
            self.prefersDefaultFocus(true, in: ns)
        } else {
            self
        }
    }
}
