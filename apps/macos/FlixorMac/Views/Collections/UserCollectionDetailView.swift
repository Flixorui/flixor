//
//  UserCollectionDetailView.swift
//  FlixorMac
//
//  A collection's page: poster grid across all its sources, infinite scrolling,
//  with a notice for any source that failed.
//

import SwiftUI

struct UserCollectionDetailView: View {
    let route: UserCollectionRoute

    @StateObject private var viewModel = UserCollectionDetailViewModel()
    @ObservedObject private var store = UserCollectionsStore.shared
    @EnvironmentObject private var router: NavigationRouter
    @EnvironmentObject private var mainViewState: MainViewState
    @Environment(\.flixorTheme) private var theme
    @Environment(\.windowMetrics) private var metrics
    @Environment(\.dismiss) private var dismiss

    @State private var contentWidth: CGFloat = 0
    @State private var editorRequest: UserCollectionEditorRequest?

    private static let scrollBarAllowance: CGFloat = DS.Space.s16

    private var collection: UserCollection? { store.collection(id: route.collectionId) }
    private var gutter: CGFloat { metrics.pageGutter }

    private var grid: PosterGridLayout {
        PosterGridLayout(
            availableWidth: (contentWidth > 0 ? contentWidth : metrics.width) - gutter * 2 - Self.scrollBarAllowance,
            minItemWidth: metrics.posterWidth(base: 160),
            spacing: DS.Space.s16
        )
    }

    var body: some View {
        Group {
            if let collection {
                page(collection)
                    .task(id: collection.contentKey) { viewModel.start(sources: collection.sources) }
            } else {
                BrowseMessageView(systemImage: "rectangle.stack", title: "This collection no longer exists")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("")
        .sheet(item: $editorRequest) { request in
            UserCollectionEditorView(collection: request.collection, onDeleted: { dismiss() })
        }
    }

    private func page(_ collection: UserCollection) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s28) {
                header(collection)
                failureNotice
                content
            }
            .padding(.horizontal, gutter)
            .padding(.vertical, DS.Space.s32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .readContentWidth(into: $contentWidth)
        .background(BrowsePageBackdrop(url: backdropURL(collection)))
    }

    private func backdropURL(_ collection: UserCollection) -> URL? {
        if let cover = collection.cover, cover.style == .backdrop {
            return URL(string: cover.url)
        }
        return viewModel.items.lazy.compactMap { $0.art.flatMap(URL.init(string:)) }.first
    }

    // MARK: - Header

    private func header(_ collection: UserCollection) -> some View {
        HStack(alignment: .center, spacing: DS.Space.s16) {
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                Text(collection.name)
                    .flixorFont(.display)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                Text(collection.sources.map(\.title).joined(separator: " · "))
                    .flixorFont(.callout)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(2)
                if !viewModel.items.isEmpty {
                    Text(viewModel.canLoadMore ? "\(viewModel.items.count)+ titles" : "\(viewModel.items.count) titles")
                        .flixorFont(.footnote, weight: .medium)
                        .foregroundStyle(theme.textTertiary)
                }
            }
            Spacer(minLength: DS.Space.s16)
            Button {
                editorRequest = UserCollectionEditorRequest(collection: collection)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .accessibilityLabel("Edit collection")
        }
    }

    // MARK: - Failure notice

    @ViewBuilder
    private var failureNotice: some View {
        // With nothing to show, the full-page error below covers it.
        if !viewModel.failures.isEmpty && !viewModel.items.isEmpty {
            HStack(alignment: .top, spacing: DS.Space.s12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(theme.warning)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    ForEach(viewModel.failures) { failure in
                        Text("\(failure.sourceTitle): \(failure.message)")
                            .flixorFont(.callout)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                Spacer(minLength: DS.Space.s8)
                Button("Retry") { viewModel.retryFailedSources() }
                    .accessibilityLabel("Retry failed sources")
            }
            .padding(DS.Space.s12)
            .background(theme.hoverFill, in: RoundedRectangle(cornerRadius: DS.Radius.compactCard, style: .continuous))
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        let grid = self.grid
        switch viewModel.phase {
        case .loading:
            BrowseSkeletonPosterGrid(layout: grid, rows: 3)
        case .failed(let message):
            BrowseMessageView(
                systemImage: "exclamationmark.triangle",
                title: "Couldn't load this collection",
                message: message,
                retryTitle: "Try Again",
                onRetry: { viewModel.retryFailedSources() }
            )
        case .empty:
            BrowseMessageView(
                systemImage: "rectangle.stack",
                title: "Nothing here yet",
                message: "These sources didn't return any titles. Edit the collection to change them."
            )
        case .loaded:
            // Lazy so the footer's load-more fallback only appears near the visible end.
            LazyVStack(spacing: DS.Space.s24) {
                BrowsePosterGrid(
                    items: viewModel.items,
                    layout: grid,
                    content: { item in
                        BrowsePosterCell(item: item, width: grid.itemWidth) {
                            router.push(DetailsNavigationItem(item: item), on: mainViewState.selectedTab)
                        }
                    },
                    onItemAppear: { index in
                        viewModel.itemAppeared(at: index, prefetchDistance: grid.columns * 2)
                    }
                )
                pagingFooter
            }
        }
    }

    @ViewBuilder
    private var pagingFooter: some View {
        if viewModel.isLoadingMore {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Space.s16)
                .accessibilityLabel("Loading more titles")
        } else if viewModel.canLoadMore {
            // Fallback trigger when the last row is visible without scrolling.
            Color.clear
                .frame(height: DS.Space.s4)
                .onAppear { viewModel.loadMore() }
        }
    }
}
