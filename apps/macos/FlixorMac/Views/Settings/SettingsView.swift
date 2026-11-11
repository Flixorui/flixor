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
    case stremio
    #if FLIXOR_LIVE_TV
    case liveTV
    #endif
    case player
    case content
    case homeScreenAppearance
    case libraryScreen
    case detailsScreen
    case sidebar
    case tmdb
    case mdblist
    case overseerr
    case trakt
    case streamingAvailability
    case appearance
    case advanced
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plex: return "Plex"
        case .stremio: return "Stremio"
        #if FLIXOR_LIVE_TV
        case .liveTV: return "Live TV"
        #endif
        case .player: return String(localized: "Player")
        case .content: return String(localized: "Content")
        case .homeScreenAppearance: return String(localized: "Home")
        case .libraryScreen: return String(localized: "Library")
        case .detailsScreen: return String(localized: "Details")
        case .sidebar: return String(localized: "Navigation")
        case .tmdb: return "TMDB"
        case .mdblist: return "MDBList"
        case .overseerr: return "Overseerr"
        case .trakt: return "Trakt"
        case .streamingAvailability: return String(localized: "Top 10 Lists")
        case .appearance: return String(localized: "Appearance")
        case .advanced: return String(localized: "Advanced")
        case .about: return String(localized: "About")
        }
    }

    var description: String {
        switch self {
        case .plex: return String(localized: "Account and servers")
        case .stremio: return String(localized: "Addons, subtitles and alternate playback")
        #if FLIXOR_LIVE_TV
        case .liveTV: return "Xtream channels and the xtream-web guide. Personal build only."
        #endif
        case .player: return String(localized: "Playback, decoding, buffering and seeking")
        case .content: return String(localized: "Which libraries show, and whether Flixor suggests things you don't own")
        case .homeScreenAppearance: return String(localized: "Hero, rows, Continue Watching and cards")
        case .libraryScreen: return String(localized: "Grid, genre chips, tabs and what the Library remembers")
        case .detailsScreen: return String(localized: "Episodes, sections and layout")
        case .sidebar: return String(localized: "Navigation style and tabs")
        case .tmdb: return String(localized: "Artwork, metadata and language from The Movie Database")
        case .mdblist: return String(localized: "Ratings from IMDb, Rotten Tomatoes, Letterboxd and more")
        case .overseerr: return String(localized: "Request movies and shows you don't have yet")
        case .trakt: return String(localized: "Watch history, ratings and scrobbling")
        case .streamingAvailability: return String(localized: "Top 10 and new arrivals from FlixPatrol and Streaming Availability")
        case .appearance: return String(localized: "Accent colour and background")
        case .advanced: return String(localized: "Debug logging and diagnostics")
        case .about: return String(localized: "App information and credits")
        }
    }

    /// Words that should find this page in the sidebar search, for pages that
    /// absorbed others (old page names still work).
    var searchTerms: String {
        switch self {
        case .content: return "catalogs libraries discovery mode library only search tmdb results"
        case .homeScreenAppearance: return "home screen rows settings hero continue watching posters cards"
        case .libraryScreen: return "library screen grid tabs"
        case .detailsScreen: return "details screen episodes"
        case .sidebar: return "navbar navigation tabs new & popular"
        case .streamingAvailability: return "flixpatrol streaming availability movie of the night top 10 netflix prime disney apple max paramount hulu starz hotstar api key"
        default: return ""
        }
    }

    /// SF Symbol for pages without a service logo.
    var icon: String {
        switch self {
        case .plex: return "server.rack"
        case .stremio: return "puzzlepiece.extension.fill"
        #if FLIXOR_LIVE_TV
        case .liveTV: return "antenna.radiowaves.left.and.right"
        #endif
        case .player: return "play.fill"
        case .content: return "square.stack.fill"
        case .homeScreenAppearance: return "house.fill"
        case .libraryScreen: return "square.grid.3x2.fill"
        case .detailsScreen: return "rectangle.fill.on.rectangle.fill"
        case .sidebar: return "sidebar.left"
        case .tmdb: return "film"
        case .mdblist: return "star"
        case .overseerr: return "arrow.down.circle"
        case .trakt: return "chart.bar"
        case .streamingAvailability: return "list.number"
        case .appearance: return "paintpalette.fill"
        case .advanced: return "gearshape.fill"
        case .about: return "info"
        }
    }

    /// Asset for pages that show a service logo instead of a symbol.
    private var logoAsset: (name: String, template: Bool)? {
        switch self {
        case .plex: return ("plexcolor", false)
        case .tmdb: return ("tmdbcolor", false)
        case .mdblist: return ("mdblistcolor", false)
        case .overseerr: return ("overseerr", false)
        case .trakt: return ("trakt", true)
        default: return nil
        }
    }

    /// Rounded-square icon used in the sidebar (20pt) and the page header (32pt).
    @ViewBuilder
    func iconView(size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(logoAsset == nil ? AnyShapeStyle(color.gradient) : AnyShapeStyle(color))
            if let logo = logoAsset {
                Image(logo.name)
                    .renderingMode(logo.template ? .template : .original)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .frame(width: size * 0.64, height: size * 0.64)
            } else {
                Image(systemName: icon)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }

    var color: Color {
        switch self {
        case .plex: return Color(hex: "272A2D")
        case .stremio: return Color(hex: "6D4FD8")
        #if FLIXOR_LIVE_TV
        case .liveTV: return Color(hex: "D4202A")
        #endif
        case .player: return Color(hex: "0A84FF")
        case .content: return Color(hex: "A64FD8")
        case .homeScreenAppearance: return Color(hex: "5E5CE6")
        case .libraryScreen: return Color(hex: "0A7AFF")
        case .detailsScreen: return Color(hex: "2AA3BD")
        case .sidebar: return Color(hex: "3B9FD6")
        case .tmdb: return Color(hex: "042541")
        case .mdblist: return Color(hex: "4284CA")
        case .overseerr: return Color(hex: "0B1223")
        case .trakt: return Color(hex: "ED1C24")
        case .streamingAvailability: return Color(hex: "7C3AED")
        case .appearance: return Color(hex: "E0405F")
        case .advanced: return Color(hex: "6E6E73")
        case .about: return Color(hex: "55555A")
        }
    }
}

