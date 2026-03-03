import Foundation
import FlixorKit
import SwiftUI

struct TVHomeView: View {
    @ObservedObject private var vm: TVHomeViewModel
    let focusHandoffToken: UUID?

    @Namespace private var contentFocusNS
    @EnvironmentObject private var session: SessionManager
    @EnvironmentObject private var profileSettings: TVProfileSettings
    @EnvironmentObject private var focusCoordinator: TVFocusCoordinator
    @Environment(\.tvThemePalette) private var theme
    @Environment(\.tvTypography) private var typography

    @State private var focusedRowId: String?
    @State private var nextRowToReceiveFocus: String?
    @State private var showingDetails: MediaItem?
    @State private var playbackItem: MediaItem?
    @State private var selectedBrowseSection: TVHomeSectionDescriptor?
    @State private var currentGradientColors: UltraBlurColors?
    @State private var billboardIndex = 0
    @State private var heroFocusRequestToken: UUID?
    @State private var clearNextRowFocusTask: Task<Void, Never>?
    @State private var clearRowFocusTask: Task<Void, Never>?
    @State private var gradientDebounceTask: Task<Void, Never>?
    @State private var trailerPrefetchTask: Task<Void, Never>?

    init(viewModel: TVHomeViewModel, focusHandoffToken: UUID? = nil) {
        self._vm = ObservedObject(wrappedValue: viewModel)
        self.focusHandoffToken = focusHandoffToken
    }

    var body: some View {
        ZStack {
            UltraBlurGradientBackground(colors: currentGradientColors ?? TVHomeViewModel.defaultRowColors)
                .animation(.easeInOut(duration: 0.8), value: currentGradientColors?.topLeft ?? "default")

            ScrollViewReader { vProxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 40) {
                        if profileSettings.homeLayoutMode == .modern {
                            heroSection
                        }

                        if profileSettings.homeLayoutMode == .grid {
                            gridSections
                        } else {
                            railSections
                        }

                        if let error = vm.error {
                            VStack(spacing: 12) {
                                Text("Unable to load content")
                                    .font(typography.title)
                                    .foregroundStyle(theme.textPrimary)
                                Text(error)
                                    .font(typography.body)
                                    .foregroundStyle(theme.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(40)
                        }

                        if vm.isLoading {
                            loadingSkeletons
                        }

                        Color.clear.frame(height: UX.homeBottomOverscan + UX.rowSnapInset)
                    }
                    .padding(.bottom, 80)
                }
                .ignoresSafeArea(edges: .top)
                .onPreferenceChange(RowFocusKey.self) { newId in
                    handleRowFocusChange(newId, vProxy: vProxy)
                }
                .onPreferenceChange(BillboardFocusKey.self) { hasFocus in
                    if hasFocus, focusedRowId == nil, profileSettings.homeLayoutMode == .modern {
                        withAnimation(.easeInOut(duration: 0.24)) {
                            vProxy.scrollTo("billboard", anchor: .top)
                        }
                    }
                }
                .onPreferenceChange(RowItemFocusKey.self) { value in
                    if let rowId = value.rowId, let itemId = value.itemId {
                        focusCoordinator.remember(screen: .home, sectionID: rowId, itemID: itemId)
                    }
                }
                .onChange(of: focusHandoffToken) { token in
                    guard let token else { return }
                    focusedRowId = nil
                    nextRowToReceiveFocus = nil

                    if shouldShowHero {
                        heroFocusRequestToken = token
                        withAnimation(.easeInOut(duration: 0.22)) {
                            vProxy.scrollTo("billboard", anchor: .top)
                        }
                    } else if let targetRow = focusCoordinator.lastFocusedSection(screen: .home) ?? firstVisibleRowId {
                        focusedRowId = targetRow
                        nextRowToReceiveFocus = targetRow
                        withAnimation(.easeInOut(duration: 0.22)) {
                            vProxy.scrollTo("row-\(targetRow)", anchor: .top)
                        }
                    }

                    #if DEBUG
                    print("🎯 [Home] Received sidebar focus handoff: \(token.uuidString)")
                    #endif
                }
            }
        }
        .background(theme.background)
        .focusScope(contentFocusNS)
        .fullScreenCover(item: $showingDetails) { item in
            TVDetailsView(item: item)
        }
        .fullScreenCover(item: $playbackItem) { item in
            PlayerView(item: item)
        }
        .fullScreenCover(item: $selectedBrowseSection) { section in
            TVBrowseFeedView(section: section)
        }
        .task {
            await vm.loadIfNeeded()
            vm.startDynamicSectionPolling()
            warmInitialRowTrailersIfNeeded()

            if focusedRowId == nil, !shouldShowHero {
                focusedRowId = focusCoordinator.lastFocusedSection(screen: .home) ?? firstVisibleRowId
            }

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
        .onChange(of: resolvedBillboardItems.map(\.id)) { ids in
            if billboardIndex >= ids.count {
                billboardIndex = max(0, ids.count - 1)
            }
            if let active = currentBillboardItem {
                Task { await vm.fetchUltraBlurColors(for: active) }
            }
        }
        .onChange(of: homeTrailerWarmupSignature) { _ in
            warmInitialRowTrailersIfNeeded()
        }
        .onChange(of: billboardIndex) { _ in
            if let active = currentBillboardItem {
                Task { await vm.fetchUltraBlurColors(for: active) }
            }
        }
        .onChange(of: focusedRowId) { rowId in
            gradientDebounceTask?.cancel()
            gradientDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 200_000_000)
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
            if focusedRowId == nil, let colors = billboardColors, !colorsEqual(currentGradientColors, colors) {
                currentGradientColors = colors
            }
        }
        .onDisappear {
            clearNextRowFocusTask?.cancel()
            clearRowFocusTask?.cancel()
            gradientDebounceTask?.cancel()
            trailerPrefetchTask?.cancel()
            vm.stopDynamicSectionPolling()
        }
    }

