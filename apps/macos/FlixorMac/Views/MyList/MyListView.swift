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
    @Environment(\.windowMetrics) private var metrics
    @EnvironmentObject private var watchlistController: WatchlistController
    @EnvironmentObject private var router: NavigationRouter
    @EnvironmentObject private var mainViewState: MainViewState
    @StateObject private var viewModel = MyListViewModel()
    @StateObject private var traktLists = TraktListsViewModel()

    @State private var listEditor: TraktListEditorMode?
    @State private var listPendingDelete: TraktUserList?

    private let horizontalPadding: CGFloat = 64
    private let gridSpacing: CGFloat = 18
    private var minGridItemWidth: CGFloat {
        metrics.posterWidth(designWidth: 180, storedSize: profileSettings.posterSize)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, horizontalPadding)
                .padding(.top, DS.Space.s32)

            if traktLists.isConnected {
                TraktListSwitcher(
                    model: traktLists,
                    myListCount: viewModel.items.count,
                    horizontalInset: horizontalPadding,
                    onCreate: { listEditor = .create },
                    onEdit: { listEditor = .edit($0) },
                    onDelete: { listPendingDelete = $0 }
                )
                .padding(.top, DS.Space.s16)
            }

            if let list = traktLists.selectedList {
                TraktListContentView(model: traktLists, list: list)
                    .id(list.id)
            } else {
                controls
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, DS.Space.s24)

                content
                    .padding(.top, DS.Space.s16)
            }
        }
        .background(HomeBackground())
        .navigationTitle("")
        .task {
            viewModel.attach(watchlistController)
            traktLists.refreshConnection()
            await viewModel.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchlistDidChange)) { _ in
            Task { await viewModel.reload() }
        }
        .onChange(of: mainViewState.selectedTab) { _ in
            traktLists.refreshConnection()
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

    private var header: some View {
        HStack(alignment: .top, spacing: DS.Space.s16) {
            VStack(alignment: .leading, spacing: DS.Space.s8) {
                Text(traktLists.selectedList?.name ?? String(localized: "My List"))
                    .font(.system(size: 34, weight: .bold))
                    .lineLimit(1)
                Text(headerSubtitle)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let list = traktLists.selectedList {
                Menu {
                    TraktListActions(
                        list: list,
                        onEdit: { listEditor = .edit($0) },
                        onDelete: { listPendingDelete = $0 }
                    )
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.flixorIcon(DS.Icon.lg))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(traktLists.isMutating)
                .accessibilityLabel("List options")
            }
        }
    }

    private var headerSubtitle: String {
        traktLists.selectedListSummary
            ?? String(localized: "\(viewModel.items.count) titles")
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            HStack(spacing: DS.Space.s16) {
                TextField("Search My List", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, DS.Space.s14)
                    .padding(.vertical, DS.Space.s10)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.Radius.r10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.r10, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .frame(width: 260)

                Picker("Type", selection: $viewModel.filter) {
                    ForEach(MyListViewModel.FilterType.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)

                Spacer()

                Picker("Sort", selection: $viewModel.sort) {
                    ForEach(MyListViewModel.SortOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)

                Button {
                    viewModel.bulkMode.toggle()
                    if !viewModel.bulkMode {
                        viewModel.clearSelection()
                    }
                } label: {
                    Text(viewModel.bulkMode ? "Cancel" : "Select")
                        .font(.flixor(.callout, weight: .semibold))
                        .padding(.horizontal, DS.Space.s16)
                        .padding(.vertical, DS.Space.s10)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: DS.Radius.r10, style: .continuous))
                }
                .buttonStyle(.plain)

                if viewModel.bulkMode && !viewModel.selectedIDs.isEmpty {
                    Button(role: .destructive) {
                        Task { await viewModel.removeSelected() }
                    } label: {
                        Text("Remove (\(viewModel.selectedIDs.count))")
                            .font(.flixor(.callout, weight: .semibold))
                            .padding(.horizontal, DS.Space.s16)
                            .padding(.vertical, DS.Space.s10)
                            .background(Color.red.opacity(0.7), in: RoundedRectangle(cornerRadius: DS.Radius.r10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            if let error = viewModel.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Retry") {
                        Task { await viewModel.reload() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.visibleItems.isEmpty {
            skeletonGrid
        } else if viewModel.visibleItems.isEmpty {
            emptyState
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
                .padding(.vertical, DS.Space.s32)
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
                        ZStack(alignment: .topTrailing) {
                            PosterCard(
                                item: item.canonicalMediaItem,
                                width: cardWidth,
                                badge: AnyView(SourceBadge(source: item.source)),
                                topTrailingOverlay: AnyView(
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
                                ),
                                isSelected: viewModel.selectedIDs.contains(item.id),
                                customImageURL: item.imageURL,
                                onTap: {
                                    if viewModel.bulkMode {
                                        viewModel.toggleSelection(for: item)
                                    } else {
                                        router.myListPath.append(DetailsNavigationItem(item: item.canonicalMediaItem))
                                    }
                                }
                            )

                            // Selection checkbox overlay for bulk mode
                            if viewModel.bulkMode {
                                Circle()
                                    .strokeBorder(Color.white, lineWidth: 2)
                                    .frame(width: 26, height: 26)
                                    .background(
                                        Circle()
                                            .fill(viewModel.selectedIDs.contains(item.id) ? Color.white : Color.clear)
                                    )
                                    .overlay(
                                        Image(systemName: "checkmark")
                                            .font(.flixorIcon(DS.Icon.sm, weight: .bold))
                                            .foregroundStyle(viewModel.selectedIDs.contains(item.id) ? Color.black : Color.white.opacity(0.6))
                                    )
                                    .padding(DS.Space.s10)
                            }
                        }
                        .contextMenu {
                            Button("View Details") {
                                router.myListPath.append(DetailsNavigationItem(item: item.canonicalMediaItem))
                            }
                            if item.source == .plex || item.source == .both {
                                Button("Play") {
                                    router.myListPath.append(DetailsNavigationItem(item: item.canonicalMediaItem))
                                }
                            }
                            Button("Remove from My List", role: .destructive) {
                                Task { await viewModel.remove(item: item) }
                            }
                        }
                    }
                }
                .background(TabScrollObserver(tab: .myList))
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, DS.Space.s32)
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