// MARK: - Sidebar Section

private struct SidebarSection {
    let title: String
    let categories: [SettingsCategory]

    private static var sourceCategories: [SettingsCategory] {
        #if FLIXOR_LIVE_TV
        return [.plex, .stremio, .liveTV]
        #else
        return [.plex, .stremio]
        #endif
    }

    static var all: [SidebarSection] {
        [
            SidebarSection(title: String(localized: "Sources"), categories: sourceCategories),
            SidebarSection(title: String(localized: "Playback & Content"), categories: [.player, .content]),
            SidebarSection(title: String(localized: "Screens"), categories: [.homeScreenAppearance, .libraryScreen, .detailsScreen, .sidebar]),
            SidebarSection(title: String(localized: "Integrations"), categories: [.tmdb, .mdblist, .overseerr, .trakt, .streamingAvailability]),
            SidebarSection(title: String(localized: "General"), categories: [.appearance, .advanced, .about])
        ]
    }
}

// MARK: - Main Settings View

struct SettingsView: View {
    /// The main window shows Settings as a sheet, which has no traffic lights,
    /// so it needs its own close button. The Settings window (⌘,) does not.
    var showsCloseButton = false

    @Environment(\.flixorTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appMode = AppModeStore.shared
    @State private var selectedCategory: SettingsCategory = .plex
    @State private var searchText: String = ""

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)

            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 920, height: 680)
        .background(theme.settingsWindowBackground)
        .toggleStyle(SettingsSwitchToggleStyle())
        // Accent red is kept for switches (above). Everything else (pickers,
        // bordered buttons, links) stays neutral so red only marks what's on.
        .tint(SettingsChrome.neutralTint)
        .overlay(alignment: .topTrailing) {
            if showsCloseButton {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.flixorIcon(DS.Icon.lg))
                        .foregroundStyle(.secondary)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(DS.Space.s12)
                .help("Close Settings")
                .keyboardShortcut(.cancelAction)
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.s6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.Space.s8)
            .frame(height: 28)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .padding(.horizontal, DS.Space.s10)
            .padding(.top, DS.Space.s12)
            .padding(.bottom, DS.Space.s6)

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s12) {
                    ForEach(Array(SidebarSection.all.enumerated()), id: \.offset) { _, section in
                        let filteredCategories = filterCategories(section.categories)
                        if !filteredCategories.isEmpty {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(section.title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, DS.Space.s8)
                                    .padding(.bottom, DS.Space.s2)

                                ForEach(filteredCategories) { category in
                                    SettingsSidebarRow(
                                        category: category,
                                        isSelected: selectedCategory == category
                                    ) {
                                        selectedCategory = category
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, DS.Space.s10)
                .padding(.top, DS.Space.s6)
                .padding(.bottom, DS.Space.s16)
            }
            .scrollIndicators(.never)
        }
        .background(theme.chromeColor(default: SettingsChrome.sidebarBackground, pureBlack: theme.background))
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.white.opacity(0.07)).frame(width: 1)
        }
    }

    private func filterCategories(_ categories: [SettingsCategory]) -> [SettingsCategory] {
        if searchText.isEmpty {
            return categories
        }
        let term = searchText.lowercased()
        return categories.filter {
            $0.title.lowercased().contains(term) ||
            $0.description.lowercased().contains(term) ||
            $0.searchTerms.contains(term)
        }
    }

    // MARK: - Content Area

    private var contentArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s16) {
                if selectedCategory != .about {
                    contentHeader
                        .padding(.bottom, DS.Space.s4)
                }
                categoryContent(for: selectedCategory)
            }
            .padding(.horizontal, DS.Space.s28)
            .padding(.top, DS.Space.s20)
            .padding(.bottom, DS.Space.s32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(selectedCategory)
        }
    }

    private var contentHeader: some View {
        HStack(spacing: DS.Space.s12) {
            selectedCategory.iconView(size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(selectedCategory.title)
                    .font(.system(size: 19, weight: .bold))
                Text(categoryDescription(for: selectedCategory))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.trailing, showsCloseButton ? DS.Space.s32 : 0)
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
        case .stremio:
            StremioSettingsView()
        #if FLIXOR_LIVE_TV
        case .liveTV:
            LiveTVSettingsView()
        #endif
        case .player:
            PlayerSettingsView()
        case .content:
            ContentSettingsView()
        case .homeScreenAppearance:
            HomeScreenAppearanceView()
        case .libraryScreen:
            LibraryScreenSettingsView()
        case .detailsScreen:
            DetailsScreenSettingsView()
        case .sidebar:
            SidebarSettingsView()
        case .tmdb:
            TMDBSettingsView()
        case .mdblist:
            MDBListSettingsView()
        case .overseerr:
            OverseerrSettingsView()
        case .trakt:
            TraktSettingsContent()
        case .streamingAvailability:
            StreamingAvailabilitySettingsView()
        case .appearance:
            AppearanceSettingsView()
        case .advanced:
            AdvancedSettingsContent()
        case .about:
            AboutSettingsContent()
        }
    }
}

