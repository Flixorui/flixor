import SwiftUI
import FlixorKit

struct TVNewPopularView: View {
    @ObservedObject private var viewModel: TVNewPopularViewModel
    @EnvironmentObject private var profileSettings: TVProfileSettings
    @EnvironmentObject private var watchlistController: TVWatchlistController
    @Namespace private var focusNS

    @State private var selectedItem: MediaItem?
    @FocusState private var focusedTopControl: String?
    @State private var focusedRowId: String?
    @State private var rowLastFocusedItem: [String: String] = [:]
    @State private var nextRowToReceiveFocus: String?
    @State private var clearNextRowFocusTask: Task<Void, Never>?

    init(viewModel: TVNewPopularViewModel) {
        self._viewModel = ObservedObject(wrappedValue: viewModel)
    }

    var body: some View {
        ZStack {
            UltraBlurGradientBackground(colors: TVHomeViewModel.defaultRowColors)
                .ignoresSafeArea()

            if profileSettings.discoveryDisabled {
                discoveryDisabledView
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            if let hero = viewModel.hero, !viewModel.isLoading {
                                TVNewPopularHero(
                                    data: hero,
                                    onPlay: { openHeroDetails(hero) },
                                    onMoreInfo: { openHeroDetails(hero) },
                                    onMyList: { Task { await addHeroToWatchlist(hero) } },
                                    onTrailer: { openHeroDetails(hero) }
                                )
                            }

                            controls
                                .padding(.horizontal, UX.gridH)
                                .padding(.top, 18)

                            Divider()
                                .overlay(Color.white.opacity(0.14))
                                .padding(.horizontal, UX.gridH)
                                .padding(.top, 20)

                            content
                                .padding(.top, 24)

                            Color.clear.frame(height: 100)
                        }
                    }
                    .ignoresSafeArea(edges: .top)
                    .onPreferenceChange(RowFocusKey.self) { newId in
                        let previousId = focusedRowId
                        if previousId != newId {
                            nextRowToReceiveFocus = newId
                            focusedRowId = newId
                            clearNextRowFocusTask?.cancel()
                            clearNextRowFocusTask = Task {
                                try? await Task.sleep(nanoseconds: 200_000_000)
                                guard !Task.isCancelled else { return }
                                nextRowToReceiveFocus = nil
                            }
                        }

                        if let rid = newId, rid != previousId, rid != firstVisibleRowId {
                            withAnimation(.easeInOut(duration: 0.24)) {
                                proxy.scrollTo("np-row-\(rid)", anchor: .top)
                            }
                        }
                    }
                    .onPreferenceChange(RowItemFocusKey.self) { value in
                        if let rowId = value.rowId, let itemId = value.itemId {
                            rowLastFocusedItem[rowId] = itemId
                        }
                    }
                }
            }
        }
        .focusScope(focusNS)
        .task {
            await viewModel.load()
        }
        .onChange(of: viewModel.activeTab) { _ in
            focusedRowId = nil
            nextRowToReceiveFocus = nil
        }
        .fullScreenCover(item: $selectedItem) { item in
            TVDetailsView(item: item)
        }
        .onDisappear {
            clearNextRowFocusTask?.cancel()
        }
    }

    private var controls: some View {
        HStack(spacing: 20) {
            HStack(spacing: 12) {
                ForEach(TVNewPopularViewModel.Tab.allCases) { tab in
                    let key = "tab-\(tab.id)"
                    let isFocused = focusedTopControl == key
                    Button {
                        guard viewModel.activeTab != tab else { return }
                        viewModel.activeTab = tab
                        Task { await viewModel.load() }
                    } label: {
                        controlChip(
                            title: tab.rawValue,
                            key: key,
                            isSelected: viewModel.activeTab == tab
                        )
                    }
                    .buttonStyle(.plain)
                    .focused($focusedTopControl, equals: key)
                    .focusEffectDisabled()
                }
            }
            .focusSection()

            Spacer()

            HStack(spacing: 12) {
                ForEach(TVNewPopularViewModel.ContentType.allCases) { type in
                    let key = "ctype-\(type.id)"
                    Button {
                        guard viewModel.contentType != type else { return }
                        viewModel.contentType = type
                        Task { await viewModel.load() }
                    } label: {
                        controlChip(
                            title: type.rawValue,
                            key: key,
                            isSelected: viewModel.contentType == type
                        )
                    }
                    .buttonStyle(.plain)
                    .focused($focusedTopControl, equals: key)
                    .focusEffectDisabled()
                }

                if viewModel.activeTab == .trending || viewModel.activeTab == .top10 {
                    ForEach(TVNewPopularViewModel.Period.allCases) { period in
                        let key = "period-\(period.id)"
                        Button {
                            guard viewModel.period != period else { return }
                            viewModel.period = period
                            Task { await viewModel.load() }
                        } label: {
                            controlChip(
                                title: period.rawValue,
                                key: key,
                                isSelected: viewModel.period == period
                            )
                        }
                        .buttonStyle(.plain)
                        .focused($focusedTopControl, equals: key)
                        .focusEffectDisabled()
                    }
                }
            }
        }
    }

    private func controlChip(title: String, key: String, isSelected: Bool) -> some View {
        let isFocused = focusedTopControl == key
        return Text(title)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.9))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.18) : Color.black.opacity(0.28))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(isFocused ? 0.62 : (isSelected ? 0.34 : 0.18)), lineWidth: isFocused ? 2 : 1)
            )
            .scaleEffect(isFocused ? 1.03 : 1.0)
            .shadow(color: .black.opacity(isFocused ? 0.32 : 0.18), radius: isFocused ? 10 : 4, y: 3)
            .animation(.easeOut(duration: UX.focusDur), value: isFocused)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            loadingView
        } else if let errorMessage = viewModel.errorMessage {
            errorView(errorMessage)
        } else {
            switch viewModel.activeTab {
            case .trending:
                trendingContent
            case .top10:
                top10Content
            case .comingSoon:
                comingSoonContent
            case .worthWait:
                worthWaitContent
            }
        }
    }

    private var trendingContent: some View {
        VStack(spacing: 24) {
            if !viewModel.recentlyAdded.isEmpty {
                mediaRow(title: "New on Your Plex", items: viewModel.recentlyAdded, kind: .landscape, sectionId: "np-recent")
            }
            if !viewModel.popularPlex.isEmpty {
                mediaRow(title: "Popular on Your Plex", items: viewModel.popularPlex, kind: .landscape, sectionId: "np-plex-pop")
            }

            if (viewModel.contentType == .all || viewModel.contentType == .movies), !viewModel.trendingMovies.isEmpty {
                mediaRow(title: "Trending Movies", items: viewModel.trendingMovies, kind: .poster, sectionId: "np-trending-movies")
            }

            if (viewModel.contentType == .all || viewModel.contentType == .shows), !viewModel.trendingShows.isEmpty {
                mediaRow(title: "Trending TV Shows", items: viewModel.trendingShows, kind: .poster, sectionId: "np-trending-shows")
            }
        }
    }

    private var top10Content: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Top 10 \(viewModel.period.rawValue)")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, UX.gridH)

            if viewModel.top10.isEmpty {
                Text("No top 10 content available")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, UX.gridH)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: UX.itemSpacing) {
                        ForEach(Array(viewModel.top10.enumerated()), id: \.element.id) { index, item in
                            TVTopRankCard(item: item, rank: index + 1) {
                                selectedItem = item.toMediaItem()
                            }
                        }
                    }
                    .padding(.horizontal, UX.gridH)
                }
                .frame(height: UX.posterHeight + 22)
            }
        }
    }

    private var comingSoonContent: some View {
        VStack(spacing: 20) {
            if viewModel.upcoming.isEmpty {
                Text("No upcoming content available")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, UX.gridH)
            } else {
                mediaRow(title: "Coming Soon", items: viewModel.upcoming, kind: .poster, sectionId: "np-coming")
            }
        }
    }

    private var worthWaitContent: some View {
        VStack(spacing: 20) {
            if viewModel.anticipated.isEmpty {
                Text("No anticipated content available")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, UX.gridH)
            } else {
                mediaRow(title: "Most Anticipated", items: viewModel.anticipated, kind: .poster, sectionId: "np-anticipated")
            }
        }
    }

    @ViewBuilder
    private func mediaRow(title: String, items: [TVNewPopularViewModel.DisplayMediaItem], kind: TVRowCardKind, sectionId: String) -> some View {
        let media = items.map { $0.toMediaItem() }
        if !media.isEmpty {
            TVCarouselRow(
                title: title,
                items: media,
                kind: kind,
                focusNS: focusNS,
                defaultFocus: focusedRowId == sectionId || nextRowToReceiveFocus == sectionId || (focusedRowId == nil && sectionId == firstVisibleRowId),
                preferredFocusItemId: rowLastFocusedItem[sectionId],
                sectionId: sectionId,
                landscapeFocusOutline: kind == .landscape,
                onSelect: { selectedItem = $0 }
            )
            .id("np-row-\(sectionId)")
        }
    }

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.4)
                .tint(.white)
            Text("Loading New & Popular")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
            Button {
                Task { await viewModel.load() }
            } label: {
                Text("Retry")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 14)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }

    private var discoveryDisabledView: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 62, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
            Text("Discovery Mode is Off")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(.white)
            Text("Enable discovery in Settings to use New & Popular.")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openHeroDetails(_ hero: TVNewPopularViewModel.HeroData) {
        let item = MediaItem(
            id: hero.id,
            title: hero.title,
            type: hero.mediaType == "tv" ? "show" : "movie",
            thumb: hero.posterURL?.absoluteString,
            art: hero.backdropURL?.absoluteString,
            year: hero.year.flatMap(Int.init),
            rating: nil,
            duration: hero.runtime.map { $0 * 60000 },
            viewOffset: nil,
            summary: hero.overview,
            grandparentTitle: nil,
            grandparentThumb: nil,
            grandparentArt: nil,
            parentIndex: nil,
            index: nil
        )
        selectedItem = item
    }

    private func addHeroToWatchlist(_ hero: TVNewPopularViewModel.HeroData) async {
        guard hero.id.hasPrefix("tmdb:"),
              let tmdbId = Int(hero.id.split(separator: ":").last ?? "") else { return }

        struct TraktPayload: Codable {
            let tmdbId: Int
            let mediaType: String
        }

        do {
            let mediaType = hero.mediaType == "tv" ? "show" : "movie"
            let _: SimpleOkResponse = try await APIClient.shared.post(
                "/api/trakt/watchlist",
                body: TraktPayload(tmdbId: tmdbId, mediaType: mediaType)
            )
            watchlistController.registerAdd(id: hero.id)
        } catch {
            #if DEBUG
            print("⚠️ [TVNewPopular] addHeroToWatchlist failed: \(error)")
            #endif
        }
    }

    private var firstVisibleRowId: String? {
        switch viewModel.activeTab {
        case .trending:
            if !viewModel.recentlyAdded.isEmpty { return "np-recent" }
            if !viewModel.popularPlex.isEmpty { return "np-plex-pop" }
            if (viewModel.contentType == .all || viewModel.contentType == .movies), !viewModel.trendingMovies.isEmpty {
                return "np-trending-movies"
            }
            if (viewModel.contentType == .all || viewModel.contentType == .shows), !viewModel.trendingShows.isEmpty {
                return "np-trending-shows"
            }
            return nil
        case .top10:
            return viewModel.top10.isEmpty ? nil : "np-top10"
        case .comingSoon:
            return viewModel.upcoming.isEmpty ? nil : "np-coming"
        case .worthWait:
            return viewModel.anticipated.isEmpty ? nil : "np-anticipated"
        }
    }
}

private struct TVTopRankCard: View {
    let item: TVNewPopularViewModel.DisplayMediaItem
    let rank: Int
    var onSelect: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .topLeading) {
                if let imageURL = item.imageURL {
                    CachedAsyncImage(url: imageURL, contentMode: .fill) {
                        Color.white.opacity(0.06)
                    }
                    .frame(width: UX.posterWidth, height: UX.posterHeight)
                    .clipShape(RoundedRectangle(cornerRadius: UX.posterRadius, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: UX.posterRadius, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: UX.posterWidth, height: UX.posterHeight)
                }

                Text("\(rank)")
                    .font(.system(size: 88, weight: .black))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.8), radius: 8, x: 2, y: 3)
                    .padding(.leading, 16)
                    .padding(.top, 12)
            }
        }
        .buttonStyle(.plain)
        .focusable(true)
        .focused($focused)
        .tvFocusSurface(isFocused: focused, cornerRadius: UX.posterRadius)
    }
}
