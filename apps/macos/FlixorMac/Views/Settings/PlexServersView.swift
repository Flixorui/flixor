//
//  PlexServersView.swift
//  FlixorMac
//
//  Displays backend-managed Plex servers with active-state controls.
//

import SwiftUI
import FlixorKit

struct PlexServersView: View {
    @State private var servers: [PlexServer] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var isPerformingAction = false
    @State private var selectedServer: PlexServer?
    @State private var showLogoutConfirmation = false
    @State private var plexUsername: String?
    @State private var plexEmail: String?
    @State private var plexThumb: String?

    private var activeServer: PlexServer? {
        servers.first { $0.isActive == true }
    }

    private var isAuthenticated: Bool {
        FlixorCore.shared.isPlexAuthenticated
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Account Status Section
            accountSection

            // Servers Section
            if isAuthenticated {
                serversSection
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
        .sheet(item: $selectedServer, onDismiss: {
            Task { await loadServers(force: true) }
        }) { server in
            let binding = Binding(get: { selectedServer != nil }, set: { if !$0 { selectedServer = nil } })
            ServerConnectionView(server: server, isPresented: binding) {
                Task { await loadServers(force: true) }
            }
        }
        .alert("Sign Out", isPresented: $showLogoutConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                Task { await signOut() }
            }
        } message: {
            Text("Are you sure you want to sign out of Plex? You'll need to sign in again to access your libraries.")
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSectionHeader(title: "Account")

            SettingsGroupCard {
                if isAuthenticated {
                    HStack(spacing: 12) {
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
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            } else {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(hex: "E5A00D").gradient)
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Text(plexUsername?.prefix(1).uppercased() ?? "P")
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundStyle(.white)
                                    )
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(plexUsername ?? "Signed In")
                                .font(.system(size: 13, weight: .semibold))
                            if let email = plexEmail {
                                Text(email)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            } else if let server = activeServer {
                                Text("Connected to \(server.name)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Button("Sign Out") {
                            showLogoutConfirmation = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(12)
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Not Signed In")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Sign in to access your Plex libraries")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(12)
                }
            }
        }
    }

    // MARK: - Servers Section

    private var serversSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSectionHeader(title: "Servers")

            if isLoading {
                SettingsGroupCard {
                    HStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Loading servers...")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(16)
                }
            } else if let errorMessage {
                messageRow(text: errorMessage, style: .error)
            } else if servers.isEmpty {
                messageRow(text: "No servers found. Use Refresh to try again.", style: .info)
            } else {
                serverList
            }

            // Refresh button
            HStack {
                Spacer()
                Button(action: { Task { await loadServers(force: true) } }) {
                    Label("Refresh Servers", systemImage: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLoading || isPerformingAction)
            }
        }
    }

    // MARK: - Server List

    @ViewBuilder
    private var serverList: some View {
        SettingsGroupCard {
            ForEach(Array(servers.enumerated()), id: \.element.id) { index, server in
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        // Server icon
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(server.isActive == true ? Color.blue.gradient : Color.gray.opacity(0.3).gradient)
                                .frame(width: 32, height: 32)
                            Image(systemName: "server.rack")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(server.isActive == true ? .white : .secondary)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(server.name)
                                    .font(.system(size: 13, weight: .medium))

                                if server.isActive == true {
                                    Text("Active")
                                        .font(.system(size: 9, weight: .semibold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.2))
                                        .foregroundStyle(.blue)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }

                                if server.owned == true {
                                    Text("Owned")
                                        .font(.system(size: 9, weight: .semibold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.2))
                                        .foregroundStyle(.green)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                            }

                            Text(server.baseURLDisplay)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        HStack(spacing: 8) {
                            if server.isActive != true {
                                Button("Connect") {
                                    Task { await setActiveServer(server) }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(isPerformingAction)
                            }

                            Button(action: { selectedServer = server }) {
                                Image(systemName: "ellipsis.circle")
                                    .font(.system(size: 16))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .disabled(isPerformingAction)
                        }
                    }
                    .padding(12)

                    if index < servers.count - 1 {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
        }
    }

    private func badge(text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.2))
            .foregroundStyle(tint)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private enum MessageStyle { case error, success, info }

    private func messageRow(text: String, style: MessageStyle) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: icon(for: style))
            Text(text)
        }
        .font(.footnote)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background(for: style))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            errorMessage = "Failed to load servers. Please try again."
            print("❌ [Settings] Failed to load Plex servers: \(error)")
        }

        isLoading = false
    }

    @MainActor
    private func setActiveServer(_ server: PlexServer) async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        statusMessage = "Updating active server…"

        do {
            _ = try await APIClient.shared.setCurrentPlexServer(serverId: server.id)
            statusMessage = "Active server updated to \(server.name)."
            await loadServers(force: true)
        } catch {
            errorMessage = "Unable to set active server."
            print("❌ [Settings] Failed to set active server: \(error)")
        }

        isPerformingAction = false
    }

    @MainActor
    private func signOut() async {
        isPerformingAction = true
        statusMessage = "Signing out..."

        await SessionManager.shared.logout()
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