// MARK: - Settings Sidebar Item

private struct SettingsSidebarRow: View {
    let category: SettingsCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s8) {
                category.iconView(size: 20)
                Text(category.title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Space.s8)
            .frame(height: 28)
            .background(
                isSelected ? Color.white.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared Chrome

enum SettingsChrome {
    /// Tint for pickers, bordered buttons and other non-switch controls.
    static let neutralTint = Color(white: 0.86)
    static let sidebarBackground = Color.white.opacity(0.035)
    static let destructive = Color(red: 1, green: 0.42, blue: 0.38)
}

/// A switch tinted with the accent colour. Applied to the whole Settings
/// window, so plain `Toggle`s are switches too.
struct SettingsSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        SettingsSwitch(configuration: configuration)
    }

    private struct SettingsSwitch: View {
        let configuration: ToggleStyleConfiguration
        @Environment(\.flixorTheme) private var theme

        var body: some View {
            Toggle(configuration)
                .toggleStyle(.switch)
                .tint(theme.accent)
        }
    }
}

extension ToggleStyle where Self == SettingsSwitchToggleStyle {
    static var settingsSwitch: SettingsSwitchToggleStyle { SettingsSwitchToggleStyle() }
}

/// The one main action on a page: a white button with black text.
struct SettingsPrimaryButtonStyle: ButtonStyle {
    var fullWidth = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.black)
            .padding(.horizontal, DS.Space.s16)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: 28)
            .background(Color.white.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
    }
}

