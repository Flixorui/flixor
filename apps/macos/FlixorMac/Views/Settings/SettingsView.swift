//
//  SettingsView.swift
//  FlixorMac
//
//  macOS System Settings style settings window
//

import SwiftUI
import AppKit

// MARK: - Settings Categories

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case plex
    case player
    case discoveryMode
    case catalog
    case rowsSettings
    case sidebar
    case search
    case appearance
    case homeScreenAppearance
    case detailsScreen
    case tmdb
    case stremio
    case mdblist
    case overseerr
    case trakt
    case advanced
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plex: return "Plex"
        case .player: return String(localized: "Player")
        case .discoveryMode: return String(localized: "Discovery Mode")
        case .catalog: return String(localized: "Catalogs")
        case .rowsSettings: return String(localized: "Rows Settings")
        case .sidebar: return String(localized: "NavBar")
        case .search: return String(localized: "Search")
        case .appearance: return String(localized: "Appearance")
        case .homeScreenAppearance: return String(localized: "Home Screen")
        case .detailsScreen: return String(localized: "Details Screen")
        case .tmdb: return "TMDB"
        case .stremio: return "Stremio"
        case .mdblist: return "MDBList"
        case .overseerr: return "Overseerr"
        case .trakt: return "Trakt"
        case .advanced: return String(localized: "Advanced")
        case .about: return String(localized: "About")
        }
    }

    var description: String {
        switch self {
        case .plex: return String(localized: "Manage your Plex server connections")
        case .player: return String(localized: "Video playback and MPV configuration")
        case .discoveryMode: return String(localized: "Control external content discovery features")
        case .catalog: return String(localized: "Configure library visibility and filtering")
        case .rowsSettings: return String(localized: "Choose which content rows to display")
        case .sidebar: return String(localized: "Configure navigation tabs visibility")
        case .search: return String(localized: "Configure search sources and behavior")
        case .appearance: return String(localized: "Accent color and background style")
        case .homeScreenAppearance: return String(localized: "Customize hero, posters and visual appearance")
        case .detailsScreen: return String(localized: "Episode display and layout options")
        case .tmdb: return String(localized: "The Movie Database metadata settings")
        case .stremio: return String(localized: "Addon sources, subtitles, and alternate playback")
        case .mdblist: return String(localized: "Multi-source ratings aggregation")
        case .overseerr: return String(localized: "Media request management integration")
        case .trakt: return String(localized: "Watch history and scrobbling")
        case .advanced: return String(localized: "Debug logging and diagnostics")
        case .about: return String(localized: "App information and credits")
        }
    }

    /// SF Symbol for sidebar (outline style, monotonic)
    var icon: String {
        switch self {
        case .plex: return "server.rack"
        case .player: return "play.rectangle.fill"
        case .discoveryMode: return "eye.slash"
        case .catalog: return "rectangle.stack"
        case .rowsSettings: return "square.grid.3x1.below.line.grid.1x2"
        case .sidebar: return "sidebar.left"
        case .search: return "magnifyingglass"
        case .appearance: return "paintpalette"
        case .homeScreenAppearance: return "house"
        case .detailsScreen: return "play.rectangle"
        case .tmdb: return "film"
        case .stremio: return "puzzlepiece.extension.fill"
        case .mdblist: return "star"
        case .overseerr: return "arrow.down.circle"
        case .trakt: return "chart.bar"
        case .advanced: return "ladybug"
        case .about: return "info.circle"
        }
    }

    /// Whether this category uses a custom service icon
    var hasCustomIcon: Bool {
        switch self {
        case .plex, .tmdb, .mdblist, .overseerr, .trakt:
            return true
        default:
            return false
        }
    }

    /// Custom service icon view for sidebar (28pt)
    @ViewBuilder
    var sidebarIcon: some View {
        switch self {
        case .plex:
            PlexServiceIcon(size: 24)
        case .tmdb:
            TMDBServiceIcon(size: 24)
        case .mdblist:
            MDBListServiceIcon(size: 24)
        case .overseerr:
            OverseerrServiceIcon(size: 24)
        case .trakt:
            TraktServiceIcon(size: 24)
        default:
            EmptyView()
        }
    }

    /// Custom service icon view for header (64pt) - colorful version
    @ViewBuilder
    var headerIcon: some View {
        let size: CGFloat = 64
        switch self {
        case .plex:
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.r14, style: .continuous)
                    .fill(color)
                    .frame(width: size, height: size)
                Image("plexcolor")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.65, height: size * 0.65)
            }
        case .tmdb:
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.r14, style: .continuous)
                    .fill(color)
                    .frame(width: size, height: size)
                Image("tmdbcolor")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.65, height: size * 0.65)
            }
        case .mdblist:
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.r14, style: .continuous)
                    .fill(color)
                    .frame(width: size, height: size)
                Image("mdblistcolor")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.65, height: size * 0.65)
            }
        case .overseerr:
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.r14, style: .continuous)
                    .fill(color)
                    .frame(width: size, height: size)
                Image("overseerr")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.65, height: size * 0.65)
            }
        case .trakt:
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.r14, style: .continuous)
                    .fill(color)
                    .frame(width: size, height: size)
                Image("trakt")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.white)
                    .frame(width: size * 0.65, height: size * 0.65)
            }
        default:
            EmptyView()
        }
    }

    var color: Color {
        switch self {
        case .plex: return Color(hex: "272A2D")
        case .player: return .blue
        case .discoveryMode: return Color(hex: "FF6B6B")
        case .catalog: return .purple
        case .rowsSettings: return .blue
        case .sidebar: return .cyan
        case .search: return .mint
        case .appearance: return .pink
        case .homeScreenAppearance: return .indigo
        case .detailsScreen: return .teal
        case .tmdb: return Color(hex: "042541")
        case .stremio: return .orange
        case .mdblist: return Color(hex: "4284CA")
        case .overseerr: return Color(hex: "0B1223")
        case .trakt: return Color(hex: "ED1C24")
        case .advanced: return .gray
        case .about: return .orange
        }
    }
}

