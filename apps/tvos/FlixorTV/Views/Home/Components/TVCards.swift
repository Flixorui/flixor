import SwiftUI
import FlixorKit

// MARK: - Image helper
struct TVImage: View {
    let url: URL?
    let corner: CGFloat
    let aspect: CGFloat // width / height

    init(url: URL?, corner: CGFloat = 14, aspect: CGFloat) {
        self.url = url
        self.corner = corner
        self.aspect = aspect
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    LinearGradient(colors: [Color.black.opacity(0.2), Color.black.opacity(0.0)], startPoint: .bottom, endPoint: .top)
                        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
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
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

// MARK: - Poster (2:3)
struct TVPosterCard: View {
    let item: MediaItem
    let isFocused: Bool
    var body: some View {
        TVImage(url: ImageService.shared.thumbURL(for: item, width: 360, height: 540), corner: 16, aspect: 2/3)
            .scaleEffect(isFocused ? 1.08 : 1.0)
            .shadow(color: .black.opacity(isFocused ? 0.6 : 0.3), radius: isFocused ? 18 : 8, y: 6)
            .animation(.easeOut(duration: 0.2), value: isFocused)
    }
}

// MARK: - Landscape (16:9)
struct TVLandscapeCard: View {
    let item: MediaItem
    let showBadges: Bool
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            TVImage(url: ImageService.shared.continueWatchingURL(for: item, width: 960, height: 540), corner: 18, aspect: 16/9)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.system(size: 28, weight: .semibold))
                if showBadges {
                    HStack(spacing: 8) {
                        Text("Comedy").opacity(0.85)
                        Text("2024").opacity(0.85)
                        Text("TV‑14").opacity(0.85)
                    }
                    .font(.system(size: 18, weight: .medium))
                }
            }
            .foregroundStyle(.white)
            .padding(18)
            .shadow(color: .black.opacity(0.6), radius: 12, y: 4)
        }
    }
}

// MARK: - Expanded Preview (morph target)
struct TVExpandedPreviewCard: View {
    let item: MediaItem
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TVLandscapeCard(item: item, showBadges: true)
            Text("A group of armed men take hundreds hostage in a real‑life heist…")
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
    }
}
