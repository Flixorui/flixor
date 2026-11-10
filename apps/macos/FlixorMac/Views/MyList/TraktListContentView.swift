//
//  TraktListContentView.swift
//  FlixorMac
//
//  One Trakt list on the My List screen: the poster grid. Search, chips, sort
//  and Select are in the My List header.
//

import SwiftUI
import FlixorKit

struct TraktListContentView: View {
    @ObservedObject var model: TraktListsViewModel
    let list: TraktUserList

    @EnvironmentObject private var router: NavigationRouter
    @Environment(\.flixorTheme) private var theme
    @Environment(\.windowMetrics) private var windowMetrics
    @ObservedObject private var profileSettings = ProfileSettings.shared
    @ObservedObject private var librarySettings = LibraryScreenSettings.shared

    // The same grid as MyListView and the Library.
    private let horizontalPadding = DS.Space.s64
    private var gridSpacing: CGFloat { librarySettings.density.spacing }
    private var minGridItemWidth: CGFloat {
        let size = librarySettings.posterSize.resolved(homeSize: profileSettings.posterSize)
        return windowMetrics.posterWidth(designWidth: 180, storedSize: size.rawValue)
    }
    private let skeletonCount = 12

    // Search, type chips, sort and Select live in the My List header.
    var body: some View {
        content
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if model.isLoadingItems && model.items.isEmpty {
            skeletonGrid
        } else if let error = model.itemsError, model.items.isEmpty {
            centered(
                BrowseMessageView(
                    systemImage: "exclamationmark.triangle",
                    title: "Couldn't load this list",
                    message: .verbatim(error),
                    retryTitle: "Try Again",
                    onRetry: { model.retry() }
                )
            )
        } else if model.items.isEmpty {
            centered(
                BrowseMessageView(
                    systemImage: "list.bullet",
                    title: "This list is empty",
                    message: "Right-click a poster anywhere in Flixor and choose Add to Trakt List."
                )
            )
        } else if model.visibleItems.isEmpty {
            centered(
                BrowseMessageView(
                    systemImage: "magnifyingglass",
                    title: "No matching titles",
                    message: "Try a different search or chip."
                )
            )
        } else {
            grid
        }
    }

    private func centered(_ message: BrowseMessageView) -> some View {
        message.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private struct GridMetrics {
        let columns: [GridItem]
        let cardWidth: CGFloat
    }

    private func gridMetrics(width: CGFloat) -> GridMetrics {
        let available = max(320, width - horizontalPadding * 2)
        let count = max(2, Int((available + gridSpacing) / (minGridItemWidth + gridSpacing)))
        return GridMetrics(
            columns: Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: count),
            cardWidth: (available - CGFloat(count - 1) * gridSpacing) / CGFloat(count)
        )
    }

    private var skeletonGrid: some View {
        GeometryReader { geometry in
            let metrics = gridMetrics(width: geometry.size.width)
            ScrollView {
                LazyVGrid(columns: metrics.columns, spacing: gridSpacing) {
                    ForEach(0..<skeletonCount, id: \.self) { _ in
                        SkeletonPosterCard(width: metrics.cardWidth)
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, DS.Space.s32)
            }
            .accessibilityLabel("Loading list")
        }
    }

    private var grid: some View {
        GeometryReader { geometry in
            let metrics = gridMetrics(width: geometry.size.width)
            ScrollView {
                LazyVGrid(columns: metrics.columns, spacing: gridSpacing) {
                    ForEach(model.visibleItems) { item in
                        cell(item, width: metrics.cardWidth)
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, DS.Space.s24)
            }
        }
    }

    private func cell(_ item: TraktListGridItem, width: CGFloat) -> some View {
        let isSelected = model.selectedIDs.contains(item.id)
        return HoverReveal { hovering in
          ZStack(alignment: .topTrailing) {
            PosterCard(
                item: item.cardItem,
                width: width,
                showTitle: librarySettings.titleDisplay != .none,
                showYear: librarySettings.titleDisplay == .titleAndYear,
                badge: item.badgeText.map { AnyView(EntryBadge(text: $0)) },
                // The − shows on hover, like My List.
                topTrailingOverlay: model.bulkMode || !hovering ? nil : AnyView(removeButton(for: item)),
                isSelected: isSelected,
                customImageURL: item.imageURL,
                // The artwork has its own context menu, which wins over the one below.
                extraMenuActions: [
                    CardMenuAction(title: String(localized: "Remove from \(list.name)"), role: .destructive, isDisabled: model.isMutating) {
                        Task { await model.remove(item) }
                    }
                ],
                onTap: {
                    if model.bulkMode {
                        model.toggleSelection(for: item)
                    } else {
                        openDetails(item)
                    }
                }
            )

            if model.bulkMode {
                selectionMark(isSelected: isSelected)
            }
          }
        }
        .contextMenu {
            Button("View Details") { openDetails(item) }
            Button("Remove from \(list.name)", role: .destructive) {
                Task { await model.remove(item) }
            }
            .disabled(model.isMutating)
        }
    }

    private func openDetails(_ item: TraktListGridItem) {
        router.myListPath.append(DetailsNavigationItem(item: item.detailsItem))
    }

    private func removeButton(for item: TraktListGridItem) -> some View {
        Button {
            Task { await model.remove(item) }
        } label: {
            Image(systemName: "minus")
                .font(.flixorIcon(DS.Icon.xs, weight: .bold))
                .foregroundStyle(theme.textPrimary)
                .frame(width: DS.Space.s28, height: DS.Space.s28)
                .background(theme.scrim(), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(model.isMutating)
        .help("Remove from \(list.name)")
        .accessibilityLabel("Remove \(item.title) from \(list.name)")
    }

    private func selectionMark(isSelected: Bool) -> some View {
        Circle()
            .strokeBorder(theme.textPrimary, lineWidth: DS.Border.medium)
            .frame(width: DS.Icon.xl, height: DS.Icon.xl)
            .background(Circle().fill(isSelected ? theme.textPrimary : Color.clear))
            .overlay(
                Image(systemName: "checkmark")
                    .font(.flixorIcon(DS.Icon.xs, weight: .bold))
                    .foregroundStyle(isSelected ? theme.background : theme.textTertiary)
            )
            .padding(DS.Space.s10)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// "S2" or "S2 E5" on season and episode entries.
private struct EntryBadge: View {
    let text: String

    @Environment(\.flixorTheme) private var theme

    var body: some View {
        Text(text)
            .flixorFont(.nano, weight: .bold)
            .foregroundStyle(theme.textPrimary)
            .padding(.horizontal, DS.Space.s6)
            .padding(.vertical, 3)
            .background(theme.scrim(DS.Opacity.scrimHeavy), in: RoundedRectangle(cornerRadius: DS.Radius.badge, style: .continuous))
    }
}

/// Hands its content whether the pointer is over it.
struct HoverReveal<Content: View>: View {
    @ViewBuilder let content: (Bool) -> Content
    @State private var hovering = false

    var body: some View {
        content(hovering)
            .onHover { hovering = $0 }
            .animation(DS.Motion.quick, value: hovering)
    }
}
