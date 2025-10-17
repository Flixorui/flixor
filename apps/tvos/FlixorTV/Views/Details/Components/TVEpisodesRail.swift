import SwiftUI

struct TVEpisodesRail: View {
    @ObservedObject var vm: TVDetailsViewModel
    var focusNS: Namespace.ID
    var defaultFocus: Bool

    var body: some View {
        if vm.episodesLoading {
            HStack { ProgressView().tint(.white) }.padding(.horizontal, 48)
        } else if !vm.episodes.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(Array(vm.episodes.enumerated()), id: \.element.id) { index, ep in
                        ZStack(alignment: .bottomLeading) {
                            TVImage(url: ep.image, corner: UX.landscapeRadius, aspect: 16/9)
                            LinearGradient(colors: [Color.black.opacity(0.65), .clear], startPoint: .bottom, endPoint: .top)
                                .clipShape(RoundedRectangle(cornerRadius: UX.landscapeRadius, style: .continuous))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ep.title)
                                    .font(.headline)
                                HStack(spacing: 10) {
                                    if let d = ep.durationMin { Text("\(d)m").foregroundStyle(.white.opacity(0.85)) }
                                    if let p = ep.progressPct { Text("\(p)%").foregroundStyle(.white.opacity(0.85)) }
                                }
                                .font(.footnote)
                            }
                            .padding(12)
                        }
                        .frame(width: 960 * 0.6, height: 540 * 0.6)
                        .overlay(progressOverlay(ep))
                        .focusable(true)
                        .prefersDefaultFocus(defaultFocus && index == 0, in: focusNS)
                    }
                }
                .padding(.horizontal, 48)
            }
        }
    }

    private func progressOverlay(_ ep: TVDetailsViewModel.Episode) -> some View {
        GeometryReader { geo in
            VStack {
                Spacer()
                if let d = ep.durationMin, let viewOffset = ep.viewOffset {
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
