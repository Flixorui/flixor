import SwiftUI
import FlixorKit

struct TVSearchView: View {
    @ObservedObject private var viewModel: TVSearchViewModel
    @EnvironmentObject private var profileSettings: TVProfileSettings
    @Namespace private var focusNS

    @State private var selectedItem: MediaItem?

    init(viewModel: TVSearchViewModel) {
        self._viewModel = ObservedObject(wrappedValue: viewModel)
    }

    var body: some View {
        ZStack {
            UltraBlurGradientBackground(colors: TVHomeViewModel.defaultRowColors)
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.horizontal, UX.gridH)
                        .padding(.top, 36)

                    Group {
                        switch viewModel.searchMode {
                        case .idle:
                            idleView
                        case .searching:
                            loadingView
                        case .results:
                            resultsView
                        }
                    }
                    .padding(.top, 24)

                    Color.clear.frame(height: 100)
                }
            }
        }
        .focusScope(focusNS)
        .task {
            if profileSettings.includeTmdbInSearch,
               viewModel.popularItems.isEmpty,
               viewModel.trendingItems.isEmpty {
                await viewModel.loadInitialContent()
            }
        }
        .onChange(of: profileSettings.includeTmdbInSearch) { _ in
            Task { await viewModel.loadInitialContent() }
        }
        .fullScreenCover(item: $selectedItem) { item in
            TVDetailsView(item: item)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Search")
                .font(.system(size: 54, weight: .bold))
                .foregroundStyle(.white)

            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))

                TextField("Search movies and TV shows", text: $viewModel.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.white)

                if !viewModel.query.isEmpty {
                    Button {
                        viewModel.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .frame(maxWidth: 780)
        }
    }

    @ViewBuilder
    private var idleView: some View {
        if profileSettings.includeTmdbInSearch {
            VStack(spacing: 26) {
                if !viewModel.trendingItems.isEmpty {
                    searchRow(
                        title: "Trending Now",
                        items: viewModel.trendingItems,
                        kind: .landscape,
                        sectionId: "idle-trending",
                        defaultFocus: true
                    )
                }

                if !viewModel.popularItems.isEmpty {
                    searchRow(
                        title: "Popular Right Now",
                        items: viewModel.popularItems,
                        kind: .landscape,
                        sectionId: "idle-popular"
                    )
                }

                if viewModel.trendingItems.isEmpty && viewModel.popularItems.isEmpty {
                    loadingView
                }
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                Text("Search Your Library")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.white)
                Text("Enable TMDB in Settings to get discovery feeds.")
                    .font(.system(size: 24))
                    .foregroundStyle(.white.opacity(0.68))
            }
            .frame(maxWidth: .infinity, minHeight: 620)
        }
    }

    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.4)
                .tint(.white)
            Text("Searching...")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white.opacity(0.86))
        }
        .frame(maxWidth: .infinity, minHeight: 460)
    }

    @ViewBuilder
    private var resultsView: some View {
        let hasResults = !viewModel.plexResults.isEmpty || !viewModel.tmdbMovies.isEmpty || !viewModel.tmdbShows.isEmpty
        if hasResults {
            VStack(spacing: 26) {
                if !viewModel.plexResults.isEmpty {
                    searchRow(
                        title: "Results from Your Plex",
                        items: viewModel.plexResults,
                        kind: .landscape,
                        sectionId: "results-plex",
                        defaultFocus: true
                    )
                }

                if !viewModel.tmdbMovies.isEmpty {
                    searchRow(
                        title: viewModel.plexResults.isEmpty ? "Top Results" : "Movies",
                        items: viewModel.tmdbMovies,
                        kind: .poster,
                        sectionId: "results-movies",
                        defaultFocus: viewModel.plexResults.isEmpty
                    )
                }

                if !viewModel.tmdbShows.isEmpty {
                    searchRow(
                        title: "TV Shows",
                        items: viewModel.tmdbShows,
                        kind: .poster,
                        sectionId: "results-shows"
                    )
                }

                ForEach(viewModel.genreRows) { row in
                    searchRow(
                        title: row.title,
                        items: row.items,
                        kind: .poster,
                        sectionId: "genre-\(row.id)"
                    )
                }
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                Text("No results for \"\(viewModel.query)\"")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)
                Text("Try a different title, genre, or actor.")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, minHeight: 620)
        }
    }

    @ViewBuilder
    private func searchRow(
        title: String,
        items: [TVSearchViewModel.SearchResult],
        kind: TVRowCardKind,
        sectionId: String,
        defaultFocus: Bool = false
    ) -> some View {
        let mediaItems = items.map(\.mediaItem)
        if !mediaItems.isEmpty {
            TVCarouselRow(
                title: title,
                items: mediaItems,
                kind: kind,
                focusNS: focusNS,
                defaultFocus: defaultFocus,
                sectionId: sectionId,
                landscapeFocusOutline: kind == .landscape,
                onSelect: { selectedItem = $0 }
            )
        }
    }
}
