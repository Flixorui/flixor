//
//  TVLibraryFilterBar.swift
//  FlixorTV
//
//  Filter bar for library with section pills (Phase 1: Section switching only)
//

import SwiftUI

struct TVLibraryFilterBar: View {
    @ObservedObject var viewModel: TVLibraryViewModel
    let showSectionPills: Bool

    @Namespace private var filterNS

    @State private var showGenrePicker = false
    @State private var showYearPicker = false
    @State private var showSortPicker = false

    var body: some View {
        VStack(spacing: 16) {
            // Row 1: Section pills (horizontal scroll) - only when not navigating from tabs
            if showSectionPills && !viewModel.sections.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.sections) { section in
                            SectionPill(
                                section: section,
                                isActive: viewModel.activeSection?.id == section.id
                            )
                            .onTapGesture {
                                viewModel.selectSection(section)
                            }
                        }
                    }
                    .padding(.horizontal, 60)
                    .padding(.vertical, 2)
                }
                .frame(height: 70)
                .focusSection()
            }

            // Row 2: Filter buttons
            HStack(spacing: 24) {
                // Genre filter
                FilterButton(
                    title: "Genre",
                    value: viewModel.selectedGenre?.label ?? "All"
                )
                .onTapGesture {
                    showGenrePicker = true
                }

                // Year filter
                FilterButton(
                    title: "Year",
                    value: viewModel.selectedYear?.label ?? "All"
                )
                .onTapGesture {
                    showYearPicker = true
                }

                Spacer()

                // Sort menu
                FilterButton(
                    title: "Sort",
                    value: viewModel.sort.label
                )
                .onTapGesture {
                    showSortPicker = true
                }

                // Clear filters (only show if filters are active)
                if viewModel.selectedGenre != nil || viewModel.selectedYear != nil {
                    FilterButton(
                        title: "Clear",
                        value: nil
                    )
                    .onTapGesture {
                        viewModel.clearFilters()
                    }
                }
            }
            .padding(.horizontal, 60)
            .focusSection()
        }
        .padding(.top, showSectionPills ? 32 : 48)
        .padding(.bottom, 16)
        .sheet(isPresented: $showGenrePicker) {
            GenrePickerSheet(
                genres: viewModel.genres,
                selected: viewModel.selectedGenre,
                onSelect: { genre in
                    print("🎬 [FilterBar] Genre selected in sheet: \(genre?.label ?? "All")")
                    viewModel.updateGenre(genre)
                    showGenrePicker = false
                }
            )
        }
        .sheet(isPresented: $showYearPicker) {
            YearPickerSheet(
                years: viewModel.years,
                selected: viewModel.selectedYear,
                onSelect: { year in
                    viewModel.updateYear(year)
                    showYearPicker = false
                }
            )
        }
        .sheet(isPresented: $showSortPicker) {
            SortPickerSheet(
                options: TVLibraryViewModel.SortOption.allCases,
                selected: viewModel.sort,
                onSelect: { sort in
                    viewModel.sort = sort
                    showSortPicker = false
                }
            )
        }
    }
}

// MARK: - Section Pill Component

private struct SectionPill: View {
    let section: TVLibraryViewModel.LibrarySectionSummary
    let isActive: Bool

    @State private var isFocused: Bool = false

    var body: some View {
        Text(section.title.uppercased())
            .font(.system(size: 22, weight: .semibold))
            .kerning(1.2)
            .foregroundStyle(textColor)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(strokeColor, lineWidth: strokeWidth)
            )
            .focusable(true) { focused in
                isFocused = focused
            }
            .scaleEffect(isFocused ? 1.08 : 1.0)
            .shadow(color: .black.opacity(isFocused ? 0.4 : 0.2), radius: isFocused ? 16 : 8, y: isFocused ? 8 : 4)
            .animation(.easeOut(duration: UX.focusDur), value: isFocused)
    }

    private var textColor: Color {
        if isActive {
            return .black
        } else {
            return .white.opacity(isFocused ? 1.0 : 0.9)
        }
    }

    private var backgroundColor: Color {
        if isActive {
            return .white
        } else if isFocused {
            return Color.white.opacity(0.35)
        } else {
            return Color.white.opacity(0.10)
        }
    }

    private var strokeColor: Color {
        if isActive {
            return .clear
        } else if isFocused {
            return Color.white.opacity(0.5)
        } else {
            return Color.white.opacity(0.2)
        }
    }

    private var strokeWidth: CGFloat {
        if isActive {
            return 0
        } else if isFocused {
            return 2
        } else {
            return 1
        }
    }
}