// MARK: - Sidebar Section

private struct SidebarSection {
    let title: String
    let categories: [SettingsCategory]

    static var all: [SidebarSection] {
        [
            SidebarSection(title: String(localized: "Account"), categories: [.plex]),
            SidebarSection(title: String(localized: "Player"), categories: [.player]),
            SidebarSection(title: String(localized: "Content & Discovery"), categories: [.discoveryMode, .catalog, .rowsSettings, .sidebar, .search]),
            SidebarSection(title: String(localized: "Appearance"), categories: [.appearance, .homeScreenAppearance, .detailsScreen]),
            SidebarSection(title: String(localized: "Integrations"), categories: [.tmdb, .stremio, .mdblist, .overseerr, .trakt]),
            SidebarSection(title: String(localized: "System"), categories: [.advanced, .about])
        ]
    }
}

// MARK: - Main Settings View

struct SettingsView: View {
    @Environment(\.flixorTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appMode = AppModeStore.shared
    @State private var selectedCategory: SettingsCategory = .plex
    @State private var searchText: String = ""

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 0) {
                // Sidebar
                sidebar
                    .frame(width: 260)

                // Content
                contentArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Close button
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.flixorIcon(DS.Icon.lg))
                    .foregroundStyle(.secondary)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(DS.Space.s12)
            .help("Close Settings")
        }
        .frame(width: 920, height: 680)
        .background(theme.settingsWindowBackground)
        .onChange(of: appMode.mode) { _ in
            // Disconnecting Plex removes Catalogs from the sidebar; don't leave a
            // pane selected that can no longer be reached.
            if appMode.isStremioOnly && selectedCategory == .catalog {
                selectedCategory = .plex
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Search
            HStack(spacing: DS.Space.s8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.flixor(.callout))
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.flixor(.callout))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.flixorIcon(DS.Icon.xs))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.Space.s10)
            .padding(.vertical, 7)
            .background(theme.settingsGroupBackground)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r8, style: .continuous))
            .padding(.horizontal, DS.Space.s16)
            .padding(.top, DS.Space.s16)
            .padding(.bottom, DS.Space.s12)

            // Categories with section headers
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s16) {
                    ForEach(Array(SidebarSection.all.enumerated()), id: \.offset) { _, section in
                        let filteredCategories = filterCategories(section.categories)
                        if !filteredCategories.isEmpty {
                            VStack(alignment: .leading, spacing: DS.Space.s4) {
                                // Section header
                                Text(section.title.uppercased())
                                    .font(.flixor(.caption, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, DS.Space.s14)
                                    .padding(.top, DS.Space.s4)

                                // Section items
                                VStack(spacing: DS.Space.s2) {
                                    ForEach(filteredCategories) { category in
                                        SettingsSidebarRow(
                                            category: category,
                                            isSelected: selectedCategory == category
                                        ) {
                                            withAnimation(.easeInOut(duration: 0.15)) {
                                                selectedCategory = category
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, DS.Space.s12)
                .padding(.bottom, DS.Space.s20)
            }
        }
        .background(theme.chromeColor(default: Color(NSColor.windowBackgroundColor).opacity(0.5)))
    }

    private func filterCategories(_ categories: [SettingsCategory]) -> [SettingsCategory] {
        // "Catalogs" configures Plex library visibility, so it has nothing to show
        // without a server. Plex itself stays, as the way to connect one.
        var categories = categories
        if appMode.isStremioOnly {
            categories.removeAll { $0 == .catalog }
        }

        if searchText.isEmpty {
            return categories
        }
        let term = searchText.lowercased()
        return categories.filter {
            $0.title.lowercased().contains(term) ||
            $0.description.lowercased().contains(term)
        }
    }

    // MARK: - Content Area

    private var contentArea: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    // Header (hide for About screen)
                    if selectedCategory != .about {
                        contentHeader
                            .padding(.top, DS.Space.s32)
                            .padding(.bottom, DS.Space.s24)
                    }

                    // Content
                    VStack(alignment: .leading, spacing: DS.Space.s16) {
                        categoryContent(for: selectedCategory)
                    }
                    .padding(.horizontal, DS.Space.s40)
                    .padding(.top, selectedCategory == .about ? 32 : 0)
                    .padding(.bottom, DS.Space.s40)
                }
            }
        }
        .background(theme.chromeColor(default: Color(NSColor.controlBackgroundColor).opacity(0.3)))
    }

    private var contentHeader: some View {
        VStack(spacing: DS.Space.s12) {
            // Icon - use custom service icon or SF Symbol
            if selectedCategory.hasCustomIcon {
                selectedCategory.headerIcon
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: DS.Radius.r14, style: .continuous)
                        .fill(selectedCategory.color.gradient)
                        .frame(width: 64, height: 64)
                    Image(systemName: selectedCategory.icon)
                        .font(.flixor(.largeTitle, weight: .medium))
                        .foregroundStyle(.white)
                }
            }

            // Title
            Text(selectedCategory.title)
                .font(.system(size: 22, weight: .bold))

            // Description
            Text(categoryDescription(for: selectedCategory))
                .font(.flixor(.callout))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
    }

    /// Plex is optional in Stremio-only mode, so say so rather than implying it's
    /// already set up.
    private func categoryDescription(for category: SettingsCategory) -> String {
        if category == .plex && appMode.isStremioOnly {
            return String(localized: "Optional. Connect a Plex account to add your own library alongside Stremio.")
        }
        return category.description
    }

    @ViewBuilder
    private func categoryContent(for category: SettingsCategory) -> some View {
        switch category {
        case .plex:
            PlexServersView()
        case .player:
            PlayerSettingsView()
        case .discoveryMode:
            DiscoveryModeSettingsView()
        case .catalog:
            CatalogSettingsView()
        case .rowsSettings:
            RowsSettingsView()
        case .sidebar:
            SidebarSettingsView()
        case .search:
            SearchSettingsView()
        case .appearance:
            AppearanceSettingsView()
        case .homeScreenAppearance:
            HomeScreenAppearanceView()
        case .detailsScreen:
            DetailsScreenSettingsView()
        case .tmdb:
            TMDBSettingsView()
        case .stremio:
            StremioSettingsView()
        case .mdblist:
            MDBListSettingsView()
        case .overseerr:
            OverseerrSettingsView()
        case .trakt:
            TraktSettingsContent()
        case .advanced:
            AdvancedSettingsContent()
        case .about:
            AboutSettingsContent()
        }
    }
}

