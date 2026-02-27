import SwiftUI
import FlixorKit

private enum TVSettingsCategory: String, CaseIterable, Identifiable {
    case plex
    case player
    case discoveryMode
    case catalogs
    case rowsSettings
    case sidebar
    case search
    case homeScreen
    case detailsScreen
    case tmdb
    case mdblist
    case overseerr
    case trakt
    case advanced
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plex: return "Plex"
        case .player: return "Player"
        case .discoveryMode: return "Discovery Mode"
        case .catalogs: return "Catalogs"
        case .rowsSettings: return "Rows Settings"
        case .sidebar: return "Sidebar"
        case .search: return "Search"
        case .homeScreen: return "Home Screen"
        case .detailsScreen: return "Details Screen"
        case .tmdb: return "TMDB"
        case .mdblist: return "MDBList"
        case .overseerr: return "Overseerr"
        case .trakt: return "Trakt"
        case .advanced: return "Advanced"
        case .about: return "About"
        }
    }

    var description: String {
        switch self {
        case .plex: return "Account and server connection"
        case .player: return "Playback engine and transport defaults"
        case .discoveryMode: return "Control external discovery surfaces"
        case .catalogs: return "Library visibility and inclusion"
        case .rowsSettings: return "Home rows and row-level behavior"
        case .sidebar: return "Sidebar destinations and visibility"
        case .search: return "Search provider behavior"
        case .homeScreen: return "Hero and card presentation"
        case .detailsScreen: return "Details metadata display"
        case .tmdb: return "TMDB metadata configuration"
        case .mdblist: return "Multi-source rating integration"
        case .overseerr: return "Request management integration"
        case .trakt: return "Auth and sync behavior"
        case .advanced: return "Diagnostics and debug options"
        case .about: return "App information"
        }
    }

    var icon: String {
        switch self {
        case .plex: return "server.rack"
        case .player: return "play.rectangle.fill"
        case .discoveryMode: return "eye.slash"
        case .catalogs: return "rectangle.stack"
        case .rowsSettings: return "square.grid.3x1.below.line.grid.1x2"
        case .sidebar: return "sidebar.left"
        case .search: return "magnifyingglass"
        case .homeScreen: return "house"
        case .detailsScreen: return "play.rectangle"
        case .tmdb: return "film"
        case .mdblist: return "star"
        case .overseerr: return "arrow.down.circle"
        case .trakt: return "chart.bar"
        case .advanced: return "wrench.and.screwdriver"
        case .about: return "info.circle"
        }
    }

    var integrationAssetName: String? {
        switch self {
        case .plex: return "plexcolor"
        case .tmdb: return "tmdbcolor"
        case .mdblist: return "mdblistcolor"
        case .overseerr: return "overseerr"
        case .trakt: return "trakt"
        default: return nil
        }
    }

    var tint: Color {
        switch self {
        case .plex: return Color(hex: "E5A00D")
        case .player: return .blue
        case .discoveryMode: return Color(hex: "FF6B6B")
        case .catalogs: return .purple
        case .rowsSettings: return .cyan
        case .sidebar: return .mint
        case .search: return .indigo
        case .homeScreen: return .teal
        case .detailsScreen: return Color(hex: "5A6CF3")
        case .tmdb: return Color(hex: "01B4E4")
        case .mdblist: return Color(hex: "F5C518")
        case .overseerr: return Color(hex: "6366F1")
        case .trakt: return Color(hex: "ED1C24")
        case .advanced: return .orange
        case .about: return .gray
        }
    }
}

private struct TVSettingsSidebarSection: Identifiable {
    let title: String
    let categories: [TVSettingsCategory]
    var id: String { title }

    static var all: [TVSettingsSidebarSection] {
        [
            TVSettingsSidebarSection(title: "Account", categories: [.plex]),
            TVSettingsSidebarSection(title: "Playback", categories: [.player]),
            TVSettingsSidebarSection(title: "Content", categories: [.discoveryMode, .catalogs, .rowsSettings, .sidebar, .search]),
            TVSettingsSidebarSection(title: "Appearance", categories: [.homeScreen, .detailsScreen]),
            TVSettingsSidebarSection(title: "Integrations", categories: [.tmdb, .mdblist, .overseerr, .trakt]),
            TVSettingsSidebarSection(title: "System", categories: [.advanced, .about])
        ]
    }
}

private enum TVSettingsParityState {
    case complete
    case partial

    var label: String {
        switch self {
        case .complete: return "Parity"
        case .partial: return "Partial"
        }
    }

    var color: Color {
        switch self {
        case .complete: return .green
        case .partial: return .orange
        }
    }
}

private struct TVSettingsChoice<Value: Hashable>: Identifiable {
    let value: Value
    let label: String
    var id: String { "\(label)-\(String(describing: value))" }
}

