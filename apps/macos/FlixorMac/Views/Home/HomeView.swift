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

    // Home Screen Settings
    @AppStorage("heroLayout") private var heroLayout: String = "billboard"
    @AppStorage("showHeroSection") private var showHeroSection: Bool = true
    @AppStorage("showContinueWatching") private var showContinueWatching: Bool = true
    @AppStorage("continueWatchingLayout") private var continueWatchingLayout: String = "landscape"
    @AppStorage("rowLayout") private var rowLayout: String = "landscape"

    var body: some View {
        ZStack {
            Group {
                if let error = viewModel.error {
                    ErrorView(message: error) {
                        Task {
                            await viewModel.refresh()
                        }
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 0) {

                            // Hero Section (Billboard or Carousel based on settings)
                            if showHeroSection {
                                Group {
                                    if !viewModel.billboardItems.isEmpty {
                                        switch heroLayout {
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
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                            }

                            // Spacing below hero
                            Color.clear.frame(height: 24)

                            // Content sections with modular skeleton loading
                            VStack(spacing: 40) {
                                // Continue Watching - shows skeleton until loaded (if enabled)
                                if showContinueWatching {
                                    SectionContainer(
                                        state: viewModel.continueWatchingState,
                                        content: {
                                            switch continueWatchingLayout {
                                            case "poster":
                                                ContinueWatchingPosterRow(
                                                    items: viewModel.continueWatchingItems,
                                                    onTap: { item in viewModel.showItemDetails(item) }
                                                )
                                            default: // "landscape"
                                                ContinueWatchingLandscapeRow(
                                                    items: viewModel.continueWatchingItems,
                                                    onTap: { item in viewModel.showItemDetails(item) }
                                                )
                                            }
                                        },
                                        skeleton: {
                                            SkeletonCarouselRow(
                                                itemWidth: continueWatchingLayout == "poster" ? 160 : 380,
                                                itemCount: continueWatchingLayout == "poster" ? 6 : 4,
                                                cardType: continueWatchingLayout == "poster" ? .poster : .landscape
                                            )
                                        }
                                    )
                                }

                                // Extra sections (Popular on Plex, Trending Now, Watchlist, Genres, Trakt)
                                // Show skeleton placeholders while loading, then fade in actual content
                                if viewModel.extraSectionsState.isLoading {
                                    // Show expected number of skeleton rows
                                    ForEach(0..<viewModel.expectedExtraSectionCount, id: \.self) { _ in
                                        SkeletonCarouselRow(
                                            itemWidth: rowLayout == "poster" ? 160 : 420,
                                            itemCount: rowLayout == "poster" ? 6 : 4,
                                            cardType: rowLayout == "poster" ? .poster : .landscape
                                        )
                                    }
                                } else {
                                    ForEach(viewModel.extraSections) { section in
                                        Group {
                                            if rowLayout == "poster" {
                                                PosterSectionRow(
                                                    section: section,
                                                    onTap: { item in
                                                        viewModel.showItemDetails(item)
                                                    },
                                                    onBrowse: { context in
                                                        presentBrowse(context)
                                                    }
                                                )
                                            } else {
                                                LandscapeSectionView(
                                                    section: section,
                                                    onTap: { item in
                                                        viewModel.showItemDetails(item)
                                                    },
                                                    onBrowse: { context in
                                                        presentBrowse(context)
                                                    }
                                                )
                                            }
                                        }
                                        .transition(.opacity)
                                    }
                                }
                            }
                            .padding(.vertical, 40)
                            .animation(.easeInOut(duration: 0.3), value: viewModel.extraSectionsState)
                        }
                    }
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
        .onDisappear {
            viewModel.stopBillboardRotation()
        }
        .toast()
        .onChange(of: viewModel.pendingAction) { action in
            guard let action = action else { return }
            switch action {
            case .play(let item):
                router.homePath.append(item)
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
    @AppStorage("heroAutoRotate") private var heroAutoRotate: Bool = true

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
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(.ultraThinMaterial.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovered ? 1 : 0)

                    Spacer()

                    // Right arrow
                    Button(action: nextItem) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(.ultraThinMaterial.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovered ? 1 : 0)
                }
                .padding(.horizontal, 24)

                // Page indicators at the bottom
                VStack {
                    Spacer()

                    HStack(spacing: 6) {
                        ForEach(0..<viewModel.billboardItems.count, id: \.self) { index in
                            Button(action: { goToIndex(index) }) {
                                Circle()
                                    .fill(index == viewModel.currentBillboardIndex ? Color.white : Color.white.opacity(0.4))
                                    .frame(width: index == viewModel.currentBillboardIndex ? 10 : 8, height: index == viewModel.currentBillboardIndex ? 10 : 8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial.opacity(0.4))
                    .clipShape(Capsule())
                    .padding(.bottom, 40)
                }
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
            // Pause/resume auto-rotation on hover
            if heroAutoRotate {
                if hovering {
                    viewModel.stopBillboardRotation()
                } else {
                    viewModel.resumeBillboardRotation()
                }
            }
        }
        .animation(.easeInOut(duration: 0.5), value: viewModel.currentBillboardIndex)
        .onChange(of: heroAutoRotate) { newValue in
            if newValue {
                viewModel.resumeBillboardRotation()
            } else {
                viewModel.stopBillboardRotation()
            }
        }
    }

    // MARK: - Navigation

    private func previousItem() {
        withAnimation(.easeInOut(duration: 0.5)) {
            if viewModel.currentBillboardIndex > 0 {
                viewModel.currentBillboardIndex -= 1
            } else {
                viewModel.currentBillboardIndex = viewModel.billboardItems.count - 1
            }
        }
        viewModel.updateHeroColorsForCurrentItem()
    }

    private func nextItem() {
        withAnimation(.easeInOut(duration: 0.5)) {
            if viewModel.currentBillboardIndex < viewModel.billboardItems.count - 1 {
                viewModel.currentBillboardIndex += 1
            } else {
                viewModel.currentBillboardIndex = 0
            }
        }
        viewModel.updateHeroColorsForCurrentItem()
    }

    private func goToIndex(_ index: Int) {
        withAnimation(.easeInOut(duration: 0.5)) {
            viewModel.currentBillboardIndex = index
        }
        viewModel.updateHeroColorsForCurrentItem()
    }
}

// MARK: - Hero Skeleton

struct HeroSkeleton: View {
    private let height: CGFloat = 600

    var body: some View {
        SkeletonView(height: height, cornerRadius: 22)
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
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

    var body: some View {
        CarouselRow(
            title: section.title,
            items: section.items,
            itemWidth: 150,
            browseAction: section.browseContext.map { context in
                { onBrowse?(context) }
            }
        ) { item in
            PosterCard(item: item, width: 150) {
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

    // Default fallback colors (teal/red theme)
    private let defaultTopRight = "144c54"  // Teal
    private let defaultBottomLeft = "7a1612" // Deep red

    // Get colors with fallback
    private var topRightColor: Color {
        Color(hex: heroColors?.topRight ?? defaultTopRight)
    }

    private var bottomLeftColor: Color {
        Color(hex: heroColors?.bottomLeft ?? defaultBottomLeft)
    }

    var body: some View {
        ZStack {
            // Base dark gradient
            LinearGradient(colors: [Color(hex: 0x0a0a0a), Color(hex: 0x0f0f10), Color(hex: 0x0b0c0d)], startPoint: .top, endPoint: .bottom)

            // Top-right glow (from hero colors)
            RadialGradient(
                gradient: Gradient(colors: [
                    topRightColor.opacity(0.50),
                    topRightColor.opacity(0.25),
                    .clear
                ]),
                center: .init(x: 0.84, y: 0.06),
                startRadius: 0,
                endRadius: 800
            )

            // Bottom-left glow (from hero colors)
            RadialGradient(
                gradient: Gradient(colors: [
                    bottomLeftColor.opacity(0.55),
                    bottomLeftColor.opacity(0.25),
                    .clear
                ]),
                center: .init(x: 0.10, y: 0.92),
                startRadius: 0,
                endRadius: 800
            )

            // Subtle echoes
            RadialGradient(
                gradient: Gradient(colors: [
                    bottomLeftColor.opacity(0.12),
                    bottomLeftColor.opacity(0.06),
                    .clear
                ]),
                center: .init(x: 0.08, y: 0.08),
                startRadius: 0,
                endRadius: 700
            )

            RadialGradient(
                gradient: Gradient(colors: [
                    topRightColor.opacity(0.12),
                    topRightColor.opacity(0.06),
                    .clear
                ]),
                center: .init(x: 0.92, y: 0.92),
                startRadius: 0,
                endRadius: 700
            )

            // Soft vignette
            RadialGradient(gradient: Gradient(colors: [.clear, Color.black.opacity(0.22)]), center: .init(x: 0.5, y: 0.45), startRadius: 300, endRadius: 1200)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.8), value: heroColors?.topRight)
        .animation(.easeInOut(duration: 0.8), value: heroColors?.bottomLeft)
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }

    /// Initialize from hex string (e.g., "144c54" or "#144c54")
    init(hex: String, alpha: Double = 1.0) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexString.hasPrefix("#") {
            hexString.removeFirst()
        }

        guard hexString.count == 6,
              let hexValue = UInt(hexString, radix: 16) else {
            // Fallback to black if invalid
            self.init(.sRGB, red: 0, green: 0, blue: 0, opacity: alpha)
            return
        }

        self.init(hex: hexValue, alpha: alpha)
    }
}

// MARK: - Error View

struct ErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundStyle(.orange)

            Text("Something went wrong")
                .font(.title2.bold())

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button(action: onRetry) {
                Text("Try Again")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(Color.orange)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