/// Grey button; `destructive` gives it red text (Sign Out, Disconnect, Remove).
struct SettingsSecondaryButtonStyle: ButtonStyle {
    var destructive = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(destructive ? SettingsChrome.destructive : Color.primary)
            .padding(.horizontal, DS.Space.s10)
            .frame(height: 24)
            .background(Color.white.opacity(configuration.isPressed ? 0.2 : 0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == SettingsPrimaryButtonStyle {
    static var settingsPrimary: SettingsPrimaryButtonStyle { SettingsPrimaryButtonStyle() }
}

extension ButtonStyle where Self == SettingsSecondaryButtonStyle {
    static var settingsSecondary: SettingsSecondaryButtonStyle { SettingsSecondaryButtonStyle() }
    static var settingsDestructive: SettingsSecondaryButtonStyle { SettingsSecondaryButtonStyle(destructive: true) }
}

enum SettingsStatus { case connected, notSetUp, warning, error }

/// The first row of an integration page: where it stands, plus its action.
struct SettingsStatusRow<Trailing: View>: View {
    let state: SettingsStatus
    let title: String
    let subtitle: String?
    @ViewBuilder let trailing: () -> Trailing

    init(_ state: SettingsStatus, title: String, subtitle: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.state = state
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: DS.Space.s10) {
            ZStack {
                Circle().fill(badgeColor)
                Image(systemName: badgeSymbol)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(state == .notSetUp ? Color.white.opacity(0.8) : .black)
            }
            .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: DS.Space.s8)
            trailing()
        }
        .padding(.horizontal, DS.Space.s12)
        .padding(.vertical, DS.Space.s10)
    }

    private var badgeColor: Color {
        switch state {
        case .connected: return Color(red: 0.19, green: 0.82, blue: 0.35)
        case .notSetUp: return Color.white.opacity(0.18)
        case .warning: return .orange
        case .error: return SettingsChrome.destructive
        }
    }

    private var badgeSymbol: String {
        switch state {
        case .connected: return "checkmark"
        case .notSetUp: return "minus"
        case .warning: return "exclamationmark"
        case .error: return "xmark"
        }
    }
}

/// A text field with a visible box, for settings rows.
struct SettingsTextFieldStyle: TextFieldStyle {
    @Environment(\.flixorTheme) private var theme

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(.system(size: 12.5))
            .padding(.horizontal, DS.Space.s8)
            .frame(height: 26)
            .background(theme.settingsFieldBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
    }
}

extension TextFieldStyle where Self == SettingsTextFieldStyle {
    static var settings: SettingsTextFieldStyle { SettingsTextFieldStyle() }
}

/// Footnote under a group.
struct SettingsFootnote: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, DS.Space.s10)
            .padding(.top, -DS.Space.s8)
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
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.r10, style: .continuous).strokeBorder(Color.white.opacity(0.05), lineWidth: 1))
    }
}

// MARK: - Settings Section Header