struct TVSettingsView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionManager
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var profileSettings: TVProfileSettings

    @State private var selectedCategory: TVSettingsCategory = .plex

    @State private var error: String?
    @State private var statusMessage: String?
    @State private var showTestPlayer = false
    @State private var servers: [PlexServer] = []
    @State private var loadingServers = false
    @State private var connectingServerId: String?

    @State private var libraries: [PlexLibrary] = []
    @State private var loadingLibraries = false

    @State private var traktDeviceCode: TraktDeviceCodeResponse?
    @State private var traktExpiresAt: Date?
    @State private var traktPollingTask: Task<Void, Never>?
    @State private var traktMessage: String?
    @State private var mdblistMessage: String?
    @State private var overseerrMessage: String?
    @State private var overseerrTesting = false
    @FocusState private var focusedSidebarCategory: TVSettingsCategory?

    private let playbackSpeedOptions: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    private var activeServer: PlexServer? {
        servers.first(where: { $0.isActive == true })
    }

    private var defaults: UserDefaults { .standard }

    private var playerBackendBinding: Binding<PlayerBackend> {
        Binding(
            get: { defaults.playerBackend },
            set: { defaults.playerBackend = $0 }
        )
    }

    private var preferDirectPlayBinding: Binding<Bool> {
        Binding(
            get: { defaults.preferDirectPlay },
            set: { defaults.preferDirectPlay = $0 }
        )
    }

    private var allowDirectStreamBinding: Binding<Bool> {
        Binding(
            get: { defaults.allowDirectStream },
            set: { defaults.allowDirectStream = $0 }
        )
    }

    private var debugOverlayBinding: Binding<Bool> {
        Binding(
            get: { defaults.showDebugInfo },
            set: { defaults.showDebugInfo = $0 }
        )
    }

    private var filteredSidebarSections: [TVSettingsSidebarSection] { TVSettingsSidebarSection.all }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(hex: "1a0d0a"), Color(hex: "111827")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            HStack(spacing: 28) {
                sidebar
                content
            }
            .padding(.horizontal, 44)
            .padding(.vertical, 30)
        }
        .task {
            await refreshServers(autoSelectIfMissing: true)
            await loadLibraries()
            ensureSelectedCategoryIsVisible()
            focusedSidebarCategory = selectedCategory
        }
        .onChange(of: selectedCategory) { _, newValue in
            let allowed = Set(filteredSidebarSections.flatMap(\.categories))
            if allowed.contains(newValue) {
                focusedSidebarCategory = newValue
            }
        }
        .onDisappear {
            traktPollingTask?.cancel()
        }
#if DEBUG
        .fullScreenCover(isPresented: $showTestPlayer) {
            UniversalPlayerView()
        }
