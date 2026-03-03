import SwiftUI

struct TVEpisodesRail: View {
    @ObservedObject var vm: TVDetailsViewModel
    var focusNS: Namespace.ID
    let focusScreenKey: String
    let focusRestoreToken: UUID
    let shouldRestoreFocus: Bool
    var onFocusChange: ((Bool) -> Void)?

    @EnvironmentObject private var profileSettings: TVProfileSettings
    @EnvironmentObject private var focusCoordinator: TVFocusCoordinator

    @FocusState private var focusedSeasonID: String?
    @FocusState private var focusedEpisodeID: String?

    var body: some View {
        Group {
            if vm.episodesLoading {
                HStack {
                    ProgressView().progressViewStyle(.circular).tint(.white)
                    Text("Loading episodes…")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 80)
            } else if vm.episodes.isEmpty {
                Text("No episodes available")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 80)
            } else {
                HStack(alignment: .top, spacing: 48) {
                    if !vm.isSeason && !vm.seasons.isEmpty {
                        SeasonSidebar(
                            vm: vm,
                            focusedSeasonID: $focusedSeasonID,
                            onFocusChange: onFocusChange
                        )
                        .frame(width: 320, alignment: .topLeading)
                    }

                    EpisodeList(
                        vm: vm,
                        focusNS: focusNS,
                        focusedEpisodeID: $focusedEpisodeID,
                        onFocusChange: onFocusChange
                    )
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 32)
                .background(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.05),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .background(Color.black.opacity(0.35))
                )
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 26, y: 18)
                .padding(.horizontal, 16)
            }
        }
        .onAppear {
            guard shouldRestoreFocus else { return }
            restoreFocusIfNeeded()
        }
        .onChange(of: focusRestoreToken) { _ in
            guard shouldRestoreFocus else { return }
            restoreFocusIfNeeded()
        }
        .onChange(of: vm.episodes.map(\.id)) { _ in
            guard shouldRestoreFocus || focusedSeasonID != nil || focusedEpisodeID != nil else { return }
            restoreFocusIfNeeded()
        }
        .onChange(of: focusedEpisodeID) { newValue in
            guard let newValue else { return }
            focusCoordinator.remember(screen: focusScreenKey, sectionID: "episodes", itemID: newValue)
            onFocusChange?(true)
        }
        .onChange(of: focusedSeasonID) { newValue in
            guard let newValue else { return }
            focusCoordinator.remember(screen: focusScreenKey, sectionID: "season", itemID: newValue)
            onFocusChange?(true)
        }
    }

    private func restoreFocusIfNeeded() {
        let rememberedSection = focusCoordinator.lastFocusedSection(screen: focusScreenKey)
        if rememberedSection == "season",
           let rememberedSeasonID = focusCoordinator.lastFocusedItem(screen: focusScreenKey, sectionID: "season"),
           vm.seasons.contains(where: { $0.id == rememberedSeasonID }) {
            DispatchQueue.main.async {
                focusedSeasonID = rememberedSeasonID
            }
            return
        }

        guard !vm.episodes.isEmpty else { return }
        let rememberedEpisodeID = focusCoordinator.lastFocusedItem(screen: focusScreenKey, sectionID: "episodes")
        if let rememberedEpisodeID,
           vm.episodes.contains(where: { $0.id == rememberedEpisodeID }) {
            DispatchQueue.main.async {
                focusedEpisodeID = rememberedEpisodeID
            }
            return
        }

        if let focusedEpisodeID,
           vm.episodes.contains(where: { $0.id == focusedEpisodeID }) {
            return
        }

        DispatchQueue.main.async {
            focusedEpisodeID = vm.episodes.first?.id
        }
    }
}

private struct SeasonSidebar: View {
    @ObservedObject var vm: TVDetailsViewModel
    var focusedSeasonID: FocusState<String?>.Binding
    var onFocusChange: ((Bool) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Seasons")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.bottom, 8)

            ForEach(vm.seasons) { season in
                SeasonRow(
                    season: season,
                    isSelected: vm.selectedSeasonKey == season.id,
                    focusedSeasonID: focusedSeasonID,
                    onSelect: {
                        Task { await vm.selectSeason(season.id) }
                    },
                    onFocusChange: onFocusChange
                )
            }
        }
    }
}

private struct SeasonRow: View {
    let season: TVDetailsViewModel.Season
    let isSelected: Bool
    var focusedSeasonID: FocusState<String?>.Binding
    let onSelect: () -> Void
    var onFocusChange: ((Bool) -> Void)?

    @State private var isFocused = false

