import SwiftUI
import FlixorKit

struct TVSearchView: View {
    @ObservedObject private var viewModel: TVSearchViewModel
    @EnvironmentObject private var profileSettings: TVProfileSettings
    @EnvironmentObject private var focusCoordinator: TVFocusCoordinator
    @Environment(\.tvThemePalette) private var theme
    @Environment(\.tvTypography) private var typography
    @Namespace private var focusNS

    @State private var selectedItem: MediaItem?
    @State private var restoredSectionID: String?
    @State private var clearRestoreTask: Task<Void, Never>?

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
               profileSettings.showSearchDiscoverContent,
               viewModel.popularItems.isEmpty,
               viewModel.trendingItems.isEmpty {
                await viewModel.loadInitialContent()
            }
            restoreFocusToRememberedSection()
        }
        .onChange(of: profileSettings.includeTmdbInSearch) { _ in
            Task { await viewModel.loadInitialContent() }
        }
        .onChange(of: profileSettings.showSearchDiscoverContent) { enabled in
            if enabled, viewModel.popularItems.isEmpty, viewModel.trendingItems.isEmpty {
                Task { await viewModel.loadInitialContent() }
            }
        }
        .fullScreenCover(item: $selectedItem, onDismiss: restoreFocusToRememberedSection) { item in
            TVDetailsView(item: item)
        }
        .onDisappear {
            clearRestoreTask?.cancel()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Search")
                .font(typography.hero)
                .foregroundStyle(theme.textPrimary)

            Group {
                if profileSettings.voiceInputEnabled {
                    TVSearchTextField(
                        text: $viewModel.query,
                        placeholder: "Search movies and TV shows",
                        accentColor: theme.accent,
                        textColor: theme.textPrimary,
                        backgroundColor: theme.backgroundCard,
                        borderColor: theme.strokeDefault
                    )
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(theme.textSecondary)

                        TextField("Search movies and TV shows", text: $viewModel.query)
                            .textFieldStyle(.plain)
                            .font(typography.custom(size: 26, weight: .medium))
                            .foregroundStyle(theme.textPrimary)

                        if !viewModel.query.isEmpty {
                            Button {
                                viewModel.query = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(theme.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(theme.backgroundCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(theme.strokeDefault, lineWidth: 1)
                    )
                }
            }
            .frame(maxWidth: 820, minHeight: 62)
        }
    }

    @ViewBuilder
    private var idleView: some View {
        if !profileSettings.showSearchDiscoverContent {
            idlePrompt(
                title: "Search Your Library",
                subtitle: "Browse discovery rows from Settings if you want TMDB suggestions here."
            )
        } else if let discoveryErrorMessage = viewModel.discoveryErrorMessage {
            TVAnimatedErrorState(
                title: "Discovery feed unavailable",
                message: discoveryErrorMessage,
                accent: theme.warning
            ) {
                Button {
                    Task { await viewModel.retryCurrentState() }
                } label: {
                    retryButtonLabel("Retry discovery")
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, minHeight: 520)
        } else if profileSettings.includeTmdbInSearch {
            let defaultSectionID = resolvedDefaultSection(
                available: [
                    !viewModel.trendingItems.isEmpty ? "idle-trending" : nil,
                    !viewModel.popularItems.isEmpty ? "idle-popular" : nil
                ].compactMap { $0 },
                fallback: !viewModel.trendingItems.isEmpty ? "idle-trending" : (!viewModel.popularItems.isEmpty ? "idle-popular" : nil)
            )

            VStack(spacing: 26) {
                if !viewModel.trendingItems.isEmpty {
                    searchRow(
                        title: "Trending Now",
                        items: viewModel.trendingItems,
                        kind: .landscape,
                        sectionId: "idle-trending",
                        defaultFocus: defaultSectionID == "idle-trending"
                    )
                }

                if !viewModel.popularItems.isEmpty {
                    searchRow(
                        title: "Popular Right Now",
                        items: viewModel.popularItems,
                        kind: .landscape,
                        sectionId: "idle-popular",
                        defaultFocus: defaultSectionID == "idle-popular"
                    )
                }

                if viewModel.trendingItems.isEmpty && viewModel.popularItems.isEmpty {
                    loadingView
                }
            }
        } else {
            idlePrompt(
                title: "Search Your Library",
                subtitle: "Enable TMDB in Settings to get discovery feeds."
            )
        }
    }

    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.4)
                .tint(theme.accent)
            Text("Searching...")
                .font(typography.body)
                .foregroundStyle(theme.textPrimary)
        }
        .frame(maxWidth: .infinity, minHeight: 460)
    }

    @ViewBuilder
    private var resultsView: some View {
        let hasResults = !viewModel.plexResults.isEmpty || !viewModel.tmdbMovies.isEmpty || !viewModel.tmdbShows.isEmpty
        let availableSections = [
            !viewModel.plexResults.isEmpty ? "results-plex" : nil,
            !viewModel.tmdbMovies.isEmpty ? "results-movies" : nil,
            !viewModel.tmdbShows.isEmpty ? "results-shows" : nil
        ] + viewModel.genreRows.map { "genre-\($0.id)" }
        let defaultSectionID = resolvedDefaultSection(
            available: availableSections.compactMap { $0 },
            fallback: !viewModel.plexResults.isEmpty ? "results-plex" : (!viewModel.tmdbMovies.isEmpty ? "results-movies" : (!viewModel.tmdbShows.isEmpty ? "results-shows" : nil))
        )

        if let searchErrorMessage = viewModel.searchErrorMessage {
            TVAnimatedErrorState(
                title: "Search unavailable",
                message: searchErrorMessage,
                accent: theme.warning
            ) {
                Button {
                    Task { await viewModel.retryCurrentState() }
                } label: {
                    retryButtonLabel("Retry search")
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, minHeight: 520)
        } else if hasResults {
            VStack(spacing: 26) {
                if !viewModel.plexResults.isEmpty {
                    searchRow(
                        title: "Results from Your Plex",
                        items: viewModel.plexResults,
                        kind: .landscape,
                        sectionId: "results-plex",
                        defaultFocus: defaultSectionID == "results-plex"
                    )
                }

                if !viewModel.tmdbMovies.isEmpty {
                    searchRow(
                        title: viewModel.plexResults.isEmpty ? "Top Results" : "Movies",
                        items: viewModel.tmdbMovies,
                        kind: .poster,
                        sectionId: "results-movies",
                        defaultFocus: defaultSectionID == "results-movies"
                    )
                }

                if !viewModel.tmdbShows.isEmpty {
                    searchRow(
                        title: "TV Shows",
                        items: viewModel.tmdbShows,
                        kind: .poster,
                        sectionId: "results-shows",
                        defaultFocus: defaultSectionID == "results-shows"
                    )
                }

                ForEach(viewModel.genreRows) { row in
                    searchRow(
                        title: row.title,
                        items: row.items,
                        kind: .poster,
                        sectionId: "genre-\(row.id)",
                        defaultFocus: defaultSectionID == "genre-\(row.id)"
                    )
                }
            }
        } else {
            idlePrompt(
                title: "No results for \"\(viewModel.query)\"",
                subtitle: "Try a different title, genre, or actor."
            )
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
                onSelect: { selectedItem = $0 },
                screenID: .search
            )
        }
    }

    private func resolvedDefaultSection(available: [String], fallback: String?) -> String? {
        if let restoredSectionID, available.contains(restoredSectionID) {
            return restoredSectionID
        }
        if let remembered = focusCoordinator.lastFocusedSection(screen: .search), available.contains(remembered) {
            return remembered
        }
        return fallback
    }

    private func restoreFocusToRememberedSection() {
        clearRestoreTask?.cancel()
        restoredSectionID = focusCoordinator.lastFocusedSection(screen: .search)
        clearRestoreTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            restoredSectionID = nil
        }
    }

    private func idlePrompt(title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(theme.textTertiary)
            Text(title)
                .font(typography.title)
                .foregroundStyle(theme.textPrimary)
            Text(subtitle)
                .font(typography.body)
                .foregroundStyle(theme.textSecondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 620)
    }

    private func retryButtonLabel(_ title: String) -> some View {
        Text(title)
            .font(typography.custom(size: 24, weight: .semibold))
            .foregroundStyle(theme.background)
            .padding(.horizontal, 34)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.accent)
            )
    }
}