#endif
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings")
                .font(.system(size: 46, weight: .bold))
                .foregroundStyle(.white)

            Text("macOS parity audit + tvOS controls")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(filteredSidebarSections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.title.uppercased())
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white.opacity(0.45))
                                .padding(.leading, 8)

                            VStack(spacing: 6) {
                                ForEach(section.categories) { category in
                                    settingsSidebarRow(category)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 6)
                .padding(.bottom, 12)
            }
        }
        .frame(width: 360)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .focusSection()
    }

    private func settingsSidebarRow(_ category: TVSettingsCategory) -> some View {
        let selected = selectedCategory == category
        let focused = focusedSidebarCategory == category

        return Button {
            selectedCategory = category
            focusedSidebarCategory = category
        } label: {
            HStack(spacing: 12) {
                categoryIcon(category, size: 22)

                Text(category.title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle((selected || focused) ? .white : .white.opacity(0.88))

                Spacer(minLength: 8)

                if selected {
                    Circle()
                        .fill(category.tint)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? category.tint.opacity(0.26) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(selected ? category.tint.opacity(0.55) : Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(focused ? Color.white.opacity(0.72) : .clear, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(focused ? 1.035 : 1.0)
            .shadow(color: focused ? Color.white.opacity(0.18) : .clear, radius: 14, x: 0, y: 6)
            .animation(.easeOut(duration: 0.16), value: focused)
            .noSystemFocusChrome()
        }
        .buttonStyle(.plain)
        .hoverEffectDisabled(true)
        .noSystemFocusChrome()
        .focused($focusedSidebarCategory, equals: category)
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .zIndex(focused ? 1 : 0)
    }

    private var content: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                contentHeader

                switch selectedCategory {
                case .plex: plexSection
                case .player: playerSection
                case .discoveryMode: discoverySection
                case .catalogs: catalogsSection
                case .rowsSettings: rowsSection
                case .sidebar: sidebarSettingsSection
                case .search: searchSection
                case .homeScreen: homeAppearanceSection
                case .detailsScreen: detailsSection
                case .tmdb: tmdbSection
                case .mdblist: mdblistSection
                case .overseerr: overseerrSection
                case .trakt: traktSection
                case .advanced: advancedSection
                case .about: aboutSection
                }

                Color.clear.frame(height: 80)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 26)
            .padding(.vertical, 18)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .focusSection()
    }

    private var contentHeader: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selectedCategory.tint.opacity(0.25))
                    .frame(width: 72, height: 72)
                categoryIcon(selectedCategory, size: 32)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(selectedCategory.title)
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(.white)

                    let parity = parityState(for: selectedCategory)
                    Text(parity.label)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(parity.color, in: Capsule(style: .continuous))
                }

                Text(selectedCategory.description)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
            }

            Spacer()
        }
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func categoryIcon(_ category: TVSettingsCategory, size: CGFloat) -> some View {
        if let asset = category.integrationAssetName {
            Image(asset)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
        } else {
            Image(systemName: category.icon)
                .font(.system(size: size * 0.75, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private func parityState(for category: TVSettingsCategory) -> TVSettingsParityState {
        _ = category
        return .complete
    }

    private var plexSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            TVSettingsPanel(title: "Connection", subtitle: "Account and active Plex server") {
                if !session.isAuthenticated {
                    Text("Sign in to Plex to manage servers.")
                        .foregroundStyle(.white.opacity(0.75))

                    Button("Sign in with Code") { appState.startLinking() }
                        .buttonStyle(.borderedProminent)
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: activeServer == nil ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                            .foregroundStyle(activeServer == nil ? .orange : .green)
                        Text(activeServer.map { "Connected to \($0.name)" } ?? "No active server selected")
                            .foregroundStyle(activeServer == nil ? Color.orange : Color.green)
                    }

                    HStack(spacing: 12) {
                        Button("Refresh") {
                            Task { await refreshServers(autoSelectIfMissing: false) }
                        }
                        .buttonStyle(.bordered)
                        .disabled(loadingServers)

                        if let fallback = servers.first(where: { $0.owned == true }) ?? servers.first, activeServer == nil {
                            Button("Connect \(fallback.name)") {
                                Task { await connect(to: fallback) }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }

            if !servers.isEmpty {
                TVSettingsPanel(title: "Servers") {
                    VStack(spacing: 10) {
                        ForEach(servers, id: \.id) { server in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(server.name)
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(.white)

                                    Text(server.owned == true ? "Owned" : "Shared")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.55))
                                }

                                Spacer()

                                if server.isActive == true {
                                    Text("Active")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.green)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Color.green.opacity(0.22), in: Capsule(style: .continuous))
                                } else {
                                    Button(connectingServerId == server.id ? "Connecting..." : "Connect") {
                                        Task { await connect(to: server) }
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(connectingServerId != nil)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }

            TVSettingsPanel(title: "Session") {
                Button("Sign Out") {
                    Task {
                        await session.logout()
                        await refreshServers(autoSelectIfMissing: false)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!session.isAuthenticated)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
            }
            if let error {
                Text(error)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var playerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            TVSettingsPanel(title: "Playback Engine", subtitle: "MPV/AVKit backend and stream mode") {
                TVSettingsChoiceRow(
                    title: "Player Backend",
                    subtitle: "System-wide playback engine",
                    selection: playerBackendBinding,
                    options: PlayerBackend.allCases.map { .init(value: $0, label: $0.displayName) }
                )

                TVSettingsToggleRow(title: "Prefer Direct Play", subtitle: "Use source file when available", isOn: preferDirectPlayBinding)
                TVSettingsToggleRow(title: "Allow Direct Stream", subtitle: "Allow remux without full transcode", isOn: allowDirectStreamBinding)
                TVSettingsChoiceRow(
                    title: "Default Quality",
                    subtitle: "Initial quality for new playback sessions",
                    selection: $profileSettings.defaultQuality,
                    options: Array(PlaybackQuality.allCases.enumerated()).map { index, quality in
                        TVSettingsChoice(value: index, label: quality.rawValue)
                    }
                )
                TVSettingsToggleRow(title: "Auto-play Next Episode", subtitle: "Automatically continue episodic playback", isOn: $profileSettings.autoPlayNext)
                TVSettingsToggleRow(title: "Remember Track Selection", subtitle: "Persist audio/subtitle selections", isOn: $profileSettings.rememberTrackSelections)
            }

            TVSettingsPanel(title: "Transport", subtitle: "Seek and speed defaults") {
                TVSettingsStepperRow(title: "Small Seek", subtitle: "Single left/right seek step", valueText: "\(profileSettings.seekTimeSmall)s") {
                    HStack(spacing: 8) {
                        TVSettingsIconButton(systemName: "minus") {
                            profileSettings.seekTimeSmall = max(1, profileSettings.seekTimeSmall - 5)
                        }
                        .disabled(profileSettings.seekTimeSmall <= 1)

                        TVSettingsIconButton(systemName: "plus") {
                            profileSettings.seekTimeSmall = min(120, profileSettings.seekTimeSmall + 5)
                        }
                        .disabled(profileSettings.seekTimeSmall >= 120)
                    }
                }

                TVSettingsStepperRow(title: "Large Seek", subtitle: "Accelerated seek step", valueText: "\(profileSettings.seekTimeLarge)s") {
                    HStack(spacing: 8) {
                        TVSettingsIconButton(systemName: "minus") {
                            profileSettings.seekTimeLarge = max(5, profileSettings.seekTimeLarge - 10)
                        }
                        .disabled(profileSettings.seekTimeLarge <= 5)

                        TVSettingsIconButton(systemName: "plus") {
                            profileSettings.seekTimeLarge = min(300, profileSettings.seekTimeLarge + 10)
                        }
                        .disabled(profileSettings.seekTimeLarge >= 300)
                    }
                }

                TVSettingsChoiceRow(
                    title: "Default Speed",
                    subtitle: "Starting playback speed",
                    selection: $profileSettings.defaultPlaybackSpeed,
                    options: playbackSpeedOptions.map { speed in
                        TVSettingsChoice(value: speed, label: "\(String(format: "%.2g", speed))x")
                    }
                )
            }

            TVSettingsPanel(title: "Auto Skip", subtitle: "Automatic intro/credits behavior") {
                TVSettingsToggleRow(title: "Skip Intro Automatically", subtitle: "If intro markers are present", isOn: $profileSettings.skipIntroAutomatically)
                TVSettingsToggleRow(title: "Skip Credits Automatically", subtitle: "If credits markers are present", isOn: $profileSettings.skipCreditsAutomatically)
            }

            TVSettingsPanel(title: "Continue Watching Cache", subtitle: "Stream URL caching behavior") {
                TVSettingsToggleRow(title: "Cache Stream URLs", subtitle: "Faster resume at the risk of stale URLs", isOn: $profileSettings.useCachedStreams)

                TVSettingsChoiceRow(
                    title: "Cache TTL",
                    subtitle: "Expiry for cached stream URLs",
                    selection: $profileSettings.streamCacheTTL,
                    options: [
                        TVSettingsChoice(value: 900, label: "15 min"),
                        TVSettingsChoice(value: 1800, label: "30 min"),
                        TVSettingsChoice(value: 3600, label: "1 hour"),
                        TVSettingsChoice(value: 21600, label: "6 hours"),
                        TVSettingsChoice(value: 43200, label: "12 hours"),
                        TVSettingsChoice(value: 86400, label: "24 hours")
                    ]
                )
                .disabled(!profileSettings.useCachedStreams)
            }

#if DEBUG
            TVSettingsPanel(title: "Debug") {
                Button("Open MPV Test Player") {
                    showTestPlayer = true
                }
                .buttonStyle(.borderedProminent)
            }
#endif
        }
    }

    private var discoverySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            TVSettingsPanel(title: "Discovery Mode") {
                TVSettingsToggleRow(
                    title: "Library Only Mode",
                    subtitle: "Disable TMDB/Trakt discovery surfaces",
                    isOn: Binding(
                        get: { profileSettings.discoveryDisabled },
                        set: { profileSettings.setDiscoveryDisabled($0) }
                    )
                )

                TVSettingsToggleRow(title: "Show Trending Rows", subtitle: "Home trending sections", isOn: $profileSettings.showTrendingRows)
                    .disabled(profileSettings.discoveryDisabled)
                TVSettingsToggleRow(title: "Show Trakt Rows", subtitle: "Trakt-based recommendations", isOn: $profileSettings.showTraktRows)
                    .disabled(profileSettings.discoveryDisabled)
                TVSettingsToggleRow(title: "Show Popular on Plex", subtitle: "Popular from your libraries", isOn: $profileSettings.showPlexPopular)
                    .disabled(profileSettings.discoveryDisabled)
            }

            Text("When Library Only Mode is enabled, discovery-heavy sections and New & Popular are automatically disabled.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
        }
    }

    private var catalogsSection: some View {
        TVSettingsPanel(title: "Library Visibility", subtitle: "Choose which libraries feed Home/Search") {
            if loadingLibraries {
                ProgressView("Loading libraries…")
            } else if libraries.isEmpty {
                Text("No libraries found")
                    .foregroundStyle(.white.opacity(0.75))
            } else {
                VStack(spacing: 10) {
                    ForEach(libraries, id: \.key) { library in
                        TVSettingsToggleRow(
                            title: library.title ?? "Library",
                            subtitle: library.type.capitalized,
                            isOn: Binding(
                                get: {
                                    let enabled = Set(profileSettings.enabledLibraryKeys)
                                    return enabled.isEmpty || enabled.contains(library.key)
                                },
                                set: { enabled in
                                    var keys = Set(profileSettings.enabledLibraryKeys)
                                    if enabled {
                                        if !keys.isEmpty { keys.insert(library.key) }
                                    } else {
                                        if keys.isEmpty { keys = Set(libraries.map(\.key)) }
                                        keys.remove(library.key)
                                    }
                                    profileSettings.enabledLibraryKeys = keys.count == libraries.count ? [] : keys.sorted()
                                }
                            )
                        )
                    }
                }
            }
        }
    }

    private var rowsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            TVSettingsPanel(title: "Row Visibility") {
                TVSettingsToggleRow(title: "Continue Watching", subtitle: "Show active progress row", isOn: $profileSettings.showContinueWatching)
                TVSettingsToggleRow(title: "Watchlist", subtitle: "Show Plex + Trakt watchlist row", isOn: $profileSettings.showWatchlist)
                TVSettingsToggleRow(title: "Collections", subtitle: "Home collection rows", isOn: $profileSettings.showCollectionRows)
                TVSettingsToggleRow(title: "On Deck", subtitle: "Compatibility row", isOn: $profileSettings.showOnDeckRow)
                TVSettingsToggleRow(title: "Group Recently Added Episodes", subtitle: "Prefer series grouping", isOn: $profileSettings.groupRecentlyAddedEpisodes)
            }

            TVSettingsPanel(title: "Hero") {
                TVSettingsToggleRow(title: "Show Hero Section", subtitle: "Display featured hero at top", isOn: $profileSettings.showHeroSection)
                TVSettingsToggleRow(title: "Auto Rotate Hero", subtitle: "Rotate featured hero entries", isOn: $profileSettings.heroAutoRotate)
                    .disabled(!profileSettings.showHeroSection)

                TVSettingsChoiceRow(
                    title: "Hero Layout",
                    subtitle: "Billboard or carousel mode",
                    selection: $profileSettings.heroLayout,
                    options: [
                        TVSettingsChoice(value: "carousel", label: "Carousel"),
                        TVSettingsChoice(value: "billboard", label: "Billboard")
                    ]
                )
                .disabled(!profileSettings.showHeroSection)
            }
        }
    }

    private var sidebarSettingsSection: some View {
        TVSettingsPanel(title: "Destinations") {
            TVSettingsToggleRow(
                title: "Show New & Popular",
                subtitle: profileSettings.discoveryDisabled ? "Disabled by Library Only Mode" : "Show New & Popular destination in sidebar",
                isOn: $profileSettings.showNewPopularTab
            )
            .disabled(profileSettings.discoveryDisabled)
        }
    }

    private var searchSection: some View {
        TVSettingsPanel(title: "Search Providers") {
            TVSettingsToggleRow(
                title: "Include TMDB Results",
                subtitle: profileSettings.discoveryDisabled ? "Disabled by Library Only Mode" : "Blend TMDB results into search",
                isOn: $profileSettings.includeTmdbInSearch
            )
            .disabled(profileSettings.discoveryDisabled)
        }
    }

    private var homeAppearanceSection: some View {
        TVSettingsPanel(title: "Cards & Rails", subtitle: "Home and library presentation") {
            TVSettingsChoiceRow(
                title: "Continue Watching Layout",
                subtitle: "Card style for Continue Watching row",
                selection: $profileSettings.continueWatchingLayout,
                options: [
                    TVSettingsChoice(value: "poster", label: "Poster"),
                    TVSettingsChoice(value: "landscape", label: "Landscape")
                ]
            )

            TVSettingsChoiceRow(
                title: "Default Row Layout",
                subtitle: "Card style for general rows",
                selection: $profileSettings.rowLayout,
                options: [
                    TVSettingsChoice(value: "poster", label: "Poster"),
                    TVSettingsChoice(value: "landscape", label: "Landscape")
                ]
            )

            TVSettingsToggleRow(title: "Show Poster Titles", subtitle: "Show title on focused posters", isOn: $profileSettings.showPosterTitles)
            TVSettingsToggleRow(title: "Show Library Titles", subtitle: "Show title in library list/grid contexts", isOn: $profileSettings.showLibraryTitles)

            TVSettingsChoiceRow(
                title: "Poster Size",
                subtitle: "Global poster density across rails and library",
                selection: $profileSettings.posterSize,
                options: [
                    TVSettingsChoice(value: "small", label: "Small"),
                    TVSettingsChoice(value: "medium", label: "Medium"),
                    TVSettingsChoice(value: "large", label: "Large")
                ]
            )

            TVSettingsChoiceRow(
                title: "Poster Corner Radius",
                subtitle: "Poster card corner rounding",
                selection: $profileSettings.posterCornerRadius,
                options: [
                    TVSettingsChoice(value: "none", label: "None"),
                    TVSettingsChoice(value: "small", label: "Small"),
                    TVSettingsChoice(value: "medium", label: "Medium"),
                    TVSettingsChoice(value: "large", label: "Large")
                ]
            )
        }
    }

    private var detailsSection: some View {
        TVSettingsPanel(title: "Details Content", subtitle: "Control what metadata appears") {
            TVSettingsToggleRow(title: "Show Related Content", subtitle: "Because You Watched / More Like This", isOn: $profileSettings.showRelatedContent)
            TVSettingsToggleRow(title: "Show Cast & Crew", subtitle: "Cast rails and hero credit blocks", isOn: $profileSettings.showCastCrew)

            TVSettingsToggleRow(title: "IMDb Rating", subtitle: "Show IMDb badge/score", isOn: $profileSettings.showIMDbRating)
            TVSettingsToggleRow(title: "Rotten Tomatoes Critics", subtitle: "Show Tomatometer score", isOn: $profileSettings.showRottenTomatoesCritic)
            TVSettingsToggleRow(title: "Rotten Tomatoes Audience", subtitle: "Show audience score", isOn: $profileSettings.showRottenTomatoesAudience)
        }
    }

    private var tmdbSection: some View {
        TVSettingsPanel(title: "TMDB") {
            TVSettingsFieldBlock(title: "Custom API Key", subtitle: "Optional override; leave empty to use app default") {
                TextField("TMDB API Key", text: Binding(
                    get: { defaults.tmdbApiKey },
                    set: { defaults.tmdbApiKey = $0 }
                ))
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08)))
            }

            TVSettingsChoiceRow(
                title: "Language",
                subtitle: "Preferred metadata localization",
                selection: $profileSettings.tmdbLanguage,
                options: [
                    TVSettingsChoice(value: "en", label: "English"),
                    TVSettingsChoice(value: "es", label: "Spanish"),
                    TVSettingsChoice(value: "fr", label: "French"),
                    TVSettingsChoice(value: "de", label: "German"),
                    TVSettingsChoice(value: "ja", label: "Japanese")
                ]
            )

            TVSettingsToggleRow(title: "Enrich Metadata", subtitle: "Fetch cast, logos, and extras", isOn: $profileSettings.tmdbEnrichMetadata)
            TVSettingsToggleRow(title: "Localized Metadata", subtitle: "Prefer localized titles/summaries", isOn: $profileSettings.tmdbLocalizedMetadata)
        }
    }

    private var mdblistSection: some View {
        TVSettingsPanel(title: "MDBList", subtitle: "External ratings enrichment") {
            TVSettingsToggleRow(title: "Enable MDBList", subtitle: "Enable MDBList rating enrichment", isOn: $profileSettings.mdblistEnabled)

            TVSettingsFieldBlock(title: "API Key") {
                SecureField("MDBList API Key", text: $profileSettings.mdblistApiKey)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08)))
                    .disabled(!profileSettings.mdblistEnabled)
                    .opacity(profileSettings.mdblistEnabled ? 1 : 0.5)
            }

            HStack(spacing: 10) {
                Button("Clear Ratings Cache") {
                    TVMDBListService.shared.clearCache()
                    mdblistMessage = "MDBList cache cleared."
                }
                .buttonStyle(.bordered)
                .disabled(!profileSettings.mdblistEnabled)

                if TVMDBListService.shared.isReady {
                    Text("Ready")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.green)
                } else {
                    Text("Not ready")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.orange)
                }
            }

            if let mdblistMessage {
                Text(mdblistMessage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
            }
        }
    }

    private var overseerrSection: some View {
        TVSettingsPanel(title: "Overseerr", subtitle: "Request workflow") {
            TVSettingsToggleRow(title: "Enable Overseerr", subtitle: "Enable request integration", isOn: $profileSettings.overseerrEnabled)

            TVSettingsFieldBlock(title: "Server URL") {
                TextField("https://overseerr.example.com", text: $profileSettings.overseerrUrl)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08)))
                    .disabled(!profileSettings.overseerrEnabled)
                    .opacity(profileSettings.overseerrEnabled ? 1 : 0.5)
            }

            TVSettingsChoiceRow(
                title: "Auth Method",
                subtitle: "API key or Plex session login",
                selection: $profileSettings.overseerrAuthMethod,
                options: [
                    TVSettingsChoice(value: TVOverseerrAuthMethod.apiKey, label: "API Key"),
                    TVSettingsChoice(value: TVOverseerrAuthMethod.plex, label: "Plex Session")
                ]
            )
            .opacity(profileSettings.overseerrEnabled ? 1 : 0.5)
            .disabled(!profileSettings.overseerrEnabled)

            if profileSettings.overseerrAuthMethod == .apiKey {
                TVSettingsFieldBlock(title: "API Key") {
                    SecureField("Overseerr API Key", text: $profileSettings.overseerrApiKey)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08)))
                        .disabled(!profileSettings.overseerrEnabled)
                        .opacity(profileSettings.overseerrEnabled ? 1 : 0.5)
                }
            } else {
                TVSettingsFieldBlock(title: "Plex Session") {
                    Text(profileSettings.overseerrSessionCookie.isEmpty ? "No session cookie stored" : "Session cookie stored")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.74))
                    if !profileSettings.overseerrPlexUsername.isEmpty {
                        Text("User: \(profileSettings.overseerrPlexUsername)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }

            HStack(spacing: 10) {
                Button(overseerrTesting ? "Testing..." : "Test Connection") {
                    Task { await testOverseerrConnection() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!profileSettings.overseerrEnabled || overseerrTesting)

                if profileSettings.overseerrAuthMethod == .plex {
                    Button("Sign Out") {
                        TVOverseerrService.shared.signOut()
                        profileSettings.overseerrSessionCookie = ""
                        profileSettings.overseerrPlexUsername = ""
                        overseerrMessage = "Signed out from Overseerr."
                    }
                    .buttonStyle(.bordered)
                    .disabled(overseerrTesting)
                }
            }

            if let overseerrMessage {
                Text(overseerrMessage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
            }
        }
    }

    private var traktSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            TVSettingsPanel(title: "Account") {
                if FlixorCore.shared.trakt.isAuthenticated {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Trakt connected")
                            .foregroundStyle(.green)
                    }

                    Button("Sign Out Trakt") {
                        Task {
                            _ = try? await api.traktSignOut()
                        }
                    }
                    .buttonStyle(.bordered)
                } else if let code = traktDeviceCode {
                    Text("Enter code: \(code.user_code)")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Visit \(code.verification_url)")
                        .foregroundStyle(.white.opacity(0.75))
                    if let expiresAt = traktExpiresAt {
                        Text("Expires: \(expiresAt.formatted(date: .omitted, time: .standard))")
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    Button("Cancel") {
                        traktPollingTask?.cancel()
                        traktDeviceCode = nil
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Connect Trakt") {
                        Task { await startTraktDeviceFlow() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            TVSettingsPanel(title: "Sync") {
                TVSettingsToggleRow(title: "Sync Watched", subtitle: "Sync watched history", isOn: $profileSettings.traktAutoSyncWatched)
                TVSettingsToggleRow(title: "Sync Ratings", subtitle: "Sync ratings to Trakt", isOn: $profileSettings.traktSyncRatings)
                TVSettingsToggleRow(title: "Sync Watchlist", subtitle: "Sync watchlist changes", isOn: $profileSettings.traktSyncWatchlist)
                TVSettingsToggleRow(title: "Enable Scrobbling", subtitle: "Report active playback", isOn: $profileSettings.traktScrobbleEnabled)
            }

            if let traktMessage {
                Text(traktMessage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
    }

    private var advancedSection: some View {
        TVSettingsPanel(title: "Diagnostics") {
            TVSettingsToggleRow(title: "Debug Overlay", subtitle: "Show runtime diagnostics", isOn: debugOverlayBinding)
            TVSettingsInfoRow(title: "App Version", value: Bundle.main.appVersion)
            TVSettingsInfoRow(title: "Build Runtime", value: "tvOS backendless core")
        }
    }

    private var aboutSection: some View {
        TVSettingsPanel(title: "Flixor tvOS") {
            Text("Backendless runtime using FlixorCore with direct Plex/TMDB/Trakt services.")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.white.opacity(0.82))

            TVSettingsInfoRow(title: "Build", value: Bundle.main.appVersion)
            TVSettingsInfoRow(title: "Platform", value: "tvOS")
            TVSettingsInfoRow(title: "Playback", value: "MPV default, AVKit fallback")
        }
    }

    private func ensureSelectedCategoryIsVisible() {
        let allowed = Set(filteredSidebarSections.flatMap(\.categories))
        if !allowed.contains(selectedCategory), let first = filteredSidebarSections.first?.categories.first {
            selectedCategory = first
        }
    }

    private func refreshServers(autoSelectIfMissing: Bool) async {
        guard session.isAuthenticated else {
            servers = []
            statusMessage = nil
            return
        }

        loadingServers = true
        defer { loadingServers = false }

        do {
            error = nil
            var fetched = try await api.getPlexServers()

            if autoSelectIfMissing, fetched.first(where: { $0.isActive == true }) == nil,
               let preferred = fetched.first(where: { $0.owned == true }) ?? fetched.first {
                _ = try await api.setCurrentPlexServer(serverId: preferred.id)
                fetched = try await api.getPlexServers()
                statusMessage = "Connected to \(preferred.name)"
            }

            servers = fetched
        } catch {
            self.error = "Failed to load Plex servers: \(error.localizedDescription)"
        }
    }

    private func connect(to server: PlexServer) async {
        connectingServerId = server.id
        defer { connectingServerId = nil }

        do {
            _ = try await api.setCurrentPlexServer(serverId: server.id)
            statusMessage = "Connected to \(server.name)"
            error = nil
            await refreshServers(autoSelectIfMissing: false)
        } catch {
            self.error = "Unable to connect \(server.name): \(error.localizedDescription)"
        }
    }

    private func loadLibraries() async {
        loadingLibraries = true
        defer { loadingLibraries = false }
        do {
            libraries = try await api.getPlexLibraries()
        } catch {
            libraries = []
        }
    }

    private func startTraktDeviceFlow() async {
        do {
            let deviceCode = try await api.traktDeviceCode()
            traktDeviceCode = deviceCode
            traktExpiresAt = Date().addingTimeInterval(TimeInterval(deviceCode.expires_in))
            traktMessage = "Approve the code in Trakt, then wait for automatic completion."
            startTraktPolling(code: deviceCode.device_code, interval: deviceCode.interval ?? 5)
        } catch {
            traktMessage = "Unable to start Trakt login: \(error.localizedDescription)"
        }
    }

    private func startTraktPolling(code: String, interval: Int) {
        traktPollingTask?.cancel()
        traktPollingTask = Task {
            while !Task.isCancelled {
                do {
                    let response = try await api.traktDeviceToken(code: code)
                    if response.ok {
                        await MainActor.run {
                            traktMessage = "Trakt connected"
                            traktDeviceCode = nil
                        }
                        return
                    }
                } catch {
                    await MainActor.run {
                        traktMessage = "Trakt polling failed: \(error.localizedDescription)"
                    }
                    return
                }
                try? await Task.sleep(nanoseconds: UInt64(max(2, interval)) * 1_000_000_000)
            }
        }
    }

    private func testOverseerrConnection() async {
        guard profileSettings.overseerrEnabled else {
            overseerrMessage = "Enable Overseerr first."
            return
        }

        let url = profileSettings.overseerrUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            overseerrMessage = "Enter an Overseerr URL."
            return
        }

        overseerrTesting = true
        defer { overseerrTesting = false }

        if profileSettings.overseerrAuthMethod == .apiKey {
            let key = profileSettings.overseerrApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                overseerrMessage = "Enter an API key."
                return
            }
            let result = await TVOverseerrService.shared.validateConnection(url: url, apiKey: key)
            if result.valid {
                overseerrMessage = "Connected as \(result.username ?? "user")."
            } else {
                overseerrMessage = result.error ?? "Connection failed."
            }
            return
        }

        // Plex-session auth flow
        if profileSettings.overseerrSessionCookie.isEmpty {
            let auth = await TVOverseerrService.shared.authenticateWithPlex(url: url)
            if auth.valid {
                if let username = auth.username {
                    profileSettings.overseerrPlexUsername = username
                }
                profileSettings.overseerrSessionCookie = UserDefaults.standard.overseerrSessionCookie
                overseerrMessage = "Connected as \(auth.username ?? "Plex user")."
            } else {
                overseerrMessage = auth.error ?? "Authentication failed."
            }
        } else {
            let result = await TVOverseerrService.shared.validatePlexSession(url: url)
            if result.valid {
                if let username = result.username {
                    profileSettings.overseerrPlexUsername = username
                }
                overseerrMessage = "Session valid for \(result.username ?? "Plex user")."
            } else {
                profileSettings.overseerrSessionCookie = ""
                profileSettings.overseerrPlexUsername = ""
                overseerrMessage = result.error ?? "Session invalid."
            }
        }
    }
}

private struct TVSettingsPanel<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

private struct TVSettingsInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
            Spacer()
            Text(value)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.white)
        }
    }
}