    private var railSections: some View {
        VStack(spacing: 0) {
            ForEach(homeSections) { section in
                rowView(section)
            }
        }
    }

    private var gridSections: some View {
        VStack(spacing: 34) {
            ForEach(homeSections) { section in
                TVHomeGridSectionBlock(
                    section: section,
                    onOpen: { item in
                        if section.usesContinueWatchingStyle {
                            play(item)
                        } else {
                            showDetails(for: item)
                        }
                    },
                    onRestart: restartFromBeginning,
                    onDetails: showDetails(for:),
                    onRemoveContinueWatching: { item in
                        Task { await vm.removeContinueWatching(item) }
                    },
                    onSeeAll: {
                        if section.supportsSeeAll {
                            selectedBrowseSection = section
                        }
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var heroSection: some View {
        if shouldShowHero {
            TVHeroCarouselView(
                items: profileSettings.heroPresentationMode == .billboard ? Array(resolvedBillboardItems.prefix(1)) : resolvedBillboardItems,
                focusNS: contentFocusNS,
                defaultFocus: true,
                chrome: profileSettings.heroPresentationMode == .billboard ? .focusOnly : .appleMinimal,
                autoAdvanceEnabled: profileSettings.heroAutoRotate && profileSettings.heroPresentationMode != .billboard,
                currentIndex: $billboardIndex,
                focusRequestToken: heroFocusRequestToken
            )
            .opacity(focusedRowId == nil ? 1 : 0)
            .animation(.easeOut(duration: 0.16), value: focusedRowId == nil)
            .allowsHitTesting(focusedRowId == nil)
            .padding(.top, UX.homeHeroTopPadding)
            .padding(.bottom, -(UX.heroRowOverlap + 40))
            .id("billboard")
            .onAppear {
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

    @ViewBuilder
    private func rowView(_ section: TVHomeSectionDescriptor) -> some View {
        if section.usesContinueWatchingStyle {
            TVContinueWatchingRow(
                items: section.items,
                kind: rowKind(for: section),
                focusNS: contentFocusNS,
                defaultFocus: focusedRowId == section.id || nextRowToReceiveFocus == section.id,
                preferredFocusItemId: focusCoordinator.lastFocusedItem(screen: .home, sectionID: section.id),
                sectionId: section.id,
                onContinue: play,
                onRestart: restartFromBeginning,
                onDetails: showDetails(for:),
                onRemove: { item in
                    Task { await vm.removeContinueWatching(item) }
                },
                onItemFocus: handleFocusedItem(_:),
                previewTrailerProvider: vm.focusedPreviewTrailer(for:),
                tailAction: section.supportsSeeAll ? seeAllAction(for: section) : nil
            )
            .id("row-\(section.id)")
        } else if !section.items.isEmpty {
            TVCarouselRow(
                title: section.title,
                items: section.items,
                kind: rowKind(for: section),
                focusNS: contentFocusNS,
                defaultFocus: focusedRowId == section.id || nextRowToReceiveFocus == section.id,
                preferredFocusItemId: focusCoordinator.lastFocusedItem(screen: .home, sectionID: section.id),
                sectionId: section.id,
                landscapeFocusOutline: rowKind(for: section) == .landscape,
                onSelect: showDetails(for:),
                screenID: .home,
                tailAction: section.supportsSeeAll ? seeAllAction(for: section) : nil,
                onItemFocus: handleFocusedItem(_:),
                previewTrailerProvider: vm.focusedPreviewTrailer(for:)
            )
            .id("row-\(section.id)")
        }
    }

    private func handleFocusedItem(_ item: MediaItem) {
        if focusedRowId == nil {
            return
        }

        scheduleTrailerPrefetch(for: item)

        if resolvedBillboardItems.contains(where: { $0.id == item.id }) {
            Task { await vm.fetchUltraBlurColors(for: item) }
        }
    }

    private func scheduleTrailerPrefetch(for item: MediaItem) {
        trailerPrefetchTask?.cancel()

        guard profileSettings.focusedPosterTrailerEnabled else {
            return
        }

        trailerPrefetchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                vm.prefetchFocusedPreviewTrailer(for: item, reason: "focusDebounce")
            }
        }
    }

    private func warmInitialRowTrailersIfNeeded() {
        vm.prefetchPreviewTrailersForInitialRows(
            sections: homeSections,
            maxSections: shouldShowHero ? 2 : 3,
            itemsPerSection: 1
        )
    }

    private func handleRowFocusChange(_ newId: String?, vProxy: ScrollViewProxy) {
        guard let rowId = newId else {
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

        clearRowFocusTask?.cancel()
        focusCoordinator.remember(screen: .home, sectionID: rowId, itemID: nil)

        HomeHitchTracer.mark("HomeRowPreferenceReceived", row: rowId, extra: "prev=\(focusedRowId ?? "nil")")

        let previousId = focusedRowId
        if previousId != rowId {
            let span = HomeHitchTracer.begin("HomeRowStateUpdate", row: rowId)
            nextRowToReceiveFocus = rowId
            focusedRowId = rowId
            HomeHitchTracer.recordVisit(rowId)
            HomeHitchTracer.measureRenderTime("HomeRowStateRender", row: rowId)
            clearNextRowFocusTask?.cancel()
            clearNextRowFocusTask = Task {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
                nextRowToReceiveFocus = nil
            }
            span.end()
        }

        if rowId != previousId, rowId != firstVisibleRowId {
            HomeHitchTracer.mark("HomeRowScrollTo", row: rowId)
            withAnimation(.easeInOut(duration: 0.24)) {
                vProxy.scrollTo("row-\(rowId)", anchor: TVScrollAlignmentPolicy.home.verticalAnchor)
            }
            HomeHitchTracer.measureRenderTime("HomeScrollToRender", row: rowId)
        }
    }

    private func colorsEqual(_ lhs: UltraBlurColors?, _ rhs: UltraBlurColors) -> Bool {
        guard let lhs else { return false }
        return lhs.topLeft == rhs.topLeft
            && lhs.topRight == rhs.topRight
            && lhs.bottomRight == rhs.bottomRight
            && lhs.bottomLeft == rhs.bottomLeft
    }

    private func rowKind(for section: TVHomeSectionDescriptor) -> TVRowCardKind {
        if let preferred = section.preferredRowKind {
            return preferred
        }
        if profileSettings.homeLayoutMode == .modern, profileSettings.modernLandscapePostersEnabled {
            return .landscape
        }
        return profileSettings.defaultRailCardShape == .landscape ? .landscape : .poster
    }

    private var homeSections: [TVHomeSectionDescriptor] {
        vm.homeSections
    }

    private var resolvedBillboardItems: [MediaItem] {
        vm.heroItems(for: profileSettings.heroSourceKeys)
    }

    private var shouldShowHero: Bool {
        profileSettings.showHeroSection
            && profileSettings.homeLayoutMode == .modern
            && !resolvedBillboardItems.isEmpty
    }

    private var currentBillboardItem: MediaItem? {
        guard !resolvedBillboardItems.isEmpty else { return nil }
        let clamped = min(max(billboardIndex, 0), resolvedBillboardItems.count - 1)
        return resolvedBillboardItems[clamped]
    }

    private var firstVisibleRowId: String? {
        homeSections.first?.id
    }

    private var homeTrailerWarmupSignature: [String] {
        guard profileSettings.focusedPosterTrailerEnabled else {
            return ["disabled"]
        }

        return [
            profileSettings.homeLayoutMode.rawValue,
            profileSettings.focusedPosterTrailerTarget.rawValue
        ] + homeSections
            .prefix(3)
            .map { section in
                "\(section.id):\(section.items.prefix(1).map(\.id).joined(separator: ","))"
            }
    }

    private func seeAllAction(for section: TVHomeSectionDescriptor) -> TVRowTailAction {
        TVRowTailAction(title: "See All", systemImage: "square.grid.2x2") {
            selectedBrowseSection = section
        }
    }

    private func play(_ item: MediaItem) {
        playbackItem = item
    }

    private func restartFromBeginning(_ item: MediaItem) {
        playbackItem = MediaItem(
            id: item.id,
            title: item.title,
            type: item.type,
            thumb: item.thumb,
            art: item.art,
            logo: item.logo,
            year: item.year,
            rating: item.rating,
            duration: item.duration,
            viewOffset: nil,
            summary: item.summary,
            grandparentTitle: item.grandparentTitle,
            grandparentThumb: item.grandparentThumb,
            grandparentArt: item.grandparentArt,
            parentIndex: item.parentIndex,
            index: item.index,
            parentRatingKey: item.parentRatingKey,
            parentTitle: item.parentTitle,
            leafCount: item.leafCount,
            viewedLeafCount: item.viewedLeafCount
        )
    }

    private func showDetails(for item: MediaItem) {
        showingDetails = item
    }

    private var placeholderBillboard: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(theme.surfaceGlass.opacity(0.5))
            .frame(height: UX.heroFullBleedHeight)
            .frame(maxWidth: .infinity)
            .ignoresSafeArea(.container, edges: .horizontal)
    }
}

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
                .font(typography.section)
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, UX.gridH)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: UX.itemSpacing) {
                    ForEach(0..<8, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: poster ? UX.posterRadius : UX.landscapeRadius, style: .continuous)
                            .fill(theme.surfaceGlass)
                            .frame(
                                width: poster ? UX.posterWidth : UX.landscapeWidth,
                                height: poster ? UX.posterHeight : UX.landscapeHeight
                            )
                    }
                }
                .padding(.horizontal, UX.gridH)
                .frame(height: poster ? UX.posterHeight : UX.landscapeHeight)
            }
        }
    }
}

