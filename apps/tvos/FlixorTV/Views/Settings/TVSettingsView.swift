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
        case .discoveryMode: return "Discovery"
        case .catalogs: return "Catalogs"
        case .rowsSettings: return "Rows"
        case .sidebar: return "Nav"
        case .search: return "Search"
        case .homeScreen: return "Home Screen"
        case .detailsScreen: return "Details"
        case .tmdb: return "TMDB"
        case .mdblist: return "MDBList"
        case .overseerr: return "Overseerr"
        case .trakt: return "Trakt"
        case .advanced: return "Advanced"
        case .about: return "About"
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
        case .advanced: return "ladybug"
        case .about: return "info.circle"
        }
    }
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

    private var activeServer: PlexServer? {
        servers.first(where: { $0.isActive == true })
    }

    private var defaults: UserDefaults { .standard }

    var body: some View {
        HStack(spacing: 24) {
            sidebar
            content
        }
        .padding(36)
        .background(Color.black)
        .task {
            await refreshServers(autoSelectIfMissing: true)
            await loadLibraries()
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
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Settings")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 10)

                ForEach(TVSettingsCategory.allCases) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: category.icon)
                                .font(.system(size: 20, weight: .semibold))
                                .frame(width: 24)
                            Text(category.title)
                                .font(.system(size: 24, weight: .semibold))
                            Spacer()
                        }
                        .foregroundStyle(selectedCategory == category ? .black : .white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(selectedCategory == category ? Color.white : Color.white.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 360)
        .focusSection()
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(selectedCategory.title)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white)

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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 60)
        }
        .frame(maxWidth: .infinity)
        .focusSection()
    }

    private var plexSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            TVSettingsCard {
                if !session.isAuthenticated {
                    Text("Sign in to Plex to manage servers.")
                        .foregroundStyle(.white.opacity(0.75))
                    Button("Sign in with Code") { appState.startLinking() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Text(activeServer.map { "Connected to \($0.name)" } ?? "No active server selected.")
                        .foregroundStyle(activeServer == nil ? .orange : .green)

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
                TVSettingsCard {
                    ForEach(servers, id: \.id) { server in
                        HStack {
                            Text(server.name)
                                .foregroundStyle(.white)
                            if server.isActive == true {
                                Text("Active")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.green.opacity(0.25), in: Capsule())
                                    .foregroundStyle(.green)
                            }
                            Spacer()
                            if server.isActive != true {
                                Button(connectingServerId == server.id ? "Connecting..." : "Connect") {
                                    Task { await connect(to: server) }
                                }
                                .buttonStyle(.bordered)
                                .disabled(connectingServerId != nil)
                            }
                        }
                    }
                }
            }

            TVSettingsCard {
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
                Text(statusMessage).foregroundStyle(.white.opacity(0.7))
            }
            if let error {
                Text(error).foregroundStyle(.orange)
            }
        }
    }

    private var playerSection: some View {
        TVSettingsCard {
            Picker("Player Backend", selection: Binding(
                get: { UserDefaults.standard.playerBackend },
                set: { UserDefaults.standard.playerBackend = $0 }
            )) {
                ForEach(PlayerBackend.allCases, id: \.self) { backend in
                    Text(backend.displayName).tag(backend)
                }
            }

            Toggle("Prefer Direct Play", isOn: Binding(
                get: { UserDefaults.standard.preferDirectPlay },
                set: { UserDefaults.standard.preferDirectPlay = $0 }
            ))

            Toggle("Allow Direct Stream", isOn: Binding(
                get: { UserDefaults.standard.allowDirectStream },
                set: { UserDefaults.standard.allowDirectStream = $0 }
            ))

            Toggle("Auto-play Next Episode", isOn: $profileSettings.autoPlayNext)
            Toggle("Remember Track Selection", isOn: $profileSettings.rememberTrackSelections)

#if DEBUG
            Button("Open MPV Test Player") {
                showTestPlayer = true
            }
            .buttonStyle(.borderedProminent)
#endif
        }
    }

    private var discoverySection: some View {
        TVSettingsCard {
            Toggle("Library Only Mode", isOn: Binding(
                get: { profileSettings.discoveryDisabled },
                set: { profileSettings.setDiscoveryDisabled($0) }
            ))
            Toggle("Show Trending Rows", isOn: $profileSettings.showTrendingRows)
                .disabled(profileSettings.discoveryDisabled)
            Toggle("Show Trakt Rows", isOn: $profileSettings.showTraktRows)
                .disabled(profileSettings.discoveryDisabled)
            Toggle("Show Popular on Plex", isOn: $profileSettings.showPlexPopular)
                .disabled(profileSettings.discoveryDisabled)
        }
    }

    private var catalogsSection: some View {
        TVSettingsCard {
            if loadingLibraries {
                ProgressView("Loading libraries…")
            } else if libraries.isEmpty {
                Text("No libraries found")
                    .foregroundStyle(.white.opacity(0.75))
            } else {
                ForEach(libraries, id: \.key) { library in
                    Toggle(
                        library.title ?? "Library",
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

    private var rowsSection: some View {
        TVSettingsCard {
            Toggle("Continue Watching", isOn: $profileSettings.showContinueWatching)
            Toggle("Watchlist", isOn: $profileSettings.showWatchlist)
            Toggle("Collections", isOn: $profileSettings.showCollectionRows)
            Toggle("On Deck (tvOS compatibility row)", isOn: $profileSettings.showOnDeckRow)
            Toggle("Group Recently Added Episodes", isOn: $profileSettings.groupRecentlyAddedEpisodes)
        }
    }

    private var sidebarSettingsSection: some View {
        TVSettingsCard {
            Toggle("Show New & Popular Destination", isOn: $profileSettings.showNewPopularTab)
                .disabled(profileSettings.discoveryDisabled)
        }
    }

    private var searchSection: some View {
        TVSettingsCard {
            Toggle("Include TMDB in Search", isOn: $profileSettings.includeTmdbInSearch)
                .disabled(profileSettings.discoveryDisabled)
        }
    }

    private var homeAppearanceSection: some View {
        TVSettingsCard {
            Toggle("Show Hero Section", isOn: $profileSettings.showHeroSection)
            Toggle("Auto Rotate Hero", isOn: $profileSettings.heroAutoRotate)

            Picker("Hero Layout", selection: $profileSettings.heroLayout) {
                Text("Billboard").tag("billboard")
                Text("Carousel").tag("carousel")
            }
            Picker("Continue Watching Layout", selection: $profileSettings.continueWatchingLayout) {
                Text("Poster").tag("poster")
                Text("Landscape").tag("landscape")
            }
            Picker("Default Row Layout", selection: $profileSettings.rowLayout) {
                Text("Poster").tag("poster")
                Text("Landscape").tag("landscape")
            }
            Toggle("Show Poster Titles", isOn: $profileSettings.showPosterTitles)
        }
    }

    private var detailsSection: some View {
        TVSettingsCard {
            Picker("Details Layout", selection: $profileSettings.detailsScreenLayout) {
                Text("Unified").tag("unified")
                Text("Tabbed").tag("tabbed")
            }
            Picker("Episode Layout", selection: $profileSettings.episodeLayout) {
                Text("Horizontal").tag("horizontal")
                Text("Vertical").tag("vertical")
            }
            Picker("Suggested Layout", selection: $profileSettings.suggestedLayout) {
                Text("Landscape").tag("landscape")
                Text("Poster").tag("poster")
            }
            Toggle("Show Related Content", isOn: $profileSettings.showRelatedContent)
            Toggle("Show Cast & Crew", isOn: $profileSettings.showCastCrew)
        }
    }

    private var tmdbSection: some View {
        TVSettingsCard {
            TextField("TMDB API Key (optional)", text: Binding(
                get: { defaults.tmdbApiKey },
                set: { defaults.tmdbApiKey = $0 }
            ))
            .textFieldStyle(.plain)
            Picker("Language", selection: $profileSettings.tmdbLanguage) {
                Text("English").tag("en")
                Text("Spanish").tag("es")
                Text("French").tag("fr")
                Text("German").tag("de")
                Text("Japanese").tag("ja")
            }
            Toggle("Enrich Metadata", isOn: $profileSettings.tmdbEnrichMetadata)
            Toggle("Localized Metadata", isOn: $profileSettings.tmdbLocalizedMetadata)
        }
    }

    private var mdblistSection: some View {
        TVSettingsCard {
            Toggle("Enable MDBList", isOn: $profileSettings.mdblistEnabled)
            SecureField("MDBList API Key", text: $profileSettings.mdblistApiKey)
                .textFieldStyle(.plain)
                .disabled(!profileSettings.mdblistEnabled)
        }
    }

    private var overseerrSection: some View {
        TVSettingsCard {
            Toggle("Enable Overseerr", isOn: $profileSettings.overseerrEnabled)
            TextField("Overseerr URL", text: $profileSettings.overseerrUrl)
                .textFieldStyle(.plain)
                .disabled(!profileSettings.overseerrEnabled)
        }
    }

    private var traktSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TVSettingsCard {
                if FlixorCore.shared.trakt.isAuthenticated {
                    Text("Trakt connected")
                        .foregroundStyle(.green)
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
                Toggle("Sync Watched", isOn: $profileSettings.traktAutoSyncWatched)
                Toggle("Sync Ratings", isOn: $profileSettings.traktSyncRatings)
                Toggle("Sync Watchlist", isOn: $profileSettings.traktSyncWatchlist)
                Toggle("Enable Scrobbling", isOn: $profileSettings.traktScrobbleEnabled)
            }

            if let traktMessage {
                Text(traktMessage).foregroundStyle(.white.opacity(0.75))
            }
        }
    }

    private var advancedSection: some View {
        TVSettingsCard {
            Toggle("Debug Overlay", isOn: Binding(
                get: { UserDefaults.standard.showDebugInfo },
                set: { UserDefaults.standard.showDebugInfo = $0 }
            ))
            Text("App Version: \(Bundle.main.appVersion)")
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var aboutSection: some View {
        TVSettingsCard {
            Text("Flixor tvOS")
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text("Backendless runtime using FlixorCore with Plex/TMDB/Trakt services.")
                .foregroundStyle(.white.opacity(0.75))
            Text("Build \(Bundle.main.appVersion)")
                .foregroundStyle(.white.opacity(0.6))
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
}

private struct TVSettingsCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .font(.system(size: 22))
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }
}

private extension Bundle {
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}