private struct TVSettingsToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    @FocusState private var controlFocused: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                }
            }
            Spacer()
            Button {
                isOn.toggle()
            } label: {
                HStack(spacing: 10) {
                    Circle()
                        .fill(isOn ? Color.green : Color.white.opacity(0.25))
                        .frame(width: 10, height: 10)
                    Text(isOn ? "On" : "Off")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
                .background(
                    Capsule(style: .continuous)
                        .fill(isOn ? Color.green.opacity(0.22) : Color.white.opacity(0.08))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(isOn ? Color.green.opacity(0.55) : Color.white.opacity(0.16), lineWidth: 1)
                        )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(controlFocused ? Color.white.opacity(0.55) : .clear, lineWidth: 2)
                )
                .clipShape(Capsule(style: .continuous))
                .noSystemFocusChrome()
            }
            .buttonStyle(.plain)
            .hoverEffectDisabled(true)
            .noSystemFocusChrome()
            .focused($controlFocused)
            .scaleEffect(controlFocused ? 1.04 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.45)
            .animation(.easeOut(duration: 0.16), value: controlFocused)
            .disabled(!isEnabled)
        }
        .padding(.vertical, 4)
    }
}

private struct TVSettingsChoiceRow<Value: Hashable>: View {
    let title: String
    var subtitle: String? = nil
    @Binding var selection: Value
    let options: [TVSettingsChoice<Value>]
    @State private var showPicker = false
    @FocusState private var controlFocused: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                }
            }
            Spacer()

            Button {
                showPicker = true
            } label: {
                HStack(spacing: 10) {
                    Text(selectedLabel)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .frame(minWidth: 208, alignment: .center)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.16), lineWidth: 1)
                        )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(controlFocused ? Color.white.opacity(0.55) : .clear, lineWidth: 2)
                )
                .clipShape(Capsule(style: .continuous))
                .noSystemFocusChrome()
            }
            .buttonStyle(.plain)
            .hoverEffectDisabled(true)
            .noSystemFocusChrome()
            .focused($controlFocused)
            .scaleEffect(controlFocused ? 1.04 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.45)
            .animation(.easeOut(duration: 0.16), value: controlFocused)
            .disabled(!isEnabled)
            .sheet(isPresented: $showPicker) {
                TVSettingsChoicePickerSheet(
                    title: title,
                    subtitle: subtitle,
                    selection: $selection,
                    options: options
                )
            }
        }
        .padding(.vertical, 4)
    }

    private var selectedLabel: String {
        options.first(where: { $0.value == selection })?.label ?? "Select"
    }
}

