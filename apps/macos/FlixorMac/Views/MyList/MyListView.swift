//
//  MyListView.swift
//  FlixorMac
//
//  Watchlist / My List screen with sorting, filtering, and bulk removal.
//

import SwiftUI
import FlixorKit

struct MyListView: View {
    @ObservedObject private var profileSettings = ProfileSettings.shared
    @ObservedObject private var librarySettings = LibraryScreenSettings.shared
    @Environment(\.windowMetrics) private var metrics
    @Environment(\.flixorTheme) private var theme
    @EnvironmentObject private var watchlistController: WatchlistController
    @EnvironmentObject private var router: NavigationRouter
    @EnvironmentObject private var mainViewState: MainViewState
    @StateObject private var viewModel = MyListViewModel()
    @StateObject private var traktLists = TraktListsViewModel()

    @State private var listEditor: TraktListEditorMode?
    @State private var listPendingDelete: TraktUserList?
    @State private var searchOpen = false

    private let horizontalPadding: CGFloat = 64
    /// Same grid as the Library (Settings > Library: poster size, spacing, titles).
    private var gridSpacing: CGFloat { librarySettings.density.spacing }
    private var minGridItemWidth: CGFloat {
        let size = librarySettings.posterSize.resolved(homeSize: profileSettings.posterSize)
        return metrics.posterWidth(designWidth: 180, storedSize: size.rawValue)
    }

