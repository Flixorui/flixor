//
//  SearchView.swift
//  FlixorMac
//
//  Search screen with Popular/Trending and live search results
//

import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @EnvironmentObject private var router: NavigationRouter
    @EnvironmentObject private var mainViewState: MainViewState
    @AppStorage("includeTmdbInSearch") private var includeTmdbInSearch: Bool = true

    var body: some View {
        ZStack(alignment: .top) {
            // Background
            SearchBackground()

            ScrollView {
                VStack(spacing: 0) {
                    // Search Input Field
                    SearchInputField(query: $viewModel.query)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    // Content based on search mode
                    Group {
                        switch viewModel.searchMode {
                        case .idle:
                            if includeTmdbInSearch {
                                IdleStateView(viewModel: viewModel, onTap: { item in
                                    navigateToDetails(item: item)
                                })
                            } else {
                                SearchPlaceholderView()
                            }
                        case .searching:
                            LoadingView(message: "Searching...")
                        case .results:
                            let hasResults = !viewModel.plexResults.isEmpty ||
                                           !viewModel.tmdbMovies.isEmpty ||
                                           !viewModel.tmdbShows.isEmpty
                            if hasResults {
                                SearchResultsView(viewModel: viewModel, onTap: { item in
                                    navigateToDetails(item: item)
                                })
                            } else {
                                EmptyStateView(query: viewModel.query)
                            }
                        }
                    }
                    .padding(.top, 24)
                }
            }
        }
        .navigationTitle("")
        .task {
            if includeTmdbInSearch && viewModel.popularItems.isEmpty && viewModel.trendingItems.isEmpty {
                await viewModel.loadInitialContent()
            }
        }
        .onChange(of: includeTmdbInSearch) { newValue in
            // Reload content when setting changes
            Task {
                await viewModel.loadInitialContent()
            }
        }
        .toast()
    }

    private func navigateToDetails(item: SearchViewModel.SearchResult) {
        let mediaItem = MediaItem(
            id: item.id,
            title: item.title,
            type: item.type.rawValue,
            thumb: item.imageURL?.absoluteString,
            art: nil,
            year: item.year.flatMap { Int($0) },
            rating: nil,
            duration: nil,
            viewOffset: nil,
            summary: item.overview,
            grandparentTitle: nil,
            grandparentThumb: nil,
            grandparentArt: nil,
            grandparentRatingKey: nil,
            parentIndex: nil,
            index: nil,
            parentRatingKey: nil,
            parentTitle: nil,
            leafCount: nil,
            viewedLeafCount: nil,
            editionTitle: item.editionTitle
        )
        router.searchPath.append(DetailsNavigationItem(item: mediaItem))
    }
}

// MARK: - Search Input Field

struct SearchInputField: View {
    @Binding var query: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search for movies, TV shows...", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($isFocused)

            if !query.isEmpty {
                Button(action: {
                    query = ""
                    isFocused = true
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(isFocused ? 0.20 : 0.12), lineWidth: 1)
        )
    }
}

// MARK: - Idle State (Grid of Trending Items with Landscape Cards)

struct IdleStateView: View {
    @ObservedObject var viewModel: SearchViewModel
    let onTap: (SearchViewModel.SearchResult) -> Void

    var body: some View {
        TrendingResultsRow(items: viewModel.trendingItems, onTap: onTap)
    }
}


struct PlexResultsRow: View {
    let items: [SearchViewModel.SearchResult]
    let onTap: (SearchViewModel.SearchResult) -> Void

    private let cardWidth: CGFloat = 420

    var body: some View {
        CarouselRow(
            title: "Results from Your Plex",
            items: items,
            itemWidth: cardWidth,
            spacing: 16,
            rowHeight: (cardWidth * 0.5) + 56
        ) { item in
            LandscapeCard(item: item.asMediaItem(), width: cardWidth) {
                onTap(item)
            }
        }
    }
}
struct SearchResultsView: View {
    @ObservedObject var viewModel: SearchViewModel
    let onTap: (SearchViewModel.SearchResult) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !viewModel.plexResults.isEmpty {
                PlexResultsRow(items: viewModel.plexResults, onTap: onTap)
                    .padding(.bottom, 32)
            }

            if !viewModel.tmdbMovies.isEmpty {
                SearchHorizontalRow(
                    title: viewModel.plexResults.isEmpty ? "Top Results" : "Movies",
                    items: viewModel.tmdbMovies,
                    onTap: onTap
                )
                .padding(.bottom, 32)
            }