private struct TVHomeGridSectionBlock: View {
    let section: TVHomeSectionDescriptor
    let onOpen: (MediaItem) -> Void
    let onRestart: (MediaItem) -> Void
    let onDetails: (MediaItem) -> Void
    let onRemoveContinueWatching: (MediaItem) -> Void
    let onSeeAll: () -> Void

    @EnvironmentObject private var profileSettings: TVProfileSettings
    @EnvironmentObject private var focusCoordinator: TVFocusCoordinator
    @Environment(\.tvThemePalette) private var theme
    @Environment(\.tvTypography) private var typography
    @Environment(\.tvCardVisualTokens) private var cardTokens
    @FocusState private var focusedItemID: String?

    private var rowKind: TVRowCardKind {
        section.preferredRowKind
            ?? (profileSettings.homeLayoutMode == .modern && profileSettings.modernLandscapePostersEnabled
                ? .landscape
                : (profileSettings.defaultRailCardShape == .landscape ? .landscape : .poster))
    }

    private var columns: [GridItem] {
        if rowKind == .landscape {
            return Array(repeating: GridItem(.flexible(minimum: 460, maximum: 640), spacing: 24), count: 2)
        }

        let count = max(3, profileSettings.posterWidthPreset.libraryGridColumnCount)
        return Array(repeating: GridItem(.flexible(minimum: 220, maximum: 320), spacing: 20), count: count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.title)
                        .font(typography.section)
                        .foregroundStyle(theme.textPrimary)

                    Text("\(section.items.count) titles")
                        .font(typography.meta)
                        .foregroundStyle(theme.textTertiary)
                }

