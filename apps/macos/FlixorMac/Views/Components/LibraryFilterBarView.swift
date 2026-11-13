//
//  LibraryFilterBarView.swift
//  FlixorMac
//
//  The Library header (design C): the section names are the title, with the
//  count beside the current one; search, Year, Sort and the view toggle on the
//  right; and a row of one-click genre chips with the rest under "More".
//  Shown as an inset the grid scrolls under.
//

import SwiftUI
import AppKit

struct LibraryFilterBarView: View {
    @ObservedObject var viewModel: LibraryViewModel
    var onSelectSection: (LibraryViewModel.LibrarySectionSummary) -> Void

    @Environment(\.flixorTheme) private var theme
    @ObservedObject private var librarySettings = LibraryScreenSettings.shared
    @ObservedObject private var myblurayStore = MyBluraySettingsStore.shared
    @ObservedObject private var physicalStore = PhysicalCollectionStore.shared
    @FocusState private var searchFocused: Bool
    @State private var searchOpen = false
    @State private var chipRowWidth: CGFloat = 900
    @State private var physicalSearchOpen = false

    private enum Destination: Hashable {
        case section(String)
        case collections
        case physical
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s12) {
            HStack(alignment: .center, spacing: DS.Space.s10) {
                tabs
                Spacer(minLength: DS.Space.s16)
                if viewModel.contentTab == .library {
                    searchControl
                    if !librarySettings.showGenreChips && !viewModel.genres.isEmpty { genreMenu }
                    if !viewModel.years.isEmpty { yearMenu }
                    sortMenu
                    FlixorSegmentedControl(
                        items: [
                            .init(value: LibraryViewModel.ViewMode.grid, systemImage: "square.grid.2x2", help: String(localized: "Grid")),
                            .init(value: LibraryViewModel.ViewMode.list, systemImage: "list.bullet", help: String(localized: "List")),
                        ],
                        selection: $viewModel.viewMode
                    )
                } else if viewModel.contentTab == .physical && physicalStore.isConnected {
                    physicalControls
                }
            }
            .frame(minHeight: 36)

            if viewModel.contentTab == .library && librarySettings.showGenreChips && !viewModel.genres.isEmpty {
                genreChips
            } else if viewModel.contentTab == .physical && physicalStore.isConnected {
                physicalListChips
            }
        }
        .padding(.horizontal, DS.Space.s64)
        .padding(.top, DS.Space.s8)
        .padding(.bottom, DS.Space.s14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                theme.background.opacity(0.72)
            }
            .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.separator).frame(height: DS.Border.hairline)
        }
        .animation(DS.Motion.standard, value: searchOpen)
        .onChange(of: viewModel.contentTab) { _ in closeSearchIfEmpty() }
        // Learn early whether the Physical tab has anything to show.
        .task(id: myblurayStore.isOn(.librarySection)) {
            if myblurayStore.isOn(.librarySection) { await physicalStore.load() }
        }
    }

    // MARK: Tabs as the title

    /// Plex sections in the order chosen in Settings > Library Screen, then Collections (unless hidden).
    private var destinations: [(Destination, String)] {
        let sections = librarySettings.ordered(viewModel.sections) { $0.id }
            .map { (Destination.section($0.id), $0.title) }
        let showCollections = librarySettings.showCollectionsTab || viewModel.contentTab == .collections
        // Hidden once the key turns out to have no Blu-ray.com login, unless it's the open tab.
        let showPhysical = myblurayStore.isOn(.librarySection)
            && (physicalStore.phase != .notConnected || viewModel.contentTab == .physical)
        return sections
            + (showCollections ? [(.collections, String(localized: "Collections"))] : [])
            + (showPhysical ? [(.physical, String(localized: "Physical"))] : [])
    }

    private var currentDestination: Destination {
        if viewModel.contentTab == .collections { return .collections }
        if viewModel.contentTab == .physical { return .physical }
        return .section(viewModel.activeSection?.id ?? viewModel.sections.first?.id ?? "")
    }

    private var tabs: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s20) {
            ForEach(destinations, id: \.0) { destination, title in
                let selected = destination == currentDestination
                // While searching, only the current section stays, so the count reads as results.
                if selected || !isSearching {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s8) {
                        LibraryTitleTab(title: title, selected: selected) { select(destination) }
                        if selected, let count = countText {
                            Text(count)
                                .flixorFont(.callout)
                                .foregroundStyle(theme.textTertiary)
                                .monospacedDigit()
                                .transition(.opacity)
                        }
                    }
                }
            }
        }
    }

    private var countText: String? {
        if viewModel.contentTab == .collections {
            return viewModel.collections.isEmpty ? nil : "\(viewModel.collections.count)"
        }
        if viewModel.contentTab == .physical {
            return physicalStore.entries.isEmpty ? nil : physicalStore.shown.count.formatted()
        }
        return viewModel.activeTotal.map { $0.formatted() }
    }

    private func select(_ destination: Destination) {
        switch destination {
        case .collections:
            viewModel.contentTab = .collections
        case .physical:
            viewModel.contentTab = .physical
        case .section(let id):
            viewModel.contentTab = .library
            if let section = viewModel.sections.first(where: { $0.id == id }) { onSelectSection(section) }
        }
    }

    // MARK: Physical (MyBluray collection)

    private var physicalControls: some View {
        HStack(spacing: DS.Space.s10) {
            BrowseSearchField(text: $physicalStore.query, placeholder: String(localized: "Search your discs"),
                              isOpen: $physicalSearchOpen)
            LibraryPillMenu(label: nil, value: physicalStore.format.title, isActive: physicalStore.format != .all) {
                ForEach(PhysicalCollectionStore.FormatFilter.allCases) { option in
                    Button { physicalStore.format = option } label: {
                        checkLabel(option.title, checked: physicalStore.format == option)
                    }
                }
            }
            LibraryPillMenu(label: nil, value: physicalStore.sort.shortTitle, systemImage: "arrow.up.arrow.down", isActive: false) {
                Section("Sort by") {
                    ForEach(PhysicalCollectionStore.Sort.allCases) { option in
                        Button { physicalStore.sort = option } label: {
                            checkLabel(option.title, checked: physicalStore.sort == option)
                        }
                    }
                }
                Divider()
                Button {
                    Task { await physicalStore.load(force: true) }
                } label: {
                    Label("Refresh from Blu-ray.com", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private var physicalListChips: some View {
        HStack(spacing: DS.Space.s8) {
            ForEach(physicalStore.listsInUse, id: \.list.id) { item in
                LibraryCountChip(title: item.list.name ?? item.list.id, count: item.count,
                                 selected: physicalStore.listFilter == item.list.id) {
                    physicalStore.listFilter = item.list.id
                }
            }
            LibraryCountChip(title: String(localized: "All"), count: physicalStore.entries.count,
                             selected: physicalStore.listFilter == nil) {
                physicalStore.listFilter = nil
            }
            Spacer(minLength: 0)
        }
        .frame(height: 28)
    }

    // MARK: Search

    private var isSearching: Bool { searchOpen || !viewModel.searchQuery.isEmpty }

    @ViewBuilder
    private var searchControl: some View {
        if isSearching {
            HStack(spacing: DS.Space.s8) {
                Image(systemName: "magnifyingglass").font(.flixorIcon(DS.Icon.sm)).foregroundStyle(theme.textTertiary)
                ZStack(alignment: .leading) {
                    if viewModel.searchQuery.isEmpty {
                        Text("Search \(currentTitle.lowercased())").flixorFont(.callout).foregroundStyle(theme.textTertiary)
                            .allowsHitTesting(false)
                    }
                    TextField("", text: $viewModel.searchQuery)
                        .textFieldStyle(.plain)
                        .flixorFont(.callout)
                        .foregroundStyle(theme.textPrimary)
                        .focused($searchFocused)
                        .onExitCommand { closeSearch() }
                        .onSubmit { searchFocused = false }
                }
                Button { closeSearch() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(theme.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Close search")
            }
            .padding(.horizontal, DS.Space.s14)
            .frame(minWidth: 220, idealWidth: 320, maxWidth: 360)
            .frame(height: 32)
            .background(Capsule().fill(theme.hoverFill))
            .overlay(Capsule().strokeBorder(searchFocused ? Color.white.opacity(0.35) : theme.separator, lineWidth: DS.Border.thin))
            .transition(.opacity.combined(with: .move(edge: .trailing)))
            .onAppear { searchFocused = true }
        } else {
            Button { searchOpen = true } label: {
                Image(systemName: "magnifyingglass")
                    .font(.flixorIcon(DS.Icon.sm, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(theme.hoverFill))
                    .overlay(Circle().strokeBorder(theme.separator, lineWidth: DS.Border.thin))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Search")
        }
    }

    private var currentTitle: String {
        viewModel.activeSection?.title ?? String(localized: "Library")
    }

    private func closeSearch() {
        viewModel.searchQuery = ""
        searchFocused = false
        searchOpen = false
    }

    private func closeSearchIfEmpty() {
        if viewModel.searchQuery.isEmpty { searchOpen = false }
    }

    // MARK: Genre (as a menu when the chip row is turned off)

    private var genreMenu: some View {
        LibraryPillMenu(label: "Genre", value: viewModel.selectedGenre?.label ?? String(localized: "All"),
                        isActive: viewModel.selectedGenre != nil) {
            Button { viewModel.updateGenre(nil) } label: { checkLabel("All genres", checked: viewModel.selectedGenre == nil) }
            Divider()
            ForEach(viewModel.genres) { genre in
                Button { viewModel.updateGenre(genre) } label: {
                    checkLabel(genre.label, checked: viewModel.selectedGenre?.id == genre.id)
                }
            }
        }
    }

    // MARK: Year (decades with their years)

    private var yearMenu: some View {
        LibraryPillMenu(
            label: "Year",
            value: yearValue,
            isActive: viewModel.selectedYear != nil || viewModel.selectedDecade != nil
        ) {
            Button { viewModel.updateYear(nil); viewModel.updateDecade(nil) } label: {
                checkLabel("Any year", checked: viewModel.selectedYear == nil && viewModel.selectedDecade == nil)
            }
            Divider()
            Section("Decades") {
                ForEach(viewModel.decades, id: \.self) { decade in
                    Menu {
                        Button { viewModel.updateDecade(decade) } label: {
                            checkLabel("All of the \(decadeTitle(decade))", checked: viewModel.selectedDecade == decade)
                        }
                        Divider()
                        ForEach(viewModel.years(inDecade: decade)) { year in
                            Button { viewModel.updateYear(year) } label: {
                                checkLabel(year.label, checked: viewModel.selectedYear?.id == year.id)
                            }
                        }
                    } label: {
                        checkLabel(decadeTitle(decade), checked: isInDecade(decade))
                    }
                }
            }
        }
    }

    private var yearValue: String {
        if let year = viewModel.selectedYear { return year.label }
        if let decade = viewModel.selectedDecade { return decadeTitle(decade) }
        return String(localized: "Any")
    }

    private func decadeTitle(_ decade: Int) -> String { "\(decade)s" }

    private func isInDecade(_ decade: Int) -> Bool {
        if viewModel.selectedDecade == decade { return true }
        if let year = viewModel.selectedYear.flatMap({ Int($0.value) }) { return year / 10 * 10 == decade }
        return false
    }

    // MARK: Sort (field, then order)

    private var sortMenu: some View {
        LibraryPillMenu(label: nil, value: LibrarySortField.shortLabel(viewModel.sort), systemImage: "arrow.up.arrow.down", isActive: false) {
            Section("Sort by") {
                ForEach(LibrarySortField.allCases) { field in
                    Button { viewModel.sort = field.option(descending: field.defaultDescending) } label: {
                        checkLabel(field.title, checked: LibrarySortField(viewModel.sort) == field)
                    }
                }
            }
            Divider()
            Section("Order") {
                let field = LibrarySortField(viewModel.sort)
                ForEach([true, false], id: \.self) { descending in
                    Button { viewModel.sort = field.option(descending: descending) } label: {
                        checkLabel(field.orderTitle(descending: descending), checked: LibrarySortField.isDescending(viewModel.sort) == descending)
                    }
                }
            }
        }
    }

    // MARK: Genre chips

    private var genreChips: some View {
        let layout = chipLayout()
        return HStack(spacing: DS.Space.s8) {
            LibraryGenreChip(title: String(localized: "All"), selected: viewModel.selectedGenre == nil) {
                viewModel.updateGenre(nil)
            }
            ForEach(layout.visible) { genre in
                LibraryGenreChip(title: genre.label, selected: viewModel.selectedGenre?.id == genre.id) {
                    viewModel.updateGenre(viewModel.selectedGenre?.id == genre.id ? nil : genre)
                }
            }
            if !layout.overflow.isEmpty {
                Menu {
                    ForEach(layout.overflow) { genre in
                        Button { viewModel.updateGenre(genre) } label: {
                            checkLabel(genre.label, checked: viewModel.selectedGenre?.id == genre.id)
                        }
                    }
                } label: {
                    LibraryGenreChipLabel(title: String(localized: "More"), selected: false, showsChevron: true)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            Spacer(minLength: 0)
        }
        .frame(height: 28)
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { chipRowWidth = proxy.size.width }
                .onChange(of: proxy.size.width) { chipRowWidth = $0 }
        })
    }

    /// Which genres fit on one line; the rest go under More. A selected genre
    /// from More is always shown in the row so the active filter stays visible.
    private func chipLayout() -> (visible: [LibraryViewModel.FilterOption], overflow: [LibraryViewModel.FilterOption]) {
        let font = NSFont.systemFont(ofSize: FlixorType.footnote.size, weight: .semibold)
        func width(_ text: String) -> CGFloat {
            ceil((text as NSString).size(withAttributes: [.font: font]).width) + DS.Space.s12 * 2 + DS.Border.thin * 2
        }
        let spacing = DS.Space.s8
        let moreWidth = width(String(localized: "More")) + 14 + spacing
        var used = width(String(localized: "All")) + spacing
        var visible: [LibraryViewModel.FilterOption] = []
        let all = viewModel.genres
        for (index, genre) in all.enumerated() {
            let needed = width(genre.label) + spacing
            let isLast = index == all.count - 1
            if used + needed + (isLast ? 0 : moreWidth) <= chipRowWidth {
                visible.append(genre)
                used += needed
            } else {
                break
            }
        }
        var overflow = Array(all.dropFirst(visible.count))
        if let selected = viewModel.selectedGenre, let i = overflow.firstIndex(where: { $0.id == selected.id }) {
            overflow.remove(at: i)
            if let last = visible.popLast() { overflow.insert(last, at: 0) }
            visible.append(selected)
        }
        return (visible, overflow)
    }

    @ViewBuilder
    private func checkLabel(_ title: String, checked: Bool) -> some View {
        if checked { Label(title, systemImage: "checkmark") } else { Text(title) }
    }
}

// MARK: - Pieces (shared by Library, My List and Downloads)

/// Search that sits as a round button and expands into a field (Library header style).
struct BrowseSearchField: View {
    @Binding var text: String
    let placeholder: String
    @Binding var isOpen: Bool

    @FocusState private var focused: Bool
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        if isOpen || !text.isEmpty {
            HStack(spacing: DS.Space.s8) {
                Image(systemName: "magnifyingglass").font(.flixorIcon(DS.Icon.sm)).foregroundStyle(theme.textTertiary)
                ZStack(alignment: .leading) {
                    if text.isEmpty {
                        Text(placeholder).flixorFont(.callout).foregroundStyle(theme.textTertiary).allowsHitTesting(false)
                    }
                    TextField("", text: $text)
                        .textFieldStyle(.plain)
                        .flixorFont(.callout)
                        .foregroundStyle(theme.textPrimary)
                        .focused($focused)
                        .onExitCommand { close() }
                        .onSubmit { focused = false }
                }
                Button { close() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(theme.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Close search")
            }
            .padding(.horizontal, DS.Space.s14)
            .frame(minWidth: 220, idealWidth: 300, maxWidth: 340)
            .frame(height: 32)
            .background(Capsule().fill(theme.hoverFill))
            .overlay(Capsule().strokeBorder(focused ? Color.white.opacity(0.35) : theme.separator, lineWidth: DS.Border.thin))
            .transition(.opacity.combined(with: .move(edge: .trailing)))
            .onAppear { focused = true }
        } else {
            BrowseCircleButton(systemImage: "magnifyingglass", help: String(localized: "Search")) { isOpen = true }
        }
    }

    private func close() {
        text = ""
        focused = false
        isOpen = false
    }
}

/// 32pt round grey button used in the browse headers (search, new list).
struct BrowseCircleButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.flixorIcon(DS.Icon.sm, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(hovering ? theme.pressedFill : theme.hoverFill))
                .overlay(Circle().strokeBorder(theme.separator, lineWidth: DS.Border.thin))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Grey capsule button ("Select", "Show in Finder"); `destructive` gives red text.
struct BrowsePillButton: View {
    let title: String
    var systemImage: String? = nil
    var destructive = false
    var prominent = false
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s6) {
                if let systemImage { Image(systemName: systemImage).font(.flixorIcon(DS.Icon.xs, weight: .semibold)) }
                Text(title).flixorFont(.callout, weight: .semibold).lineLimit(1)
            }
            .foregroundStyle(prominent ? Color.black : (destructive ? SettingsChrome.destructive : theme.textPrimary))
            .padding(.horizontal, DS.Space.s14)
            .frame(height: 32)
            .background(Capsule().fill(prominent ? Color.white.opacity(hovering ? 0.88 : 1) : (hovering ? theme.pressedFill : theme.hoverFill)))
            .overlay(Capsule().strokeBorder(prominent ? Color.clear : theme.separator, lineWidth: DS.Border.thin))
            .contentShape(Capsule())
            .fixedSize()
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// The frosted header inset the grid scrolls under (Library, My List, Downloads).
struct BrowseHeaderInset: ViewModifier {
    @Environment(\.flixorTheme) private var theme

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, DS.Space.s64)
            .padding(.top, DS.Space.s8)
            .padding(.bottom, DS.Space.s14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    theme.background.opacity(0.72)
                }
                .ignoresSafeArea(edges: .top)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.separator).frame(height: DS.Border.hairline)
            }
    }
}

extension View {
    func browseHeaderInset() -> some View { modifier(BrowseHeaderInset()) }
}

/// Grey count after the current title tab ("53").
struct BrowseTabCount: View {
    let text: String
    @Environment(\.flixorTheme) private var theme
    var body: some View {
        Text(text).flixorFont(.callout).foregroundStyle(theme.textTertiary).monospacedDigit()
    }
}

/// A chip with an optional count: "Movies 38".
struct BrowseCountChip: View {
    let title: String
    var count: Int? = nil
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            LibraryGenreChipLabel(title: count.map { "\(title)  \($0)" } ?? title, selected: selected, showsChevron: false)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}


/// A section name used as the page title: large white when current, dim otherwise.
struct LibraryTitleTab: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        Button(action: action) {
            Text(title)
                .flixorFont(.title1, weight: .heavy)
                .foregroundStyle(selected ? theme.textPrimary : Color.white.opacity(hovering ? 0.6 : 0.35))
                .lineLimit(1)
                .fixedSize()
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Grey capsule menu: "Year  2015 ⌄" or "⇅ Newest added ⌄".
struct LibraryPillMenu<Content: View>: View {
    let label: String?
    let value: String
    var systemImage: String? = nil
    let isActive: Bool
    @ViewBuilder let content: () -> Content
    @State private var hovering = false
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        Menu(content: content) {
            HStack(spacing: DS.Space.s6) {
                if isActive { Circle().fill(theme.accent).frame(width: 6, height: 6) }
                if let systemImage {
                    Image(systemName: systemImage).font(.flixorIcon(DS.Icon.xs, weight: .semibold)).foregroundStyle(theme.textSecondary)
                }
                if let label { Text(label).flixorFont(.callout).foregroundStyle(theme.textTertiary) }
                Text(value).flixorFont(.callout, weight: .semibold).foregroundStyle(theme.textPrimary).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(theme.textTertiary)
            }
            .padding(.horizontal, DS.Space.s14)
            .frame(height: 32)
            .background(Capsule().fill(hovering ? theme.pressedFill : theme.hoverFill))
            .overlay(Capsule().strokeBorder(theme.separator, lineWidth: DS.Border.thin))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
    }
}

struct LibraryGenreChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) { LibraryGenreChipLabel(title: title, selected: selected, showsChevron: false) }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A genre-style chip with a count: "Owned 876".
struct LibraryCountChip: View {
    let title: String
    let count: Int
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s6) {
                Text(title).flixorFont(.footnote, weight: .semibold).lineLimit(1)
                Text(count.formatted())
                    .flixorFont(.caption, weight: .medium)
                    .monospacedDigit()
                    .foregroundStyle(selected ? Color.black.opacity(0.55) : theme.textTertiary)
            }
            .foregroundStyle(selected ? Color.black : theme.textSecondary)
            .padding(.horizontal, DS.Space.s12)
            .frame(height: 28)
            .background(Capsule().fill(selected ? Color.white : (hovering ? theme.pressedFill : theme.surfaceOverlay)))
            .overlay(Capsule().strokeBorder(selected ? Color.clear : theme.separator, lineWidth: DS.Border.thin))
            .contentShape(Capsule())
            .fixedSize()
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

struct LibraryGenreChipLabel: View {
    let title: String
    let selected: Bool
    let showsChevron: Bool
    @State private var hovering = false
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            Text(title).flixorFont(.footnote, weight: .semibold).lineLimit(1)
            if showsChevron { Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)) }
        }
        .foregroundStyle(selected ? Color.black : theme.textSecondary)
        .padding(.horizontal, DS.Space.s12)
        .frame(height: 28)
        .background(Capsule().fill(selected ? Color.white : (hovering ? theme.pressedFill : theme.surfaceOverlay)))
        .overlay(Capsule().strokeBorder(selected ? Color.clear : theme.separator, lineWidth: DS.Border.thin))
        .contentShape(Capsule())
        .fixedSize()
        .onHover { hovering = $0 }
    }
}

/// The library's eight sorts as a field plus a direction.
enum LibrarySortField: CaseIterable, Identifiable {
    case dateAdded, title, year, rating
    var id: Self { self }

    init(_ option: LibraryViewModel.SortOption) {
        switch option {
        case .dateAddedDesc, .dateAddedAsc: self = .dateAdded
        case .titleAsc, .titleDesc: self = .title
        case .yearDesc, .yearAsc: self = .year
        case .ratingDesc, .ratingAsc: self = .rating
        }
    }

    static func isDescending(_ option: LibraryViewModel.SortOption) -> Bool {
        switch option {
        case .dateAddedDesc, .titleDesc, .yearDesc, .ratingDesc: return true
        default: return false
        }
    }

    var title: String {
        switch self {
        case .dateAdded: return String(localized: "Date added")
        case .title: return String(localized: "Title")
        case .year: return String(localized: "Release year")
        case .rating: return String(localized: "Rating")
        }
    }

    /// Title reads A–Z by default; the others newest/highest first.
    var defaultDescending: Bool { self != .title }

    func option(descending: Bool) -> LibraryViewModel.SortOption {
        switch self {
        case .dateAdded: return descending ? .dateAddedDesc : .dateAddedAsc
        case .title: return descending ? .titleDesc : .titleAsc
        case .year: return descending ? .yearDesc : .yearAsc
        case .rating: return descending ? .ratingDesc : .ratingAsc
        }
    }

    func orderTitle(descending: Bool) -> String {
        switch self {
        case .dateAdded, .year: return descending ? String(localized: "Newest first") : String(localized: "Oldest first")
        case .title: return descending ? String(localized: "Z to A") : String(localized: "A to Z")
        case .rating: return descending ? String(localized: "Highest first") : String(localized: "Lowest first")
        }
    }

    /// What the sort pill shows.
    static func shortLabel(_ option: LibraryViewModel.SortOption) -> String {
        switch option {
        case .dateAddedDesc: return String(localized: "Newest added")
        case .dateAddedAsc: return String(localized: "Oldest added")
        case .titleAsc: return String(localized: "Title A–Z")
        case .titleDesc: return String(localized: "Title Z–A")
        case .yearDesc: return String(localized: "Newest releases")
        case .yearAsc: return String(localized: "Oldest releases")
        case .ratingDesc: return String(localized: "Top rated")
        case .ratingAsc: return String(localized: "Lowest rated")
        }
    }
}