struct SettingsSectionHeader: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, DS.Space.s10)
            .padding(.top, DS.Space.s4)
            .padding(.bottom, -DS.Space.s8)
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
                            .frame(width: 24, height: 24)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    } else {
                        // Use SF Symbol with colored background
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(iconColor.gradient)
                                .frame(width: 24, height: 24)
                            Image(systemName: icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: DS.Space.s8)

                trailing()
                    .toggleStyle(.settingsSwitch)

                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.flixorIcon(DS.Icon.xs, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, DS.Space.s12)
            .padding(.vertical, DS.Space.s8)
            .frame(minHeight: 42)

            if showDivider {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
                    .padding(.leading, icon != nil ? 48 : 12)
                    .padding(.trailing, DS.Space.s12)
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

// MARK: - Content Settings View

/// Catalogs, Discovery Mode and Search used to be three pages; they all decide
/// what Flixor shows you, so they live together.
private struct ContentSettingsView: View {
    @ObservedObject private var settings = ProfileSettings.shared
    @ObservedObject private var appMode = AppModeStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            // Library visibility needs a Plex server.
            if !appMode.isStremioOnly {
                CatalogSettingsView()
            }

            SettingsSectionHeader(title: "Discovery")
            SettingsGroupCard {
                SettingsRow(
                    icon: "eye.slash.fill",
                    iconColor: Color(hex: "E0405F"),
                    title: "Library Only",
                    subtitle: "Hide Trending, Trakt picks, Popular on Plex, New & Popular and TMDB results"
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.discoveryDisabled },
                        set: { settings.setDiscoveryDisabled($0) }
                    ))
                    .labelsHidden()
                }
                SettingsRow(
                    icon: "magnifyingglass",
                    iconColor: Color(hex: "1E8E8E"),
                    title: "TMDB Results in Search",
                    subtitle: settings.discoveryDisabled
                        ? "Off while Library Only is on"
                        : "Movies and shows you don't own, plus suggestions before you type",
                    showDivider: false
                ) {
                    Toggle("", isOn: $settings.includeTmdbInSearch)
                        .labelsHidden()
                        .disabled(settings.discoveryDisabled)
                }
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
        VStack(alignment: .leading, spacing: DS.Space.s16) {
        SettingsGroupCard {
            if let profile {
                SettingsStatusRow(.connected, title: String(localized: "Connected"),
                                  subtitle: String(localized: "Signed in as @\(profile.ids?.slug ?? profile.username ?? "user")")) {
                    Button("Disconnect") {
                        Task { await disconnect() }
                    }
                    .buttonStyle(.settingsDestructive)
                }
            } else {
                SettingsStatusRow(.notSetUp, title: String(localized: "Not connected"),
                                  subtitle: String(localized: "Sign in to sync your watch history")) {
                    if deviceCode == nil {
                        Button(action: { Task { await startDeviceCodeFlow() } }) {
                            HStack(spacing: DS.Space.s6) {
                                if isRequestingCode { ProgressView().controlSize(.small) }
                                Text(isRequestingCode ? "Requesting…" : "Sign in with Trakt")
                            }
                        }
                        .buttonStyle(.settingsPrimary)
                        .disabled(isRequestingCode)
                    }
                }
                if let deviceCode {
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.horizontal, DS.Space.s12)
                    deviceCodeView(deviceCode)
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
                    .foregroundStyle(SettingsChrome.destructive)
                Text(errorMessage)
                    .font(.flixor(.caption))
                    .foregroundStyle(SettingsChrome.destructive)
            }
        }

        SettingsSectionHeader(title: "Sync")
        SettingsGroupCard {
            SettingsRow(icon: "arrow.triangle.2.circlepath", iconColor: .blue, title: "Auto-sync watched", subtitle: "Mark items watched on Trakt when you finish them") {
                Toggle("", isOn: $profileSettings.traktAutoSyncWatched).labelsHidden()
            }
            SettingsRow(icon: "star.fill", iconColor: .yellow, title: "Sync ratings") {
                Toggle("", isOn: $profileSettings.traktSyncRatings).labelsHidden()
            }
            SettingsRow(icon: "bookmark.fill", iconColor: .purple, title: "Sync watchlist") {
                Toggle("", isOn: $profileSettings.traktSyncWatchlist).labelsHidden()
            }
            SettingsRow(icon: "play.circle.fill", iconColor: traktColor, title: "Scrobbling", subtitle: "Report what you're watching in real time", showDivider: false) {
                Toggle("", isOn: $profileSettings.traktScrobbleEnabled).labelsHidden()
            }
        }

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
                    .buttonStyle(.settingsSecondary)

                    Button("Open Trakt") {
                        if let url = URL(string: code.verification_url) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.settingsPrimary)
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
        VStack(alignment: .leading, spacing: DS.Space.s16) {
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

            SettingsFootnote("Detailed logs help diagnose problems. They stay in memory and are cleared when Flixor quits.")

            SettingsGroupCard {
                SettingsNavigationRow(
                    icon: "doc.text.fill",
                    iconColor: .blue,
                    title: "View Logs",
                    subtitle: logger.logCount == 0 && !logger.debugEnabled
                        ? "Turn on debug logging to collect logs"
                        : "\(logger.logCount) entries",
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
    @State private var showAcknowledgements = false

    var body: some View {
        HStack(spacing: DS.Space.s12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 1) {
                Text("Flixor")
                    .font(.system(size: 19, weight: .bold))
                Text("Version \(Bundle.main.appVersion) · A native macOS client for Plex and Stremio")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, DS.Space.s4)

        SettingsGroupCard {
            SettingsNavigationRow(icon: "globe", iconColor: .gray, title: "Website", subtitle: "flixor.xyz") {
                open("https://flixor.xyz")
            }
            SettingsNavigationRow(icon: "star.fill", iconColor: .gray, title: "Star on GitHub", subtitle: "github.com/Flixorui/flixor") {
                open("https://github.com/Flixorui/flixor")
            }
            SettingsNavigationRow(icon: "exclamationmark.bubble.fill", iconColor: .gray, title: "Report an Issue") {
                open("https://github.com/Flixorui/flixor/issues/new")
            }
            SettingsNavigationRow(icon: "bubble.left.and.bubble.right.fill", iconColor: .gray, title: "Reddit", subtitle: "r/Flixor", showDivider: false) {
                open("https://www.reddit.com/r/Flixor/")
            }
        }

        SettingsGroupCard {
            SettingsNavigationRow(title: "Acknowledgements", subtitle: "Phosphor Icons, Heroicons") {
                showAcknowledgements = true
            }
            SettingsNavigationRow(title: "Privacy Policy") {}
            SettingsNavigationRow(title: "Terms of Service", showDivider: false) {}
        }
        .sheet(isPresented: $showAcknowledgements) {
            AcknowledgementsSheet(isPresented: $showAcknowledgements)
        }
    }

    private func open(_ address: String) {
        if let url = URL(string: address) { NSWorkspace.shared.open(url) }
    }
}

private struct AcknowledgementsSheet: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Acknowledgements")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(DS.Space.s16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s12) {
                    Text("Navigation icons: Phosphor Icons (MIT License, © 2023 Phosphor Icons) and Heroicons (MIT License, © Tailwind Labs, Inc.).")
                        .font(.system(size: 12.5))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(ThirdPartyNotices.iconLicenses)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Space.s16)
            }
        }
        .frame(width: 600, height: 520)
        .pureBlackSheetBackground()
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
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, DS.Space.s10)
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

// MARK: - Third-party notices

enum ThirdPartyNotices {
    /// Full licence texts for the navigation icons in Assets.xcassets/NavIcons.
    static let iconLicenses = """
    Phosphor Icons (https://phosphoricons.com)

    MIT License

    Copyright (c) 2023 Phosphor Icons

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.

    Heroicons (https://heroicons.com)

    MIT License

    Copyright (c) Tailwind Labs, Inc.

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
    """
}