private struct TVSettingsChoicePickerSheet<Value: Hashable>: View {
    let title: String
    var subtitle: String?
    @Binding var selection: Value
    let options: [TVSettingsChoice<Value>]

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedOptionId: String?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "0A0F1B"),
                    Color(hex: "11182A"),
                    Color(hex: "0A0F1B")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.white)
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.white.opacity(0.68))
                        }
                    }
                    Spacer()
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 34)
                .padding(.top, 28)

                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(options) { option in
                            let isSelected = option.value == selection
                            let isFocused = focusedOptionId == option.id
                            Button {
                                selection = option.value
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Text(option.label)
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Spacer()
                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 20, weight: .bold))
                                            .foregroundStyle(.green)
                                    }
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(isSelected ? Color.white.opacity(0.14) : Color.white.opacity(0.08))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .stroke(isSelected ? Color.white.opacity(0.44) : Color.white.opacity(0.18), lineWidth: 1)
                                        )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(isFocused ? Color.white.opacity(0.58) : .clear, lineWidth: 2)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .noSystemFocusChrome()
                            }
                            .buttonStyle(.plain)
                            .hoverEffectDisabled(true)
                            .noSystemFocusChrome()
                            .focused($focusedOptionId, equals: option.id)
                            .scaleEffect(isFocused ? 1.03 : 1.0)
                            .animation(.easeOut(duration: 0.16), value: isFocused)
                        }
                    }
                    .padding(.horizontal, 34)
                    .padding(.bottom, 28)
                }
            }
        }
    }
}

