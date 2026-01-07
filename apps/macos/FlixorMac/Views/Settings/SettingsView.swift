//
//  SettingsView.swift
//  FlixorMac
//
//  Modern settings window with sidebar navigation matching mobile UI patterns.
//

import SwiftUI
import AppKit

// MARK: - Settings Categories

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case homeScreen
    case plex
    case catalog
    case integrations
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .homeScreen: return "Home Screen"
        case .plex: return "Plex"
        case .catalog: return "Catalog"
        case .integrations: return "Integrations"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .homeScreen: return "rectangle.on.rectangle.fill"
        case .plex: return "play.circle.fill"
        case .catalog: return "folder.fill"
        case .integrations: return "puzzlepiece.extension.fill"
        case .about: return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .general: return .gray
        case .homeScreen: return .blue
        case .plex: return Color(hex: "E5A00D")
        case .catalog: return .purple
        case .integrations: return .green
        case .about: return .orange
        }
    }
}

private enum IntegrationTab: String, CaseIterable, Identifiable {
    case tmdb
    case mdblist
    case overseerr
    case trakt

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tmdb: return "TMDB"
        case .mdblist: return "MDBList"
        case .overseerr: return "Overseerr"
        case .trakt: return "Trakt"
        }
    }

    var icon: String {
        switch self {
        case .tmdb: return "film.fill"
        case .mdblist: return "star.fill"
        case .overseerr: return "arrow.down.circle.fill"
        case .trakt: return "chart.bar.fill"
        }
    }

    var color: Color {
        switch self {
        case .tmdb: return Color(hex: "01B4E4")
        case .mdblist: return Color(hex: "F5C518")
        case .overseerr: return Color(hex: "6366F1")
        case .trakt: return Color(hex: "ED1C24")
        }
    }
}

// MARK: - Main Settings View

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: SettingsCategory = .general
    @State private var selectedIntegration: IntegrationTab? = nil

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            sidebar
                .frame(width: 220)

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 1)

            // Content
            contentArea
        }
        .frame(width: 900, height: 640)
        .background(Color(hex: "0B0B0D"))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.5), radius: 40, x: 0, y: 20)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Categories
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(SettingsCategory.allCases) { category in
                        SidebarCategoryButton(
                            category: category,
                            isSelected: selectedCategory == category && selectedIntegration == nil
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedCategory = category
                                selectedIntegration = nil
                            }
                        }
                    }

                    // Integrations sub-items when Integrations is selected
                    if selectedCategory == .integrations {
                        VStack(spacing: 2) {
                            ForEach(IntegrationTab.allCases) { tab in
                                SidebarIntegrationButton(
                                    tab: tab,
                                    isSelected: selectedIntegration == tab
                                ) {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        selectedIntegration = tab
                                    }
                                }
                            }
                        }
                        .padding(.leading, 28)
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
            }

            Spacer()

            // Version info
            Text("Flixor v1.0.0")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 16)
        }
        .background(Color(hex: "111114").opacity(0.6))
    }

    // MARK: - Content Area

    private var contentArea: some View {
        VStack(spacing: 0) {
            // Content header
            HStack {
                if let integration = selectedIntegration {
                    HStack(spacing: 10) {
                        Image(systemName: integration.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(integration.color)
                        Text(integration.title)
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: selectedCategory.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(selectedCategory.color)
                        Text(selectedCategory.title)
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 16)

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let integration = selectedIntegration {
                        integrationContent(for: integration)
                    } else {
                        categoryContent(for: selectedCategory)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
        }
    }

    @ViewBuilder
    private func categoryContent(for category: SettingsCategory) -> some View {
        switch category {
        case .general:
            GeneralSettingsView()
        case .homeScreen:
            HomeScreenSettingsView()
        case .plex:
            PlexServersView()
        case .catalog:
            CatalogSettingsView()
        case .integrations:
            IntegrationsOverviewView(selectedIntegration: $selectedIntegration)
        case .about:
            AboutView()
        }
    }

    @ViewBuilder
    private func integrationContent(for tab: IntegrationTab) -> some View {
        switch tab {
        case .tmdb:
            TMDBSettingsView()
        case .mdblist:
            MDBListSettingsView()
        case .overseerr:
            OverseerrSettingsView()
        case .trakt:
            TraktSettingsView()
        }
    }
}

// MARK: - Sidebar Components

private struct SidebarCategoryButton: View {
    let category: SettingsCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: category.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected ? .white : category.color)
                    .frame(width: 24)

                Text(category.title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .white : .primary)

                Spacer()

                if category == .integrations {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                isSelected ? Color.white.opacity(0.1) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SidebarIntegrationButton: View {
    let tab: IntegrationTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle()
                    .fill(tab.color)
                    .frame(width: 8, height: 8)

                Text(tab.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : .secondary)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                isSelected ? Color.white.opacity(0.08) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Integrations Overview

private struct IntegrationsOverviewView: View {
    @Binding var selectedIntegration: IntegrationTab?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Select an integration to configure")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ], spacing: 16) {
                ForEach(IntegrationTab.allCases) { tab in
                    IntegrationCard(tab: tab) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedIntegration = tab
                        }
                    }
                }
            }
        }
    }
}

