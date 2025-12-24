//
//  SettingsView.swift
//  FlixorMac
//
//  Settings window shell with polished layout.
//

import SwiftUI

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case plex
    case trakt
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .plex: return "Plex Servers"
        case .trakt: return "Trakt"
        case .about: return "About"
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            VStack(alignment: .leading, spacing: 18) {
                Picker("Settings Section", selection: $selectedTab) {
                    ForEach(SettingsTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch selectedTab {
                        case .general:
                            GeneralSettingsView()
                        case .plex:
                            PlexServersView()
                        case .trakt:
                            TraktSettingsView()
                        case .about:
                            AboutView()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
        }
        .frame(width: 640, height: 500)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.black.opacity(0.35), radius: 28, x: 0, y: 18)
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(selectedTab.title)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                    .padding(8)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("playerBackend") private var selectedBackend: String = PlayerBackend.avplayer.rawValue

    private var playerBackendBinding: Binding<PlayerBackend> {
        Binding(
            get: { PlayerBackend(rawValue: selectedBackend) ?? .avplayer },
            set: { selectedBackend = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("Playback") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Player Backend")
                        .font(.headline)

                    Picker("Player Backend", selection: playerBackendBinding) {
                        ForEach(PlayerBackend.allCases) { backend in
                            Text(backend.displayName).tag(backend)
                        }
                    }
                    .pickerStyle(.radioGroup)

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
                    .padding(.leading, 20)

                    Text("Choose the media player backend. Changes will apply to new playback sessions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
        }
        .formStyle(.grouped)
    }
}

import AppKit

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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            connectionSection

            if let statusMessage {
                messageRow(text: statusMessage, style: .info)
            }

            if let errorMessage {
                messageRow(text: errorMessage, style: .error)
            }

            syncSection
        }
        .task { await refreshProfile() }
        .onDisappear { pollingTask?.cancel() }
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "chart.bar")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.red)

                VStack(alignment: .leading, spacing: 8) {
                    if let profile {
                        Text(profile.name ?? profile.username ?? profile.ids?.slug ?? "Trakt User")
                            .font(.headline)
                        if let slug = profile.ids?.slug {
                            Text("@\(slug)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 12) {
                            Button("Refresh") {
                                Task { await refreshProfile(force: true) }
                            }
                            .disabled(isLoadingProfile)

                            Button(role: .destructive, action: {
                                Task { await disconnect() }
                            }) {
                                Text("Disconnect")
                            }
                        }
                    } else {
                        Text("Not connected to Trakt")
                            .font(.headline)

                        Text("Connect your Trakt account to sync watch history, ratings, and watchlist entries across devices.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button(action: {
                            Task { await startDeviceCodeFlow() }
                        }) {
                            HStack {
                                if isRequestingCode { ProgressView().scaleEffect(0.8) }
                                Text(isRequestingCode ? "Requesting…" : "Sign in with Trakt")
                            }
                        }
                        .disabled(isRequestingCode)
                    }
                }
            }

            if let deviceCode {
                deviceCodeSection(deviceCode)
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func deviceCodeSection(_ code: TraktDeviceCodeResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Device Code")
                .font(.headline)

            HStack(spacing: 12) {
                Text(code.user_code)
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button("Copy") {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(code.user_code, forType: .string)
                    statusMessage = "Code copied to clipboard."
                }

                Button("Open Trakt") {
                    if let url = URL(string: code.verification_url) {
                        NSWorkspace.shared.open(url)
                    }
                }
            }

            if let expiresAt {
                let remaining = Int(max(0, expiresAt.timeIntervalSinceNow))
                Text("Expires in approximately \(remaining) seconds")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Cancel") {
                cancelDeviceFlow()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sync Preferences")
                .font(.headline)

            Toggle("Auto-sync watched status", isOn: $autoSyncWatched)
            Toggle("Sync ratings", isOn: $syncRatings)
            Toggle("Sync watchlist", isOn: $syncWatchlist)

            Divider()
                .padding(.vertical, 4)

            Text("Scrobbling")
                .font(.headline)

            Toggle("Enable scrobbling", isOn: $scrobbleEnabled)

            Text("When enabled, Flixor will automatically report what you're watching to Trakt in real-time. If you watch more than 80% of a movie or episode, it will be marked as watched.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private enum MessageStyle { case error, info }

    private func messageRow(text: String, style: MessageStyle) -> some View {
        HStack(spacing: 8) {
            Image(systemName: style == .error ? "exclamationmark.triangle.fill" : "info.circle.fill")
            Text(text)
        }
        .font(.footnote)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style == .error ? Color.red.opacity(0.12) : Color.blue.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
            // 401 indicates not connected; treat silently unless forced
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
            statusMessage = "Enter the code above at Trakt to authorise this device."
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
                                statusMessage = "Waiting for approval on Trakt…"
                            }
                        }
                    }
                } catch {
                    await MainActor.run {
                        statusMessage = "Polling failed, retrying…"
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

    private func normalizedProtocol(for connection: PlexConnection) -> String? {
        if let proto = connection.protocolName?.lowercased() { return proto }
        if let url = URL(string: connection.uri), let scheme = url.scheme?.lowercased() { return scheme }
        return nil
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.orange)

            Text("Flixor for macOS")
                .font(.title)

            Text("Version 1.0.0")
                .foregroundStyle(.secondary)

            Text("A native macOS client for Plex Media Server")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View { SettingsView() }
}
#endif
