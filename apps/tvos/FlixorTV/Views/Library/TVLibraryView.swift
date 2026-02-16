//
//  TVLibraryView.swift
//  FlixorTV
//
//  Main library view with poster grid and filtering
//

import SwiftUI
import FlixorKit

struct TVLibraryView: View {
    let preferredKind: TVLibraryViewModel.LibrarySectionSummary.Kind?

    @ObservedObject private var viewModel: TVLibraryViewModel
    @EnvironmentObject private var profileSettings: TVProfileSettings
    @Namespace private var contentNS
    @State private var selectedItem: MediaItem?
    @FocusState private var focusedID: String?
    @State private var focusDebounceTask: Task<Void, Never>?
    @State private var settingsRefreshTask: Task<Void, Never>?

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: UX.itemSpacing), count: 5)

    init(
        preferredKind: TVLibraryViewModel.LibrarySectionSummary.Kind? = nil,
        viewModel: TVLibraryViewModel
    ) {
        self.preferredKind = preferredKind
        self._viewModel = ObservedObject(wrappedValue: viewModel)
    }

    var body: some View {
        ZStack {
            // UltraBlur gradient background
            UltraBlurGradientBackground(colors: viewModel.currentUltraBlurColors ?? defaultColors)
                .animation(.easeInOut(duration: 0.8), value: viewModel.currentUltraBlurColors?.topLeft ?? "default")
                .ignoresSafeArea(edges: .all)

            VStack(spacing: 0) {
                // Filter bar (always show, but hide section pills when navigating from tabs)
                TVLibraryFilterBar(viewModel: viewModel, showSectionPills: preferredKind == nil)
                    .frame(height: preferredKind == nil ? 200 : 120)

                // Content area
                content
            }
        }
        .task {
            await viewModel.loadIfNeeded(preferredKind: preferredKind)
        }
        .fullScreenCover(item: $selectedItem) { item in
            TVDetailsView(item: item)
        }
        .onChange(of: focusedID) { newFocusedID in
            // Cancel any existing debounce task
            focusDebounceTask?.cancel()

            // If no item is focused, do nothing
            guard let focusedID = newFocusedID else {
                return
            }

            // Find the focused item
            guard let focusedEntry = viewModel.visibleItems.first(where: { $0.id == focusedID }) else {
                return
            }

            // Start a short debounce task to avoid recoloring during fast focus movement.
            focusDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                await viewModel.fetchUltraBlurColors(for: focusedEntry.media)
            }
        }
        .onReceive(profileSettings.objectWillChange) { _ in
            settingsRefreshTask?.cancel()
            settingsRefreshTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                await viewModel.retry()
            }
        }
        .onDisappear {
            focusDebounceTask?.cancel()
            settingsRefreshTask?.cancel()
        }
    }

    private var defaultColors: UltraBlurColors {
        UltraBlurColors(
            topLeft: "#1a1a2e",
            topRight: "#16213e",
            bottomRight: "#0a1929",
            bottomLeft: "#0f3460"
        )
    }

    @ViewBuilder
    private var content: some View {
        if let error = viewModel.errorMessage {
            errorState(message: error)
        } else if viewModel.contentTab == .collections {
            TVCollectionsGridView(
                collections: viewModel.collections,
                isLoading: viewModel.isLoadingCollections,
                onSelect: { collection in
                    Task { await viewModel.openCollection(collection) }
                }
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
            emptyState(message: "No titles found")
        } else if viewModel.viewMode == .list {
            listView
        } else {
            gridView
        }
    }

    private var skeletonGrid: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: UX.railV) {
                ForEach(0..<15, id: \.self) { _ in
                    SkeletonPoster()
                        .frame(width: UX.posterWidth, height: UX.posterHeight)
                }
            }
            .padding(.horizontal, UX.gridH)
            .padding(.top, 32)
            .padding(.bottom, 80)
        }
    }

    private var gridView: some View {
        ScrollView {
            if let activeCollectionTitle = viewModel.activeCollectionTitle {
                HStack {
                    Text(activeCollectionTitle)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.horizontal, UX.gridH)
                .padding(.top, 16)
            }

            LazyVGrid(columns: gridColumns, spacing: UX.railV) {
                ForEach(viewModel.visibleItems) { entry in
                    let isFocused = focusedID == entry.id
                    TVPosterCard(item: entry.media, isFocused: isFocused)
                        .frame(width: UX.posterWidth, height: UX.posterHeight)
                        .id(entry.id)
                        .focusable(true)
                        .focused($focusedID, equals: entry.id)
                        .scaleEffect(isFocused ? UX.focusScale : 1.0)
                        .shadow(
                            color: .black.opacity(isFocused ? 0.4 : 0.2),
                            radius: isFocused ? 16 : 8,
                            y: isFocused ? 8 : 4
                        )
                        .animation(.easeOut(duration: UX.focusDur), value: focusedID)
                        .onTapGesture {
                            selectedItem = entry.media
                        }
                        .onAppear {
                            viewModel.loadMoreIfNeeded(currentItem: entry)
                        }
                }
            }
            .padding(.horizontal, UX.gridH)
            .padding(.top, 32)
            .padding(.bottom, 80)

            if viewModel.isLoadingMore {
                ProgressView()
                    .progressViewStyle(.circular)
                    .padding(.bottom, 40)
            }
        }
        .focusScope(contentNS)
    }

    private var listView: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(viewModel.visibleItems) { entry in
                    Button {
                        selectedItem = entry.media
                    } label: {
                        HStack(spacing: 16) {
                            CachedAsyncImage(url: ImageService.shared.thumbURL(for: entry.media, width: 240, height: 360))
                                .aspectRatio(2/3, contentMode: .fill)
                                .frame(width: 130, height: 195)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.media.title)
                                    .font(.system(size: 30, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text(infoText(for: entry))
                                    .font(.system(size: 20))
                                    .foregroundStyle(.white.opacity(0.75))
                                    .lineLimit(1)
                                if let summary = entry.media.summary, !summary.isEmpty {
                                    Text(summary)
                                        .font(.system(size: 18))
                                        .foregroundStyle(.white.opacity(0.65))
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                        }
                        .padding(18)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .onAppear { viewModel.loadMoreIfNeeded(currentItem: entry) }
                }
            }
            .padding(.horizontal, UX.gridH)
            .padding(.vertical, 24)
        }
    }

    private func infoText(for entry: TVLibraryViewModel.LibraryEntry) -> String {
        var pieces: [String] = []
        if let year = entry.year {
            pieces.append(String(year))
        }
        if let rating = entry.rating {
            pieces.append(String(format: "%.1f", rating))
        }
        return pieces.joined(separator: " · ")
    }

    private func emptyState(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "film.stack")
                .font(.system(size: 60))
                .foregroundStyle(.white.opacity(0.4))
            Text(message)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.white)
            Text("Try adjusting filters or selecting a different library.")
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(80)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 64))
                .foregroundStyle(.orange)
            Text("Unable to load library")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.white)
            Text(message)
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 600)

            Button {
                Task { await viewModel.retry() }
            } label: {
                Text("Retry")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(80)
    }
}

