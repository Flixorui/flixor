//
//  LibraryView.swift
//  FlixorMac
//
//  Library / Browse experience with filtering, sorting, and collections support.
//

import SwiftUI

struct LibraryView: View {
    @ObservedObject private var profileSettings = ProfileSettings.shared
    @Environment(\.windowMetrics) private var metrics
    @StateObject private var viewModel = LibraryViewModel()
    @EnvironmentObject private var router: NavigationRouter
    @EnvironmentObject private var mainViewState: MainViewState
    @ObservedObject private var appMode = AppModeStore.shared
    /// Width of the scroll area, measured in the background so the scroll view
    /// itself can extend under the frosted header.
    @State private var contentWidth: CGFloat = 1200

    @ObservedObject private var librarySettings = LibraryScreenSettings.shared

    private let horizontalPadding: CGFloat = 64
    private var gridSpacing: CGFloat { librarySettings.density.spacing }
    /// Settings > Library Screen > Poster Size ("Same as Home" follows the Home card size).
    private var minGridItemWidth: CGFloat {
        let size = librarySettings.posterSize.resolved(homeSize: profileSettings.posterSize)
        return metrics.posterWidth(designWidth: 180, storedSize: size.rawValue)
    }

    var body: some View {
        if appMode.isStremioOnly {
            // No Plex libraries to browse: the page is the user's collections.
            UserCollectionsPage()
        } else {
            plexLibrary
        }
    }

