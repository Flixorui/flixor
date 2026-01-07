//
//  NewPopularView.swift
//  FlixorMac
//
//  New & Popular screen - 1:1 feature match with web version
//

import SwiftUI

struct NewPopularView: View {
    @StateObject private var viewModel = NewPopularViewModel()
    @EnvironmentObject private var router: NavigationRouter
    @EnvironmentObject private var watchlistController: WatchlistController

    private let horizontalPadding: CGFloat = 64
    private let gridSpacing: CGFloat = 16

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Hero Section
                if let hero = viewModel.hero, !viewModel.isLoading {
                    NewPopularHero(
                        data: hero,
                        onPlay: {
                            if hero.canPlay {
                                navigateToPlayer(hero.id)
                            }
                        },
                        onMoreInfo: {
                            navigateToDetails(hero.id, mediaType: hero.mediaType)
                        },
                        onMyList: {
                            // TODO: Add to watchlist
                        },
                        isInMyList: false
                    )
                }

                // Tab Navigation + Filters
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 0) {
                        // Tabs
                        tabNavigation
                        Spacer()
                        // Filters
                        filterControls
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 32)

                    Divider()
                        .padding(.horizontal, horizontalPadding)
                }

                // Content Area
                if viewModel.isLoading {
                    loadingView
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, 32)
                } else if let errorMessage = viewModel.errorMessage {
                    errorView(errorMessage)
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, 32)
                } else {
                    contentView
                        .padding(.top, 32)
                }
            }
        }
        .background(HomeBackground())
        .navigationTitle("")
        .task {
            await viewModel.load()
        }
        .onChange(of: viewModel.activeTab) { _ in
            Task { await viewModel.load() }
        }
        .onChange(of: viewModel.contentType) { _ in
            Task { await viewModel.load() }
        }
        .onChange(of: viewModel.period) { _ in
            Task { await viewModel.load() }
        }
    }

    // MARK: - Tab Navigation

    private var tabNavigation: some View {
        HStack(spacing: 32) {
            ForEach(NewPopularViewModel.Tab.allCases) { tab in
                Button(action: {
                    viewModel.activeTab = tab
                }) {
                    VStack(spacing: 6) {
                        Text(tab.rawValue)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(viewModel.activeTab == tab ? .white : .white.opacity(0.5))

                        Rectangle()
                            .fill(viewModel.activeTab == tab ? Color.white : Color.clear)
                            .frame(height: 3)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Filter Controls

    private var filterControls: some View {
        HStack(spacing: 16) {
            // Content Type Filter
            Picker("Type", selection: $viewModel.contentType) {
                ForEach(NewPopularViewModel.ContentType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 140)

            // Period Filter (only for Trending and Top 10)
            if viewModel.activeTab == .trending || viewModel.activeTab == .top10 {
                Picker("Period", selection: $viewModel.period) {
                    ForEach(NewPopularViewModel.Period.allCases) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)
            }
        }
    }

    // MARK: - Content Views

    @ViewBuilder
    private var contentView: some View {
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

    private var trendingContent: some View {
        VStack(alignment: .leading, spacing: 40) {
            // New on Plex
            if !viewModel.recentlyAdded.isEmpty {
                contentRow(title: "New on Your Plex", items: viewModel.recentlyAdded)
            }

            // Popular on Plex
            if !viewModel.popularPlex.isEmpty {
                contentRow(title: "Popular on Your Plex", items: viewModel.popularPlex)
            }

            // Trending Movies
            if (viewModel.contentType == .all || viewModel.contentType == .movies) && !viewModel.trendingMovies.isEmpty {
                contentRow(title: "Trending Movies", items: viewModel.trendingMovies)
            }

            // Trending TV Shows
            if (viewModel.contentType == .all || viewModel.contentType == .shows) && !viewModel.trendingShows.isEmpty {
                contentRow(title: "Trending TV Shows", items: viewModel.trendingShows)
            }
        }
        .padding(.bottom, 40)
    }

    private var top10Content: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Top 10 \(viewModel.period.rawValue)")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, horizontalPadding)

            if !viewModel.top10.isEmpty {
                Top10GridView(items: viewModel.top10) { id, mediaType in
                    navigateToDetails(id, mediaType: mediaType)
                }
                .padding(.horizontal, horizontalPadding)
            } else {
                Text("No top 10 content available")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, horizontalPadding)
            }
        }
        .padding(.bottom, 32)
    }

    private var comingSoonContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            if !viewModel.upcoming.isEmpty {
                contentRow(title: "Coming Soon", items: viewModel.upcoming)
                    .padding(.horizontal, horizontalPadding)
            } else {
                Text("No upcoming content available")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, horizontalPadding)
            }
        }
        .padding(.bottom, 32)
    }

    private var worthWaitContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            if !viewModel.anticipated.isEmpty {
                contentRow(title: "Most Anticipated", items: viewModel.anticipated)
                    .padding(.horizontal, horizontalPadding)
            } else {
                Text("No anticipated content available")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, horizontalPadding)
            }
        }
        .padding(.bottom, 32)
    }

    // MARK: - Content Row

    private func contentRow(title: String, items: [DisplayMediaItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(.primary)
                .padding(.horizontal, 20)

            // Carousel with navigation arrows
            CarouselView(
                items: items,
                itemWidth: 420,
                spacing: 16,
                rowHeight: (420 * 0.5) + 56
            ) { item in
                LandscapeCard(
                    item: item.toMediaItem(),
                    width: 420,
                    onTap: {
                        navigateToDetails(item.id, mediaType: item.mediaType)
                    }
                )
            }
            .frame(height: (420 * 0.5) + 56)
        }
    }

    // MARK: - Loading & Error States

    private var loadingView: some View {
        VStack(spacing: 40) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 12) {
                    // Title skeleton
                    SkeletonView(height: 24, cornerRadius: 8)
                        .frame(width: 200)
                        .padding(.horizontal, 20)

                    // Cards skeleton - landscape aspect ratio (2:1) with 420px width
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 16) {
                            ForEach(0..<8, id: \.self) { _ in
                                SkeletonView(height: 210, cornerRadius: 14)
                                    .frame(width: 420)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .frame(height: (420 * 0.5) + 56)
                }
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text(message)
                .font(.headline)
                .foregroundStyle(.white)

            Button("Retry") {
                Task { await viewModel.load() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    // MARK: - Navigation Helpers

    private func navigateToDetails(_ id: String, mediaType: String) {
        // Convert DisplayMediaItem to MediaItem for navigation
        let item = MediaItem(
            id: id,
            title: "",
            type: mediaType == "tv" ? "show" : "movie",
            thumb: nil,
            art: nil,
            year: nil,
            rating: nil,
            duration: nil,
            viewOffset: nil,
            summary: nil,
            grandparentTitle: nil,
            grandparentThumb: nil,
            grandparentArt: nil,
            grandparentRatingKey: nil,
            parentIndex: nil,
            index: nil,
            parentRatingKey: nil,
            parentTitle: nil,
            leafCount: nil,
            viewedLeafCount: nil
        )
        router.newPopularPath.append(DetailsNavigationItem(item: item))
    }

    private func navigateToPlayer(_ id: String) {
        let item = MediaItem(
            id: id,
            title: "",
            type: "movie",
            thumb: nil,
            art: nil,
            year: nil,
            rating: nil,
            duration: nil,
            viewOffset: nil,
            summary: nil,
            grandparentTitle: nil,
            grandparentThumb: nil,
            grandparentArt: nil,
            grandparentRatingKey: nil,
            parentIndex: nil,
            index: nil,
            parentRatingKey: nil,
            parentTitle: nil,
            leafCount: nil,
            viewedLeafCount: nil
        )
        router.newPopularPath.append(item)
    }
}

// MARK: - Top 10 Grid Component

private struct Top10GridView: View {
    let items: [DisplayMediaItem]
    let onTap: (String, String) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 5), spacing: 16) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Top10Card(item: item, rank: index + 1) {
                    onTap(item.id, item.mediaType)
                }
            }
        }
    }
}

private struct Top10Card: View {
    let item: DisplayMediaItem
    let rank: Int
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topLeading) {
                // Poster Image
                if let imageURL = item.imageURL {
                    CachedAsyncImage(url: imageURL)
                        .aspectRatio(2/3, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.3))
                        .aspectRatio(2/3, contentMode: .fit)
                }

                // Rank number overlay
                Text("\(rank)")
                    .font(.system(size: 72, weight: .black))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.8), radius: 4, x: 2, y: 2)
                    .padding(16)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(isHovered ? 0.9 : 0.15), lineWidth: isHovered ? 2 : 1)
            )
            .shadow(color: .black.opacity(isHovered ? 0.5 : 0.2), radius: isHovered ? 12 : 6, y: isHovered ? 6 : 3)
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#if DEBUG && canImport(PreviewsMacros)
#Preview {
    NavigationStack {
        NewPopularView()
            .environmentObject(NavigationRouter())
            .environmentObject(WatchlistController())
    }
}
#endif