private struct TVCollectionsGridView: View {
    let collections: [TVLibraryViewModel.CollectionEntry]
    let isLoading: Bool
    var onSelect: (TVLibraryViewModel.CollectionEntry) -> Void

    private let columns = [GridItem(.adaptive(minimum: 420), spacing: 24)]

    var body: some View {
        if isLoading {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(0..<6, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 240)
                    }
                }
                .padding(.horizontal, UX.gridH)
                .padding(.vertical, 28)
            }
        } else if collections.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.5))
                Text("No collections available")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(collections) { collection in
                        Button {
                            onSelect(collection)
                        } label: {
                            ZStack(alignment: .bottomLeading) {
                                CachedAsyncImage(url: collection.artwork)
                                    .aspectRatio(16/9, contentMode: .fill)
                                    .frame(height: 240)
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .overlay(
                                        LinearGradient(
                                            colors: [Color.black.opacity(0.72), Color.clear],
                                            startPoint: .bottom,
                                            endPoint: .top
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    )

                                VStack(alignment: .leading, spacing: 6) {
                                    Text(collection.title)
                                        .font(.system(size: 30, weight: .bold))
                                        .foregroundStyle(.white)
                                        .lineLimit(2)
                                    Text("\(collection.count) items")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.85))
                                }
                                .padding(18)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, UX.gridH)
                .padding(.vertical, 28)
            }
        }
    }
}