private struct TVSettingsStepperRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var valueText: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                }
            }

            HStack(spacing: 12) {
                Text(valueText)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .frame(minWidth: 62, alignment: .leading)
                trailing()
            }
        }
        .padding(.vertical, 4)
    }
}

private struct TVSettingsIconButton: View {
    let systemName: String
    let action: () -> Void
    @FocusState private var isFocused: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isFocused ? Color.white.opacity(0.55) : .clear, lineWidth: 2)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .noSystemFocusChrome()
        }
        .buttonStyle(.plain)
        .hoverEffectDisabled(true)
        .noSystemFocusChrome()
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.04 : 1.0)
        .opacity(isEnabled ? 1.0 : 0.45)
        .animation(.easeOut(duration: 0.16), value: isFocused)
        .disabled(!isEnabled)
    }
}

private struct TVSettingsFieldBlock<Field: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let field: () -> Field

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
            }
            field()
        }
    }
}

private extension Bundle {
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}

private extension Color {
    init(hex: String) {
        var sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if sanitized.count == 3 {
            sanitized = sanitized.map { "\($0)\($0)" }.joined()
        }

        var int: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&int)
        let r, g, b: UInt64
        switch sanitized.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (255, 255, 255)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}

private extension View {
    @ViewBuilder
    func noSystemFocusChrome() -> some View {
        self
            .focusEffectDisabled()
            .hoverEffectDisabled(true)
    }
}