    var body: some View {
        Group {
            if let list = traktLists.selectedList {
                TraktListContentView(model: traktLists, list: list)
                    .id(list.id)
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // A frosted inset like the Library header: the grid scrolls under it.
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .background(HomeBackground())
        .navigationTitle("")
        .task {
            viewModel.attach(watchlistController)
            traktLists.refreshConnection()
            await viewModel.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchlistDidChange)) { _ in
            Task { await viewModel.handleWatchlistDidChange() }
        }
        .onChange(of: mainViewState.selectedTab) { _ in
            traktLists.refreshConnection()
        }
        .onChange(of: traktLists.selectedListId) { _ in
            searchOpen = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            traktLists.refreshConnection()
        }
        .sheet(item: $listEditor) { mode in
            listEditorSheet(mode)
        }
        .alert(
            "Delete List",
            isPresented: Binding(
                get: { listPendingDelete != nil },
                set: { if !$0 { listPendingDelete = nil } }
            ),
            presenting: listPendingDelete
        ) { list in
            Button("Delete", role: .destructive) {
                Task { await traktLists.deleteList(list) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { list in
            Text("Delete \"\(list.name)\" from your Trakt account? This can't be undone.")
        }
    }

    private func listEditorSheet(_ mode: TraktListEditorMode) -> some View {
        TraktListEditorSheet(mode: mode) { name, description, privacy in
            switch mode {
            case .create:
                return await traktLists.createList(name: name, description: description, privacy: privacy)
            case .edit(let list):
                return await traktLists.updateList(list, name: name, description: description, privacy: privacy)
            }
        }
    }

    // MARK: - Header (Library style)

    private var isTraktList: Bool { traktLists.selectedList != nil }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.s12) {
            HStack(alignment: .center, spacing: DS.Space.s10) {
                tabs
                Spacer(minLength: DS.Space.s16)
                if isTraktList {
                    BrowseSearchField(text: $traktLists.searchQuery,
                                      placeholder: String(localized: "Search this list"),
                                      isOpen: $searchOpen)
                    sortMenu(selection: $traktLists.sort)
                    selectControls(bulk: $traktLists.bulkMode, count: traktLists.selectedIDs.count,
                                   isMutating: traktLists.isMutating,
                                   onClear: { traktLists.clearSelection() },
                                   onRemove: { Task { await traktLists.removeSelected() } })
                    if let list = traktLists.selectedList { listMenu(list) }
                } else {
                    BrowseSearchField(text: $viewModel.searchQuery,
                                      placeholder: String(localized: "Search My List"),
                                      isOpen: $searchOpen)
                    sortMenu(selection: $viewModel.sort)
                    selectControls(bulk: $viewModel.bulkMode, count: viewModel.selectedIDs.count,
                                   isMutating: false,
                                   onClear: { viewModel.clearSelection() },
                                   onRemove: { Task { await viewModel.removeSelected() } })
                }
            }
            .frame(minHeight: 36)

            chips

            if let error = isTraktList ? (traktLists.items.isEmpty ? nil : traktLists.itemsError) : viewModel.errorMessage {
                HStack(spacing: DS.Space.s8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(theme.warning)
                    Text(error).flixorFont(.callout).foregroundStyle(theme.warning).lineLimit(2)
                    Spacer()
                    BrowsePillButton(title: String(localized: "Retry")) {
                        if isTraktList { traktLists.retry() } else { Task { await viewModel.reload() } }
                    }
                }
            }
        }
        .browseHeaderInset()
        .animation(DS.Motion.standard, value: searchOpen)
    }

    /// My List and each Trakt list as title tabs, like the Library's sections,
    /// with ＋ right after them. Scrolls sideways only when there are too many.
    private var tabs: some View {
        ViewThatFits(in: .horizontal) {
            tabsRow.fixedSize()
            ScrollView(.horizontal, showsIndicators: false) { tabsRow }
        }
    }

    private var tabsRow: some View {
        HStack(alignment: .center, spacing: DS.Space.s20) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s20) {
                tab(title: String(localized: "My List"), count: viewModel.items.count, selected: !isTraktList) {
                    withAnimation(DS.Motion.quick) { traktLists.select(nil) }
                }
                if traktLists.isConnected {
                    ForEach(traktLists.lists) { list in
                        tab(title: shortName(list.name), count: traktLists.count(for: list),
                            selected: traktLists.selectedListId == list.id) {
                            withAnimation(DS.Motion.quick) { traktLists.select(list.id) }
                        }
                        .help(list.name)
                        .contextMenu {
                            TraktListActions(list: list, onEdit: { listEditor = .edit($0) }, onDelete: { listPendingDelete = $0 })
                        }
                    }
                }
            }
            if traktLists.isConnected {
                if traktLists.isLoadingLists {
                    ProgressView().controlSize(.small)
                } else if traktLists.listsError != nil {
                    Button { traktLists.loadLists() } label: {
                        Label("Lists didn't load. Retry", systemImage: "exclamationmark.triangle.fill")
                            .flixorFont(.callout, weight: .medium)
                            .foregroundStyle(theme.warning)
                    }
                    .buttonStyle(.plain)
                }
                BrowseCircleButton(systemImage: "plus", help: String(localized: "New Trakt list")) {
                    listEditor = .create
                }
                .disabled(traktLists.isMutating)
            }
        }
        .padding(.vertical, DS.Space.s2)
    }

