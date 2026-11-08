//
//  SearchDiscoverView.swift
//  FlixorMac
//
//  Discover mode of the Search screen: a filter bar (type, genre, sort, year
//  range, minimum rating) over a responsive, infinitely paged poster grid.
//

import SwiftUI

struct SearchDiscoverView: View {
    @ObservedObject var viewModel: DiscoverViewModel
    let onTap: (SearchViewModel.SearchResult) -> Void

    @Environment(\.flixorTheme) private var theme
    @Environment(\.windowMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s20) {
            DiscoverFilterBar(viewModel: viewModel)
                .padding(.horizontal, SearchLayout.gutter)

            content
        }
        .padding(.bottom, DS.Space.sectionGap)
        .onAppear { viewModel.activate() }
    }

    // MARK: Grid geometry

    private var gridSpacing: CGFloat { DS.Space.s16 }

    private var columnCount: Int {
        // Allowance for a visible scroller so the last column never clips.
        let available = metrics.width - SearchLayout.gutter * 2 - DS.Space.s16
        let minWidth = metrics.posterWidth(base: 150)
        return max(2, Int((available + gridSpacing) / (minWidth + gridSpacing)))
    }

    private var itemWidth: CGFloat {
        let available = metrics.width - SearchLayout.gutter * 2 - DS.Space.s16
        let columns = CGFloat(columnCount)
        return floor((available - gridSpacing * (columns - 1)) / columns)
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(itemWidth), spacing: gridSpacing, alignment: .top), count: columnCount)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            skeletonGrid
        } else if let message = viewModel.errorMessage, viewModel.items.isEmpty {
            DiscoverMessageView(
                icon: "wifi.exclamationmark",
                title: "Couldn't load Discover",
                message: message,
                actionTitle: "Retry",
                action: { viewModel.retry() }
            )
        } else if viewModel.items.isEmpty {
            DiscoverMessageView(
                icon: "line.3.horizontal.decrease.circle",
                title: "No titles match these filters",
                message: "Try a different genre, year range or rating.",
                actionTitle: viewModel.filters.hasActiveFilters ? "Reset Filters" : nil,
                action: { viewModel.resetFilters() }
            )
        } else {
            grid
        }
    }

    private var grid: some View {
        let items = viewModel.items
        let threshold = max(items.count - columnCount * 2, 0)
        return VStack(spacing: DS.Space.s20) {
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: DS.Space.s24) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    PosterCard(item: item.asMediaItem(), width: itemWidth) {
                        onTap(item)
                    }
                    .onAppear {
                        if index >= threshold {
                            viewModel.loadMore()
                        }
                    }
                }
            }
            .padding(.horizontal, SearchLayout.gutter)

            footer
        }
    }

    @ViewBuilder
    private var footer: some View {
        if viewModel.isLoadingMore {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Space.s12)
        } else if viewModel.loadMoreFailed {
            SearchSectionErrorRow(message: "Couldn't load more titles.") {
                viewModel.retry()
            }
        }
    }

    private var skeletonGrid: some View {
        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: DS.Space.s24) {
            ForEach(0..<(columnCount * 2), id: \.self) { _ in
                VStack(alignment: .leading, spacing: DS.Space.s8) {
                    RoundedRectangle(cornerRadius: DS.Radius.poster, style: .continuous)
                        .fill(theme.surfaceOverlay)
                        .frame(width: itemWidth, height: itemWidth * DS.Layout.posterAspect)
                    RoundedRectangle(cornerRadius: DS.Radius.badge, style: .continuous)
                        .fill(theme.surfaceOverlay)
                        .frame(width: itemWidth * 0.7, height: DS.Space.s12)
                }
            }
        }
        .padding(.horizontal, SearchLayout.gutter)
        .accessibilityLabel(Text("Loading titles"))
    }
}

// MARK: - Filter bar

private struct DiscoverFilterBar: View {
    @ObservedObject var viewModel: DiscoverViewModel

    @Environment(\.flixorTheme) private var theme

    private var filters: DiscoverFilters { viewModel.filters }

