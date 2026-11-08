//
//  BrowseControls.swift
//  FlixorMac
//
//  Small controls shared by the person and company/network pages: capsule
//  filter chips, underlined tabs, a sort menu, poster grid cells, and the
//  empty / error placeholders.
//

import SwiftUI

// MARK: - Filter chips

struct BrowseChipBar<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    var count: ((Option) -> Int?)? = nil

    var body: some View {
        HStack(spacing: DS.Space.controlGap) {
            ForEach(options, id: \.self) { option in
                BrowseChip(
                    title: title(option),
                    count: count?(option),
                    isSelected: option == selection
                ) {
                    withAnimation(DS.Motion.quick) { selection = option }
                }
            }
        }
    }
}

struct BrowseChip: View {
    let title: String
    var count: Int? = nil
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.flixorTheme) private var theme
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s6) {
                Text(title)
                    .flixorFont(.callout, weight: .semibold)
                if let count {
                    Text("\(count)")
                        .flixorFont(.caption, weight: .medium)
                        .foregroundStyle(isSelected ? theme.onAccent.opacity(DS.Opacity.strong) : theme.textTertiary)
                }
            }
            .foregroundStyle(isSelected ? theme.onAccent : theme.textSecondary)
            .padding(.horizontal, DS.Space.s14)
            .padding(.vertical, DS.Space.s6)
            .background(
                Capsule().fill(isSelected ? theme.accent : (isHovered ? theme.pressedFill : theme.hoverFill))
            )
            .overlay(
                Capsule().stroke(isSelected ? Color.clear : theme.separator, lineWidth: DS.Border.thin)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DS.Motion.quick) { isHovered = hovering }
        }
        .accessibilityLabel(count.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Underlined tabs

struct BrowseTabBar<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    var count: ((Option) -> Int)? = nil

    @Environment(\.flixorTheme) private var theme

    var body: some View {
        HStack(spacing: DS.Space.s24) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    withAnimation(DS.Motion.standard) { selection = option }
                } label: {
                    VStack(alignment: .leading, spacing: DS.Space.s6) {
                        HStack(spacing: DS.Space.s6) {
                            Text(title(option))
                                .flixorFont(.headline)
                                .foregroundStyle(isSelected ? theme.textPrimary : theme.textTertiary)
                            if let value = count?(option) {
                                Text("\(value)")
                                    .flixorFont(.footnote, weight: .medium)
                                    .foregroundStyle(theme.textTertiary)
                            }
                        }
                        Capsule()
                            .fill(isSelected ? theme.accent : Color.clear)
                            .frame(height: DS.Border.medium)
                    }
                    .fixedSize()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title(option))
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

// MARK: - Sort menu

struct BrowseSortMenu<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String

    @Environment(\.flixorTheme) private var theme

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    if option == selection {
                        Label(title(option), systemImage: "checkmark")
                    } else {
                        Text(title(option))
                    }
                }
            }
        } label: {
            HStack(spacing: DS.Space.s6) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.flixorIcon(DS.Icon.xs, weight: .semibold))
                Text(title(selection))
                    .flixorFont(.callout, weight: .semibold)
            }
            .foregroundStyle(theme.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Sort by \(title(selection))")
    }
}

// MARK: - Poster cell

/// PosterCard plus an optional muted line under it (character, job, ...).
struct BrowsePosterCell: View {
    let item: MediaItem
    let width: CGFloat
    var subtitle: String? = nil
    let onTap: () -> Void

    @Environment(\.flixorTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            PosterCard(item: item, width: width, onTap: onTap)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .flixorFont(.caption)
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
                    .frame(width: width, alignment: .leading)
            }
        }
        .frame(width: width, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onTap() }
    }

    private var accessibilityText: String {
        var parts = [item.title]
        if let year = item.year { parts.append(String(year)) }
        if let subtitle, !subtitle.isEmpty { parts.append(subtitle) }
        return parts.joined(separator: ", ")
    }
}

/// Fixed-column poster grid; `onItemAppear` drives paging.
struct BrowsePosterGrid<Item: Identifiable>: View {
    let items: [Item]
    let layout: PosterGridLayout
    let content: (Item) -> BrowsePosterCell
    var onItemAppear: ((Int) -> Void)? = nil

    var body: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.fixed(layout.itemWidth), spacing: layout.spacing, alignment: .top),
                count: layout.columns
            ),
            alignment: .leading,
            spacing: DS.Space.s24
        ) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                content(item)
                    .onAppear { onItemAppear?(index) }
            }
        }
    }
}

struct BrowseSkeletonPosterGrid: View {
    let layout: PosterGridLayout
    var rows: Int = 2

    var body: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.fixed(layout.itemWidth), spacing: layout.spacing, alignment: .top),
                count: layout.columns
            ),
            alignment: .leading,
            spacing: DS.Space.s24
        ) {
            ForEach(0..<(layout.columns * rows), id: \.self) { _ in
                SkeletonPosterCard(width: layout.itemWidth)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Placeholders

struct BrowseMessageView: View {
    let systemImage: String
    let title: LocalizedStringKey
    var message: LocalizedStringKey? = nil
    var retryTitle: LocalizedStringKey? = nil
    var onRetry: (() -> Void)? = nil

    @Environment(\.flixorTheme) private var theme

    var body: some View {
        VStack(spacing: DS.Space.s12) {
            Image(systemName: systemImage)
                .font(.flixorIcon(DS.Icon.huge, weight: .light))
                .foregroundStyle(theme.textTertiary)
            Text(title)
                .flixorFont(.headline)
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .flixorParagraph(.callout)
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            if let retryTitle, let onRetry {
                Button(retryTitle, action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
                    .padding(.top, DS.Space.s4)
                    .accessibilityLabel(retryTitle)
            }
        }
        .padding(DS.Space.s40)
        .frame(maxWidth: .infinity)
    }
}

/// Faded backdrop at the top of a browse page.
struct BrowsePageBackdrop: View {
    let url: URL?

    @Environment(\.flixorTheme) private var theme
    @Environment(\.windowMetrics) private var metrics

    var body: some View {
        let height = metrics.heroHeight(for: .fraction(0.55, minimum: 360, maximum: 720))
        ZStack(alignment: .top) {
            theme.background
            if let url {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .overlay(CachedAsyncImage(url: url, contentMode: .fill) { Color.clear })
                    .clipped()
                    .opacity(DS.Opacity.scrimLight)
                    .overlay(
                        LinearGradient(
                            colors: [theme.background.opacity(DS.Opacity.scrimLight), theme.background],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - Content width

extension View {
    /// Writes this view's width (whole points) into `width`. Apply at a page
    /// root to size grids from the real content area, which is narrower than
    /// the window when the navigation rail is shown.
    func readContentWidth(into width: Binding<CGFloat>) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { width.wrappedValue = proxy.size.width.rounded(.down) }
                    .onChange(of: proxy.size.width) { width.wrappedValue = $0.rounded(.down) }
            }
        )
    }
}
