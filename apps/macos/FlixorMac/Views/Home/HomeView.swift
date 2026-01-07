//
//  HomeView.swift
//  FlixorMac
//
//  Home screen with Billboard, Continue Watching, etc.
//

import SwiftUI

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
        .background(HomeBackground())
        .navigationTitle("")
        .task {
            print("📱 [HomeView] .task triggered - billboardItems.isEmpty: \(viewModel.billboardItems.isEmpty), isLoading: \(viewModel.isLoading)")
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

    var currentItem: MediaItem? {
        guard viewModel.currentBillboardIndex < viewModel.billboardItems.count else {
            return nil
        }
        return viewModel.billboardItems[viewModel.currentBillboardIndex]
    }

    var body: some View {
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

// MARK: - Home Background Gradient (approximate web bg-home-gradient)

struct HomeBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x0a0a0a), Color(hex: 0x0f0f10), Color(hex: 0x0b0c0d)], startPoint: .top, endPoint: .bottom)

            // Muted teal glow (top-right)
            RadialGradient(gradient: Gradient(colors: [Color(red: 20/255, green: 76/255, blue: 84/255, opacity: 0.42), Color(red: 20/255, green: 76/255, blue: 84/255, opacity: 0.20), .clear]),
                            center: .init(x: 0.84, y: 0.06), startRadius: 0, endRadius: 800)

            // Deep red glow (bottom-left)
            RadialGradient(gradient: Gradient(colors: [Color(red: 122/255, green: 22/255, blue: 18/255, opacity: 0.44), Color(red: 122/255, green: 22/255, blue: 18/255, opacity: 0.20), .clear]),
                            center: .init(x: 0.10, y: 0.92), startRadius: 0, endRadius: 800)

            // Subtle echoes
            RadialGradient(gradient: Gradient(colors: [Color(red: 122/255, green: 22/255, blue: 18/255, opacity: 0.12), Color(red: 122/255, green: 22/255, blue: 18/255, opacity: 0.06), .clear]),
                            center: .init(x: 0.08, y: 0.08), startRadius: 0, endRadius: 700)

            RadialGradient(gradient: Gradient(colors: [Color(red: 20/255, green: 76/255, blue: 84/255, opacity: 0.12), Color(red: 20/255, green: 76/255, blue: 84/255, opacity: 0.06), .clear]),
                            center: .init(x: 0.92, y: 0.92), startRadius: 0, endRadius: 700)

            // Soft vignette
            RadialGradient(gradient: Gradient(colors: [.clear, Color.black.opacity(0.22)]), center: .init(x: 0.5, y: 0.45), startRadius: 300, endRadius: 1200)
        }
        .ignoresSafeArea()
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