    private func tab(title: String, count: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s8) {
            LibraryTitleTab(title: title, selected: selected, action: action)
            if selected {
                BrowseTabCount(text: "\(count)")
            }
        }
    }

    private func shortName(_ name: String) -> String {
        name.count > 28 ? String(name.prefix(28)) + "…" : name
    }

    private func sortMenu(selection: Binding<MyListViewModel.SortOption>) -> some View {
        LibraryPillMenu(label: nil, value: selection.wrappedValue.title, systemImage: "arrow.up.arrow.down", isActive: false) {
            ForEach(MyListViewModel.SortOption.allCases) { option in
                Button {
                    selection.wrappedValue = option
                } label: {
                    if selection.wrappedValue == option { Label(option.title, systemImage: "checkmark") } else { Text(option.title) }
                }
            }
        }
    }

    @ViewBuilder
    private func selectControls(bulk: Binding<Bool>, count: Int, isMutating: Bool,
                                onClear: @escaping () -> Void, onRemove: @escaping () -> Void) -> some View {
        if bulk.wrappedValue && count > 0 {
            BrowsePillButton(title: String(localized: "Remove \(count)"), systemImage: "minus.circle", destructive: true, action: onRemove)
                .disabled(isMutating)
        }
        BrowsePillButton(title: bulk.wrappedValue ? String(localized: "Done") : String(localized: "Select")) {
            bulk.wrappedValue.toggle()
            if !bulk.wrappedValue { onClear() }
        }
    }

    private func listMenu(_ list: TraktUserList) -> some View {
        Menu {
            TraktListActions(list: list, onEdit: { listEditor = .edit($0) }, onDelete: { listPendingDelete = $0 })
        } label: {
            Image(systemName: "ellipsis")
                .font(.flixorIcon(DS.Icon.sm, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(theme.hoverFill))
                .overlay(Circle().strokeBorder(theme.separator, lineWidth: DS.Border.thin))
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(traktLists.isMutating)
        .help("List options")
    }

    // MARK: Chips

    @ViewBuilder
    private var chips: some View {
        HStack(spacing: DS.Space.s8) {
            if isTraktList {
                typeChips(filter: $traktLists.filter, all: traktLists.items.count,
                          movies: traktLists.movieCount, shows: traktLists.showCount)
                BrowseCountChip(title: String(localized: "Added this month"), selected: traktLists.recentOnly) {
                    traktLists.recentOnly.toggle()
                }
            } else {
                typeChips(filter: $viewModel.filter, all: viewModel.items.count,
                          movies: viewModel.movieCount, shows: viewModel.showCount)
                if viewModel.items.contains(where: { $0.source == .plex || $0.source == .both }) {
                    BrowseCountChip(title: String(localized: "In your library"), selected: viewModel.inLibraryOnly) {
                        viewModel.inLibraryOnly.toggle()
                    }
                }
                BrowseCountChip(title: String(localized: "Added this month"), selected: viewModel.recentOnly) {
                    viewModel.recentOnly.toggle()
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func typeChips(filter: Binding<MyListViewModel.FilterType>, all: Int, movies: Int, shows: Int) -> some View {
        BrowseCountChip(title: String(localized: "All"), selected: filter.wrappedValue == .all) { filter.wrappedValue = .all }
        if movies > 0 {
            BrowseCountChip(title: String(localized: "Movies"), count: movies, selected: filter.wrappedValue == .movies) {
                filter.wrappedValue = filter.wrappedValue == .movies ? .all : .movies
            }
        }
        if shows > 0 {
            BrowseCountChip(title: String(localized: "TV Shows"), count: shows, selected: filter.wrappedValue == .shows) {
                filter.wrappedValue = filter.wrappedValue == .shows ? .all : .shows
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.visibleItems.isEmpty {
            skeletonGrid
        } else if viewModel.items.isEmpty {
            emptyState
        } else if viewModel.visibleItems.isEmpty {
            BrowseMessageView(
                systemImage: "magnifyingglass",
                title: "No matching titles",
                message: "Try a different search or chip."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            gridContent
        }
    }

    private var skeletonGrid: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVGrid(columns: gridColumns(width: geometry.size.width), spacing: gridSpacing) {
                    ForEach(0..<12, id: \.self) { _ in
                        SkeletonView(height: minGridItemWidth * 1.5, cornerRadius: DS.Radius.r12)
                            .frame(height: minGridItemWidth * 1.5)
                    }
                }
                .background(TabScrollObserver(tab: .myList))
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, DS.Space.s24)
            }
        }
    }

    private func gridColumns(width: CGFloat) -> [GridItem] {
        let available = max(320, width - horizontalPadding * 2)
        let columns = max(2, Int((available + gridSpacing) / (minGridItemWidth + gridSpacing)))
        return Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: columns)
    }

    private var gridContent: some View {
        GeometryReader { geometry in
            let availableWidth = max(320, geometry.size.width - horizontalPadding * 2)
            let columnsCount = max(2, Int((availableWidth + gridSpacing) / (minGridItemWidth + gridSpacing)))
            let cardWidth = (availableWidth - CGFloat(columnsCount - 1) * gridSpacing) / CGFloat(columnsCount)
            let columns = Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: columnsCount)

            ScrollView {
                LazyVGrid(columns: columns, spacing: gridSpacing) {
                    ForEach(viewModel.visibleItems) { item in
                        MyListPosterCell(
                            item: item,
                            width: cardWidth,
                            showTitle: librarySettings.titleDisplay != .none,
                            showYear: librarySettings.titleDisplay == .titleAndYear,
                            bulkMode: viewModel.bulkMode,
                            isSelected: viewModel.selectedIDs.contains(item.id),
                            onOpen: { router.myListPath.append(DetailsNavigationItem(item: item.canonicalMediaItem)) },
                            onToggleSelection: { viewModel.toggleSelection(for: item) },
                            onRemove: { Task { await viewModel.remove(item: item) } }
                        )
                    }
                }
                .background(TabScrollObserver(tab: .myList))
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, DS.Space.s24)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DS.Space.s12) {
            Image(systemName: "bookmark.slash")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Your list is empty")
                .font(.title2.weight(.semibold))
            Text("Add movies and TV shows to My List from the details screen.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DS.Space.s80)
    }
}

/// A poster with nothing on it until you hover: then where it comes from
/// (Plex, Trakt, this Mac) and a − to remove it. In Select mode, a check.
private struct MyListPosterCell: View {
    let item: MyListViewModel.WatchlistItem
    let width: CGFloat
    let showTitle: Bool
    let showYear: Bool
    let bulkMode: Bool
    let isSelected: Bool
    let onOpen: () -> Void
    let onToggleSelection: () -> Void
    let onRemove: () -> Void

    @State private var hovering = false
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PosterCard(
                item: item.canonicalMediaItem,
                width: width,
                showTitle: showTitle,
                showYear: showYear,
                badge: hovering && !bulkMode ? AnyView(MyListSourceLabel(source: item.source)) : nil,
                topTrailingOverlay: hovering && !bulkMode ? AnyView(removeButton) : nil,
                isSelected: isSelected,
                customImageURL: item.imageURL,
                extraMenuActions: [
                    CardMenuAction(title: String(localized: "Remove from My List"), role: .destructive, isDisabled: false, action: onRemove)
                ],
                onTap: { bulkMode ? onToggleSelection() : onOpen() }
            )

            if bulkMode {
                Circle()
                    .strokeBorder(Color.white, lineWidth: 2)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(isSelected ? Color.white : Color.black.opacity(0.3)))
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.flixorIcon(DS.Icon.sm, weight: .bold))
                            .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.6))
                    )
                    .padding(DS.Space.s10)
                    .allowsHitTesting(false)
            }
        }
        .onHover { hovering = $0 }
        .animation(DS.Motion.quick, value: hovering)
    }

    private var removeButton: some View {
        Button(action: onRemove) {
            Image(systemName: "minus")
                .font(.flixorIcon(DS.Icon.xs, weight: .bold))
                .foregroundStyle(theme.textPrimary)
                .frame(width: 28, height: 28)
                .background(theme.scrim(), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Remove from My List")
        .accessibilityLabel("Remove \(item.title) from My List")
    }
}

/// "Plex", "Trakt", "Plex · Trakt" or "This Mac", shown on hover.
private struct MyListSourceLabel: View {
    let source: MyListViewModel.Source
    @Environment(\.flixorTheme) private var theme

    private var text: String {
        switch source {
        case .plex: return "Plex"
        case .trakt: return "Trakt"
        case .both: return "Plex · Trakt"
        case .local: return String(localized: "This Mac")
        }
    }

    var body: some View {
        Text(text)
            .flixorFont(.nano, weight: .bold)
            .foregroundStyle(theme.textPrimary)
            .padding(.horizontal, DS.Space.s6)
            .padding(.vertical, 3)
            .background(theme.scrim(DS.Opacity.scrimHeavy), in: RoundedRectangle(cornerRadius: DS.Radius.badge, style: .continuous))
    }
}

private struct WatchlistCard: View {
    let item: MyListViewModel.WatchlistItem
    let width: CGFloat
    let isSelected: Bool
    let bulkMode: Bool
    @ObservedObject var watchlistController: WatchlistController
    var onToggleSelection: () -> Void
    var onRemove: () -> Void
    var onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: {
            if bulkMode {
                onToggleSelection()
            } else {
                onOpen()
            }
        }) {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: DS.Space.s8) {
                    ZStack(alignment: .topTrailing) {
                        CachedAsyncImage(url: item.imageURL)
                            .aspectRatio(2/3, contentMode: .fill)
                            .frame(width: width, height: width * 1.5)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.r12, style: .continuous)
                                    .stroke(
                                        isSelected ? Color.white : Color.white.opacity(isHovered ? 0.9 : 0.15),
                                        lineWidth: isSelected ? 2 : (isHovered ? 2 : 1)
                                    )
                            )
                            .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                            .overlay(alignment: .topLeading) {
                                // Source badge overlay
                                SourceBadge(source: item.source)
                                    .padding(DS.Space.s8)
                            }

                        WatchlistButton(
                            canonicalId: item.id,
                            mediaType: item.mediaType,
                            plexRatingKey: item.plexRatingKey,
                            plexGuid: item.plexGuid,
                            tmdbId: item.tmdbId,
                            imdbId: item.imdbId,
                            title: item.title,
                            year: Int(item.year ?? ""),
                            style: .icon
                        )
                        .padding(DS.Space.s10)
                    }

                    VStack(alignment: .leading, spacing: DS.Space.s4) {
                        Text(item.title)
                            .font(.flixor(.body, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        HStack(spacing: DS.Space.s8) {
                            if let year = item.year {
                                Text(year)
                                    .font(.flixor(.footnote, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            if let rating = item.ratingText {
                                Text(rating)
                                    .font(.flixor(.footnote, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                    }
                    .frame(width: width, alignment: .leading)
                }

                if bulkMode {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 2)
                        .frame(width: 26, height: 26)
                        .background(
                            Circle()
                                .fill(isSelected ? Color.white : Color.clear)
                        )
                        .overlay(
                            Image(systemName: "checkmark")
                                .font(.flixorIcon(DS.Icon.sm, weight: .bold))
                                .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.6))
                        )
                        .padding(DS.Space.s10)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DS.Motion.quick) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button("View Details") {
                onOpen()
            }
            if item.source == .plex || item.source == .both {
                Button("Play") {
                    onOpen()
                }
            }
            Button("Remove from My List", role: .destructive) {
                onRemove()
            }
        }
    }
}

private struct SourceBadge: View {
    let source: MyListViewModel.Source

    var body: some View {
        HStack(spacing: DS.Space.s4) {
            switch source {
            case .plex:
                badgeView(text: "PLEX", color: .orange)
            case .trakt:
                badgeView(text: "TRAKT", color: .red)
            case .both:
                HStack(spacing: 3) {
                    badgeView(text: "PLEX", color: .orange)
                    badgeView(text: "TRAKT", color: .red)
                }
            case .local:
                badgeView(text: String(localized: "THIS MAC"), color: .gray)
            }
        }
    }

    private func badgeView(text: String, color: Color) -> some View {
        Text(text)
            .font(.flixor(.nano, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, DS.Space.s6)
            .padding(.vertical, 3)
            .background(color.opacity(0.9), in: RoundedRectangle(cornerRadius: DS.Radius.r4, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    }
}

#if DEBUG && canImport(PreviewsMacros)
#Preview {
    NavigationStack {
        MyListView()
            .environmentObject(WatchlistController())
    }
}
#endif