// MARK: - Filter Button Component

private struct FilterButton: View {
    let title: String
    let value: String?

    @State private var isFocused: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(titleColor)

            if let value = value {
                Text(value)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(valueColor)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(strokeColor, lineWidth: strokeWidth)
        )
        .focusable(true) { focused in
            isFocused = focused
        }
        .scaleEffect(isFocused ? 1.06 : 1.0)
        .shadow(color: .black.opacity(isFocused ? 0.35 : 0.0), radius: isFocused ? 12 : 0, y: isFocused ? 6 : 0)
        .animation(.easeOut(duration: UX.focusDur), value: isFocused)
    }

    private var backgroundColor: Color {
        isFocused ? Color.white.opacity(0.30) : Color.white.opacity(0.10)
    }

    private var strokeColor: Color {
        isFocused ? Color.white.opacity(0.4) : Color.clear
    }

    private var strokeWidth: CGFloat {
        isFocused ? 2 : 0
    }

    private var titleColor: Color {
        isFocused ? Color.white.opacity(0.85) : Color.white.opacity(0.6)
    }

    private var valueColor: Color {
        isFocused ? Color.white : Color.white.opacity(0.9)
    }
}

// MARK: - Genre Picker Sheet

private struct GenrePickerSheet: View {
    let genres: [TVLibraryViewModel.FilterOption]
    let selected: TVLibraryViewModel.FilterOption?
    let onSelect: (TVLibraryViewModel.FilterOption?) -> Void

    var body: some View {
        NavigationView {
            List {
                // "All" option
                Button {
                    print("🔘 [GenrePicker] 'All Genres' button tapped")
                    onSelect(nil)
                } label: {
                    HStack {
                        Text("All Genres")
                            .foregroundStyle(.white)
                        Spacer()
                        if selected == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)

                // Genre options
                ForEach(genres) { genre in
                    Button {
                        print("🔘 [GenrePicker] '\(genre.label)' button tapped")
                        onSelect(genre)
                    } label: {
                        HStack {
                            Text(genre.label)
                                .foregroundStyle(.white)
                            Spacer()
                            if selected?.id == genre.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Filter by Genre")
        }
    }
}

// MARK: - Year Picker Sheet

private struct YearPickerSheet: View {
    let years: [TVLibraryViewModel.FilterOption]
    let selected: TVLibraryViewModel.FilterOption?
    let onSelect: (TVLibraryViewModel.FilterOption?) -> Void

    var body: some View {
        NavigationView {
            List {
                // "All" option
                Button {
                    onSelect(nil)
                } label: {
                    HStack {
                        Text("All Years")
                            .foregroundStyle(.white)
                        Spacer()
                        if selected == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)

                // Year options
                ForEach(years) { year in
                    Button {
                        onSelect(year)
                    } label: {
                        HStack {
                            Text(year.label)
                                .foregroundStyle(.white)
                            Spacer()
                            if selected?.id == year.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Filter by Year")
        }
    }
}

// MARK: - Sort Picker Sheet

private struct SortPickerSheet: View {
    let options: [TVLibraryViewModel.SortOption]
    let selected: TVLibraryViewModel.SortOption
    let onSelect: (TVLibraryViewModel.SortOption) -> Void

    var body: some View {
        NavigationView {
            List {
                ForEach(options) { option in
                    Button {
                        onSelect(option)
                    } label: {
                        HStack {
                            Text(option.label)
                                .foregroundStyle(.white)
                            Spacer()
                            if selected.id == option.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Sort By")
        }
    }
}