// MARK: - Settings Sidebar Item

private struct SettingsSidebarRow: View {
    @Environment(\.flixorTheme) private var theme
    let category: SettingsCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s12) {
                // Use custom service icon or SF Symbol
                if category.hasCustomIcon {
                    category.sidebarIcon
                } else {
                    // SF Symbol with grey background
                    ZStack {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 24, height: 24)
                        Image(systemName: category.icon)
                            .font(.flixorIcon(DS.Icon.xs, weight: .medium))
                            .foregroundStyle(.white)
                    }
                }

                Text(category.title)
                    .font(.flixor(.callout))
                    .foregroundStyle(isSelected ? theme.onAccent : .primary)

                Spacer()
            }
            .padding(.horizontal, DS.Space.s10)
            .padding(.vertical, DS.Space.s8)
            .background(
                isSelected
                    ? theme.accent
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: DS.Radius.r8, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings Group Card

struct SettingsGroupCard<Content: View>: View {
    @Environment(\.flixorTheme) private var theme
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(theme.settingsGroupBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r10, style: .continuous))
    }
}

// MARK: - Settings Section Header

struct SettingsSectionHeader: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .textCase(.uppercase)
            .font(.flixor(.caption, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.leading, DS.Space.s4)
    }
}

// MARK: - Settings Row

