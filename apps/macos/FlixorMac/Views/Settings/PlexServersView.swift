//
//  PlexServersView.swift
//  FlixorMac
//
//  Displays backend-managed Plex servers with active-state controls.
//

import SwiftUI
import FlixorKit

struct PlexServersView: View {
    @EnvironmentObject private var flixorCore: FlixorCore
    @ObservedObject private var appMode = AppModeStore.shared
    @StateObject private var authViewModel = PlexAuthViewModel()

    @State private var servers: [PlexServer] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var isPerformingAction = false
    @State private var selectedServer: PlexServer?
    @State private var showLogoutConfirmation = false
    @State private var showingServerFlow = false
    @State private var plexUsername: String?
    @State private var plexEmail: String?
    @State private var plexThumb: String?

    private var activeServer: PlexServer? {
        servers.first { $0.isActive == true }
    }

    private var isAuthenticated: Bool {
        flixorCore.isPlexAuthenticated
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            // Account Status Section
            accountSection

            // Servers Section
            if isAuthenticated {
                serversSection
            }

            // Switching to Stremio-only keeps every setting; signing out resets them.
            if isAuthenticated && !appMode.isStremioOnly {
                modeSection
            }

            if let statusMessage, !statusMessage.isEmpty {
                messageRow(text: statusMessage, style: .success)
            }
        }
        .onAppear {
            Task {
                await loadServers(force: false)
                await loadPlexUser()
            }
        }
        .onReceive(authViewModel.$authToken) { token in
            // PIN authorized from Settings - pick a server next.
            if token != nil {
                showingServerFlow = true
            }
        }
        .sheet(isPresented: $showingServerFlow) {
            ServerEndpointFlowView {
                showingServerFlow = false
                appMode.select(.plex)
                Task {
                    SessionManager.shared.updateFromFlixorCore()
                    await loadServers(force: true)
                    await loadPlexUser()
                }
            }
            .frame(minWidth: 900, minHeight: 700)
        }
        .sheet(item: $selectedServer, onDismiss: {
            Task { await loadServers(force: true) }
        }) { server in
            let binding = Binding(get: { selectedServer != nil }, set: { if !$0 { selectedServer = nil } })
            ServerConnectionView(server: server, isPresented: binding) {
                Task { await loadServers(force: true) }
            }
        }
        .alert(appMode.isStremioOnly ? "Disconnect Plex" : "Sign Out", isPresented: $showLogoutConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button(appMode.isStremioOnly ? "Disconnect" : "Sign Out", role: .destructive) {
                Task { await signOut() }
            }
        } message: {
            Text(appMode.isStremioOnly
                 ? "Disconnect your Plex account? Flixor keeps working as a standalone Stremio app - your addons, watch history and settings are preserved."
                 : "Are you sure you want to sign out of Plex? You'll need to sign in again to access your libraries.")
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            SettingsGroupCard {
                if isAuthenticated {
                    HStack(spacing: DS.Space.s12) {
                        // User avatar or Plex icon
                        ZStack {
                            if let thumbUrl = plexThumb, let url = URL(string: thumbUrl) {
                                AsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Color(hex: "E5A00D")
                                }
                                .frame(width: 32, height: 32)
                                .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(Color(hex: "E5A00D").gradient)
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Text(plexUsername?.prefix(1).uppercased() ?? "P")
                                            .font(.flixor(.title3, weight: .bold))
                                            .foregroundStyle(.white)
                                    )
                            }
                        }

                        VStack(alignment: .leading, spacing: DS.Space.s2) {
                            Text(plexUsername ?? String(localized: "Signed In"))
                                .font(.flixor(.callout, weight: .semibold))
                            if let email = plexEmail {
                                Text(email)
                                    .font(.flixor(.caption))
                                    .foregroundStyle(.secondary)
                            } else if let server = activeServer {
                                Text("Connected to \(server.name)")
                                    .font(.flixor(.caption))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if !flixorCore.isPlexServerConnected {
                            Button("Choose Server") {
                                showingServerFlow = true
                            }
                            .buttonStyle(.settingsPrimary)
                        }

                        Button(appMode.isStremioOnly ? "Disconnect" : "Sign Out") {
                            showLogoutConfirmation = true
                        }
                        .buttonStyle(.settingsDestructive)
                    }
                    .padding(.horizontal, DS.Space.s12)
                    .padding(.vertical, DS.Space.s10)
                } else {
                    HStack(spacing: DS.Space.s12) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: DS.Space.s2) {
                            Text("Not Connected")
                                .font(.flixor(.callout, weight: .semibold))
                            Text(appMode.isStremioOnly
                                 ? "Optional. Connect Plex to add your own library alongside Stremio."
                                 : "Sign in to access your Plex libraries")
                                .font(.flixor(.caption))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button(authViewModel.isAuthenticating ? "Waiting…" : "Connect Plex") {
                            Task { await authViewModel.startAuthentication() }
                        }
                        .buttonStyle(.settingsPrimary)
                        .disabled(authViewModel.isAuthenticating)
                    }
                    .padding(DS.Space.s12)
                }

                if let authError = authViewModel.error, !authError.isEmpty {
                    Divider()
                    Text(authError)
                        .font(.flixor(.caption))
                        .foregroundStyle(SettingsChrome.destructive)
                        .padding(DS.Space.s12)
                }
            }
        }
    }

    // MARK: - Mode Section

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            SettingsSectionHeader(title: "Mode")
            SettingsGroupCard {
                SettingsRow(
                    title: "Use Stremio Only",
                    subtitle: "Disconnect Plex and run Flixor as a Stremio app. Your settings are kept.",
                    showDivider: false
                ) {
                    Button("Switch…") {
                        Task { await switchToStremioOnly() }
                    }
                    .buttonStyle(.settingsSecondary)
                    .disabled(isPerformingAction)
                }
            }
        }
    }

    // MARK: - Servers Section

    private var serversSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            HStack {
                SettingsSectionHeader(title: "Servers")
                Spacer()
                Button(action: { Task { await loadServers(force: true) } }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(.link)
                .disabled(isLoading || isPerformingAction)
                .padding(.bottom, -DS.Space.s8)
            }

            if isLoading {
                SettingsGroupCard {
                    HStack(spacing: DS.Space.s12) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Loading servers...")
                            .font(.flixor(.callout))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(DS.Space.s16)
                }
            } else if let errorMessage {
                messageRow(text: errorMessage, style: .error)
            } else if servers.isEmpty {
                messageRow(text: String(localized: "No servers found. Use Refresh to try again."), style: .info)
            } else {
                serverList
            }

        }
    }

    // MARK: - Server List

    @ViewBuilder
    private var serverList: some View {
        SettingsGroupCard {
            ForEach(Array(servers.enumerated()), id: \.element.id) { index, server in
                VStack(spacing: 0) {
                    HStack(spacing: DS.Space.s12) {
                        // Server icon
                        ZStack {
                            RoundedRectangle(cornerRadius: DS.Radius.r6, style: .continuous)
                                .fill(server.isActive == true ? Color.blue.gradient : Color.gray.opacity(0.3).gradient)
                                .frame(width: 28, height: 28)
                            Image(systemName: "server.rack")
                                .font(.flixorIcon(DS.Icon.sm, weight: .medium))
                                .foregroundStyle(server.isActive == true ? .white : .secondary)
                        }

                        VStack(alignment: .leading, spacing: DS.Space.s2) {
                            HStack(spacing: DS.Space.s6) {
                                Text(server.name)
                                    .font(.flixor(.callout, weight: .medium))

                                if server.isActive == true {
                                    Text("Active")
                                        .font(.flixor(.nano, weight: .semibold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, DS.Space.s2)
                                        .background(Color.blue.opacity(0.2))
                                        .foregroundStyle(.blue)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }

                                if server.owned == true {
                                    Text("Owned")
                                        .font(.flixor(.nano, weight: .semibold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, DS.Space.s2)
                                        .background(Color.green.opacity(0.2))
                                        .foregroundStyle(.green)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                            }

                            Text(server.baseURLDisplay)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(server.baseURLDisplay)
                        }

                        Spacer()

                        HStack(spacing: DS.Space.s8) {
                            if server.isActive != true {
                                Button("Connect") {
                                    Task { await setActiveServer(server) }
                                }
                                .buttonStyle(.settingsSecondary)
                                .disabled(isPerformingAction)
                            }

                            Button(action: { selectedServer = server }) {
                                Image(systemName: "ellipsis.circle")
                                    .font(.flixorIcon(DS.Icon.md))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .disabled(isPerformingAction)
                        }
                    }
                    .padding(.horizontal, DS.Space.s12)
                    .padding(.vertical, DS.Space.s10)

                    if index < servers.count - 1 {
                        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                            .padding(.leading, 52).padding(.trailing, DS.Space.s12)
                    }
                }
            }
        }
    }

    private func badge(text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, DS.Space.s6)
            .padding(.vertical, DS.Space.s2)
            .background(tint.opacity(0.2))
            .foregroundStyle(tint)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r4, style: .continuous))
    }

    private enum MessageStyle { case error, success, info }

    private func messageRow(text: String, style: MessageStyle) -> some View {
        HStack(alignment: .center, spacing: DS.Space.s8) {
            Image(systemName: icon(for: style))
            Text(text)
        }
        .font(.footnote)
        .padding(DS.Space.s10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background(for: style))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r8, style: .continuous))
    }

    private func icon(for style: MessageStyle) -> String {
        switch style {
        case .error: return "exclamationmark.triangle.fill"
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func background(for style: MessageStyle) -> Color {
        switch style {
        case .error: return Color.red.opacity(0.12)
        case .success: return Color.green.opacity(0.12)
        case .info: return Color.gray.opacity(0.12)
        }
    }

    // MARK: - Actions

    @MainActor
    private func loadServers(force: Bool) async {
        if isLoading { return }
        if !force && !servers.isEmpty { return }

        isLoading = true
        errorMessage = nil
        statusMessage = nil

        do {
            let fetched = try await APIClient.shared.getPlexServers()
            servers = fetched.sorted { ($0.name.lowercased()) < ($1.name.lowercased()) }
        } catch {
            errorMessage = String(localized: "Failed to load servers. Please try again.")
            print("❌ [Settings] Failed to load Plex servers: \(error)")
        }

        isLoading = false
    }

    @MainActor
    private func setActiveServer(_ server: PlexServer) async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        statusMessage = String(localized: "Updating active server…")

        do {
            _ = try await APIClient.shared.setCurrentPlexServer(serverId: server.id)
            statusMessage = String(localized: "Active server updated to \(server.name).")
            await loadServers(force: true)
        } catch {
            errorMessage = String(localized: "Unable to set active server.")
            print("❌ [Settings] Failed to set active server: \(error)")
        }

        isPerformingAction = false
    }

    @MainActor
    private func signOut() async {
        isPerformingAction = true
        statusMessage = appMode.isStremioOnly ? String(localized: "Disconnecting...") : String(localized: "Signing out...")

        if appMode.isStremioOnly {
            // Keep the app usable standalone; don't reset settings or bounce to the chooser.
            await SessionManager.shared.disconnectPlex()
        } else {
            await SessionManager.shared.logout()
        }
        servers = []
        plexUsername = nil
        plexEmail = nil
        plexThumb = nil
        statusMessage = nil
        errorMessage = nil

        isPerformingAction = false
    }

    @MainActor
    private func switchToStremioOnly() async {
        isPerformingAction = true
        statusMessage = String(localized: "Switching to Stremio only...")

        await SessionManager.shared.disconnectPlex()
        servers = []
        plexUsername = nil
        plexEmail = nil
        plexThumb = nil
        statusMessage = nil
        errorMessage = nil

        isPerformingAction = false
    }

    @MainActor
    private func loadPlexUser() async {
        guard let token = FlixorCore.shared.plexToken else { return }

        do {
            let user = try await FlixorCore.shared.plexAuth.getUser(token: token)
            plexUsername = user.username
            plexEmail = user.email
            plexThumb = user.thumb
        } catch {
            print("⚠️ [Settings] Failed to load Plex user: \(error)")
        }
    }
}
