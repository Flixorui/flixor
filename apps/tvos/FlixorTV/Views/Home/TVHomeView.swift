import SwiftUI
import FlixorKit

struct TVHomeView: View {
    @ObservedObject private var vm: TVHomeViewModel
    @Namespace private var contentFocusNS
    @EnvironmentObject private var session: SessionManager

    @State private var focusedRowId: String?
    @State private var rowLastFocusedItem: [String: String] = [:]
    @State private var nextRowToReceiveFocus: String?
    @State private var showingDetails: MediaItem?
    @State private var currentGradientColors: UltraBlurColors?
    @State private var clearNextRowFocusTask: Task<Void, Never>?
    @State private var gradientDebounceTask: Task<Void, Never>?

    init(viewModel: TVHomeViewModel) {
        self._vm = ObservedObject(wrappedValue: viewModel)
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
                if let first = vm.billboardItems.first {
                    TVBillboardView(item: first, focusNS: contentFocusNS, defaultFocus: true)
                        .padding(.top, UX.billboardTopPadding)
                        .id("billboard")
                        .onAppear {
                            // When billboard appears, ensure we're showing billboard colors
                            if focusedRowId != nil {
                                focusedRowId = nil
                            }
                        }
                } else if vm.isLoading {
                    placeholderBillboard
                        .padding(.top, UX.billboardTopPadding)
                        .id("billboard-placeholder")
                }

                // Row Order per spec
                // 1) My List (poster)
                if let myList = vm.additionalSections.first(where: { $0.id == "plex-watchlist" }), !myList.items.isEmpty {
                    TVCarouselRow(
                        title: "My List",
                        items: myList.items,
                        kind: .poster,
                        focusNS: contentFocusNS,
                        defaultFocus: focusedRowId == myList.id || nextRowToReceiveFocus == myList.id,
                        preferredFocusItemId: rowLastFocusedItem[myList.id],
                        sectionId: myList.id,
                        onSelect: { showingDetails = $0 }
                    )
                    .padding(.top, focusedRowId == myList.id ? UX.rowSnapTopPadding : 0) // snap padding
                    .id("row-\(myList.id)")
                }

                // 2) Continue Watching — poster rail with inline expansion
                if !vm.continueWatching.isEmpty {
                    TVCarouselRow(
                        title: "Continue Watching",
                        items: vm.continueWatching,
                        kind: .poster,
                        focusNS: contentFocusNS,
                        defaultFocus: focusedRowId == "continue-watching" || nextRowToReceiveFocus == "continue-watching",
                        preferredFocusItemId: rowLastFocusedItem["continue-watching"],
                        sectionId: "continue-watching",
                        onSelect: { showingDetails = $0 }
                    )
                    .padding(.top, focusedRowId == "continue-watching" ? UX.rowSnapTopPadding : 0) // snap padding
                    .id("row-continue-watching")
                }

                // 3) New on Flixor (Recently Added) — poster rail with inline expansion
                if !vm.recentlyAdded.isEmpty {
                    TVCarouselRow(
                        title: "New on Flixor",
                        items: vm.recentlyAdded,
                        kind: .poster,
                        focusNS: contentFocusNS,
                        defaultFocus: focusedRowId == "recently-added" || nextRowToReceiveFocus == "recently-added",
                        preferredFocusItemId: rowLastFocusedItem["recently-added"],
                        sectionId: "recently-added",
                        onSelect: { showingDetails = $0 }
                    )
                    .padding(.top, focusedRowId == "recently-added" ? UX.rowSnapTopPadding : 0) // snap padding
                    .id("row-recently-added")
                }

                // 4) Popular on Plex (TMDB popular movies)
                if let popular = vm.additionalSections.first(where: { $0.id == "tmdb-popular-movies" }), !popular.items.isEmpty {
                    TVCarouselRow(
                        title: "Popular on Plex",
                        items: popular.items,
                        kind: .poster,
                        focusNS: contentFocusNS,
                        defaultFocus: focusedRowId == popular.id || nextRowToReceiveFocus == popular.id,
                        preferredFocusItemId: rowLastFocusedItem[popular.id],
                        sectionId: popular.id,
                        onSelect: { showingDetails = $0 }
                    )
                    .padding(.top, focusedRowId == popular.id ? UX.rowSnapTopPadding : 0) // snap padding
                    .id("row-\(popular.id)")
                }

                // 5) Trending Now (TMDB trending TV)
                if let trending = vm.additionalSections.first(where: { $0.id == "tmdb-trending" }), !trending.items.isEmpty {
                    TVCarouselRow(
                        title: "Trending Now",
                        items: trending.items,
                        kind: .poster,
                        focusNS: contentFocusNS,
                        defaultFocus: focusedRowId == trending.id || nextRowToReceiveFocus == trending.id,
                        preferredFocusItemId: rowLastFocusedItem[trending.id],
                        sectionId: trending.id,
                        onSelect: { showingDetails = $0 }
                    )
                    .padding(.top, focusedRowId == trending.id ? UX.rowSnapTopPadding : 0) // snap padding
                    .id("row-\(trending.id)")
                }

                // 6) On Deck — poster rail with inline expansion
                if !vm.onDeck.isEmpty {
                    TVCarouselRow(
                        title: "On Deck",
                        items: vm.onDeck,
                        kind: .poster,
                        focusNS: contentFocusNS,
                        defaultFocus: focusedRowId == "on-deck" || nextRowToReceiveFocus == "on-deck",
                        preferredFocusItemId: rowLastFocusedItem["on-deck"],
                        sectionId: "on-deck",
                        onSelect: { showingDetails = $0 }
                    )
                    .padding(.top, focusedRowId == "on-deck" ? UX.rowSnapTopPadding : 0) // snap padding
                    .id("row-on-deck")
                }

                // Any remaining sections (Genre, Trakt, etc.) not already displayed
                ForEach(vm.additionalSections.filter { !["plex-watchlist","tmdb-popular-movies","tmdb-trending"].contains($0.id) }) { section in
                    TVCarouselRow(
                        title: section.title,
                        items: section.items,
                        kind: .poster,
                        focusNS: contentFocusNS,
                        defaultFocus: focusedRowId == section.id || nextRowToReceiveFocus == section.id,
                        preferredFocusItemId: rowLastFocusedItem[section.id],
                        sectionId: section.id,
                        onSelect: { showingDetails = $0 }
                    )
                    .padding(.top, focusedRowId == section.id ? UX.rowSnapTopPadding : 0) // snap padding
                    .id("row-\(section.id)")
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

                // Provide extra trailing space so the last row can snap under the tab bar
                Color.clear.frame(height: UX.tabHeight + UX.rowSnapInset + 150)
            }
            .padding(.bottom, 80)
        }
        // no permanent inset; content can scroll under the transparent tab bar
        .onPreferenceChange(RowFocusKey.self) { newId in
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
            if let rid = newId, rid != previousId {
                withAnimation(.easeInOut(duration: 0.24)) {
                    vProxy.scrollTo("row-\(rid)", anchor: .top)
                }
            }
        }
        .onPreferenceChange(BillboardFocusKey.self) { hasFocus in
            // Keep billboard at top when it has focus
            if hasFocus {
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
        }
        }
        .background(Color.black)
        .focusScope(contentFocusNS)
        .fullScreenCover(item: $showingDetails) { item in
            TVDetailsView(item: item)
        }
        .task {
            await vm.loadIfNeeded()
            if vm.billboardUltraBlurColors == nil, let first = vm.billboardItems.first {
                await vm.fetchUltraBlurColors(for: first)
            }
        }
        .onChange(of: session.isAuthenticated) { authed in
            if authed { Task { await vm.load() } }
        }
        .onChange(of: vm.billboardItems.first?.id) { newId in
            if let first = vm.billboardItems.first {
                Task { await vm.fetchUltraBlurColors(for: first) }
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
    }

    private func colorsEqual(_ lhs: UltraBlurColors?, _ rhs: UltraBlurColors) -> Bool {
        guard let lhs else { return false }
        return lhs.topLeft == rhs.topLeft
            && lhs.topRight == rhs.topRight
            && lhs.bottomRight == rhs.bottomRight
            && lhs.bottomLeft == rhs.bottomLeft
    }

    private var placeholderBillboard: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .frame(height: 820)
            .padding(.horizontal, 40)
    }
}

// MARK: - Loading skeletons for perceived performance
extension TVHomeView {
    @ViewBuilder
    var loadingSkeletons: some View {
        VStack(spacing: 32) {
            skeletonRow(title: "My List", poster: true)
            skeletonRow(title: "Continue Watching", poster: false)
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