struct SettingsRow<Trailing: View>: View {
    let icon: String?
    let iconColor: Color
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    let showChevron: Bool
    let showDivider: Bool
    let useImageAsset: Bool
    @ViewBuilder let trailing: () -> Trailing

    init(
        icon: String? = nil,
        iconColor: Color = .gray,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        showChevron: Bool = false,
        showDivider: Bool = true,
        useImageAsset: Bool = false,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.showChevron = showChevron
        self.showDivider = showDivider
        self.useImageAsset = useImageAsset
        self.trailing = trailing
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.s12) {
                if let icon {
                    if useImageAsset {
                        // Use image from assets
                        Image(icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r6, style: .continuous))
                    } else {
                        // Use SF Symbol with colored background
                        ZStack {
                            RoundedRectangle(cornerRadius: DS.Radius.r6, style: .continuous)
                                .fill(iconColor.gradient)
                                .frame(width: 28, height: 28)
                            Image(systemName: icon)
                                .font(.flixorIcon(DS.Icon.sm, weight: .medium))
                                .foregroundStyle(.white)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    Text(title)
                        .font(.flixor(.callout))
                    if let subtitle {
                        Text(subtitle)
                            .font(.flixor(.caption))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                trailing()
                    .toggleStyle(.switch)

                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.flixorIcon(DS.Icon.xs, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, DS.Space.s12)
            .padding(.vertical, DS.Space.s10)

            if showDivider {
                Divider()
                    .padding(.leading, icon != nil ? 52 : 12)
            }
        }
    }
}

// MARK: - Clickable Settings Row

struct SettingsNavigationRow: View {
    let icon: String?
    let iconColor: Color
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    let showDivider: Bool
    let action: () -> Void

    init(
        icon: String? = nil,
        iconColor: Color = .gray,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        showDivider: Bool = true,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.showDivider = showDivider
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            SettingsRow(
                icon: icon,
                iconColor: iconColor,
                title: title,
                subtitle: subtitle,
                showChevron: true,
                showDivider: showDivider
            ) {
                EmptyView()
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Discovery Mode Settings View

private struct DiscoveryModeSettingsView: View {
    @ObservedObject private var settings = ProfileSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            SettingsGroupCard {
                SettingsRow(
                    icon: "eye.slash.fill",
                    iconColor: Color(hex: "FF6B6B"),
                    title: "Library Only Mode",
                    subtitle: "Turn off all discovery features",
                    showDivider: false
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.discoveryDisabled },
                        set: { newValue in
                            settings.setDiscoveryDisabled(newValue)
                        }
                    ))
                    .labelsHidden()
                }
            }

            Text("When enabled, this disables all external discovery features including trending rows, Trakt recommendations, Popular on Plex, New & Popular tab, and TMDB search results. Only content from your Plex library will be shown.")
                .font(.flixor(.caption))
                .foregroundStyle(.secondary)
                .padding(.horizontal, DS.Space.s4)

            if settings.discoveryDisabled {
                HStack(spacing: DS.Space.s8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Library Only Mode is active")
                        .font(.flixor(.footnote, weight: .medium))
                }
                .padding(.horizontal, DS.Space.s4)
            }
        }
    }
}

