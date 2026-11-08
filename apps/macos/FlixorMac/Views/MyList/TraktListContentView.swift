//
//  TraktListContentView.swift
//  FlixorMac
//
//  One Trakt list on the My List screen: the same search, type filter, sort,
//  poster grid and bulk mode as My List.
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

    // The same grid geometry as MyListView.
    private let horizontalPadding = DS.Space.s64
    private let gridSpacing = DS.Space.s18
    private var minGridItemWidth: CGFloat {
        windowMetrics.posterWidth(designWidth: 180, storedSize: profileSettings.posterSize)
    }
    private let skeletonCount = 12

    var body: some View {
        VStack(spacing: 0) {
            controls
                .padding(.horizontal, horizontalPadding)
                .padding(.top, DS.Space.s24)

            content
                .padding(.top, DS.Space.s16)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            HStack(spacing: DS.Space.s16) {
                TextField("Search \(list.name)", text: $model.searchQuery)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, DS.Space.s14)
                    .padding(.vertical, DS.Space.s10)
                    .background(theme.hoverFill, in: RoundedRectangle(cornerRadius: DS.Radius.group, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.group, style: .continuous)
                            .stroke(theme.separator, lineWidth: DS.Border.thin)
                    )
                    .frame(width: 260)
                    .accessibilityLabel("Search this list")

                Picker("Type", selection: $model.filter) {
                    ForEach(TraktListsViewModel.FilterType.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
                .accessibilityLabel("Filter by type")

                Spacer()

                Picker("Sort", selection: $model.sort) {
                    ForEach(TraktListsViewModel.SortOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)
                .accessibilityLabel("Sort by")

                bulkButton

                if model.bulkMode && !model.selectedIDs.isEmpty {
                    removeSelectedButton
                }
            }

            if let error = model.itemsError, !model.items.isEmpty {
                errorBanner(error)
            }
        }
    }

    private var bulkButton: some View {
        Button {
            model.bulkMode.toggle()
            if !model.bulkMode {
                model.clearSelection()
            }
        } label: {
            Text(model.bulkMode ? "Cancel" : "Select")
                .flixorFont(.callout, weight: .semibold)
                .padding(.horizontal, DS.Space.s16)
                .padding(.vertical, DS.Space.s10)
                .background(theme.pressedFill, in: RoundedRectangle(cornerRadius: DS.Radius.group, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.bulkMode ? "Cancel selection" : "Select titles")
    }

    private var removeSelectedButton: some View {
        Button(role: .destructive) {
            Task { await model.removeSelected() }
        } label: {
            Text("Remove (\(model.selectedIDs.count))")
                .flixorFont(.callout, weight: .semibold)
                .padding(.horizontal, DS.Space.s16)
                .padding(.vertical, DS.Space.s10)
                .background(theme.danger.opacity(DS.Opacity.strong), in: RoundedRectangle(cornerRadius: DS.Radius.group, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(model.isMutating)
        .accessibilityLabel("Remove \(model.selectedIDs.count) selected from \(list.name)")
    }

    private func errorBanner(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.warning)
                .accessibilityHidden(true)
            Text(error)
                .foregroundStyle(theme.warning)
            Spacer()
            Button("Retry") { model.retry() }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
                .accessibilityLabel("Retry loading this list")
        }
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
                    message: error,
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
                    message: "Try a different search or type filter."
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
                .padding(.vertical, DS.Space.s32)
            }
        }
    }

    private func cell(_ item: TraktListGridItem, width: CGFloat) -> some View {
        let isSelected = model.selectedIDs.contains(item.id)
        return ZStack(alignment: .topTrailing) {
            PosterCard(
                item: item.cardItem,
                width: width,
                badge: item.badgeText.map { AnyView(EntryBadge(text: $0)) },
                topTrailingOverlay: model.bulkMode ? nil : AnyView(removeButton(for: item)),
                isSelected: isSelected,
                customImageURL: item.imageURL,
                // The artwork has its own context menu, which wins over the one below.
                extraMenuActions: [
                    CardMenuAction(title: "Remove from \(list.name)", role: .destructive, isDisabled: model.isMutating) {
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
