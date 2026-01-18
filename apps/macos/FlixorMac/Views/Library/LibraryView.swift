//
//  LibraryView.swift
//  FlixorMac
//
//  Library / Browse experience with filtering, sorting, and collections support.
//

import SwiftUI

struct LibraryView: View {
    @StateObject private var viewModel = LibraryViewModel()
    @EnvironmentObject private var router: NavigationRouter
    @EnvironmentObject private var mainViewState: MainViewState

    private let horizontalPadding: CGFloat = 64
    private let gridSpacing: CGFloat = 18
    private let minGridItemWidth: CGFloat = 180

    var body: some View {
        VStack(spacing: 0) {
            LibraryFilterBarView(viewModel: viewModel) { section in
                viewModel.selectSection(section)
            }

            content
        }
        .background(HomeBackground())
        .navigationTitle("")
        .task {
            await viewModel.loadIfNeeded()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let error = viewModel.errorMessage {
            errorState(message: error)
        } else if viewModel.contentTab == .collections {
            CollectionsView(
                collections: viewModel.collections,
                isLoading: viewModel.isLoadingCollections,
                onSelect: { _ in }
            )
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
        GeometryReader { geometry in
            ScrollView {
                LazyVGrid(columns: gridColumns(for: geometry.size.width), spacing: gridSpacing) {
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

    private func gridColumns(for width: CGFloat) -> [GridItem] {
        let availableWidth = max(320, width - (horizontalPadding * 2))
        let columns = max(2, Int((availableWidth + gridSpacing) / (minGridItemWidth + gridSpacing)))
        return Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: columns)
    }

    private var gridView: some View {
        GeometryReader { geometry in
            let availableWidth = max(320, geometry.size.width - (horizontalPadding * 2))
            let columnsCount = max(2, Int((availableWidth + gridSpacing) / (minGridItemWidth + gridSpacing)))
            let cardWidth = (availableWidth - (CGFloat(columnsCount - 1) * gridSpacing)) / CGFloat(columnsCount)
            let columns = Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: columnsCount)

            ScrollView {
                LazyVGrid(columns: columns, spacing: gridSpacing) {
                    ForEach(viewModel.visibleItems) { entry in
                        PosterCard(
                            item: entry.media,
                            width: cardWidth,
                            showTitle: true
                        ) {
                            router.libraryPath.append(DetailsNavigationItem(item: entry.media))
                        }
                        .onAppear {
                            viewModel.loadMoreIfNeeded(currentItem: entry)
                        }
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 32)

                if viewModel.isLoadingMore {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .padding(.bottom, 40)
                }
            }
        }
    }

    private var listView: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
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
                        .padding(.vertical, 24)
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 48)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "film.stack")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("No titles found")
                .font(.title2.weight(.semibold))
            Text("Try adjusting filters or search for a different title.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(80)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 16) {
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
        .padding(80)
    }
}

private struct LibraryListRow: View {
    let entry: LibraryViewModel.LibraryEntry
    var onTap: () -> Void

    private let imageWidth: CGFloat = 120

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                CachedAsyncImage(
                    url: ImageService.shared.thumbURL(for: entry.media, width: Int(imageWidth * 2), height: Int(imageWidth * 3))
                )
                .aspectRatio(2/3, contentMode: .fill)
                .frame(width: imageWidth, height: imageWidth * 1.5)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 6) {
                    Text(entry.media.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    HStack(spacing: 12) {
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
            .padding(16)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
