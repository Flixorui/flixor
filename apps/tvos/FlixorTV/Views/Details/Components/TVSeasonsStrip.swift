import SwiftUI

struct TVSeasonsStrip: View {
    @ObservedObject var vm: TVDetailsViewModel
    var focusNS: Namespace.ID
    var defaultFocus: Bool

    var body: some View {
        if vm.isSeason {
            // Season-only mode: no strip
            EmptyView()
        } else if !vm.seasons.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(vm.seasons) { season in
                        let selected = vm.selectedSeasonKey == season.id
                        Text(season.title)
                            .font(.headline)
                            .foregroundStyle(selected ? Color.black : .white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(selected ? Color.white : Color.white.opacity(0.18)))
                            .overlay(Capsule().stroke(Color.white.opacity(selected ? 0.0 : 0.25), lineWidth: 1))
                            .focusable(true)
                            .prefersDefaultFocus(defaultFocus && selected, in: focusNS)
                            .onTapGesture { Task { await vm.selectSeason(season.id) } }
                    }
                }
                .padding(.horizontal, 48)
            }
        }
    }
}