// MARK: - Sidebar Settings View

private struct SidebarSettingsView: View {
    @ObservedObject private var settings = ProfileSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            NavigationStyleSettingsSection()

            SettingsGroupCard {
                SettingsRow(
                    icon: "play.circle.fill",
                    iconColor: .red,
                    title: "New & Popular Tab",
                    subtitle: settings.discoveryDisabled ? "Disabled by Library Only Mode" : "Show New & Popular tab in navigation",
                    showDivider: false
                ) {
                    Toggle("", isOn: $settings.showNewPopularTab)
                        .labelsHidden()
                        .disabled(settings.discoveryDisabled)
                }
            }

            Text("The New & Popular tab shows trending content, top 10 lists, and upcoming releases.")
                .font(.flixor(.caption))
                .foregroundStyle(.secondary)
                .padding(.horizontal, DS.Space.s4)

            if AppModeStore.shared.isStremioOnly {
                Text("Library and Downloads are hidden because they need a Plex server. Connect Plex in Settings → Plex to show them.")
                    .font(.flixor(.caption))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, DS.Space.s4)
            }
        }
    }
}

// MARK: - Search Settings View

private struct SearchSettingsView: View {
    @ObservedObject private var settings = ProfileSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            SettingsGroupCard {
                SettingsRow(
                    icon: "film.fill",
                    iconColor: .blue,
                    title: "Include TMDB Results",
                    subtitle: settings.discoveryDisabled ? "Disabled by Library Only Mode" : "Show TMDB movies and shows in search",
                    showDivider: false
                ) {
                    Toggle("", isOn: $settings.includeTmdbInSearch)
                        .labelsHidden()
                        .disabled(settings.discoveryDisabled)
                }
            }

            Text("When enabled, search results will include content from The Movie Database (TMDB) in addition to your Plex library. Recommendations will also be shown when not searching.")
                .font(.flixor(.caption))
                .foregroundStyle(.secondary)
                .padding(.horizontal, DS.Space.s4)
        }
    }
}

// MARK: - General Settings Content

