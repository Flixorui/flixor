import SwiftUI
import FlixorKit
import Foundation

struct TVHomeView: View {
    @ObservedObject private var vm: TVHomeViewModel
    let focusHandoffToken: UUID?
    @Namespace private var contentFocusNS
    @EnvironmentObject private var session: SessionManager
    @EnvironmentObject private var profileSettings: TVProfileSettings

    @State private var focusedRowId: String?
    @State private var rowLastFocusedItem: [String: String] = [:]
    @State private var nextRowToReceiveFocus: String?
    @State private var showingDetails: MediaItem?
    @State private var currentGradientColors: UltraBlurColors?
    @State private var billboardIndex: Int = 0
    @State private var heroFocusRequestToken: UUID?
    @State private var clearNextRowFocusTask: Task<Void, Never>?
    @State private var clearRowFocusTask: Task<Void, Never>?
    @State private var gradientDebounceTask: Task<Void, Never>?

    init(viewModel: TVHomeViewModel, focusHandoffToken: UUID? = nil) {
        self._vm = ObservedObject(wrappedValue: viewModel)
        self.focusHandoffToken = focusHandoffToken
    }

    var body: some View {
        ZStack {
            // UltraBlur gradient background (always show, use default row colors as fallback)
            UltraBlurGradientBackground(colors: currentGradientColors ?? TVHomeViewModel.defaultRowColors)
                .animation(.easeInOut(duration: 0.8), value: currentGradientColors?.topLeft ?? "default")

            ScrollViewReader { vProxy in
            ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 40) {

                // Billboard
                if profileSettings.showHeroSection {
                    if !vm.billboardItems.isEmpty {
                        TVHeroCarouselView(
                            items: profileSettings.heroLayout == "billboard" ? Array(vm.billboardItems.prefix(1)) : vm.billboardItems,
                            focusNS: contentFocusNS,
                            defaultFocus: true,
                            chrome: profileSettings.heroLayout == "billboard" ? .focusOnly : .appleMinimal,
                            autoAdvanceEnabled: profileSettings.heroAutoRotate && profileSettings.heroLayout != "billboard",
                            currentIndex: $billboardIndex,
                            focusRequestToken: heroFocusRequestToken
                        )
                            .opacity(focusedRowId == nil ? 1 : 0)
                            .animation(.easeOut(duration: 0.16), value: focusedRowId == nil)
                            .allowsHitTesting(focusedRowId == nil)
                            .padding(.top, UX.homeHeroTopPadding)
                            // Keep overlap static so focus transitions do not relayout the entire stack.
                            .padding(.bottom, -(UX.heroRowOverlap + 40))
                            .id("billboard")
                            .onAppear {
                                // When billboard appears, ensure we're showing billboard colors
                                if focusedRowId != nil {
                                    focusedRowId = nil
                                }
                            }
                    } else if vm.isLoading {
                        placeholderBillboard
                            .padding(.top, UX.homeHeroTopPadding)
                            .padding(.bottom, -(UX.heroRowOverlap + 40))
                            .id("billboard-placeholder")
                    }
                }

                // 1) Continue Watching (top-most row)
                if profileSettings.showContinueWatching, !vm.continueWatching.isEmpty {
                    rowView(
                        title: "Continue Watching",
                        items: vm.continueWatching,
                        kind: continueWatchingRowKind,
                        sectionId: "continue-watching"
                    )
                }

                // 2) Watchlist / My List
                if let myList = vm.additionalSections.first(where: { $0.id == "plex-watchlist" }),
                   profileSettings.showWatchlist,
                   !myList.items.isEmpty {
                    rowView(
                        title: "My List",
                        items: myList.items,
                        kind: effectiveRowKind,
                        sectionId: myList.id
                    )
                }

                // 3) Recently added per library rows
                ForEach(vm.recentlyAddedSections) { section in
                    rowView(
                        title: section.title,
                        items: section.items,
                        kind: effectiveRowKind,
                        sectionId: section.id
                    )
                }

                // 4) Collection rows
                if profileSettings.showCollectionRows {
                    ForEach(vm.collectionSections) { section in
                        rowView(
                            title: section.title,
                            items: section.items,
                            kind: effectiveRowKind,
                            sectionId: section.id
                        )
                    }
                }

                // 5) Popular + trending
                if let popular = vm.additionalSections.first(where: { $0.id == "tmdb-popular-movies" }), !popular.items.isEmpty {
                    rowView(
                        title: "Popular on Plex",
                        items: popular.items,
                        kind: effectiveRowKind,
                        sectionId: popular.id
                    )
                }

                if let trending = vm.additionalSections.first(where: { $0.id == "tmdb-trending" }), !trending.items.isEmpty {
                    rowView(
                        title: "Trending Now",
                        items: trending.items,
                        kind: effectiveRowKind,
                        sectionId: trending.id
                    )
                }

                // 6) tvOS compatibility row (optional)
                if profileSettings.showOnDeckRow, !vm.onDeck.isEmpty {
                    rowView(
                        title: "On Deck",
                        items: vm.onDeck,
                        kind: effectiveRowKind,
                        sectionId: "on-deck"
                    )
                }

                // 7) Remaining rows (genres, Trakt)
                ForEach(vm.additionalSections.filter { !["plex-watchlist", "tmdb-popular-movies", "tmdb-trending"].contains($0.id) }) { section in
                    rowView(
                        title: section.title,
                        items: section.items,
                        kind: effectiveRowKind,
                        sectionId: section.id
                    )
                }

                // Error message
                if let error = vm.error {
                    VStack(spacing: 12) {
                        Text("Unable to load content")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                        Text(error)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .padding(40)
                }

                // Loading skeletons
                if vm.isLoading {
                    loadingSkeletons
                }

                // Provide extra trailing space for comfortable overscan snap at the bottom.
                Color.clear.frame(height: UX.homeBottomOverscan + UX.rowSnapInset)
            }
            .padding(.bottom, 80)
        }
        .ignoresSafeArea(edges: .top)
        // no permanent inset; content can scroll edge-to-edge under the native sidebar shell
        .onPreferenceChange(RowFocusKey.self) { newId in
            if let newId {
                clearRowFocusTask?.cancel()
            } else {
                // During horizontal focus movement, tvOS may emit brief nil focus pulses.
                // Clear row focus only if nil persists, which indicates real exit to hero/nav.
                clearRowFocusTask?.cancel()
                clearRowFocusTask = Task {
                    try? await Task.sleep(nanoseconds: 140_000_000)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        focusedRowId = nil
                        nextRowToReceiveFocus = nil
                    }
                }
                return
            }

            // Update focused row ID (nil when billboard is focused, sectionId when row is focused)
            let previousId = focusedRowId
            if previousId != newId {
                // Set next row to receive focus BEFORE updating focusedRowId
                nextRowToReceiveFocus = newId

                focusedRowId = newId
                clearNextRowFocusTask?.cancel()
                clearNextRowFocusTask = Task {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    guard !Task.isCancelled else { return }
                    nextRowToReceiveFocus = nil
                }
            }

            // Scroll to row if focused
            if newId != previousId, newId != firstVisibleRowId {
                withAnimation(.easeInOut(duration: 0.24)) {
                    vProxy.scrollTo("row-\(newId)", anchor: .top)
                }
            }
        }
        .onPreferenceChange(BillboardFocusKey.self) { hasFocus in
            // Keep billboard at top when it has focus
            if hasFocus, focusedRowId == nil {
                withAnimation(.easeInOut(duration: 0.24)) {
                    vProxy.scrollTo("billboard", anchor: .top)
                }
            }
        }
        .onPreferenceChange(RowItemFocusKey.self) { value in
            // Track which item is focused in which row
            if let rowId = value.rowId, let itemId = value.itemId {
                rowLastFocusedItem[rowId] = itemId
            }
        }
        .onChange(of: focusHandoffToken) { token in
            guard let token else { return }
            focusedRowId = nil
            nextRowToReceiveFocus = nil
            if profileSettings.showHeroSection, !vm.billboardItems.isEmpty {
                heroFocusRequestToken = token
                withAnimation(.easeInOut(duration: 0.22)) {
                    vProxy.scrollTo("billboard", anchor: .top)
                }
            } else if let firstRowId = firstVisibleRowId {
                withAnimation(.easeInOut(duration: 0.22)) {
                    vProxy.scrollTo("row-\(firstRowId)", anchor: .top)
                }
            }
            #if DEBUG
            print("🎯 [Home] Received sidebar focus handoff: \(token.uuidString)")
            #endif
        }
        }
        }
        .background(Color.black)
        .focusScope(contentFocusNS)
        .fullScreenCover(item: $showingDetails) { item in
            TVDetailsView(item: item)
        }
        .task {
            await vm.loadIfNeeded()
            vm.startDynamicSectionPolling()
            if vm.billboardUltraBlurColors == nil, let active = currentBillboardItem {
                await vm.fetchUltraBlurColors(for: active)
            }
        }
        .onChange(of: session.isAuthenticated) { authed in
            if authed {
                Task { await vm.load() }
                vm.startDynamicSectionPolling()
            } else {
                vm.stopDynamicSectionPolling()
            }
        }
        .onChange(of: profileSettings.groupRecentlyAddedEpisodes) { _ in
            Task { await vm.load() }
        }
        .onChange(of: profileSettings.enabledLibraryKeys) { _ in
            Task { await vm.load() }
        }
        .onChange(of: vm.billboardItems.map(\.id)) { _ in
            if billboardIndex >= vm.billboardItems.count {
                billboardIndex = max(0, vm.billboardItems.count - 1)
            }
            if let active = currentBillboardItem {
                Task { await vm.fetchUltraBlurColors(for: active) }
            }
        }
        .onChange(of: billboardIndex) { _ in
            if let active = currentBillboardItem {
                Task { await vm.fetchUltraBlurColors(for: active) }
            }
        }
        .onChange(of: focusedRowId) { rowId in
            // Debounce gradient color changes to avoid recomputes during fast scrolling
            gradientDebounceTask?.cancel()
            gradientDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms debounce
                guard !Task.isCancelled else { return }
                if rowId != nil {
                    let rowColors = TVHomeViewModel.defaultRowColors
                    if !colorsEqual(currentGradientColors, rowColors) {
                        currentGradientColors = rowColors
                    }
                } else if let billboardColors = vm.billboardUltraBlurColors {
                    if !colorsEqual(currentGradientColors, billboardColors) {
                        currentGradientColors = billboardColors
                    }
                }
            }
        }
        .onChange(of: vm.billboardUltraBlurColors) { billboardColors in
            // Update gradient to billboard colors only if no row is focused
            if focusedRowId == nil, let colors = billboardColors {
                if !colorsEqual(currentGradientColors, colors) {
                    currentGradientColors = colors
                }
            }
        }
        .onDisappear {
            clearNextRowFocusTask?.cancel()
            clearRowFocusTask?.cancel()
            gradientDebounceTask?.cancel()
            vm.stopDynamicSectionPolling()
        }
    }

    private func colorsEqual(_ lhs: UltraBlurColors?, _ rhs: UltraBlurColors) -> Bool {
        guard let lhs else { return false }
        return lhs.topLeft == rhs.topLeft
            && lhs.topRight == rhs.topRight
            && lhs.bottomRight == rhs.bottomRight
            && lhs.bottomLeft == rhs.bottomLeft
    }

    private var effectiveRowKind: TVRowCardKind {
        profileSettings.rowLayout == "landscape" ? .landscape : .poster
    }

    private var continueWatchingRowKind: TVRowCardKind {
        profileSettings.continueWatchingLayout == "landscape" ? .landscape : .poster
    }

    @ViewBuilder
    private func rowView(
        title: String,
        items: [MediaItem],
        kind: TVRowCardKind,
        sectionId: String
    ) -> some View {
        if !items.isEmpty {
            TVCarouselRow(
                title: title,
                items: items,
                kind: kind,
                focusNS: contentFocusNS,
                defaultFocus: focusedRowId == sectionId || nextRowToReceiveFocus == sectionId,
                preferredFocusItemId: rowLastFocusedItem[sectionId],
                sectionId: sectionId,
                landscapeFocusOutline: kind == .landscape,
                onSelect: { showingDetails = $0 }
            )
            .id("row-\(sectionId)")
        }
    }

    private var currentBillboardItem: MediaItem? {
        guard !vm.billboardItems.isEmpty else { return nil }
        let clamped = min(max(billboardIndex, 0), vm.billboardItems.count - 1)
        return vm.billboardItems[clamped]
    }

    private var firstVisibleRowId: String? {
        if profileSettings.showContinueWatching, !vm.continueWatching.isEmpty { return "continue-watching" }
        if let myList = vm.additionalSections.first(where: { $0.id == "plex-watchlist" && !$0.items.isEmpty }),
           profileSettings.showWatchlist {
            return myList.id
        }
        if let firstRecent = vm.recentlyAddedSections.first(where: { !$0.items.isEmpty }) { return firstRecent.id }
        if profileSettings.showCollectionRows,
           let firstCollection = vm.collectionSections.first(where: { !$0.items.isEmpty }) {
            return firstCollection.id
        }
        if let popular = vm.additionalSections.first(where: { $0.id == "tmdb-popular-movies" && !$0.items.isEmpty }) {
            return popular.id
        }
        if let trending = vm.additionalSections.first(where: { $0.id == "tmdb-trending" && !$0.items.isEmpty }) {
            return trending.id
        }
        if profileSettings.showOnDeckRow, !vm.onDeck.isEmpty { return "on-deck" }
        if let section = vm.additionalSections
            .filter({ !["plex-watchlist", "tmdb-popular-movies", "tmdb-trending"].contains($0.id) })
            .first(where: { !$0.items.isEmpty }) {
            return section.id
        }
        return nil
    }

    private var placeholderBillboard: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .frame(height: UX.heroFullBleedHeight)
            .frame(maxWidth: .infinity)
            .ignoresSafeArea(.container, edges: .horizontal)
    }
}

// MARK: - Loading skeletons for perceived performance
extension TVHomeView {
    @ViewBuilder
    var loadingSkeletons: some View {
        VStack(spacing: 32) {
            skeletonRow(title: "Continue Watching", poster: false)
            skeletonRow(title: "My List", poster: true)
            skeletonRow(title: "New on Flixor", poster: true)
        }
    }

    private func skeletonRow(title: String, poster: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, UX.gridH)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: UX.itemSpacing) {
                    ForEach(0..<8, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: poster ? UX.posterRadius : UX.landscapeRadius, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .frame(width: poster ? UX.posterWidth : UX.landscapeWidth,
                                   height: poster ? UX.posterHeight : UX.landscapeHeight)
                    }
                }
                .padding(.horizontal, UX.gridH)
                .frame(height: poster ? UX.posterHeight : UX.landscapeHeight)
            }
        }
    }
}
