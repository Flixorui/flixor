//
//  BrowsePageView.swift
//  FlixorMac
//
//  A row's "Browse" page, in the Library style: the row name as the title with
//  a count, the source as a quiet caption, Sort and grid/list on the right,
//  Movies / TV Shows chips when the row mixes both, and the Library poster grid
//  (Settings > Library). More load as you scroll. Pushed like a details page.
//

import SwiftUI

struct BrowsePageView: View {
    let route: BrowseRoute

    @StateObject private var viewModel = BrowseModalViewModel()
    @EnvironmentObject private var router: NavigationRouter
    @EnvironmentObject private var mainViewState: MainViewState
    @ObservedObject private var profileSettings = ProfileSettings.shared
    @ObservedObject private var librarySettings = LibraryScreenSettings.shared
    @Environment(\.windowMetrics) private var metrics
    @Environment(\.flixorTheme) private var theme

    @State private var sort: BrowseSort = .source
    @State private var typeFilter: TypeFilter = .all
    @State private var viewMode: LibraryViewModel.ViewMode = .grid
    @State private var contentWidth: CGFloat = 1200

    private let horizontalPadding: CGFloat = 64
    private var gridSpacing: CGFloat { librarySettings.density.spacing }
    private var minGridItemWidth: CGFloat {
        let size = librarySettings.posterSize.resolved(homeSize: profileSettings.posterSize)
        return metrics.posterWidth(designWidth: 180, storedSize: size.rawValue)
    }

    enum TypeFilter { case all, movies, shows }

    /// "Source order" keeps what the row was sorted by (popularity, trending...).
    enum BrowseSort: CaseIterable, Identifiable {
        case source, newest, oldest, rating, title
        var id: Self { self }
        var label: String {
            switch self {
            case .source: return String(localized: "Default order")
            case .newest: return String(localized: "Newest")
            case .oldest: return String(localized: "Oldest")
            case .rating: return String(localized: "Rating")
            case .title: return String(localized: "Title")
            }
        }
    }

    // MARK: Items

    private func isShow(_ item: MediaItem) -> Bool { item.type == "show" || item.type == "tv" || item.type == "episode" }
    private var movieCount: Int { uniqueItems.filter { !isShow($0) }.count }
    private var showCount: Int { uniqueItems.filter { isShow($0) }.count }
    private var mixesTypes: Bool { movieCount > 0 && showCount > 0 }

    /// Sources sometimes repeat a title on a later page; a repeated id leaves an
    /// empty cell in a lazy grid, so keep the first of each.
    private var uniqueItems: [MediaItem] {
        var seen = Set<String>()
        return viewModel.items.filter { seen.insert($0.id).inserted }
    }