private struct GeneralSettingsContent: View {
    var body: some View {
        SettingsGroupCard {
            VStack(spacing: 0) {
                SettingsRow(
                    icon: "play.rectangle.fill",
                    iconColor: .blue,
                    title: "Playback Engine",
                    showDivider: false
                ) {
                    Text("MPV")
                        .font(.flixor(.callout, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }

        VStack(alignment: .leading, spacing: DS.Space.s8) {
            Label("MPV is required on macOS for Plex, offline files, direct URL playback, custom headers, and Stremio streams.", systemImage: "checkmark.circle.fill")
                .font(.flixor(.footnote))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.top, DS.Space.s8)

        Text("Playback engine selection is no longer configurable on macOS.")
            .font(.flixor(.caption))
            .foregroundStyle(.secondary)
            .padding(.top, DS.Space.s4)
    }
}

// MARK: - Trakt Settings Content

private struct TraktSettingsContent: View {
    @State private var profile: TraktUserProfile?
    @State private var isLoadingProfile = false
    @State private var isRequestingCode = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var deviceCode: TraktDeviceCodeResponse?
    @State private var expiresAt: Date?
    @State private var pollingTask: Task<Void, Never>?

    @ObservedObject private var profileSettings = ProfileSettings.shared

    private var traktColor: Color { Color(hex: "ED1C24") }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s24) {
        // Status
        if let profile {
            SettingsGroupCard {
                HStack(spacing: DS.Space.s12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.flixorIcon(DS.Icon.xl))
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        Text("Connected")
                            .font(.flixor(.callout, weight: .semibold))
                        Text("Signed in as @\(profile.ids?.slug ?? profile.username ?? "user")")
                            .font(.flixor(.caption))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Disconnect") {
                        Task { await disconnect() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(DS.Space.s12)
            }
        } else {
            SettingsGroupCard {
                VStack(spacing: DS.Space.s12) {
                    HStack(spacing: DS.Space.s12) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.flixorIcon(DS.Icon.xl))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: DS.Space.s2) {
                            Text("Not Connected")
                                .font(.flixor(.callout, weight: .semibold))
                            Text("Sign in to sync watch history")
                                .font(.flixor(.caption))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, DS.Space.s12)
                    .padding(.top, DS.Space.s12)

                    if let deviceCode {
                        Divider()
                        deviceCodeView(deviceCode)
                    } else {
                        Button(action: { Task { await startDeviceCodeFlow() } }) {
                            HStack {
                                if isRequestingCode {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .frame(width: 14, height: 14)
                                }
                                Text(isRequestingCode ? "Requesting..." : "Sign in with Trakt")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(traktColor)
                        .controlSize(.large)
                        .disabled(isRequestingCode)
                        .padding(.horizontal, DS.Space.s12)
                        .padding(.bottom, DS.Space.s12)
                    }
                }
            }
        }

        if let statusMessage {
            HStack(spacing: DS.Space.s8) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue)
                Text(statusMessage)
                    .font(.flixor(.caption))
                    .foregroundStyle(.secondary)
            }
        }

        if let errorMessage {
            HStack(spacing: DS.Space.s8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(errorMessage)
                    .font(.flixor(.caption))
                    .foregroundStyle(.red)
            }
        }

        // Sync Settings
        SettingsGroupCard {
            SettingsRow(icon: "arrow.triangle.2.circlepath", iconColor: .blue, title: "Auto-sync watched") {
                Toggle("", isOn: $profileSettings.traktAutoSyncWatched).labelsHidden()
            }
            SettingsRow(icon: "star.fill", iconColor: .yellow, title: "Sync ratings") {
                Toggle("", isOn: $profileSettings.traktSyncRatings).labelsHidden()
            }
            SettingsRow(icon: "bookmark.fill", iconColor: .purple, title: "Sync watchlist") {
                Toggle("", isOn: $profileSettings.traktSyncWatchlist).labelsHidden()
            }
            SettingsRow(icon: "play.circle.fill", iconColor: traktColor, title: "Enable scrobbling", showDivider: false) {
                Toggle("", isOn: $profileSettings.traktScrobbleEnabled).labelsHidden()
            }
        }

        Text("Scrobbling reports your watching activity to Trakt in real-time.")
            .font(.flixor(.caption))
            .foregroundStyle(.secondary)
            .padding(.horizontal, DS.Space.s4)
        }
        .onAppear {
            Task { await refreshProfile() }
        }
    }

    @ViewBuilder
    private func deviceCodeView(_ code: TraktDeviceCodeResponse) -> some View {
        VStack(spacing: DS.Space.s12) {
            Text("Enter this code at trakt.tv/activate")
                .font(.flixor(.footnote))
                .foregroundStyle(.secondary)

            HStack(spacing: DS.Space.s16) {
                Text(code.user_code)
                    .font(.flixor(.display, weight: .bold, design: .monospaced))
                    .kerning(6)

                VStack(spacing: DS.Space.s8) {
                    Button("Copy") {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(code.user_code, forType: .string)
                        statusMessage = String(localized: "Code copied!")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Open Trakt") {
                        if let url = URL(string: code.verification_url) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(traktColor)
                    .controlSize(.small)
                }
            }

            if let expiresAt {
                let remaining = Int(max(0, expiresAt.timeIntervalSinceNow))
                Text("Expires in \(remaining)s")
                    .font(.flixor(.caption))
                    .foregroundStyle(.secondary)
            }

            Button("Cancel") { cancelDeviceFlow() }
                .buttonStyle(.plain)
                .font(.flixor(.footnote))
                .foregroundStyle(.secondary)
        }
        .padding(DS.Space.s16)
    }

    // MARK: - Actions

    @MainActor
    private func refreshProfile(force: Bool = false) async {
        if isLoadingProfile && !force { return }
        isLoadingProfile = true
        errorMessage = nil
        defer { isLoadingProfile = false }

        do {
            profile = try await APIClient.shared.traktUserProfile()
        } catch {
            profile = nil
            if force {
                errorMessage = String(localized: "Unable to load Trakt profile.")
            }
        }
    }

    @MainActor
    private func startDeviceCodeFlow() async {
        pollingTask?.cancel()
        errorMessage = nil
        statusMessage = nil
        deviceCode = nil

        isRequestingCode = true
        defer { isRequestingCode = false }

        do {
            let code = try await APIClient.shared.traktDeviceCode()
            deviceCode = code
            expiresAt = Date().addingTimeInterval(TimeInterval(code.expires_in))
            statusMessage = String(localized: "Waiting for authorization...")
            beginPolling(deviceCode: code)
        } catch {
            errorMessage = String(localized: "Failed to start Trakt device flow.")
        }
    }

    private func beginPolling(deviceCode: TraktDeviceCodeResponse) {
        pollingTask?.cancel()
        let expiry = Date().addingTimeInterval(TimeInterval(deviceCode.expires_in))
        let interval = max(deviceCode.interval ?? 5, 3)

        pollingTask = Task {
            while !Task.isCancelled {
                if Date() > expiry {
                    await MainActor.run {
                        statusMessage = nil
                        errorMessage = String(localized: "Device code expired. Please try again.")
                        self.deviceCode = nil
                    }
                    return
                }

                do {
                    let response = try await APIClient.shared.traktDeviceToken(code: deviceCode.device_code)
                    if response.ok {
                        await MainActor.run {
                            statusMessage = String(localized: "Connected successfully!")
                            self.deviceCode = nil
                        }
                        await refreshProfile(force: true)
                        return
                    }
                } catch {}

                try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            }
        }
    }

    @MainActor
    private func cancelDeviceFlow() {
        pollingTask?.cancel()
        deviceCode = nil
        expiresAt = nil
        statusMessage = nil
    }

    @MainActor
    private func disconnect() async {
        pollingTask?.cancel()
        statusMessage = nil
        errorMessage = nil

        do {
            _ = try await APIClient.shared.traktSignOut()
            profile = nil
        } catch {
            errorMessage = String(localized: "Failed to disconnect.")
        }
    }
}

// MARK: - Advanced Settings Content

private struct AdvancedSettingsContent: View {
    @ObservedObject private var logger = AppLogger.shared
    @State private var showLogsSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s24) {
            // Debug Logging Toggle
            SettingsGroupCard {
                SettingsRow(
                    icon: "ladybug.fill",
                    iconColor: .gray,
                    title: "Debug Logging",
                    subtitle: "Enable verbose logging for troubleshooting",
                    showDivider: false
                ) {
                    Toggle("", isOn: Binding(
                        get: { logger.debugEnabled },
                        set: { logger.setDebugEnabled($0) }
                    ))
                    .labelsHidden()
                }
            }

            Text("When enabled, the app captures detailed logs that can help diagnose issues. Logs are stored in memory and cleared when the app restarts.")
                .font(.flixor(.caption))
                .foregroundStyle(.secondary)
                .padding(.horizontal, DS.Space.s4)

            // View Logs
            SettingsGroupCard {
                SettingsNavigationRow(
                    icon: "doc.text.fill",
                    iconColor: .blue,
                    title: "View Logs",
                    subtitle: "\(logger.logCount) entries",
                    showDivider: false
                ) {
                    showLogsSheet = true
                }
            }
        }
        .sheet(isPresented: $showLogsSheet) {
            LogsSheetView(isPresented: $showLogsSheet)
        }
    }
}

