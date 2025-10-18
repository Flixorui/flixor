import SwiftUI

struct TVSeasonsStrip: View {
    @ObservedObject var vm: TVDetailsViewModel
    var focusNS: Namespace.ID

    var body: some View {
        if vm.isSeason {
            // Season-only mode: no strip
            EmptyView()
        } else if !vm.seasons.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(vm.seasons) { season in
                        SeasonButton(
                            season: season,
                            isSelected: vm.selectedSeasonKey == season.id,
                            onSelect: { Task { await vm.selectSeason(season.id) } }
                        )
                    }
                }
                .padding(.horizontal, 48)
            }
        }
    }
}

// MARK: - Season Button with Focus
private struct SeasonButton: View {
    let season: TVDetailsViewModel.Season
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isFocused = false

    private var backgroundColor: Color {
        if isSelected && isFocused {
            return Color.white  // Selected + Focused: Full white
        } else if isSelected {
            return Color.white  // Selected only: Full white
        } else if isFocused {
            return Color.white.opacity(0.35)  // Focused only: Brighter
        } else {
            return Color.white.opacity(0.18)  // Default: Dim
        }
    }

    private var textColor: Color {
        if isSelected {
            return Color.black  // Selected: Black text
        } else if isFocused {
            return Color.white  // Focused: Bright white
        } else {
            return Color.white.opacity(0.85)  // Default: Dimmed white
        }
    }

    private var strokeOpacity: Double {
        if isSelected {
            return 0.0  // No stroke when selected
        } else if isFocused {
            return 0.5  // Visible stroke when focused
        } else {
            return 0.25  // Subtle stroke otherwise
        }
    }

    var body: some View {
        Text(season.title)
            .font(.headline)
            .foregroundStyle(textColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Capsule().fill(backgroundColor))
            .overlay(Capsule().stroke(Color.white.opacity(strokeOpacity), lineWidth: 2))
            .scaleEffect(isFocused ? UX.focusScale : 1.0)
            .shadow(color: .black.opacity(isFocused ? 0.35 : 0.0), radius: 12, y: 4)
            .focusable(true) { focused in isFocused = focused }
            .animation(.easeOut(duration: UX.focusDur), value: isFocused)
            .onTapGesture { onSelect() }
    }
}
