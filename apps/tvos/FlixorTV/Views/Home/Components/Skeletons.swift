import SwiftUI

struct SkeletonPoster: View {
    var body: some View {
        RoundedRectangle(cornerRadius: UX.posterRadius, style: .continuous)
            .fill(Color.white.opacity(0.08))
            .frame(width: UX.posterWidth, height: UX.posterHeight)
            .shimmer()
    }
}

struct SkeletonLandscape: View {
    var body: some View {
        RoundedRectangle(cornerRadius: UX.landscapeRadius, style: .continuous)
            .fill(Color.white.opacity(0.08))
            .frame(width: UX.landscapeWidth, height: UX.landscapeHeight)
            .shimmer()
    }
}

struct SkeletonRow: View {
    let title: String
    let poster: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, UX.gridH)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: UX.itemSpacing) {
                    ForEach(0..<8, id: \.self) { _ in
                        if poster { SkeletonPoster() } else { SkeletonLandscape() }
                    }
                }
                .padding(.horizontal, UX.gridH)
                .frame(height: poster ? UX.posterHeight : UX.landscapeHeight)
            }
        }
    }
}
