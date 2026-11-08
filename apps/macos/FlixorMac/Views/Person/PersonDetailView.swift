//
//  PersonDetailView.swift
//  FlixorMac
//
//  Full page for a cast or crew member (PersonRoute). Wide windows show the
//  identity as a sidebar with the credits scrolling beside it; narrow windows
//  stack the identity header above the credits.
//

import SwiftUI

struct PersonDetailView: View {
    @ObservedObject private var profileSettings = ProfileSettings.shared
    @StateObject private var viewModel: PersonDetailViewModel
    @EnvironmentObject private var router: NavigationRouter
    @EnvironmentObject private var mainViewState: MainViewState
    @Environment(\.flixorTheme) private var theme
    @Environment(\.windowMetrics) private var metrics
    /// Measured width of the page (the content area, excluding the nav rail).
    @State private var contentWidth: CGFloat = 0

    /// Content width from which the identity moves into a sidebar.
    private static let sidebarMinContentWidth: CGFloat = 1180
    /// Room for a legacy (always visible) scroll bar so grids never clip.
    private static let scrollBarAllowance: CGFloat = DS.Space.s16

    init(route: PersonRoute) {
        _viewModel = StateObject(wrappedValue: PersonDetailViewModel(route: route))
    }

    var body: some View {
        Group {
            if case .failed(let message) = viewModel.phase {
                BrowseMessageView(
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    title: "Couldn't load \(viewModel.displayName.isEmpty ? "this person" : viewModel.displayName)",
                    message: message,
                    retryTitle: "Try Again",
                    onRetry: { viewModel.load() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if usesSidebar {
                wideLayout
            } else {
                stackedLayout
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .readContentWidth(into: $contentWidth)
        .background(BrowsePageBackdrop(url: viewModel.backdropURL))
        .animation(DS.Motion.standard, value: viewModel.phase)
        .navigationTitle("")
        .task { viewModel.loadIfNeeded() }
    }

    // MARK: - Layout metrics

    /// Content area width; window width only until the first measurement.
    private var availableWidth: CGFloat { contentWidth > 0 ? contentWidth : metrics.width }
    private var usesSidebar: Bool { availableWidth >= Self.sidebarMinContentWidth }
    private var gutter: CGFloat { metrics.pageGutter }
    private var sidebarContentWidth: CGFloat { (340 * metrics.itemScale).rounded() }
    private var sidebarTrailingPadding: CGFloat { DS.Space.s32 }
    private var creditsLeadingPadding: CGFloat { DS.Space.s40 }

    private var wideCreditsWidth: CGFloat {
        availableWidth - gutter - sidebarContentWidth - sidebarTrailingPadding - DS.Border.thin
            - creditsLeadingPadding - gutter - Self.scrollBarAllowance
    }

    private var stackedCreditsWidth: CGFloat {
        availableWidth - gutter * 2 - Self.scrollBarAllowance
    }

    private var isLoading: Bool { viewModel.phase == .loading }

    // MARK: - Wide

    private var wideLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                Group {
                    if isLoading {
                        PersonIdentitySkeleton(layout: .sidebar)
                    } else {
                        PersonIdentitySidebar(viewModel: viewModel)
                    }
                }
                .frame(width: sidebarContentWidth, alignment: .leading)
                .padding(.leading, gutter)
                .padding(.trailing, sidebarTrailingPadding)
                .padding(.vertical, DS.Space.s32)
            }
            .frame(width: gutter + sidebarContentWidth + sidebarTrailingPadding)

            Rectangle()
                .fill(theme.separator)
                .frame(width: DS.Border.thin)
                .padding(.vertical, DS.Space.s32)

            ScrollView {
                creditsColumn(width: wideCreditsWidth)
                    .padding(.leading, creditsLeadingPadding)
                    .padding(.trailing, gutter)
                    .padding(.vertical, DS.Space.s32)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Stacked

    private var stackedLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s40) {
                if isLoading {
                    PersonIdentitySkeleton(layout: .header)
                } else {
                    PersonIdentityHeader(viewModel: viewModel)
                }
                creditsColumn(width: stackedCreditsWidth)
            }
            .padding(.horizontal, gutter)
            .padding(.vertical, DS.Space.s32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Credits

    @ViewBuilder
    private func creditsColumn(width: CGFloat) -> some View {
        let grid = PosterGridLayout(
            availableWidth: width,
            minItemWidth: metrics.posterWidth(designWidth: 150, storedSize: profileSettings.posterSize),
            spacing: DS.Space.s16
        )
        VStack(alignment: .leading, spacing: DS.Space.sectionGap) {
            if isLoading {
                VStack(alignment: .leading, spacing: DS.Space.s16) {
                    SkeletonView(width: 160, height: 22, cornerRadius: DS.Radius.badge)
                    BrowseSkeletonPosterGrid(layout: grid, rows: 2)
                }
            } else if viewModel.castCount == 0 && viewModel.crewCount == 0 {
                BrowseMessageView(
                    systemImage: "film.stack",
                    title: "No credits yet",
                    message: "TMDB doesn't list any movies or shows for \(viewModel.displayName)."
                )
            } else {
                if !viewModel.knownFor.isEmpty {
                    knownForSection
                }
                filmographySection(grid: grid)
            }
        }
    }

    private var knownForSection: some View {
        let cardWidth = metrics.posterWidth(designWidth: 140, storedSize: profileSettings.posterSize)
        return VStack(alignment: .leading, spacing: DS.Space.s14) {
            Text("Known for")
                .flixorFont(.title2)
                .foregroundStyle(theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: DS.Space.itemGap) {
                    ForEach(viewModel.knownFor) { credit in
                        BrowsePosterCell(item: credit.item, width: cardWidth, subtitle: credit.subtitle) {
                            open(credit.item)
                        }
                    }
                }
                .padding(.vertical, DS.Space.s4)
            }
        }
    }

    private func filmographySection(grid: PosterGridLayout) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            Text("Filmography")
                .flixorFont(.title2)
                .foregroundStyle(theme.textPrimary)
                .accessibilityAddTraits(.isHeader)

            if viewModel.hasBothDepartments {
                BrowseTabBar(
                    options: PersonDetailViewModel.Department.allCases,
                    selection: $viewModel.department,
                    title: { $0.title },
                    count: { $0 == .acting ? viewModel.castCount : viewModel.crewCount }
                )
            }

            HStack(spacing: DS.Space.s16) {
                BrowseChipBar(
                    options: PersonDetailViewModel.MediaFilter.allCases,
                    selection: $viewModel.mediaFilter,
                    title: { $0.title },
                    count: { viewModel.filterCounts[$0] }
                )
                Spacer(minLength: DS.Space.s8)
                BrowseSortMenu(
                    options: PersonDetailViewModel.SortOrder.allCases,
                    selection: $viewModel.sort,
                    title: { $0.title }
                )
            }

            if viewModel.credits.isEmpty {
                BrowseMessageView(
                    systemImage: viewModel.mediaFilter == .tv ? "tv" : "film",
                    title: emptyFilterTitle
                )
            } else {
                BrowsePosterGrid(items: viewModel.credits, layout: grid) { credit in
                    BrowsePosterCell(item: credit.item, width: grid.itemWidth, subtitle: credit.subtitle) {
                        open(credit.item)
                    }
                }
                .padding(.top, DS.Space.s8)
            }
        }
    }

    private var emptyFilterTitle: String {
        let role = viewModel.department == .acting ? "acting" : "crew"
        switch viewModel.mediaFilter {
        case .all: return "No \(role) credits"
        case .movies: return "No movie \(role) credits"
        case .tv: return "No TV \(role) credits"
        }
    }

    private func open(_ item: MediaItem) {
        router.push(DetailsNavigationItem(item: item), on: mainViewState.selectedTab)
    }
}

// MARK: - Skeleton

struct PersonIdentitySkeleton: View {
    enum Layout { case sidebar, header }
    let layout: Layout

    var body: some View {
        Group {
            switch layout {
            case .sidebar:
                VStack(alignment: .leading, spacing: DS.Space.s24) {
                    SkeletonView(width: 168, height: 168, cornerRadius: 84)
                    SkeletonView(width: 220, height: 30, cornerRadius: DS.Radius.badge)
                    factLines
                    SkeletonView(height: DS.Border.thin, cornerRadius: 0)
                    bioLines
                }
            case .header:
                VStack(alignment: .leading, spacing: DS.Space.s24) {
                    HStack(alignment: .top, spacing: DS.Space.s28) {
                        SkeletonView(width: 148, height: 148, cornerRadius: 74)
                        VStack(alignment: .leading, spacing: DS.Space.s16) {
                            SkeletonView(width: 280, height: 34, cornerRadius: DS.Radius.badge)
                            factLines
                        }
                        .padding(.top, DS.Space.s8)
                    }
                    bioLines
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Loading")
    }

    private var factLines: some View {
        VStack(alignment: .leading, spacing: DS.Space.s14) {
            ForEach(0..<3, id: \.self) { index in
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    SkeletonView(width: 70, height: 9, cornerRadius: DS.Radius.r2)
                    SkeletonView(width: index == 1 ? 200 : 150, height: 14, cornerRadius: DS.Radius.badge)
                }
            }
        }
    }

    private var bioLines: some View {
        VStack(alignment: .leading, spacing: DS.Space.s8) {
            ForEach(0..<5, id: \.self) { index in
                SkeletonView(height: 13, cornerRadius: DS.Radius.badge)
                    .frame(maxWidth: index == 4 ? 220 : .infinity, alignment: .leading)
            }
        }
    }
}
