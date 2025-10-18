import SwiftUI

struct TVEpisodesRail: View {
    @ObservedObject var vm: TVDetailsViewModel
    var focusNS: Namespace.ID

    var body: some View {
        if vm.episodesLoading {
            HStack { ProgressView().tint(.white) }.padding(.horizontal, 48)
        } else if !vm.episodes.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(Array(vm.episodes.enumerated()), id: \.element.id) { index, ep in
                        EpisodeCard(episode: ep)
                    }
                }
                .padding(.horizontal, 48)
            }
        }
    }

}

// MARK: - Episode Card with Focus
private struct EpisodeCard: View {
    let episode: TVDetailsViewModel.Episode
    @State private var isFocused = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            TVImage(url: episode.image, corner: UX.landscapeRadius, aspect: 16/9)
            LinearGradient(colors: [Color.black.opacity(0.65), .clear], startPoint: .bottom, endPoint: .top)
                .clipShape(RoundedRectangle(cornerRadius: UX.landscapeRadius, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(episode.title)
                    .font(.headline)
                HStack(spacing: 10) {
                    if let d = episode.durationMin { Text("\(d)m").foregroundStyle(.white.opacity(0.85)) }
                    if let p = episode.progressPct { Text("\(p)%").foregroundStyle(.white.opacity(0.85)) }
                }
                .font(.footnote)
            }
            .padding(12)
        }
        .frame(width: 960 * 0.6, height: 540 * 0.6)
        .overlay(progressOverlay)
        .overlay(
            RoundedRectangle(cornerRadius: UX.landscapeRadius, style: .continuous)
                .stroke(Color.white.opacity(isFocused ? 0.8 : 0.0), lineWidth: 4)
        )
        .scaleEffect(isFocused ? UX.focusScale : 1.0)
        .shadow(color: .black.opacity(isFocused ? 0.4 : 0.0), radius: 16, y: 8)
        .focusable(true) { focused in isFocused = focused }
        .animation(.easeOut(duration: UX.focusDur), value: isFocused)
    }

    private var progressOverlay: some View {
        GeometryReader { geo in
            VStack {
                Spacer()
                if let d = episode.durationMin, let viewOffset = episode.viewOffset {
                    let durationMs = d * 60_000
                    let progress = min(1.0, max(0.0, Double(viewOffset) / Double(durationMs)))
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.25))
                        Capsule().fill(Color.white).frame(width: max(2, geo.size.width * progress))
                    }
                    .frame(height: 6)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
            }
        }
    }
}