private struct IntegrationCard: View {
    let tab: IntegrationTab
    let action: () -> Void

    @AppStorage("mdblistEnabled") private var mdblistEnabled = false
    @AppStorage("overseerrEnabled") private var overseerrEnabled = false

    private var isConfigured: Bool {
        switch tab {
        case .tmdb: return true // Always available
        case .mdblist: return mdblistEnabled
        case .overseerr: return overseerrEnabled
        case .trakt: return false // Would need to check Trakt connection
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(tab.color.opacity(0.15))
                        .frame(width: 52, height: 52)
                    Image(systemName: tab.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(tab.color)
                }

                Text(tab.title)
                    .font(.system(size: 15, weight: .semibold))

                HStack(spacing: 4) {
                    Circle()
                        .fill(isConfigured ? Color.green : Color.gray)
                        .frame(width: 6, height: 6)
                    Text(isConfigured ? "Configured" : "Not configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Reusable Settings Components

struct SettingsCard<Content: View>: View {
    let title: String?
    @ViewBuilder let content: () -> Content

    init(title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .kerning(1)
                    .padding(.bottom, 10)
            }

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .background(Color(hex: "111114").opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
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
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(iconColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                    if let description {
                        Text(description)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                trailing()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)

            if showDivider {
                Divider()
                    .background(Color.white.opacity(0.06))
                    .padding(.leading, 62)
            }
        }
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
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(14)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(color.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @AppStorage("playerBackend") private var selectedBackend: String = PlayerBackend.avplayer.rawValue

    private var playerBackendBinding: Binding<PlayerBackend> {
        Binding(
            get: { PlayerBackend(rawValue: selectedBackend) ?? .avplayer },
            set: { selectedBackend = $0.rawValue }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(title: "Playback") {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Player Backend")
                        .font(.headline)
                        .padding(.horizontal, 14)
                        .padding(.top, 14)

                    Picker("Player Backend", selection: playerBackendBinding) {
                        ForEach(PlayerBackend.allCases) { backend in
                            Text(backend.displayName).tag(backend)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .padding(.horizontal, 14)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(PlayerBackend.allCases) { backend in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(backend.displayName)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    Text(backend.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 14)

                    Text("Choose the media player backend. Changes will apply to new playback sessions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 14)
                }
            }
        }
    }
}

// MARK: - Trakt Settings

struct TraktSettingsView: View {
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
        VStack(alignment: .leading, spacing: 20) {
            // Status card
            if let profile {
                StatusCard(
                    icon: "checkmark.circle.fill",
                    color: .green,
                    title: "Connected to Trakt",
                    description: "Signed in as @\(profile.ids?.slug ?? profile.username ?? "user")"
                )
            } else {
                StatusCard(
                    icon: "exclamationmark.triangle.fill",
                    color: .orange,
                    title: "Not Connected",
                    description: "Sign in to sync watch history and ratings"
                )
            }

            // Connection section
            SettingsCard(title: "Account") {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(traktColor.opacity(0.15))
                                .frame(width: 56, height: 56)
                            Image(systemName: "chart.bar.fill")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(traktColor)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Trakt")
                                .font(.system(size: 18, weight: .bold))
                            Text("Track what you watch")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)

                    Divider().background(Color.white.opacity(0.06))

                    if let profile {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.name ?? profile.username ?? "Trakt User")
                                    .font(.system(size: 15, weight: .semibold))
                                if let slug = profile.ids?.slug {
                                    Text("@\(slug)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            HStack(spacing: 8) {
                                Button("Refresh") {
                                    Task { await refreshProfile(force: true) }
                                }
                                .disabled(isLoadingProfile)

                                Button(role: .destructive) {
                                    Task { await disconnect() }
                                } label: {
                                    Text("Disconnect")
                                        .foregroundStyle(.red)
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(14)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Connect your Trakt account to sync watch history, ratings, and watchlist entries across devices.")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)

                            Button(action: { Task { await startDeviceCodeFlow() } }) {
                                HStack {
                                    if isRequestingCode {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                            .frame(width: 16, height: 16)
                                    }
                                    Text(isRequestingCode ? "Requesting..." : "Sign in with Trakt")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(traktColor)
                            .disabled(isRequestingCode)
                        }
                        .padding(14)
                    }

                    if let deviceCode {
                        deviceCodeSection(deviceCode)
                    }
                }
            }

            if let statusMessage {
                StatusCard(icon: "info.circle.fill", color: .blue, title: "Status", description: statusMessage)
            }

            if let errorMessage {
                StatusCard(icon: "exclamationmark.triangle.fill", color: .red, title: "Error", description: errorMessage)
            }

            // Sync settings
            SettingsCard(title: "Sync Preferences") {
                VStack(spacing: 0) {
                    SettingRow(icon: "arrow.triangle.2.circlepath", iconColor: .blue, title: "Auto-sync watched", description: "Sync watch status automatically") {
                        Toggle("", isOn: $autoSyncWatched)
                            .labelsHidden()
                    }
                    SettingRow(icon: "star.fill", iconColor: .yellow, title: "Sync ratings", description: "Sync your ratings to Trakt") {
                        Toggle("", isOn: $syncRatings)
                            .labelsHidden()
                    }
                    SettingRow(icon: "bookmark.fill", iconColor: .purple, title: "Sync watchlist", description: "Sync watchlist entries", showDivider: false) {
                        Toggle("", isOn: $syncWatchlist)
                            .labelsHidden()
                    }
                }
            }

            // Scrobbling
            SettingsCard(title: "Scrobbling") {
                VStack(spacing: 0) {
                    SettingRow(icon: "play.circle.fill", iconColor: traktColor, title: "Enable scrobbling", description: "Report watching activity in real-time", showDivider: false) {
                        Toggle("", isOn: $scrobbleEnabled)
                            .labelsHidden()
                    }
                }
            }
        }
        .task { await refreshProfile() }
        .onDisappear { pollingTask?.cancel() }
    }

    @ViewBuilder
    private func deviceCodeSection(_ code: TraktDeviceCodeResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider().background(Color.white.opacity(0.06))

            VStack(alignment: .leading, spacing: 10) {
                Text("Device Code")
                    .font(.headline)

                HStack(spacing: 12) {
                    Text(code.user_code)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .kerning(4)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Button("Copy") {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(code.user_code, forType: .string)
                        statusMessage = "Code copied to clipboard."
                    }
                    .buttonStyle(.bordered)

                    Button("Open Trakt") {
                        if let url = URL(string: code.verification_url) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(traktColor)
                }

                if let expiresAt {
                    let remaining = Int(max(0, expiresAt.timeIntervalSinceNow))
                    Text("Expires in \(remaining) seconds")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Cancel") { cancelDeviceFlow() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
        }
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
                errorMessage = "Unable to load Trakt profile. Please connect again."
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
            statusMessage = "Enter the code above at Trakt to authorize this device."
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
                            statusMessage = "Trakt account linked successfully."
                            self.deviceCode = nil
                        }
                        await refreshProfile(force: true)
                        return
                    } else {
                        await MainActor.run {
                            if let description = response.error_description, !description.isEmpty {
                                statusMessage = description.capitalized
                            } else {
                                statusMessage = "Waiting for approval on Trakt..."
                            }
                        }
                    }
                } catch {
                    await MainActor.run {
                        statusMessage = "Polling failed, retrying..."
                    }
                }

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
            errorMessage = "Failed to disconnect from Trakt."
        }
    }
}

// MARK: - About View

struct AboutView: View {
    var body: some View {
        VStack(spacing: 0) {
            SettingsCard {
                VStack(spacing: 24) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.orange.opacity(0.15))
                            .frame(width: 80, height: 80)
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(.orange)
                    }

                    VStack(spacing: 8) {
                        Text("Flixor for macOS")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Version 1.0.0")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text("A native macOS client for Plex Media Server with Netflix-style experience.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)

                    Divider()
                        .background(Color.white.opacity(0.06))
                        .padding(.horizontal, 20)

                    VStack(spacing: 12) {
                        FeatureRow(icon: "play.circle.fill", text: "Beautiful media browsing")
                        FeatureRow(icon: "tv.fill", text: "Native macOS player")
                        FeatureRow(icon: "chart.bar.fill", text: "Trakt integration")
                        FeatureRow(icon: "star.fill", text: "Multi-source ratings")
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.green)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View { SettingsView() }
}
#endif