// MARK: - Logs Sheet View

private struct LogsSheetView: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("App Logs")
                    .font(.flixor(.bodyLarge, weight: .semibold))
                Spacer()
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(DS.Space.s16)

            Divider()

            // Logs content
            LogsView()
                .padding(DS.Space.s16)
        }
        .frame(width: 700, height: 550)
        .pureBlackSheetBackground()
    }
}

// MARK: - About Content

private struct AboutSettingsContent: View {
    var body: some View {
        SettingsGroupCard {
            VStack(spacing: DS.Space.s20) {
                // App Icon from assets
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r18, style: .continuous))

                VStack(spacing: DS.Space.s4) {
                    Text("Flixor")
                        .font(.flixor(.title2, weight: .bold))
                    Text("Version \(Bundle.main.appVersion)")
                        .font(.flixor(.footnote))
                        .foregroundStyle(.secondary)
                }

                Text("A native macOS client for Plex and Stremio addons")
                    .font(.flixor(.callout))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Space.s24)
        }

        SettingsGroupCard {
            SettingsNavigationRow(
                icon: "globe",
                iconColor: .gray,
                title: "Website",
                subtitle: "flixor.xyz"
            ) {
                if let url = URL(string: "https://flixor.xyz") {
                    NSWorkspace.shared.open(url)
                }
            }
            SettingsNavigationRow(
                icon: "star.fill",
                iconColor: .gray,
                title: "Star on Github",
                subtitle: "github.com/Flixorui/flixor"
            ) {
                if let url = URL(string: "https://github.com/Flixorui/flixor") {
                    NSWorkspace.shared.open(url)
                }
            }
            SettingsNavigationRow(
                icon: "exclamationmark.bubble.fill",
                iconColor: .gray,
                title: "Report Issue"
            ) {
                if let url = URL(string: "https://github.com/Flixorui/flixor/issues/new") {
                    NSWorkspace.shared.open(url)
                }
            }
            SettingsNavigationRow(
                icon: "bubble.left.and.bubble.right.fill",
                iconColor: .gray,
                title: "Reddit",
                subtitle: "r/Flixor",
                showDivider: false
            ) {
                if let url = URL(string: "https://www.reddit.com/r/Flixor/") {
                    NSWorkspace.shared.open(url)
                }
            }
        }

        SettingsGroupCard {
            SettingsNavigationRow(
                icon: "doc.text.fill",
                iconColor: .gray,
                title: "Privacy Policy"
            ) {}
            SettingsNavigationRow(
                icon: "doc.text.fill",
                iconColor: .gray,
                title: "Terms of Service",
                showDivider: false
            ) {}
        }

        Text("Made with love for Plex enthusiasts")
            .font(.flixor(.caption))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, DS.Space.s8)
    }
}