    private var plexLibrary: some View {
        // The header is a frosted inset: the grid starts below it and scrolls
        // under it instead of being clipped at a hard edge.
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                LibraryFilterBarView(viewModel: viewModel) { section in
                    viewModel.selectSection(section)
                }
            }
        .background(HomeBackground())
        .navigationTitle("")
        .task {
            await viewModel.loadIfNeeded()
        }
    }

    @ViewBuilder
    private var content: some View {
        // My Collections need no Plex, so a Plex error only fills the Plex section there.
        if viewModel.contentTab == .physical {
            // Covers sized like the Library's own poster grid.
            PhysicalCollectionView(horizontalPadding: horizontalPadding, minItemWidth: minGridItemWidth, spacing: gridSpacing)
        } else if viewModel.contentTab == .collections {
            CollectionsView(
                collections: viewModel.collections,
                isLoading: viewModel.isLoadingCollections,
                plexError: viewModel.errorMessage,
                onRetryPlex: { Task { await viewModel.retry() } },
                onSelect: { _ in }
            )
        } else if let error = viewModel.errorMessage {
            errorState(message: error)
        } else {
            libraryContent
        }
    }

    @ViewBuilder
    private var libraryContent: some View {
        if viewModel.isLoading && viewModel.visibleItems.isEmpty {
            skeletonGrid
        } else if viewModel.visibleItems.isEmpty {
            emptyState
        } else if viewModel.viewMode == .grid {
            gridView
        } else {
            listView
        }
    }

    private var skeletonGrid: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns(for: contentWidth), spacing: gridSpacing) {
                ForEach(0..<12, id: \.self) { _ in
                    SkeletonView(height: minGridItemWidth * 1.5, cornerRadius: DS.Radius.r12)
                        .frame(height: minGridItemWidth * 1.5)
                }
            }
            .background(TabScrollObserver(tab: .library))
            .padding(.horizontal, horizontalPadding)
            .padding(.top, DS.Space.s24)
            .padding(.bottom, DS.Space.s32)
        }
        .background(widthReader)
    }

    private var widthReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { contentWidth = proxy.size.width }
                .onChange(of: proxy.size.width) { contentWidth = $0 }
        }
    }

    private func gridColumns(for width: CGFloat) -> [GridItem] {
        let availableWidth = max(320, width - (horizontalPadding * 2))
        let columns = max(2, Int((availableWidth + gridSpacing) / (minGridItemWidth + gridSpacing)))
        return Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: columns)
    }

    private var gridView: some View {
        let availableWidth = max(320, contentWidth - (horizontalPadding * 2))
        let columnsCount = max(2, Int((availableWidth + gridSpacing) / (minGridItemWidth + gridSpacing)))
        let cardWidth = (availableWidth - (CGFloat(columnsCount - 1) * gridSpacing)) / CGFloat(columnsCount)
        let columns = Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: columnsCount)

        return ScrollView {
                LazyVGrid(columns: columns, spacing: gridSpacing) {
                    ForEach(viewModel.visibleItems) { entry in
                        PosterCard(
                            item: entry.media,
                            width: cardWidth,
                            showTitle: librarySettings.titleDisplay != .none,
                            showYear: librarySettings.titleDisplay == .titleAndYear
                        ) {
                            router.libraryPath.append(DetailsNavigationItem(item: entry.media))
                        }
                        .onAppear {
                            viewModel.loadMoreIfNeeded(currentItem: entry)
                        }
                    }
                }
                .background(TabScrollObserver(tab: .library))
                .padding(.horizontal, horizontalPadding)
                .padding(.top, DS.Space.s24)
                .padding(.bottom, DS.Space.s32)

                if viewModel.isLoadingMore {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .padding(.bottom, DS.Space.s40)
                }
            }
            .background(widthReader)
    }

    private var listView: some View {
        ScrollView {
            LazyVStack(spacing: DS.Space.s14) {
                ForEach(viewModel.visibleItems) { entry in
                    LibraryListRow(entry: entry) {
                        router.libraryPath.append(DetailsNavigationItem(item: entry.media))
                    }
                    .padding(.horizontal, horizontalPadding)
                    .onAppear {
                        viewModel.loadMoreIfNeeded(currentItem: entry)
                    }
                }

                if viewModel.isLoadingMore {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .padding(.vertical, DS.Space.s24)
                }
            }
            .background(TabScrollObserver(tab: .library))
            .padding(.top, DS.Space.s24)
            .padding(.bottom, DS.Space.s48)
        }
    }

    private var emptyState: some View {
        VStack(spacing: DS.Space.s12) {
            Image(systemName: "film.stack")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("No titles found")
                .font(.title2.weight(.semibold))
            Text("Try adjusting filters or search for a different title.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DS.Space.s80)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: DS.Space.s16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 46))
                .foregroundStyle(.orange)
            Text("Unable to load library")
                .font(.title2.weight(.bold))
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Try Again") {
                Task { await viewModel.retry() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DS.Space.s80)
    }
}

private struct LibraryListRow: View {
    let entry: LibraryViewModel.LibraryEntry
    var onTap: () -> Void

    private let imageWidth: CGFloat = 120

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DS.Space.s16) {
                CachedAsyncImage(
                    url: ImageService.shared.thumbURL(for: entry.media, width: Int(imageWidth * 2), height: Int(imageWidth * 3))
                )
                .aspectRatio(2/3, contentMode: .fill)
                .frame(width: imageWidth, height: imageWidth * 1.5)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.r12, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: DS.Space.s6) {
                    Text(entry.media.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    HStack(spacing: DS.Space.s12) {
                        if entry.year != nil || entry.media.editionTitle != nil {
                            Label {
                                Text(yearEditionText(year: entry.year, edition: entry.media.editionTitle))
                            } icon: {
                                Image(systemName: "calendar")
                            }
                        }
                        if let rating = entry.rating {
                            Label {
                                Text(String(format: "%.1f", rating))
                            } icon: {
                                Image(systemName: "star.fill")
                            }
                        }
                        if let added = entry.addedAt {
                            Label {
                                Text(added.formatted(date: .abbreviated, time: .omitted))
                            } icon: {
                                Image(systemName: "tray.and.arrow.down")
                            }
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))

                    if let summary = entry.media.summary, !summary.isEmpty {
                        Text(summary)
                            .foregroundStyle(.white.opacity(0.75))
                            .font(.subheadline)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(DS.Space.s16)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func yearEditionText(year: Int?, edition: String?) -> String {
        var parts: [String] = []
        if let year = year {
            parts.append(String(year))
        }
        if let edition = edition {
            parts.append(edition)
        }
        return parts.joined(separator: " · ")
    }
}

#if DEBUG && canImport(PreviewsMacros)
#Preview {
    LibraryView()
}
#endif