            if !viewModel.tmdbShows.isEmpty {
                SearchHorizontalRow(
                    title: "TV Shows",
                    items: viewModel.tmdbShows,
                    onTap: onTap
                )
                .padding(.bottom, 32)
            }

            ForEach(viewModel.genreRows) { genreRow in
                SearchHorizontalRow(
                    title: genreRow.title,
                    items: genreRow.items,
                    onTap: onTap
                )
                .padding(.bottom, 32)
            }
        }
    }
}


// MARK: - Trending Results Row (Landscape Cards)

struct TrendingResultsRow: View {
    let items: [SearchViewModel.SearchResult]
    let onTap: (SearchViewModel.SearchResult) -> Void

    var body: some View {
        CarouselRow(
            title: "Recommended TV Shows & Movies",
            items: items,
            itemWidth: 420,
            spacing: 16,
            rowHeight: (420 * 0.5) + 56
        ) { item in
            LandscapeCard(item: item.asMediaItem(), width: 420) {
                onTap(item)
            }
        }
    }
}

// MARK: - Horizontal Row

struct SearchHorizontalRow: View {
    let title: String
    let items: [SearchViewModel.SearchResult]
    let onTap: (SearchViewModel.SearchResult) -> Void

    var body: some View {
        CarouselRow(
            title: title,
            items: items,
            itemWidth: 150,
            spacing: 14,
            rowHeight: (150 * 1.5) + 68
        ) { item in
            PosterCard(
                item: item.asMediaItem(),
                width: 150,
                topTrailingOverlay: item.available ? AnyView(AvailableBadge().padding(6)) : nil
            ) {
                onTap(item)
            }
        }
    }
}

// MARK: - SearchResult Adapter

extension SearchViewModel.SearchResult {
    func asMediaItem() -> MediaItem {
        MediaItem(
            id: id,
            title: title,
            type: type.rawValue,
            thumb: imageURL?.absoluteString,
            art: imageURL?.absoluteString,
            year: year.flatMap { Int($0) },
            rating: nil,
            duration: nil,
            viewOffset: nil,
            summary: overview,
            grandparentTitle: nil,
            grandparentThumb: nil,
            grandparentArt: nil,
            grandparentRatingKey: nil,
            parentIndex: nil,
            index: nil,
            parentRatingKey: nil,
            parentTitle: nil,
            leafCount: nil,
            viewedLeafCount: nil,
            editionTitle: editionTitle
        )
    }
}
// MARK: - Available Badge

struct AvailableBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
            Text("In Library")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.green.opacity(0.9))
        .clipShape(Capsule())
    }
}

// MARK: - Placeholder Image

struct PlaceholderImage: View {
    var body: some View {
        ZStack {
            Color.white.opacity(0.08)
            Image(systemName: "film")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Empty State View

struct EmptyStateView: View {
    let query: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("No results for \"\(query)\"")
                .font(.title2.bold())

            Text("Try searching for something else")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 120)
    }
}

// MARK: - Search Placeholder View (when TMDB is disabled)

struct SearchPlaceholderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("Search Your Library")
                .font(.title2.bold())

            Text("Type to search for movies and TV shows in your Plex library")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 120)
        .padding(.horizontal, 40)
    }
}

// MARK: - Search Background

struct SearchBackground: View {
    var body: some View {
        ZStack {
            // Base gradient
            LinearGradient(
                colors: [
                    Color(hex: 0x0a0a0a),
                    Color(hex: 0x0f0f10),
                    Color(hex: 0x0b0c0d)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Subtle teal accent (top-right)
            RadialGradient(
                gradient: Gradient(colors: [
                    Color(red: 20/255, green: 76/255, blue: 84/255, opacity: 0.28),
                    .clear
                ]),
                center: .init(x: 0.88, y: 0.10),
                startRadius: 0,
                endRadius: 600
            )

            // Subtle red accent (bottom-left)
            RadialGradient(
                gradient: Gradient(colors: [
                    Color(red: 122/255, green: 22/255, blue: 18/255, opacity: 0.30),
                    .clear
                ]),
                center: .init(x: 0.12, y: 0.88),
                startRadius: 0,
                endRadius: 600
            )
        }
        .ignoresSafeArea()
    }
}

#if DEBUG && canImport(PreviewsMacros)
#Preview {
    SearchView()
        .environmentObject(SessionManager.shared)
        .environmentObject(APIClient.shared)
        .frame(width: 1200, height: 800)
}
#endif