//
//  MyListView.swift
//  FlixorMac
//
//  Watchlist / My List screen with sorting, filtering, and bulk removal.
//

import SwiftUI

struct MyListView: View {
    @EnvironmentObject private var watchlistController: WatchlistController
    @EnvironmentObject private var router: NavigationRouter
    @EnvironmentObject private var mainViewState: MainViewState
    @StateObject private var viewModel = MyListViewModel()

    private let horizontalPadding: CGFloat = 64
    private let gridSpacing: CGFloat = 18
    private let minGridItemWidth: CGFloat = 180

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 32)

            controls
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 24)

            content
                .padding(.top, 16)
        }
        .background(HomeBackground())
        .navigationTitle("")
        .task {
            viewModel.attach(watchlistController)
            await viewModel.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchlistDidChange)) { _ in
            Task { await viewModel.reload() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("My List")
                .font(.system(size: 34, weight: .bold))
            Text("\(viewModel.items.count) \(viewModel.items.count == 1 ? "title" : "titles")")
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                TextField("Search My List", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
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
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                if viewModel.bulkMode && !viewModel.selectedIDs.isEmpty {
                    Button(role: .destructive) {
                        Task { await viewModel.removeSelected() }
                    } label: {
                        Text("Remove (\(viewModel.selectedIDs.count))")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.red.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                        SkeletonView(height: minGridItemWidth * 1.5, cornerRadius: 12)
                            .frame(height: minGridItemWidth * 1.5)
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 32)
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
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(viewModel.selectedIDs.contains(item.id) ? Color.black : Color.white.opacity(0.6))
                                    )
                                    .padding(10)
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
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 32)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bookmark.slash")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Your list is empty")
                .font(.title2.weight(.semibold))
            Text("Add movies and TV shows to My List from the details screen.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(80)
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
                VStack(alignment: .leading, spacing: 8) {
                    ZStack(alignment: .topTrailing) {
                        CachedAsyncImage(url: item.imageURL)
                            .aspectRatio(2/3, contentMode: .fill)
                            .frame(width: width, height: width * 1.5)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(
                                        isSelected ? Color.white : Color.white.opacity(isHovered ? 0.9 : 0.15),
                                        lineWidth: isSelected ? 2 : (isHovered ? 2 : 1)
                                    )
                            )
                            .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                            .overlay(alignment: .topLeading) {
                                // Source badge overlay
                                SourceBadge(source: item.source)
                                    .padding(8)
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
                        .padding(10)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        HStack(spacing: 8) {
                            if let year = item.year {
                                Text(year)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            if let rating = item.ratingText {
                                Text(rating)
                                    .font(.system(size: 12, weight: .medium))
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
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.6))
                        )
                        .padding(10)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
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
        HStack(spacing: 4) {
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
            }
        }
    }

    private func badgeView(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.9), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
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