    var body: some View {
        SearchChipFlowLayout(spacing: DS.Space.controlGap, lineSpacing: DS.Space.controlGap) {
            SearchSegmentedControl(
                options: DiscoverMediaType.allCases.map { SearchSegmentOption(value: $0, label: $0.label) },
                selection: Binding(
                    get: { viewModel.filters.mediaType },
                    set: { viewModel.setMediaType($0) }
                ),
                accessibilityTitle: "Type"
            )

            DiscoverFilterChip(
                title: "Genre",
                value: filters.genreName ?? "All",
                isActive: filters.genreId != nil
            ) { dismiss in
                DiscoverOptionList(
                    options: [DiscoverOption(value: Int?.none, label: "All Genres")]
                        + viewModel.genres.map { DiscoverOption(value: Optional($0.id), label: $0.name) },
                    selected: filters.genreId,
                    emptyMessage: viewModel.genres.isEmpty ? "Loading genres..." : nil
                ) { id in
                    viewModel.setGenre(id.flatMap { id in viewModel.genres.first { $0.id == id } })
                    dismiss()
                }
            }

            DiscoverFilterChip(
                title: "Sort",
                value: filters.sort.label,
                isActive: filters.sort != .popular
            ) { dismiss in
                DiscoverOptionList(
                    options: DiscoverSortOption.allCases.map { DiscoverOption(value: $0, label: $0.label) },
                    selected: filters.sort
                ) { sort in
                    viewModel.setSort(sort)
                    dismiss()
                }
            }

            DiscoverFilterChip(
                title: "Year",
                value: filters.yearLabel,
                isActive: filters.yearFrom != nil || filters.yearTo != nil
            ) { dismiss in
                DiscoverYearRangePicker(
                    from: filters.yearFrom,
                    to: filters.yearTo,
                    onChange: { viewModel.setYears(from: $0, to: $1) },
                    onDone: dismiss
                )
            }

            DiscoverFilterChip(
                title: "Rating",
                value: filters.ratingLabel,
                isActive: filters.minimumRating != nil
            ) { dismiss in
                DiscoverOptionList(
                    options: [DiscoverOption(value: Double?.none, label: "Any Rating")]
                        + DiscoverViewModel.ratingOptions.map {
                            DiscoverOption(value: Optional($0), label: "\(Int($0))+ stars")
                        },
                    selected: filters.minimumRating
                ) { rating in
                    viewModel.setMinimumRating(rating)
                    dismiss()
                }
            }

            if filters.hasActiveFilters {
                Button(action: { viewModel.resetFilters() }) {
                    HStack(spacing: DS.Space.s4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.flixorIcon(DS.Icon.xs, weight: .semibold))
                        Text("Reset")
                            .flixorFont(.callout, weight: .medium)
                    }
                    .foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, DS.Space.s10)
                    .padding(.vertical, DS.Space.s8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Reset filters"))
            }
        }
    }
}

// MARK: - Segmented control

struct SearchSegmentOption<Value: Hashable>: Identifiable {
    let value: Value
    let label: String
    var id: Value { value }
}

/// Capsule segmented control styled with the theme accent.
struct SearchSegmentedControl<Value: Hashable>: View {
    let options: [SearchSegmentOption<Value>]
    @Binding var selection: Value
    var accessibilityTitle: String

    @Environment(\.flixorTheme) private var theme

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            ForEach(options) { option in
                let isSelected = option.value == selection
                Button {
                    withAnimation(DS.Motion.quick) { selection = option.value }
                } label: {
                    Text(option.label)
                        .flixorFont(.callout, weight: isSelected ? .semibold : .medium)
                        .foregroundStyle(isSelected ? theme.onAccent : theme.textSecondary)
                        .padding(.horizontal, DS.Space.s14)
                        .padding(.vertical, DS.Space.s6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected ? theme.accent : Color.clear)
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(accessibilityTitle): \(option.label)"))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(DS.Space.s2)
        .background(Capsule(style: .continuous).fill(theme.surfaceOverlay))
        .overlay(Capsule(style: .continuous).strokeBorder(theme.separator, lineWidth: DS.Border.thin))
    }
}

// MARK: - Filter chip

/// Capsule button showing "Title: Value" that opens a popover.
private struct DiscoverFilterChip<PopoverContent: View>: View {
    let title: String
    let value: String
    let isActive: Bool
    @ViewBuilder let content: (_ dismiss: @escaping () -> Void) -> PopoverContent

    @Environment(\.flixorTheme) private var theme
    @State private var isPresented = false
    @State private var isHovered = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: DS.Space.s6) {
                Text(title)
                    .flixorFont(.callout)
                    .foregroundStyle(theme.textTertiary)
                Text(value)
                    .flixorFont(.callout, weight: .semibold)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.flixor(.micro, weight: .bold))
                    .foregroundStyle(theme.textTertiary)
            }
            .padding(.horizontal, DS.Space.s12)
            .padding(.vertical, DS.Space.s8)
            .background(
                Capsule(style: .continuous)
                    .fill(isActive ? theme.accentSoft : (isHovered ? theme.hoverFill : theme.surfaceOverlay))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(isActive ? theme.accent.opacity(DS.Opacity.tertiary) : theme.separator,
                                  lineWidth: DS.Border.thin)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DS.Motion.quick) { isHovered = hovering }
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            content { isPresented = false }
        }
        .accessibilityLabel(Text("\(title): \(value)"))
    }
}

// MARK: - Option list

struct DiscoverOption<Value: Hashable>: Identifiable {
    let value: Value
    let label: String
    var id: Value { value }
}

private struct DiscoverOptionList<Value: Hashable>: View {
    let options: [DiscoverOption<Value>]
    let selected: Value
    var emptyMessage: String? = nil
    let onSelect: (Value) -> Void

    @Environment(\.flixorTheme) private var theme

    private static var rowHeight: CGFloat { DS.Space.s32 }
    private static var maxHeight: CGFloat { 360 }

