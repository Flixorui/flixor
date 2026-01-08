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
    case catalog
    case rowsSettings
    case homeScreenAppearance
    case detailsScreen
    case tmdb
    case mdblist
    case overseerr
    case trakt
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plex: return "Plex"
        case .catalog: return "Catalogs"
        case .rowsSettings: return "Rows Settings"
        case .homeScreenAppearance: return "Home Screen"
        case .detailsScreen: return "Details Screen"
        case .tmdb: return "TMDB"
        case .mdblist: return "MDBList"
        case .overseerr: return "Overseerr"
        case .trakt: return "Trakt"
        case .about: return "About"
        }
    }

    var description: String {
        switch self {
        case .plex: return "Manage your Plex server connections"
        case .catalog: return "Configure library visibility and filtering"
        case .rowsSettings: return "Choose which content rows to display"
        case .homeScreenAppearance: return "Customize hero, posters and visual appearance"
        case .detailsScreen: return "Episode display and layout options"
        case .tmdb: return "The Movie Database metadata settings"
        case .mdblist: return "Multi-source ratings aggregation"
        case .overseerr: return "Media request management integration"
        case .trakt: return "Watch history and scrobbling"
        case .about: return "App information and credits"
        }
    }

    /// SF Symbol for sidebar (outline style, monotonic)
    var icon: String {
        switch self {
        case .plex: return "server.rack"
        case .catalog: return "rectangle.stack"
        case .rowsSettings: return "house"
        case .homeScreenAppearance: return "square.grid.2x2"
        case .detailsScreen: return "play.rectangle"
        case .tmdb: return "film"
        case .mdblist: return "star"
        case .overseerr: return "arrow.down.circle"
        case .trakt: return "chart.bar"
        case .about: return "info.circle"
        }
    }

    /// Image asset name for content header (branding)
    var imageAsset: String? {
        switch self {
        case .plex: return "plex"
        case .tmdb: return "tmdb"
        case .mdblist: return "mdblist"
        case .overseerr: return "overseerr"
        case .trakt: return "trakt"
        default: return nil
        }
    }

    var color: Color {
        switch self {
        case .plex: return Color(hex: "E5A00D")
        case .catalog: return .purple
        case .rowsSettings: return .blue
        case .homeScreenAppearance: return .indigo
        case .detailsScreen: return .teal
        case .tmdb: return Color(hex: "01B4E4")
        case .mdblist: return Color(hex: "F5C518")
        case .overseerr: return Color(hex: "6366F1")
        case .trakt: return Color(hex: "ED1C24")
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
            SidebarSection(title: "Account", categories: [.plex]),
            SidebarSection(title: "Content & Discovery", categories: [.catalog, .rowsSettings]),
            SidebarSection(title: "Appearance", categories: [.homeScreenAppearance, .detailsScreen]),
            SidebarSection(title: "Integrations", categories: [.tmdb, .mdblist, .overseerr, .trakt]),
            SidebarSection(title: "About", categories: [.about])
        ]
    }
}

