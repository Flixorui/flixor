//
//  LibraryScreenSettingsView.swift
//  FlixorMac
//
//  Settings > Library Screen: a live preview, then grid appearance, the
//  header's genre chips, tab order and default tab, and what the Library
//  remembers. Values live in LibraryScreenSettings (per profile).
//

import SwiftUI
import UniformTypeIdentifiers

struct LibraryScreenSettingsView: View {
    @ObservedObject private var settings = LibraryScreenSettings.shared
    @ObservedObject private var profileSettings = ProfileSettings.shared
    @State private var showPreview = true
    @State private var libraries: [LibraryTab] = []
    @State private var draggingId: String?

    struct LibraryTab: Identifiable, Equatable {
        let id: String
        let title: String
        let type: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sectionGap) {
            CollapsiblePreviewSection(title: "Library Preview", isExpanded: $showPreview) {
                LibraryScreenPreview(
                    tabs: orderedLibraries.map(\.title),
                    showCollections: settings.showCollectionsTab,
                    showGenreChips: settings.showGenreChips,
                    posterSize: settings.posterSize.resolved(homeSize: profileSettings.posterSize),
                    density: settings.density,
                    titles: settings.titleDisplay
                )
            }

            VStack(alignment: .leading, spacing: DS.Space.controlGap) {
                SettingsSectionHeader(title: "Grid")
                SettingsGroupCard {
                    SettingsRow(icon: "arrow.up.left.and.arrow.down.right", iconColor: .green, title: "Poster Size",
                                subtitle: "\"Same as Home\" follows Home Screen > Card Poster Size") {
                        Picker("", selection: $settings.posterSize) {
                            ForEach(LibraryPosterSize.allCases) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden().frame(width: 160)
                    }
                    SettingsRow(icon: "square.grid.3x3", iconColor: .blue, title: "Spacing") {
                        Picker("", selection: $settings.density) {
                            ForEach(LibraryGridDensity.allCases) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 200)
                    }
                    SettingsRow(icon: "textformat", iconColor: .purple, title: "Under Posters", showDivider: false) {
                        Picker("", selection: $settings.titleDisplay) {
                            ForEach(LibraryTitleDisplay.allCases) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden().frame(width: 160)
                    }
                }
            }

            VStack(alignment: .leading, spacing: DS.Space.controlGap) {
                SettingsSectionHeader(title: "Header")
                SettingsGroupCard {
                    SettingsRow(icon: "tag", iconColor: .orange, title: "Genre Chips",
                                subtitle: "One-click genres under the title. When off, Genre is a menu next to Year.",
                                showDivider: false) {
                        Toggle("", isOn: $settings.showGenreChips).labelsHidden()
                    }
                }
            }

            tabsSection

            VStack(alignment: .leading, spacing: DS.Space.controlGap) {
                SettingsSectionHeader(title: "Remember")
                SettingsGroupCard {
                    SettingsRow(icon: "square.grid.2x2", iconColor: .teal, title: "Grid or List View",
                                subtitle: "Reopen in the view you used last") {
                        Toggle("", isOn: $settings.rememberViewMode).labelsHidden()
                    }
                    SettingsRow(icon: "arrow.up.arrow.down", iconColor: .indigo, title: "Sort for Each Library",
                                subtitle: "e.g. Movies by newest added, TV Shows by title") {
                        Toggle("", isOn: $settings.rememberSort).labelsHidden()
                    }
                    SettingsRow(icon: "line.3.horizontal.decrease.circle", iconColor: .pink, title: "Filters for Each Library",
                                subtitle: "Keep the selected genre and year when you come back", showDivider: false) {
                        Toggle("", isOn: $settings.rememberFilters).labelsHidden()
                    }
                }
            }

            HStack {
                Spacer()
                Button("Reset Library Screen to Defaults") {
                    withAnimation(DS.Motion.standard) { settings.resetToDefaults() }
                }
                .controlSize(.small)
            }
        }
        .task { await loadLibraries() }
    }

    // MARK: Tabs

    private var orderedLibraries: [LibraryTab] {
        settings.ordered(libraries) { $0.id }
    }

    private var tabsSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.controlGap) {
            SettingsSectionHeader(title: "Tabs")
            SettingsGroupCard {
                if libraries.isEmpty {
                    SettingsRow(icon: "server.rack", iconColor: .gray, title: "No Plex libraries",
                                subtitle: "Connect a Plex server to arrange the Library tabs.")
                }
                ForEach(Array(orderedLibraries.enumerated()), id: \.element.id) { index, library in
                    tabRow(library, index: index)
                        .onDrag {
                            draggingId = library.id
                            return NSItemProvider(object: library.id as NSString)
                        }
                        .onDrop(of: [UTType.text], delegate: LibraryTabDropDelegate(
                            target: library.id, dragging: $draggingId, settings: settings,
                            currentIds: orderedLibraries.map(\.id)))
                }
                SettingsRow(icon: "square.stack.3d.up", iconColor: .gray, title: "Collections Tab",
                            subtitle: "Shown after your libraries") {
                    Toggle("", isOn: $settings.showCollectionsTab).labelsHidden()
                }
                SettingsRow(icon: "flag", iconColor: .green, title: "Open Library On", showDivider: false) {
                    Picker("", selection: $settings.defaultTab) {
                        Text("Last used").tag(LibraryScreenSettings.lastUsedTab)
                        Divider()
                        ForEach(orderedLibraries) { library in
                            Text(library.title).tag(LibraryScreenSettings.sectionTab(library.id))
                        }
                        if settings.showCollectionsTab {
                            Text("Collections").tag(LibraryScreenSettings.collectionsTab)
                        }
                    }
                    .labelsHidden().frame(width: 160)
                }
            }
            Text("Drag libraries to reorder the tabs. Which libraries appear at all is set in Catalogs.")
                .font(.flixor(.caption))
                .foregroundStyle(.secondary)
                .padding(.horizontal, DS.Space.s4)
        }
    }

    private func tabRow(_ library: LibraryTab, index: Int) -> some View {
        HStack(spacing: 0) {
            Image(systemName: "line.3.horizontal")
                .font(.flixorIcon(DS.Icon.xs, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: DS.Space.s24)
                .padding(.leading, DS.Space.s8)
                .help("Drag to reorder")
            SettingsRow(icon: library.type == "show" ? "tv" : "film", iconColor: library.type == "show" ? .purple : .blue,
                        title: LocalizedStringKey(library.title),
                        subtitle: LocalizedStringKey(library.type == "show" ? "TV Shows library" : "Movies library")) {
                HStack(spacing: DS.Space.s4) {
                    moveButton(library, by: -1, systemImage: "chevron.up").disabled(index == 0)
                    moveButton(library, by: 1, systemImage: "chevron.down").disabled(index == orderedLibraries.count - 1)
                }
            }
        }
    }

    private func moveButton(_ library: LibraryTab, by offset: Int, systemImage: String) -> some View {
        Button {
            var ids = orderedLibraries.map(\.id)
            guard let from = ids.firstIndex(of: library.id), ids.indices.contains(from + offset) else { return }
            ids.swapAt(from, from + offset)
            withAnimation(DS.Motion.standard) { settings.tabOrder = ids }
        } label: {
            Image(systemName: systemImage).font(.flixorIcon(DS.Icon.xs, weight: .semibold)).frame(width: 22, height: 22)
        }
        .buttonStyle(.borderless)
    }

    private func loadLibraries() async {
        struct LibraryResponse: Codable { let key: String; let title: String; let type: String }
        guard let libs: [LibraryResponse] = try? await APIClient.shared.get("/api/plex/libraries") else { return }
        libraries = libs.filter { $0.type == "movie" || $0.type == "show" }
            .map { LibraryTab(id: $0.key, title: $0.title, type: $0.type) }
    }
}