    var body: some View {
        let listHeight = min(CGFloat(options.count) * Self.rowHeight + DS.Space.s8 * 2, Self.maxHeight)
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(options) { option in
                        DiscoverOptionRow(
                            label: option.label,
                            isSelected: option.value == selected,
                            height: Self.rowHeight
                        ) {
                            onSelect(option.value)
                        }
                    }
                }
                .padding(.vertical, DS.Space.s8)
            }
            .frame(height: listHeight)

            if let emptyMessage {
                Text(emptyMessage)
                    .flixorFont(.caption)
                    .foregroundStyle(theme.textTertiary)
                    .padding(.horizontal, DS.Space.s12)
                    .padding(.bottom, DS.Space.s8)
            }
        }
        .frame(width: 240)
    }
}

private struct DiscoverOptionRow: View {
    let label: String
    let isSelected: Bool
    let height: CGFloat
    let action: () -> Void

    @Environment(\.flixorTheme) private var theme
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.controlGap) {
                Image(systemName: "checkmark")
                    .font(.flixorIcon(DS.Icon.xs, weight: .bold))
                    .foregroundStyle(theme.accent)
                    .opacity(isSelected ? 1 : 0)
                Text(label)
                    .flixorFont(.body, weight: isSelected ? .semibold : .regular)
                    .foregroundStyle(theme.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Space.s12)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .fill(isHovered ? theme.hoverFill : Color.clear)
                    .padding(.horizontal, DS.Space.s4)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Year range

private struct DiscoverYearRangePicker: View {
    let from: Int?
    let to: Int?
    let onChange: (Int?, Int?) -> Void
    let onDone: () -> Void

    @Environment(\.flixorTheme) private var theme

    private var years: [Int] {
        Array((DiscoverViewModel.earliestYear...DiscoverViewModel.currentYear).reversed())
    }

    private struct Preset: Identifiable {
        let label: String
        let from: Int?
        let to: Int?
        var id: String { label }
    }

    private var presets: [Preset] {
        let year = DiscoverViewModel.currentYear
        let decade = year - year % 10
        var list: [Preset] = [
            Preset(label: "This Year", from: year, to: year),
            Preset(label: "Last 5 Years", from: year - 4, to: year),
        ]
        for start in stride(from: decade, through: decade - 40, by: -10) {
            list.append(Preset(label: "\(start)s", from: start, to: start + 9))
        }
        list.append(Preset(label: "Before \(decade - 40)", from: nil, to: decade - 41))
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            Text("Release Year")
                .flixorFont(.headline)
                .foregroundStyle(theme.textPrimary)

            HStack(spacing: DS.Space.itemGap) {
                yearPicker(title: "From", selection: Binding(
                    get: { from },
                    set: { onChange($0, to) }
                ))
                yearPicker(title: "To", selection: Binding(
                    get: { to },
                    set: { onChange(from, $0) }
                ))
            }

            SearchChipFlowLayout(spacing: DS.Space.s6, lineSpacing: DS.Space.s6) {
                ForEach(presets) { preset in
                    let isSelected = preset.from == from && preset.to == to
                    Button {
                        onChange(preset.from, preset.to)
                    } label: {
                        Text(preset.label)
                            .flixorFont(.footnote, weight: .medium)
                            .foregroundStyle(isSelected ? theme.onAccent : theme.textSecondary)
                            .padding(.horizontal, DS.Space.s10)
                            .padding(.vertical, DS.Space.s4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isSelected ? theme.accent : theme.hoverFill)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Years: \(preset.label)"))
                }
            }

            HStack {
                Button("Any Year") { onChange(nil, nil) }
                    .disabled(from == nil && to == nil)
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DS.Space.s16)
        .frame(width: 300)
    }

    private func yearPicker(title: String, selection: Binding<Int?>) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            Text(title)
                .flixorFont(.caption, weight: .medium)
                .foregroundStyle(theme.textTertiary)
            Picker(title, selection: selection) {
                Text("Any").tag(Int?.none)
                ForEach(years, id: \.self) { year in
                    Text(String(year)).tag(Optional(year))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .accessibilityLabel(Text("\(title) year"))
        }
    }
}

// MARK: - Empty / error message

private struct DiscoverMessageView: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: () -> Void

    @Environment(\.flixorTheme) private var theme

    var body: some View {
        VStack(spacing: DS.Space.itemGap) {
            Image(systemName: icon)
                .font(.flixorIcon(DS.Icon.huge))
                .foregroundStyle(theme.textTertiary)
            Text(title)
                .flixorFont(.title3)
                .foregroundStyle(theme.textPrimary)
            Text(message)
                .flixorFont(.body)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle {
                Button(action: action) {
                    Text(actionTitle)
                        .flixorFont(.callout, weight: .semibold)
                        .foregroundStyle(theme.onAccent)
                        .padding(.horizontal, DS.Space.s16)
                        .padding(.vertical, DS.Space.s8)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                                .fill(theme.accent)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, DS.Space.s4)
                .accessibilityLabel(Text(actionTitle))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.s64)
        .padding(.horizontal, SearchLayout.gutter)
    }
}