    private var backgroundColor: Color {
        if isFocused || isSelected {
            return Color.white.opacity(isFocused ? 0.2 : 0.12)
        }
        return Color.white.opacity(0.05)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(season.title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(textColor)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(isFocused ? 0.45 : (isSelected ? 0.25 : 0.08)), lineWidth: isFocused ? 3 : 1)
        )
        .focusable(true) { focus in
            isFocused = focus
            if focus {
                onFocusChange?(true)
                if !isSelected {
                    onSelect()
                }
            }
        }
        .focused(focusedSeasonID, equals: season.id)
        .onTapGesture {
            if !isSelected { onSelect() }
        }
        .animation(.easeOut(duration: UX.focusDur), value: isFocused)
        .animation(.easeOut(duration: 0.18), value: isSelected)
    }

    private var textColor: Color {
        if isSelected {
            return Color.white
        } else if isFocused {
            return Color.white.opacity(0.9)
        } else {
            return Color.white.opacity(0.7)
        }
    }
}

private struct EpisodeList: View {
    @ObservedObject var vm: TVDetailsViewModel
    var focusNS: Namespace.ID
    var focusedEpisodeID: FocusState<String?>.Binding
    var onFocusChange: ((Bool) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(headerTitle)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.bottom, 4)

            ForEach(Array(vm.episodes.enumerated()), id: \.element.id) { index, episode in
                EpisodeRow(
                    index: index + 1,
                    episode: episode,
                    isDefault: index == 0,
                    focusNS: focusNS,
                    focusedEpisodeID: focusedEpisodeID,
                    onFocusChange: onFocusChange
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerTitle: String {
        if let key = vm.selectedSeasonKey,
           let season = vm.seasons.first(where: { $0.id == key }) {
            return season.title
        }
        if vm.isSeason {
            return vm.title.isEmpty ? "Season" : vm.title
        }
        return "Episodes"
    }
}

private struct EpisodeRow: View {
    let index: Int
    let episode: TVDetailsViewModel.Episode
    let isDefault: Bool
    var focusNS: Namespace.ID
    var focusedEpisodeID: FocusState<String?>.Binding
    var onFocusChange: ((Bool) -> Void)?

    @EnvironmentObject private var profileSettings: TVProfileSettings
    @State private var isFocused = false

    private var shouldBlur: Bool {
        profileSettings.blurUnwatchedEpisodes && !episode.isWatched && episode.viewOffset == nil
    }

    var body: some View {
        HStack(spacing: 26) {
            TVImage(url: episode.image, corner: 18, aspect: 16/9)
                .frame(width: 420, height: 236)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(isFocused ? 0.45 : 0.1), lineWidth: 2)
                )
                .shadow(color: .black.opacity(isFocused ? 0.45 : 0.2), radius: isFocused ? 18 : 8, y: isFocused ? 12 : 6)

            VStack(alignment: .leading, spacing: 10) {
                Text("\(index). \(episode.title)")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if let overview = episode.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(3)
                }

                if let progress = progressValue {
                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .tint(Color(red: 0.898, green: 0.035, blue: 0.078))
                        .frame(width: 320)
                }
            }

            Spacer()

            if let runtime = episode.durationMin {
                Text(runtimeText(for: runtime))
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(isFocused ? Color.white.opacity(0.18) : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(isFocused ? 0.55 : 0.08), lineWidth: isFocused ? 3 : 1)
        )
        .opacity(shouldBlur && !isFocused ? 0.68 : 1.0)
        .scaleEffect(isFocused ? 1.01 : 1.0)
        .focusable(true) { focus in
            isFocused = focus
            if focus {
                onFocusChange?(true)
            }
        }
        .focused(focusedEpisodeID, equals: episode.id)
        .prefersDefaultFocus(isDefault, in: focusNS)
        .animation(.easeOut(duration: UX.focusDur), value: isFocused)
        .animation(.easeOut(duration: 0.2), value: shouldBlur)
    }

    private func runtimeText(for minutes: Int) -> String {
        if minutes >= 60 {
            let hrs = minutes / 60
            let mins = minutes % 60
            if mins == 0 {
                return "\(hrs)h"
            } else {
                return "\(hrs)h \(mins)m"
            }
        }
        return "\(minutes)m"
    }

    private var progressValue: Double? {
        if let viewOffset = episode.viewOffset,
           let duration = episode.durationMin,
           duration > 0 {
            let totalMs = Double(duration) * 60_000
            return min(1.0, max(0.0, Double(viewOffset) / totalMs))
        }
        if let pct = episode.progressPct {
            return min(1.0, max(0.0, Double(pct) / 100.0))
        }
        return nil
    }
}