private struct LibraryTabDropDelegate: DropDelegate {
    let target: String
    @Binding var dragging: String?
    let settings: LibraryScreenSettings
    let currentIds: [String]

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        Task { @MainActor in
            withAnimation(DS.Motion.standard) { settings.moveTab(dragging, to: target, currentIds: currentIds) }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

// MARK: - Live preview

/// A small mock of the Library header and one poster row that follows the settings.
private struct LibraryScreenPreview: View {
    let tabs: [String]
    let showCollections: Bool
    let showGenreChips: Bool
    let posterSize: CardPosterSize
    let density: LibraryGridDensity
    let titles: LibraryTitleDisplay
    @Environment(\.flixorTheme) private var theme

    private let colors: [Color] = [Color(hex: 0x2B3A55), Color(hex: 0x4A3F2C), Color(hex: 0x2C6E7E), Color(hex: 0x6B4E8A),
                                   Color(hex: 0x7AA7D6), Color(hex: 0xA5701A), Color(hex: 0x3D5A40), Color(hex: 0x8A3B3B)]
    private let sampleTitles = ["Pacific Rim", "Heart of the Beast", "Avatar", "The Vvaan", "Dhoom", "Ready", "Hungama", "Baby"]
    private let sampleYears = ["2013", "2026", "2026", "2026", "2004", "2011", "2003", "2015"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                ForEach(Array(displayTabs.enumerated()), id: \.offset) { index, tab in
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(tab).font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(index == 0 ? Color.white : Color.white.opacity(0.35))
                        if index == 0 { Text("49").font(.system(size: 10)).foregroundStyle(theme.textTertiary) }
                    }
                }
                Spacer()
                if !showGenreChips { pill("Genre All") }
                pill("Year Any")
                pill("Newest added")
            }
            if showGenreChips {
                HStack(spacing: 5) {
                    ForEach(["All", "Action", "Comedy", "Drama", "Romance", "Thriller", "Family"], id: \.self) { genre in
                        Text(genre).font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(genre == "All" ? Color.black : theme.textSecondary)
                            .padding(.horizontal, 7).frame(height: 17)
                            .background(Capsule().fill(genre == "All" ? Color.white : Color.white.opacity(0.08)))
                    }
                }
            }
            Rectangle().fill(theme.separator).frame(height: 0.5)
            HStack(alignment: .top, spacing: density.spacing * 0.45) {
                ForEach(0..<posterCount, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 2) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(LinearGradient(colors: [colors[i % colors.count], colors[i % colors.count].opacity(0.55)],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: posterWidth, height: posterWidth * 1.5)
                        if titles != .none {
                            Text(sampleTitles[i % sampleTitles.count]).font(.system(size: 8, weight: .medium)).lineLimit(1)
                                .frame(width: posterWidth, alignment: .leading)
                            if titles == .titleAndYear {
                                Text(sampleYears[i % sampleYears.count]).font(.system(size: 7)).foregroundStyle(theme.textTertiary)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(height: posterWidth * 1.5 + 26, alignment: .top)
            .clipped()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: DS.Radius.group).fill(Color(hex: 0x0E0E10)))
        .animation(DS.Motion.standard, value: posterSize)
        .animation(DS.Motion.standard, value: density)
        .animation(DS.Motion.standard, value: titles)
        .animation(DS.Motion.standard, value: showGenreChips)
    }

    private var displayTabs: [String] {
        (tabs.isEmpty ? ["Movies", "TV Shows"] : tabs) + (showCollections ? ["Collections"] : [])
    }

    /// Scaled-down poster width for each size.
    private var posterWidth: CGFloat {
        switch posterSize {
        case .small: return 42
        case .medium: return 52
        case .large: return 62
        case .xlarge: return 72
        }
    }

    private var posterCount: Int {
        switch posterSize {
        case .small: return 9
        case .medium: return 8
        case .large: return 7
        case .xlarge: return 6
        }
    }

    private func pill(_ text: String) -> some View {
        Text(text).font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 8).frame(height: 18)
            .background(Capsule().fill(Color.white.opacity(0.08)))
    }
}