// MARK: - Main Settings View

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
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
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(12)
            .help("Close Settings")
        }
        .frame(width: 920, height: 680)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Categories with section headers
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(SidebarSection.all.enumerated()), id: \.offset) { _, section in
                        let filteredCategories = filterCategories(section.categories)
                        if !filteredCategories.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                // Section header
                                Text(section.title.uppercased())
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 14)
                                    .padding(.top, 4)

                                // Section items
                                VStack(spacing: 2) {
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
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
            }
        }
        .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
    }

    private func filterCategories(_ categories: [SettingsCategory]) -> [SettingsCategory] {
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
                    // Header
                    contentHeader
                        .padding(.top, 32)
                        .padding(.bottom, 24)

                    // Content
                    VStack(alignment: .leading, spacing: 16) {
                        categoryContent(for: selectedCategory)
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }

    private var contentHeader: some View {
        VStack(spacing: 12) {
            // Icon - use image asset for branding (integrations), SF Symbol otherwise
            if let imageAsset = selectedCategory.imageAsset {
                Image(imageAsset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                ZStack {
                    Circle()
                        .fill(selectedCategory.color.opacity(0.15))
                        .frame(width: 64, height: 64)
                    Image(systemName: selectedCategory.icon)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(selectedCategory.color)
                }
            }

            // Title
            Text(selectedCategory.title)
                .font(.system(size: 22, weight: .bold))

            // Description
            Text(selectedCategory.description)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
    }

    @ViewBuilder
    private func categoryContent(for category: SettingsCategory) -> some View {
        switch category {
        case .plex:
            PlexServersView()
        case .catalog:
            CatalogSettingsView()
        case .rowsSettings:
            RowsSettingsView()
        case .homeScreenAppearance:
            HomeScreenAppearanceView()
        case .detailsScreen:
            DetailsScreenSettingsView()
        case .tmdb:
            TMDBSettingsView()
        case .mdblist:
            MDBListSettingsView()
        case .overseerr:
            OverseerrSettingsView()
        case .trakt:
            TraktSettingsContent()
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
            HStack(spacing: 12) {
                // Simple outline icon (monotonic like mobile)
                Image(systemName: category.icon)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(width: 24, height: 24)

                Text(category.title)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? .white : .primary)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                isSelected
                    ? Color.accentColor
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings Group Card

struct SettingsGroupCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Settings Section Header

struct SettingsSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
    }
}

// MARK: - Settings Row

struct SettingsRow<Trailing: View>: View {
    let icon: String?
    let iconColor: Color
    let title: String
    let subtitle: String?
    let showChevron: Bool
    let showDivider: Bool
    let useImageAsset: Bool
    @ViewBuilder let trailing: () -> Trailing

    init(
        icon: String? = nil,
        iconColor: Color = .gray,
        title: String,
        subtitle: String? = nil,
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
            HStack(spacing: 12) {
                if let icon {
                    if useImageAsset {
                        // Use image from assets
                        Image(icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    } else {
                        // Use SF Symbol
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(iconColor.gradient)
                                .frame(width: 28, height: 28)
                            Image(systemName: icon)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                trailing()
                    .toggleStyle(.switch)

                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

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
    let title: String
    let subtitle: String?
    let showDivider: Bool
    let action: () -> Void

    init(
        icon: String? = nil,
        iconColor: Color = .gray,
        title: String,
        subtitle: String? = nil,
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

// MARK: - General Settings Content

private struct GeneralSettingsContent: View {
    @AppStorage("playerBackend") private var selectedBackend: String = PlayerBackend.avplayer.rawValue

    private var playerBackendBinding: Binding<PlayerBackend> {
        Binding(
            get: { PlayerBackend(rawValue: selectedBackend) ?? .avplayer },
            set: { selectedBackend = $0.rawValue }
        )
    }

    var body: some View {
        SettingsGroupCard {
            VStack(spacing: 0) {
                SettingsRow(
                    icon: "play.rectangle.fill",
                    iconColor: .blue,
                    title: "Player Backend",
                    showDivider: false
                ) {
                    Picker("", selection: playerBackendBinding) {
                        ForEach(PlayerBackend.allCases) { backend in
                            Text(backend.displayName).tag(backend)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }
            }
        }

        // Player descriptions
        VStack(alignment: .leading, spacing: 8) {
            ForEach(PlayerBackend.allCases) { backend in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: backend == playerBackendBinding.wrappedValue ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(backend == playerBackendBinding.wrappedValue ? .green : .secondary)
                        .font(.system(size: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(backend.displayName)
                            .font(.system(size: 12, weight: .medium))
                        Text(backend.description)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)

        Text("Changes will apply to new playback sessions.")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
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

    @AppStorage("traktAutoSyncWatched") private var autoSyncWatched: Bool = true
    @AppStorage("traktSyncRatings") private var syncRatings: Bool = true
    @AppStorage("traktSyncWatchlist") private var syncWatchlist: Bool = true
    @AppStorage("traktScrobbleEnabled") private var scrobbleEnabled: Bool = true

    private var traktColor: Color { Color(hex: "ED1C24") }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
        // Status
        if let profile {
            SettingsGroupCard {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connected")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Signed in as @\(profile.ids?.slug ?? profile.username ?? "user")")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Disconnect") {
                        Task { await disconnect() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(12)
            }
        } else {
            SettingsGroupCard {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Not Connected")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Sign in to sync watch history")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

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
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                    }
                }
            }
        }

        if let statusMessage {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue)
                Text(statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }

        if let errorMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }

        // Sync Settings
        SettingsGroupCard {
            SettingsRow(icon: "arrow.triangle.2.circlepath", iconColor: .blue, title: "Auto-sync watched") {
                Toggle("", isOn: $autoSyncWatched).labelsHidden()
            }
            SettingsRow(icon: "star.fill", iconColor: .yellow, title: "Sync ratings") {
                Toggle("", isOn: $syncRatings).labelsHidden()
            }
            SettingsRow(icon: "bookmark.fill", iconColor: .purple, title: "Sync watchlist") {
                Toggle("", isOn: $syncWatchlist).labelsHidden()
            }
            SettingsRow(icon: "play.circle.fill", iconColor: traktColor, title: "Enable scrobbling", showDivider: false) {
                Toggle("", isOn: $scrobbleEnabled).labelsHidden()
            }
        }

        Text("Scrobbling reports your watching activity to Trakt in real-time.")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        }
        .onAppear {
            Task { await refreshProfile() }
        }
    }

    @ViewBuilder
    private func deviceCodeView(_ code: TraktDeviceCodeResponse) -> some View {
        VStack(spacing: 12) {
            Text("Enter this code at trakt.tv/activate")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Text(code.user_code)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .kerning(6)

                VStack(spacing: 8) {
                    Button("Copy") {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(code.user_code, forType: .string)
                        statusMessage = "Code copied!"
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
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Button("Cancel") { cancelDeviceFlow() }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(16)
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
                errorMessage = "Unable to load Trakt profile."
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
            statusMessage = "Waiting for authorization..."
            beginPolling(deviceCode: code)
        } catch {
            errorMessage = "Failed to start Trakt device flow."
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
                        errorMessage = "Device code expired. Please try again."
                        self.deviceCode = nil
                    }
                    return
                }

                do {
                    let response = try await APIClient.shared.traktDeviceToken(code: deviceCode.device_code)
                    if response.ok {
                        await MainActor.run {
                            statusMessage = "Connected successfully!"
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
            errorMessage = "Failed to disconnect."
        }
    }
}

// MARK: - About Content

private struct AboutSettingsContent: View {
    var body: some View {
        SettingsGroupCard {
            VStack(spacing: 20) {
                // App Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.orange, Color.red],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 4) {
                    Text("Flixor")
                        .font(.system(size: 20, weight: .bold))
                    Text("Version 1.0.0")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Text("A native macOS client for Plex Media Server")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }

        SettingsGroupCard {
            SettingsNavigationRow(
                icon: "globe",
                iconColor: .blue,
                title: "Website",
                subtitle: "flixor.app"
            ) {
                if let url = URL(string: "https://flixor.app") {
                    NSWorkspace.shared.open(url)
                }
            }
            SettingsNavigationRow(
                icon: "star.fill",
                iconColor: .yellow,
                title: "Rate on App Store",
                showDivider: false
            ) {
                // Open App Store
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
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
    }
}

// MARK: - Legacy Components (for compatibility)

struct SettingsCard<Content: View>: View {
    let title: String?
    @ViewBuilder let content: () -> Content

    init(title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
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
    let title: String
    let description: String?
    let showDivider: Bool
    @ViewBuilder let trailing: () -> TrailingContent

    init(
        icon: String,
        iconColor: Color = .gray,
        title: String,
        description: String? = nil,
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
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