                Spacer()

                if section.supportsSeeAll {
                    Button(action: onSeeAll) {
                        Label("See All", systemImage: "square.grid.2x2")
                            .font(typography.label)
                            .foregroundStyle(theme.textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(theme.surfaceGlass, in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(theme.strokeDefault, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, UX.gridH)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                ForEach(section.items.prefix(rowKind == .landscape ? 6 : 10), id: \.id) { item in
                    gridCard(item)
                }
            }
            .padding(.horizontal, UX.gridH)
        }
        .id("row-\(section.id)")
        .onAppear {
            focusedItemID = focusCoordinator.lastFocusedItem(screen: .home, sectionID: section.id)
        }
    }

    @ViewBuilder
    private func gridCard(_ item: MediaItem) -> some View {
        let isFocused = focusedItemID == item.id
        Button {
            onOpen(item)
        } label: {
            Group {
                if rowKind == .landscape {
                    TVLandscapeCard(
                        item: item,
                        showBadges: true,
                        isFocused: isFocused,
                        focusOutlineOnFocus: true
                    )
                    .frame(height: UX.landscapeHeight)
                } else {
                    TVPosterCard(
                        item: item,
                        isFocused: isFocused,
                        respectLibraryTitles: true
                    )
                    .frame(
                        width: UX.posterWidth * profileSettings.posterWidthMultiplier,
                        height: UX.posterHeight * profileSettings.posterWidthMultiplier
                    )
                }
            }
            .scaleEffect(isFocused ? cardTokens.focusedScale : 1.0)
            .shadow(
                color: .black.opacity(isFocused ? 0.48 : 0.22),
                radius: isFocused ? cardTokens.focusedShadowRadius : cardTokens.unfocusedShadowRadius,
                y: isFocused ? cardTokens.focusedShadowYOffset : cardTokens.unfocusedShadowYOffset
            )
            .animation(.easeOut(duration: UX.focusDur), value: isFocused)
        }
        .buttonStyle(.plain)
        .focusable(true)
        .focused($focusedItemID, equals: item.id)
        .onChange(of: isFocused) { focused in
            if focused {
                focusCoordinator.remember(screen: .home, sectionID: section.id, itemID: item.id)
            }
        }
        .contextMenu {
            if section.usesContinueWatchingStyle {
                Button {
                    onOpen(item)
                } label: {
                    Label("Continue", systemImage: "play.fill")
                }

                Button {
                    onRestart(item)
                } label: {
                    Label("Start from Beginning", systemImage: "backward.end.fill")
                }

                Button {
                    onDetails(item)
                } label: {
                    Label("Details", systemImage: "info.circle")
                }

                Button(role: .destructive) {
                    onRemoveContinueWatching(item)
                } label: {
                    Label("Remove", systemImage: "minus.circle")
                }
            }
        }
    }
}
