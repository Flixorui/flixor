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

    @StateObject private var viewModel = TVLibraryViewModel()
    @Namespace private var contentNS
    @State private var selectedItem: MediaItem?
    @FocusState private var focusedID: String?

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: UX.itemSpacing), count: 5)

    init(preferredKind: TVLibraryViewModel.LibrarySectionSummary.Kind? = nil) {
        self.preferredKind = preferredKind
    }

    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea(edges: .all)

            VStack(spacing: 0) {
                // Filter bar (only show when not navigating from tabs)
                if preferredKind == nil {
                    TVLibraryFilterBar(viewModel: viewModel)
                        .frame(height: 120)
                }

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
    }

    @ViewBuilder
    private var content: some View {
        if let error = viewModel.errorMessage {
            errorState(message: error)
        } else if viewModel.contentTab == .collections {
            // Collections view (Phase 3)
            emptyState(message: "Collections view coming soon")
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
            LazyVGrid(columns: gridColumns, spacing: UX.railV) {
                ForEach(viewModel.visibleItems) { entry in
                    TVPosterCard(item: entry.media, isFocused: focusedID == entry.id)
                        .frame(width: UX.posterWidth, height: UX.posterHeight)
                        .id(entry.id)
                        .focusable(true)
                        .focused($focusedID, equals: entry.id)
                        .scaleEffect(focusedID == entry.id ? UX.focusScale : 1.0)
                        .shadow(
                            color: .black.opacity(focusedID == entry.id ? 0.4 : 0.2),
                            radius: focusedID == entry.id ? 16 : 8,
                            y: focusedID == entry.id ? 8 : 4
                        )
                        .animation(.easeOut(duration: UX.focusDur), value: focusedID == entry.id)
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
