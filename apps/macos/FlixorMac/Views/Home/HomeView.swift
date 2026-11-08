//
//  HomeView.swift
//  FlixorMac
//
//  Home screen with Billboard, Continue Watching, etc.
//

import SwiftUI
import FlixorKit

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @EnvironmentObject private var router: NavigationRouter
    @StateObject private var browseViewModel = BrowseModalViewModel()
    @State private var showBrowseModal = false
    @State private var activeBrowseContext: BrowseContext?

    // Profile-scoped Home Screen Settings
    @ObservedObject private var profileSettings = ProfileSettings.shared
    @ObservedObject private var rowsStore = HomeRowsStore.shared
    @ObservedObject private var network = NetworkMonitor.shared
    @State private var showAddonManager = false
    @Environment(\.windowMetrics) private var metrics

    /// Width of poster placeholders, matching `PosterSectionRow`.
    private var skeletonPosterWidth: CGFloat {
        metrics.posterWidth(designWidth: 160, storedSize: profileSettings.posterSize)
    }

    var body: some View {
        ZStack {
            Group {
                if let error = viewModel.error, network.isOnline {
                    ErrorView(message: error) {
                        Task {
                            await viewModel.refresh()
                        }
                    }
                } else {
                    homeScrollContent
                }
            }

            if showBrowseModal {
                BrowseModalView(
                    isPresented: $showBrowseModal,
                    viewModel: browseViewModel,
                    onSelect: { item in
                        viewModel.showItemDetails(item)
                    }
                )
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .background(HomeBackground(heroColors: viewModel.heroColors))
        .navigationTitle("")
        .task {
            print("📱 [HomeView] .task triggered - billboardItems.isEmpty: \(viewModel.billboardItems.isEmpty), isLoading: \(viewModel.isLoading)")
            // One-time clear of TMDB cache for textless backdrop priority fix
            let cacheVersion = "tmdb_textless_v2"
            if !UserDefaults.standard.bool(forKey: cacheVersion) {
                BillboardImageCache.shared.clear()
                await FlixorCore.shared.clearTmdbCache()
                UserDefaults.standard.set(true, forKey: cacheVersion)
            }
            if viewModel.billboardItems.isEmpty && !viewModel.isLoading {
                await viewModel.loadHomeScreen()
            }
        }
        .onAppear {
            // Back from a pushed page. The first load starts these itself.
            guard !viewModel.billboardItems.isEmpty else { return }
            viewModel.startPolling()
            viewModel.resumeBillboardRotation()
        }
        .onDisappear {
            viewModel.stopBillboardRotation()
            viewModel.stopPolling()
        }
        .onChange(of: viewModel.pendingAction) { action in
            guard let action = action else { return }
            switch action {
            case .play(let destination):
                router.homePath.append(destination)
            case .details(let item):
                router.homePath.append(DetailsNavigationItem(item: item))
            }
            viewModel.pendingAction = nil
        }
        .onChange(of: showBrowseModal) { value in
            if !value {
                activeBrowseContext = nil
                browseViewModel.reset()
            }
        }
        .onChange(of: profileSettings.groupRecentlyAddedEpisodes) { _ in
            // Refresh Recently Added sections when grouping setting changes
            Task {
                await viewModel.refreshRecentlyAddedSections()
            }
        }
        .sheet(isPresented: $showAddonManager) {
            StremioAddonsView()
        }
        .onChange(of: showAddonManager) { isShowing in
            if !isShowing { viewModel.reloadExtraRows() }
        }
        .onChange(of: extraRowTogglesKey) { _ in
            viewModel.reloadExtraRows()
        }
        .onChange(of: rowsStore.heroSource) { _ in
            viewModel.applyHeroSourceChange()
        }
        .onChange(of: network.isOnline) { isOnline in
            guard isOnline, viewModel.hasRowFailures || viewModel.hasNoContent else { return }
            Task { await viewModel.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchStateDidChange)) { _ in
            // Watched / removed / reset anywhere in the app: refresh the row.
            Task { await viewModel.refreshContinueWatching() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .localWatchHistoryDidChange)) { _ in
            // Stream playback just wrote progress; pick it up when returning to Home.
            guard AppModeStore.shared.isStremioOnly else { return }
            Task { await viewModel.loadLocalContinueWatching() }
        }
    }

    // MARK: - Page

    /// One lazy stack as the scroll content, so rows below the fold are only
    /// built when they come near the viewport.
    private var homeScrollContent: some View {
        let rows = viewModel.displayRows(store: rowsStore, settings: profileSettings, isOnline: network.isOnline)
        return ScrollView {
            LazyVStack(spacing: 0) {
                heroSection

                if !network.isOnline {
                    HomeOfflineCard { Task { await viewModel.refresh() } }
                        .padding(.top, DS.Space.s8)
                }

                // Spacing below the hero
                Color.clear.frame(height: 64)

                ForEach(rows) { row in
                    rowView(row)
                        .padding(.bottom, DS.Space.s40)
                        .transition(.opacity)
                }

                if viewModel.isInitialLoadComplete && network.isOnline && rows.isEmpty {
                    emptyStateCard
                        .padding(.bottom, DS.Space.s40)
                }
            }
            .animation(DS.Motion.emphasized, value: viewModel.extraSectionsState)
            .animation(DS.Motion.emphasized, value: viewModel.recentlyAddedPerLibraryState)
        }
    }

    /// Hero Section (Billboard or Carousel based on settings)
    @ViewBuilder
    private var heroSection: some View {
        if profileSettings.showHeroSection && viewModel.heroState != .empty {
            Group {
                if !viewModel.billboardItems.isEmpty {
                    switch profileSettings.heroLayout {
                    case "carousel":
                        HeroCarousel(
                            items: viewModel.billboardItems,
                            currentIndex: $viewModel.currentBillboardIndex,
                            onPlay: { item in viewModel.playItem(item) },
                            onInfo: { item in viewModel.showItemDetails(item) },
                            onMyList: { item in viewModel.toggleMyList(item) }
                        )
                    default: // "billboard"
                        BillboardSection(viewModel: viewModel)
                    }
                } else {
                    HeroSkeleton()
                }
            }
            .padding(.horizontal, DS.Space.s20)
            .padding(.vertical, DS.Space.s16)
        }
    }

    @ViewBuilder
    private func rowView(_ row: HomeDisplayRow) -> some View {
        switch row.content {
        case .continueWatching:
            SectionContainer(
                state: viewModel.continueWatchingState,
                content: { continueWatchingRow(title: row.title) },
                skeleton: { continueWatchingSkeleton }
            )
        case .section(let section):
            sectionRow(section)
                .environment(\.rowTitleCaption, row.caption)
        case .skeleton(let cardType):
            SkeletonCarouselRow(
                itemWidth: cardType == .poster ? skeletonPosterWidth : 420,
                itemCount: cardType == .poster ? 6 : 4,
                cardType: cardType
            )
        case .failure(let failure):
            HomeRowErrorCard(
                failure: failure,
                isRetrying: viewModel.retryingRowIds.contains(failure.id),
                onRetry: { viewModel.retry(failure) }
            )
        case .userCollection(let id):
            UserCollectionHomeRow(collectionId: id, title: row.title) { item in
                viewModel.showItemDetails(item)
            }
        }
    }

    @ViewBuilder
    private func sectionRow(_ section: LibrarySection) -> some View {
        if section.isCollection {
            CollectionSectionRow(
                section: section,
                rowLayout: profileSettings.rowLayout,
                onTap: { item in viewModel.showItemDetails(item) },
                onBrowse: { context in presentBrowse(context) }
            )
        } else if profileSettings.rowLayout == "poster" {
            PosterSectionRow(
                section: section,
                onTap: { item in viewModel.showItemDetails(item) },
                onBrowse: { context in presentBrowse(context) }
            )
        } else {
            LandscapeSectionView(
                section: section,
                onTap: { item in viewModel.showItemDetails(item) },
                onBrowse: { context in presentBrowse(context) }
            )
        }
    }

    /// Nothing to show: says why and offers the most useful next step.
    private var emptyStateCard: some View {
        let hasHiddenRows = !rowsStore.hidden.isEmpty
        let showHidden = HomeStateCard.Action(title: "Show Hidden Rows") { rowsStore.showAllRows() }
        let refresh = HomeStateCard.Action(title: "Refresh") { Task { await viewModel.refresh() } }
        if AppModeStore.shared.isStremioOnly {
            return HomeStateCard(
                icon: "puzzlepiece.extension",
                title: "Nothing to show yet",
                message: "Add Stremio addons to fill your home screen with catalogs.",
                primary: .init(title: "Add Addons") { showAddonManager = true },
                secondary: hasHiddenRows ? showHidden : nil
            )
        }
        return HomeStateCard(
            icon: "rectangle.stack",
            title: "Nothing to show yet",
            message: hasHiddenRows
                ? "All of your home rows are hidden."
                : "Your libraries and rows came back empty. Check your Plex server in Settings.",
            primary: hasHiddenRows ? showHidden : refresh
        )
    }

    /// Rows Settings toggles that decide which extra rows get fetched.
    private var extraRowTogglesKey: [Bool] {
        [
            profileSettings.showTrendingRows,
            profileSettings.showTraktRows,
            profileSettings.showPlexPopular,
            profileSettings.showWatchlist,
            profileSettings.showStremioCatalogRows,
        ]
    }

    // MARK: - Continue Watching

    @ViewBuilder
    private func continueWatchingRow(title: String) -> some View {
        let items = viewModel.continueWatchingItems(sortedBy: rowsStore.continueWatchingSort)
        let onAction: ContinueWatchingActionHandler = { action, item in
            viewModel.performContinueWatchingAction(action, item: item)
        }
        Group {
            switch ContinueWatchingCardStyle(storageValue: profileSettings.continueWatchingLayout) {
            case .poster:
                ContinueWatchingPosterRow(
                    title: title,
                    items: items,
                    itemsWithMultipleVersions: viewModel.continueWatchingVersions,
                    busyItemIds: viewModel.continueWatchingBusyIds,
                    onTap: { item in viewModel.showItemDetails(item) },
                    onAction: onAction
                )
            case .wide:
                ContinueWatchingWideRow(
                    title: title,
                    items: items,
                    busyItemIds: viewModel.continueWatchingBusyIds,
                    blurUpNext: rowsStore.continueWatchingBlurNextUp,
                    onTap: { item in viewModel.showItemDetails(item) },
                    onAction: onAction
                )
            case .landscape:
                ContinueWatchingLandscapeRow(
                    title: title,
                    items: items,
                    itemsWithMultipleVersions: viewModel.continueWatchingVersions,
                    busyItemIds: viewModel.continueWatchingBusyIds,
                    onTap: { item in viewModel.showItemDetails(item) },
                    onAction: onAction
                )
            }
        }
        .animation(DS.Motion.standard, value: items.map(\.id))
    }

    private var continueWatchingSkeleton: some View {
        let style = ContinueWatchingCardStyle(storageValue: profileSettings.continueWatchingLayout)
        return SkeletonCarouselRow(
            itemWidth: style == .poster ? skeletonPosterWidth : (style == .wide ? ContinueWatchingWideRow.cardWidth : 380),
            itemCount: style == .poster ? 6 : (style == .wide ? 3 : 4),
            cardType: style == .poster ? .poster : .landscape
        )
    }

    private func presentBrowse(_ context: BrowseContext) {
        activeBrowseContext = context
        showBrowseModal = true
        Task {
            await browseViewModel.load(context: context)
        }
    }
}

// MARK: - Billboard Section

struct BillboardSection: View {
    @ObservedObject var viewModel: HomeViewModel
    @ObservedObject private var profileSettings = ProfileSettings.shared

    @State private var isHovered = false

    var currentItem: MediaItem? {
        guard viewModel.currentBillboardIndex < viewModel.billboardItems.count else {
            return nil
        }
        return viewModel.billboardItems[viewModel.currentBillboardIndex]
    }

    var body: some View {
        ZStack {
            // Billboard content
            Group {
                if let item = currentItem {
                    BillboardView(
                        item: item,
                        onPlay: {
                            viewModel.playItem(item)
                        },
                        onInfo: {
                            viewModel.showItemDetails(item)
                        },
                        onMyList: {
                            viewModel.toggleMyList(item)
                        }
                    )
                    .id(item.id) // Force recreation on item change
                    .transition(.opacity)
                }
            }

            // Navigation controls overlay (only if multiple items)
            if viewModel.billboardItems.count > 1 {
                // Left/Right arrows in the middle
                HStack {
                    // Left arrow
                    Button(action: previousItem) {
                        Image(systemName: "chevron.left")
                            .font(.flixorIcon(DS.Icon.xl, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(.ultraThinMaterial.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovered ? 1 : 0)
                    .accessibilityLabel(Text("Previous featured item"))

                    Spacer()

                    // Right arrow
                    Button(action: nextItem) {
                        Image(systemName: "chevron.right")
                            .font(.flixorIcon(DS.Icon.xl, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(.ultraThinMaterial.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovered ? 1 : 0)
                    .accessibilityLabel(Text("Next featured item"))
                }
                .padding(.horizontal, DS.Space.s24)

                // Page indicators at the bottom
                VStack {
                    Spacer()

                    HeroPageIndicator(
                        count: viewModel.billboardItems.count,
                        currentIndex: viewModel.currentBillboardIndex,
                        style: .dots,
                        onSelect: { goToIndex($0) }
                    )
                    .padding(.bottom, DS.Space.s40)
                }
            }
        }
        .onHover { hovering in
            withAnimation(DS.Motion.standard) {
                isHovered = hovering
            }
            // Pause/resume auto-rotation on hover
            if profileSettings.heroAutoRotate {
                if hovering {
                    viewModel.stopBillboardRotation()
                } else {
                    viewModel.resumeBillboardRotation()
                }
            }
        }
        .animation(DS.Motion.slow, value: viewModel.currentBillboardIndex)
        .onChange(of: profileSettings.heroAutoRotate) { newValue in
            if newValue {
                viewModel.resumeBillboardRotation()
            } else {
                viewModel.stopBillboardRotation()
            }
        }
    }

    // MARK: - Navigation

    private func previousItem() {
        withAnimation(DS.Motion.slow) {
            if viewModel.currentBillboardIndex > 0 {
                viewModel.currentBillboardIndex -= 1
            } else {
                viewModel.currentBillboardIndex = viewModel.billboardItems.count - 1
            }
        }
        viewModel.updateHeroColorsForCurrentItem()
    }

    private func nextItem() {
        withAnimation(DS.Motion.slow) {
            if viewModel.currentBillboardIndex < viewModel.billboardItems.count - 1 {
                viewModel.currentBillboardIndex += 1
            } else {
                viewModel.currentBillboardIndex = 0
            }
        }
        viewModel.updateHeroColorsForCurrentItem()
    }

    private func goToIndex(_ index: Int) {
        withAnimation(DS.Motion.slow) {
            viewModel.currentBillboardIndex = index
        }
        viewModel.updateHeroColorsForCurrentItem()
    }
}

// MARK: - Hero Skeleton

struct HeroSkeleton: View {
    @Environment(\.windowMetrics) private var metrics
    @ObservedObject private var profileSettings = ProfileSettings.shared

    private var height: CGFloat {
        profileSettings.heroLayout == "carousel" ? metrics.homeCarouselHeight : metrics.homeBillboardHeight
    }

    var body: some View {
        SkeletonView(height: height, cornerRadius: DS.Radius.r22)
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.r22, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
    }
}

// MARK: - Continue Watching Section

struct ContinueWatchingSection: View {
    @ObservedObject var viewModel: HomeViewModel
    var onTap: (MediaItem) -> Void

    var body: some View {
        CarouselRow(
            title: "Continue Watching",
            items: viewModel.continueWatchingItems,
            itemWidth: 420,
            spacing: 16,
            rowHeight: (420 * 0.5) + 56
        ) { item in
            LandscapeCard(item: item, width: 420, onTap: {
                onTap(item)
            }, showProgressBar: true)
        }
    }
}

// MARK: - On Deck Section

struct OnDeckSection: View {
    @ObservedObject var viewModel: HomeViewModel

    var body: some View {
        CarouselRow(
            title: "On Deck",
            items: viewModel.onDeckItems,
            itemWidth: 420,
            spacing: 16,
            rowHeight: (420 * 0.5) + 56
        ) { item in
            LandscapeCard(item: item, width: 420) {
                viewModel.showItemDetails(item)
            }
        }
    }
}

// MARK: - Recently Added Section

struct RecentlyAddedSection: View {
    @ObservedObject var viewModel: HomeViewModel

    var body: some View {
        CarouselRow(
            title: "Recently Added",
            items: viewModel.recentlyAddedItems,
            itemWidth: 420,
            spacing: 16,
            rowHeight: (420 * 0.5) + 56
        ) { item in
            LandscapeCard(item: item, width: 420) {
                viewModel.showItemDetails(item)
            }
        }
    }
}

// MARK: - Library Section

struct LibrarySectionView: View {
    let section: LibrarySection
    @ObservedObject var viewModel: HomeViewModel
    var onBrowse: ((BrowseContext) -> Void)?

    @ObservedObject private var profileSettings = ProfileSettings.shared
    @Environment(\.windowMetrics) private var metrics

    private var posterWidth: CGFloat {
        metrics.posterWidth(designWidth: 150, storedSize: profileSettings.posterSize)
    }

    var body: some View {
        CarouselRow(
            title: section.title,
            items: section.items,
            itemWidth: posterWidth,
            browseAction: section.browseContext.map { context in
                { onBrowse?(context) }
            }
        ) { item in
            PosterCard(item: item, width: posterWidth) {
                viewModel.showItemDetails(item)
            }
        }
    }
}

// MARK: - Generic Landscape Section (for extraSections)

struct LandscapeSectionView: View {
    let section: LibrarySection
    var onTap: (MediaItem) -> Void
    var onBrowse: ((BrowseContext) -> Void)?

    var body: some View {
        CarouselRow(
            title: section.title,
            items: section.items,
            itemWidth: 420,
            spacing: 16,
            rowHeight: (420 * 0.5) + 56,
            browseAction: section.browseContext.map { context in
                { onBrowse?(context) }
            }
        ) { item in
            LandscapeCard(item: item, width: 420) {
                // For non-continue rows, open details by default
                onTap(item)
            }
        }
    }
}

// MARK: - Home Background Gradient (dynamic UltraBlur colors)

struct HomeBackground: View {
    var heroColors: PlexUltraBlurColors?

    @Environment(\.flixorTheme) private var theme

    // Default fallback color (dark theme)
    private let defaultColor = "0d0d0f"

    // Get colors with fallback (matching mobile: topLeft at top, bottomLeft at bottom)
    private var topColor: Color {
        theme.pureBlack ? .black : Color(hex: heroColors?.topLeft ?? defaultColor)
    }

    private var bottomColor: Color {
        theme.pureBlack ? .black : Color(hex: heroColors?.bottomLeft ?? defaultColor)
    }

    var body: some View {
        // Vertical gradient matching mobile orientation:
        // Solid topLeft for hero area (0-35%), then transitions to bottomLeft
        LinearGradient(
            stops: [
                .init(color: topColor, location: 0),
                .init(color: topColor, location: 0.35),
                .init(color: bottomColor, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .animation(DS.Motion.cinematic, value: heroColors?.topLeft)
        .animation(DS.Motion.cinematic, value: heroColors?.bottomLeft)
    }
}

// MARK: - Error View

struct ErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: DS.Space.s20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundStyle(.orange)

            Text("Something went wrong")
                .font(.title2.bold())

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.Space.s40)

            Button(action: onRetry) {
                Text("Try Again")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, DS.Space.s32)
                    .padding(.vertical, DS.Space.s12)
                    .background(Color.orange)
                    .cornerRadius(DS.Radius.r8)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Collection Section Row (with sparkles icon)

struct CollectionSectionRow: View {
    let section: LibrarySection
    let rowLayout: String
    var onTap: (MediaItem) -> Void
    var onBrowse: ((BrowseContext) -> Void)?

    @State private var isHeaderHovered = false
    @Environment(\.rowTitleCaption) private var titleCaption
    @ObservedObject private var profileSettings = ProfileSettings.shared
    @Environment(\.windowMetrics) private var metrics

    private var posterWidth: CGFloat {
        metrics.posterWidth(designWidth: 150, storedSize: profileSettings.posterSize)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s12) {
            // Header with sparkles icon
            HStack(spacing: DS.Space.s8) {
                Image(systemName: "sparkles")
                    .font(.flixorIcon(DS.Icon.sm, weight: .semibold))
                    .foregroundStyle(.white)

                Text(section.title)
                    .font(.flixor(.title3, weight: .semibold))
                    .foregroundStyle(.white)

                if let titleCaption {
                    RowTitleCaptionText(caption: titleCaption)
                }

                if let browseContext = section.browseContext {
                    Button(action: { onBrowse?(browseContext) }) {
                        HStack(spacing: DS.Space.s4) {
                            Text("Browse")
                            Image(systemName: "chevron.right")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, DS.Space.s6)
                        .padding(.vertical, DS.Space.s4)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.r6, style: .continuous)
                                .fill(Color.white.opacity(isHeaderHovered ? 0.12 : 0))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(isHeaderHovered ? 1 : 0)
                    .offset(x: isHeaderHovered ? 4 : 0)
                    .animation(.easeOut(duration: 0.24), value: isHeaderHovered)
                    .allowsHitTesting(isHeaderHovered)
                }

                Spacer()
            }
            .padding(.horizontal, DS.Space.s20)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.2)) {
                    isHeaderHovered = hovering
                }
            }
            .contentShape(Rectangle())

            // Row content
            if rowLayout == "poster" {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: DS.Space.s12) {
                        ForEach(section.items) { item in
                            PosterCard(item: item, width: posterWidth) {
                                onTap(item)
                            }
                        }
                    }
                    .padding(.horizontal, DS.Space.s20)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: DS.Space.s16) {
                        ForEach(section.items) { item in
                            LandscapeCard(item: item, width: 420) {
                                onTap(item)
                            }
                        }
                    }
                    .padding(.horizontal, DS.Space.s20)
                }
            }
        }
    }
}

#if DEBUG && canImport(PreviewsMacros)
#Preview {
    HomeView()
        .environmentObject(SessionManager.shared)
        .environmentObject(APIClient.shared)
        .frame(width: 1200, height: 800)
}
#endif
