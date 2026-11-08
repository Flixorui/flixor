//
//  EntityBrowseView.swift
//  FlixorMac
//
//  Titles from a production company or TV network (EntityBrowseRoute):
//  logo header, Movies / TV toggle for companies, sort, and an infinitely
//  scrolling poster grid.
//

import SwiftUI
import FlixorKit

struct EntityBrowseView: View {
    @StateObject private var viewModel: EntityBrowseViewModel
    @EnvironmentObject private var router: NavigationRouter
    @EnvironmentObject private var mainViewState: MainViewState
    @Environment(\.flixorTheme) private var theme
    @Environment(\.windowMetrics) private var metrics
    /// Measured width of the page (the content area, excluding the nav rail).
    @State private var contentWidth: CGFloat = 0

    /// Room for a legacy (always visible) scroll bar so the grid never clips.
    private static let scrollBarAllowance: CGFloat = DS.Space.s16

    init(route: EntityBrowseRoute) {
        _viewModel = StateObject(wrappedValue: EntityBrowseViewModel(route: route))
    }

    private var gutter: CGFloat { metrics.pageGutter }

    private var grid: PosterGridLayout {
        PosterGridLayout(
            availableWidth: (contentWidth > 0 ? contentWidth : metrics.width) - gutter * 2 - Self.scrollBarAllowance,
            minItemWidth: metrics.posterWidth(base: 160),
            spacing: DS.Space.s16
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s28) {
                header
                controls
                content
            }
            .padding(.horizontal, gutter)
            .padding(.vertical, DS.Space.s32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .readContentWidth(into: $contentWidth)
        .background(BrowsePageBackdrop(url: viewModel.backdropURL))
        .navigationTitle("")
        .task { viewModel.start() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: DS.Space.s24) {
            EntityLogoPlate(url: viewModel.logoURL, name: viewModel.displayName)

            VStack(alignment: .leading, spacing: DS.Space.s6) {
                Text(viewModel.displayName)
                    .flixorFont(.display)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .accessibilityAddTraits(.isHeader)
                Text(viewModel.subtitle)
                    .flixorFont(.callout)
                    .foregroundStyle(theme.textSecondary)
                if let count = viewModel.countText {
                    Text(count)
                        .flixorFont(.footnote, weight: .medium)
                        .foregroundStyle(theme.textTertiary)
                }
                if let description = viewModel.details?.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !description.isEmpty {
                    Text(description)
                        .flixorParagraph(.callout)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(3)
                        .frame(maxWidth: 720, alignment: .leading)
                        .padding(.top, DS.Space.s4)
                }
            }
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: DS.Space.s16) {
            if viewModel.canToggleMediaType {
                BrowseChipBar(
                    options: TMDBDiscoverMediaType.allCases,
                    selection: $viewModel.mediaType,
                    title: { $0 == .movie ? "Movies" : "TV Shows" }
                )
            }
            Spacer(minLength: DS.Space.s8)
            BrowseSortMenu(
                options: EntityBrowseViewModel.Sort.allCases,
                selection: $viewModel.sort,
                title: { $0.title }
            )
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
                title: "Couldn't load titles",
                message: message,
                retryTitle: "Try Again",
                onRetry: { viewModel.reload() }
            )
        case .empty:
            BrowseMessageView(
                systemImage: viewModel.mediaType == .tv ? "tv" : "film",
                title: viewModel.mediaType == .tv ? "No shows found" : "No movies found",
                message: viewModel.canToggleMediaType
                    ? "TMDB lists nothing here for \(viewModel.displayName). Try the other media type."
                    : "TMDB lists nothing here for \(viewModel.displayName)."
            )
        case .loaded:
            VStack(spacing: DS.Space.s24) {
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
        } else if let error = viewModel.pagingError {
            HStack(spacing: DS.Space.s12) {
                Text(error)
                    .flixorFont(.callout)
                    .foregroundStyle(theme.textSecondary)
                Button("Retry") { viewModel.retryPaging() }
                    .accessibilityLabel("Retry loading more titles")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Space.s16)
        } else if viewModel.canLoadMore {
            // Fallback trigger when the last row is visible without scrolling.
            Color.clear
                .frame(height: DS.Space.s4)
                .onAppear { viewModel.loadMore() }
        }
    }
}

// MARK: - Logo

/// Company / network logo on a light plate (TMDB logos are often dark on
/// transparent), or the initials when there is no logo.
struct EntityLogoPlate: View {
    let url: URL?
    let name: String

    @Environment(\.flixorTheme) private var theme
    @Environment(\.windowMetrics) private var metrics

    var body: some View {
        let height = (88 * metrics.itemScale).rounded()
        let width = (height * 2.2).rounded()
        ZStack {
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(url == nil ? theme.surfaceElevated : Color.white.opacity(DS.Opacity.strong))
            if let url {
                CachedAsyncImage(url: url, contentMode: .fit) { Color.clear }
                    .padding(DS.Space.s16)
            } else {
                Text(initials)
                    .font(.flixor(.largeTitle, weight: .bold))
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .frame(width: width, height: height)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .stroke(theme.separator, lineWidth: DS.Border.thin)
        )
        .flixorShadow(.card)
        .accessibilityLabel("\(name) logo")
    }

    private var initials: String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}