// MARK: - Legacy Components (for compatibility)

struct SettingsCard<Content: View>: View {
    let title: LocalizedStringKey?
    @ViewBuilder let content: () -> Content

    init(title: LocalizedStringKey? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s8) {
            if let title {
                Text(title)
                    .textCase(.uppercase)
                    .font(.flixor(.caption, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, DS.Space.s4)
            }
            SettingsGroupCard {
                content()
            }
        }
    }
}

struct SettingRow<TrailingContent: View>: View {
    let icon: String
    let iconColor: Color
    let title: LocalizedStringKey
    let description: LocalizedStringKey?
    let showDivider: Bool
    @ViewBuilder let trailing: () -> TrailingContent

    init(
        icon: String,
        iconColor: Color = .gray,
        title: LocalizedStringKey,
        description: LocalizedStringKey? = nil,
        showDivider: Bool = true,
        @ViewBuilder trailing: @escaping () -> TrailingContent
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.description = description
        self.showDivider = showDivider
        self.trailing = trailing
    }

    var body: some View {
        SettingsRow(
            icon: icon,
            iconColor: iconColor,
            title: title,
            subtitle: description,
            showDivider: showDivider,
            trailing: trailing
        )
    }
}

struct StatusCard: View {
    let icon: String
    let color: Color
    let title: LocalizedStringKey
    let description: LocalizedStringKey

    var body: some View {
        HStack(spacing: DS.Space.s12) {
            Image(systemName: icon)
                .font(.flixor(.title3))
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text(title)
                    .font(.flixor(.callout, weight: .semibold))
                Text(description)
                    .font(.flixor(.caption))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(DS.Space.s12)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: DS.Radius.r10, style: .continuous))
    }
}

// Keep old GeneralSettingsView for backward compatibility
struct GeneralSettingsView: View {
    var body: some View {
        GeneralSettingsContent()
    }
}

// Keep old TraktSettingsView for backward compatibility
struct TraktSettingsView: View {
    var body: some View {
        TraktSettingsContent()
    }
}

// Keep old AboutView for backward compatibility
struct AboutView: View {
    var body: some View {
        AboutSettingsContent()
    }
}

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View { SettingsView() }
}
#endif