    private var visibleItems: [MediaItem] {
        var items = uniqueItems
        switch typeFilter {
        case .all: break
        case .movies: items = items.filter { !isShow($0) }
        case .shows: items = items.filter { isShow($0) }
        }
        switch sort {
        case .source: break
        case .newest: items.sort { ($0.year ?? 0) > ($1.year ?? 0) }
        case .oldest: items.sort { ($0.year ?? Int.max) < ($1.year ?? Int.max) }
        case .rating: items.sort { ($0.rating ?? -1) > ($1.rating ?? -1) }
        case .title: items.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
        return items
    }

    private var pageTitle: String {
        if let title = route.title, !title.isEmpty { return title }
        return viewModel.title.isEmpty ? String(localized: "Browse") : viewModel.title
    }

    /// "From TMDB", or the addon's / list's name.
    private var sourceCaption: String? {
        guard let subtitle = viewModel.subtitle, !subtitle.isEmpty else { return nil }
        // A row named by the app ("Popular on Plex") already says what it is;
        // only addon and list names add something.
        if route.title != nil, ["TMDB", "Trakt", "Plex.tv"].contains(subtitle) { return nil }
        switch subtitle {
        case "TMDB", "Trakt", "Plex.tv": return String(localized: "From \(subtitle)")
        default: return subtitle
        }
    }

    // MARK: Body

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .background(HomeBackground())
            .navigationTitle("")
            .task { await viewModel.load(context: route.context) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.s12) {
            HStack(alignment: .center, spacing: DS.Space.s10) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s10) {
                    LibraryTitleTab(title: pageTitle, selected: true) {}
                        .allowsHitTesting(false)
                    if viewModel.state == .loaded {
                        BrowseTabCount(text: countText)
                    }
                    if let sourceCaption {
                        Text(sourceCaption)
                            .flixorFont(.callout)
                            .foregroundStyle(theme.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: DS.Space.s16)
                LibraryPillMenu(label: nil, value: sort.label, systemImage: "arrow.up.arrow.down", isActive: sort != .source) {
                    ForEach(BrowseSort.allCases) { option in
                        Button { sort = option } label: {
                            if sort == option { Label(option.label, systemImage: "checkmark") } else { Text(option.label) }
                        }
                    }
                }
                FlixorSegmentedControl(
                    items: [
                        .init(value: LibraryViewModel.ViewMode.grid, systemImage: "square.grid.2x2", help: String(localized: "Grid")),
                        .init(value: LibraryViewModel.ViewMode.list, systemImage: "list.bullet", help: String(localized: "List")),
                    ],
                    selection: $viewMode
                )
            }
            .frame(minHeight: 36)
            // Leaves room for the floating back arrow.
            .padding(.leading, FloatingBackButton.size + DS.Space.s12 - DS.Space.s20)

            if mixesTypes {
                HStack(spacing: DS.Space.s8) {
                    BrowseCountChip(title: String(localized: "All"), selected: typeFilter == .all) { typeFilter = .all }
                    BrowseCountChip(title: String(localized: "Movies"), count: movieCount, selected: typeFilter == .movies) {
                        typeFilter = typeFilter == .movies ? .all : .movies
                    }
                    BrowseCountChip(title: String(localized: "TV Shows"), count: showCount, selected: typeFilter == .shows) {
                        typeFilter = typeFilter == .shows ? .all : .shows
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, FloatingBackButton.size + DS.Space.s12 - DS.Space.s20)
            }
        }
        .padding(.top, FloatingBackButton.topPadding - DS.Space.s8 - 4)
        .browseHeaderInset()
    }

    private var countText: String {
        let count = visibleItems.count
        return viewModel.canLoadMore ? "\(count)+" : "\(count)"
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            skeleton
        case .error(let message):
            BrowseMessageView(
                systemImage: "exclamationmark.triangle",
                title: "Couldn't load this row",
                message: .verbatim(message),
                retryTitle: "Try Again",
                onRetry: { Task { await viewModel.reload() } }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            BrowseMessageView(systemImage: "film", title: "Nothing here yet", message: "This row has no more titles.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            if viewMode == .grid { grid } else { list }
        }
    }

    private var columns: (items: [GridItem], cardWidth: CGFloat) {
        let available = max(320, contentWidth - horizontalPadding * 2)
        let count = max(2, Int((available + gridSpacing) / (minGridItemWidth + gridSpacing)))
        let width = (available - CGFloat(count - 1) * gridSpacing) / CGFloat(count)
        return (Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: count), width)
    }

    private var skeleton: some View {
        let layout = columns
        return ScrollView {
            LazyVGrid(columns: layout.items, spacing: gridSpacing) {
                ForEach(0..<18, id: \.self) { _ in SkeletonPosterCard(width: layout.cardWidth) }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, DS.Space.s24)
        }
        .background(widthReader)
    }

    private var grid: some View {
        let layout = columns
        let items = visibleItems
        return ScrollView {
            LazyVGrid(columns: layout.items, spacing: gridSpacing) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    // The row card: it looks up a poster for items that arrive
                    // without one, exactly as on Home.
                    PosterSectionCard(item: item, width: layout.cardWidth) { open(item) }
                    .onAppear { prefetch(index, of: items.count) }
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, DS.Space.s24)
            loadingMore
        }
        .background(widthReader)
    }

    private var list: some View {
        let items = visibleItems
        return ScrollView {
            LazyVStack(spacing: DS.Space.s12) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    BrowseListRow(item: item) { open(item) }
                        .onAppear { prefetch(index, of: items.count) }
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, DS.Space.s24)
            loadingMore
        }
        .background(widthReader)
    }

    @ViewBuilder
    private var loadingMore: some View {
        if viewModel.isLoadingMore {
            ProgressView().controlSize(.small).padding(.vertical, DS.Space.s24)
        } else {
            Color.clear.frame(height: DS.Space.s40)
        }
    }

    private var widthReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { contentWidth = proxy.size.width }
                .onChange(of: proxy.size.width) { contentWidth = $0 }
        }
    }

    /// Loads the next page near the end of what is shown (the filters work on
    /// loaded titles, so a filtered view also keeps pulling pages).
    private func prefetch(_ index: Int, of count: Int) {
        guard viewModel.canLoadMore, !viewModel.isLoadingMore, index >= count - 6 else { return }
        Task { await viewModel.loadMore() }
    }

    private func open(_ item: MediaItem) {
        router.push(DetailsNavigationItem(item: item), on: mainViewState.selectedTab)
    }
}

/// Poster, title, year and type, and the overview: the Library list look.
private struct BrowseListRow: View {
    let item: MediaItem
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: DS.Space.s16) {
                CachedAsyncImage(url: ImageService.shared.thumbURL(for: item, width: 160, height: 240))
                    .aspectRatio(2 / 3, contentMode: .fill)
                    .frame(width: 64, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r8, style: .continuous))
                VStack(alignment: .leading, spacing: DS.Space.s4) {
                    Text(item.title).flixorFont(.headline, weight: .semibold).lineLimit(1)
                    Text(meta).flixorFont(.callout).foregroundStyle(theme.textTertiary)
                    if let summary = item.summary, !summary.isEmpty {
                        Text(summary).flixorFont(.callout).foregroundStyle(theme.textSecondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(DS.Space.s10)
            .background(RoundedRectangle(cornerRadius: DS.Radius.r12, style: .continuous).fill(Color.white.opacity(hovering ? 0.07 : 0.03)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var meta: String {
        let type = (item.type == "show" || item.type == "tv") ? String(localized: "TV Show") : String(localized: "Movie")
        return [item.year.map(String.init), type, item.rating.map { String(format: "★ %.1f", $0) }]
            .compactMap { $0 }.joined(separator: " · ")
    }
}
