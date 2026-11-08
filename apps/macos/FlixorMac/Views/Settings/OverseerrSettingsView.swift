//
//  OverseerrSettingsView.swift
//  FlixorMac
//
//  Overseerr integration settings - macOS System Settings style
//

import SwiftUI
import AppKit

struct OverseerrSettingsView: View {
    @Environment(\.flixorTheme) private var theme
    @ObservedObject private var profileSettings = ProfileSettings.shared
    private let defaults = UserDefaults.standard

    @State private var isTesting: Bool = false
    @State private var isSaved: Bool = false
    @State private var testResult: OverseerrConnectionResult?

    private let overseerrColor = Color(hex: "6366F1")
    private let plexColor = Color(hex: "E5A00D")

    // Computed properties for convenience
    private var isEnabled: Bool { profileSettings.overseerrEnabled }
    private var apiKey: String { defaults.overseerrApiKey }

    private var authMethod: OverseerrAuthMethod {
        defaults.overseerrAuthMethod
    }

    private var hasChanges: Bool {
        false // Simplified - changes are saved immediately
    }

    private var canTestApiKey: Bool {
        profileSettings.overseerrEnabled && !profileSettings.overseerrUrl.isEmpty && !defaults.overseerrApiKey.isEmpty && !isSaved
    }

    private var canTestPlex: Bool {
        profileSettings.overseerrEnabled && !profileSettings.overseerrUrl.isEmpty
    }

    private var isPlexSignedIn: Bool {
        authMethod == .plex && !defaults.overseerrSessionCookie.isEmpty
    }

    private var isConfigured: Bool {
        guard profileSettings.overseerrEnabled, !profileSettings.overseerrUrl.isEmpty else { return false }
        switch authMethod {
        case .apiKey:
            return !defaults.overseerrApiKey.isEmpty
        case .plex:
            return !defaults.overseerrSessionCookie.isEmpty
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s24) {
            // Status
            SettingsSectionHeader(title: "Status")
            statusCard

            // Enable
            SettingsSectionHeader(title: "Integration")
            SettingsGroupCard {
                SettingsRow(icon: "arrow.down.circle.fill", iconColor: overseerrColor, title: "Enable Overseerr", subtitle: "Request movies and TV shows", showDivider: false) {
                    Toggle("", isOn: $profileSettings.overseerrEnabled)
                        .labelsHidden()
                        .onChange(of: profileSettings.overseerrEnabled) { newValue in
                            if !newValue {
                                Task { @MainActor in
                                    OverseerrService.shared.clearCache()
                                }
                                testResult = nil
                                isSaved = false
                            } else {
                                isSaved = false
                            }
                        }
                }
            }

            // Server URL
            SettingsSectionHeader(title: "Server URL")
            SettingsGroupCard {
                VStack(alignment: .leading, spacing: DS.Space.s12) {
                    TextField("https://overseerr.example.com", text: $profileSettings.overseerrUrl)
                        .textFieldStyle(.plain)
                        .padding(DS.Space.s10)
                        .background(theme.settingsFieldBackground)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r8, style: .continuous))
                        .disabled(!profileSettings.overseerrEnabled)
                        .opacity(isEnabled ? 1 : 0.5)
                        .onChange(of: profileSettings.overseerrUrl) { _ in
                            testResult = nil
                            isSaved = false
                        }
                }
                .padding(DS.Space.s12)
            }

            // Authentication Method
            SettingsSectionHeader(title: "Authentication")
            SettingsGroupCard {
                VStack(alignment: .leading, spacing: DS.Space.s12) {
                    // Plex Auth Option
                    AuthMethodRow(
                        icon: "person.crop.circle.fill",
                        iconColor: plexColor,
                        title: "Sign in with Plex",
                        subtitle: "Use your existing Plex account (recommended)",
                        isSelected: authMethod == .plex,
                        isEnabled: isEnabled
                    ) {
                        defaults.overseerrAuthMethod = .plex
                        testResult = nil
                        isSaved = false
                    }

                    Divider()

                    // API Key Option
                    AuthMethodRow(
                        icon: "key.fill",
                        iconColor: .gray,
                        title: "API Key",
                        subtitle: "Use an API key for authentication",
                        isSelected: authMethod == .apiKey,
                        isEnabled: isEnabled
                    ) {
                        defaults.overseerrAuthMethod = .apiKey
                        testResult = nil
                        isSaved = false
                    }
                }
                .padding(DS.Space.s12)
            }

            // Plex Sign In Section
            if authMethod == .plex {
                SettingsSectionHeader(title: "Plex Sign In")
                SettingsGroupCard {
                    VStack(alignment: .leading, spacing: DS.Space.s12) {
                        if isPlexSignedIn {
                            // Signed in state
                            Button(action: {}) {
                                HStack(spacing: DS.Space.s8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.flixorIcon(DS.Icon.md))
                                    Text("Signed in as \(defaults.overseerrPlexUsername.isEmpty ? "Plex User" : defaults.overseerrPlexUsername)")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .controlSize(.large)
                            .disabled(true)

                            Button(action: handleSignOut) {
                                Text("Sign Out")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        } else {
                            // Sign in button
                            Button(action: signInWithPlex) {
                                HStack(spacing: DS.Space.s8) {
                                    if isTesting {
                                        ProgressView()
                                            .scaleEffect(0.6)
                                            .frame(width: 14, height: 14)
                                    } else {
                                        Image(systemName: "person.crop.circle.badge.checkmark")
                                            .font(.flixorIcon(DS.Icon.sm))
                                    }
                                    Text("Sign in with Plex")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(plexColor)
                            .controlSize(.large)
                            .disabled(!canTestPlex || isTesting)
                        }

                        Text("Uses your existing Plex account to authenticate with Overseerr. Your Plex account must have access to the Overseerr server.")
                            .font(.flixor(.caption))
                            .foregroundStyle(.secondary)
                    }
                    .padding(DS.Space.s12)
                    .opacity(isEnabled ? 1 : 0.5)
                }
            }

            // API Key Section
            if authMethod == .apiKey {
                SettingsSectionHeader(title: "API Key")
                SettingsGroupCard {
                    VStack(alignment: .leading, spacing: DS.Space.s12) {
                        SecureField("Enter your Overseerr API key", text: Binding(
                                get: { defaults.overseerrApiKey },
                                set: { defaults.overseerrApiKey = $0 }
                            ))
                            .textFieldStyle(.plain)
                            .padding(DS.Space.s10)
                            .background(theme.settingsFieldBackground)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r8, style: .continuous))
                            .disabled(!profileSettings.overseerrEnabled)
                            .opacity(isEnabled ? 1 : 0.5)
                            .onChange(of: defaults.overseerrApiKey) { _ in
                                testResult = nil
                                isSaved = false
                            }

                        Button(action: testApiKeyConnection) {
                            HStack(spacing: DS.Space.s6) {
                                if isTesting {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .frame(width: 14, height: 14)
                                }
                                Text(isSaved && !hasChanges ? "Saved" : "Test & Save")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(isSaved && !hasChanges ? .green : overseerrColor)
                        .controlSize(.large)
                        .disabled(!canTestApiKey || isTesting || (isSaved && !hasChanges))

                        Text("Find your API key in Overseerr Settings → General → API Key")
                            .font(.flixor(.caption))
                            .foregroundStyle(.secondary)
                    }
                    .padding(DS.Space.s12)
                    .opacity(isEnabled ? 1 : 0.5)
                }

                // Instructions for API Key
                SettingsSectionHeader(title: "Setup Instructions")
                SettingsGroupCard {
                    VStack(alignment: .leading, spacing: DS.Space.s12) {
                        InstructionStepRow(number: 1, text: "Open your Overseerr web interface")
                        InstructionStepRow(number: 2, text: "Go to Settings → General")
                        InstructionStepRow(number: 3, text: "Copy the API Key and paste above")

                        Divider()

                        Button(action: {
                            if let url = URL(string: "https://docs.overseerr.dev/") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            HStack(spacing: DS.Space.s6) {
                                Text("Overseerr Documentation")
                                Image(systemName: "arrow.up.right")
                                    .font(.flixor(.micro))
                            }
                            .font(.flixor(.callout))
                        }
                        .buttonStyle(.link)
                    }
                    .padding(DS.Space.s12)
                }
            }

            // Features
            SettingsSectionHeader(title: "Features")
            SettingsGroupCard {
                VStack(alignment: .leading, spacing: DS.Space.s10) {
                    FeatureCheckRow(text: "Request movies and TV shows")
                    FeatureCheckRow(text: "See request status on details page")
                    FeatureCheckRow(text: "Works with Radarr and Sonarr")
                }
                .padding(DS.Space.s12)
            }
        }
        .onAppear {
            loadSavedState()
        }
    }

    // MARK: - Load Saved State

    private func loadSavedState() {
        // Check if we already have saved configuration
        let savedUrl = UserDefaults.standard.overseerrUrl

        if isEnabled && !savedUrl.isEmpty {
            if authMethod == .apiKey {
                let savedKey = UserDefaults.standard.overseerrApiKey
                if !savedKey.isEmpty {
                    isSaved = true
                    // Validate API key connection in background
                    Task {
                        let result = await OverseerrService.shared.validateConnection(
                            url: savedUrl,
                            apiKey: savedKey
                        )
                        await MainActor.run {
                            testResult = result
                        }
                    }
                }
            } else {
                // Plex auth
                let savedCookie = UserDefaults.standard.overseerrSessionCookie
                if !savedCookie.isEmpty {
                    isSaved = true
                    // Validate Plex session in background
                    Task {
                        let result = await OverseerrService.shared.validatePlexSession(url: savedUrl)
                        await MainActor.run {
                            testResult = result
                        }
                    }
                }
            }
        }
    }

    private var statusCard: some View {
        let info = statusInfo

        return SettingsGroupCard {
            HStack(spacing: DS.Space.s12) {
                Image(systemName: info.icon)
                    .font(.flixorIcon(DS.Icon.lg))
                    .foregroundStyle(info.color)
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    Text(info.title)
                        .font(.flixor(.callout, weight: .semibold))
                    Text(info.description)
                        .font(.flixor(.caption))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(DS.Space.s12)
        }
    }

    private var statusInfo: (icon: String, color: Color, title: String, description: String) {
        if !profileSettings.overseerrEnabled {
            return ("exclamationmark.circle.fill", .gray, String(localized: "Disabled"), String(localized: "Enable Overseerr to request movies and shows"))
        }
        if profileSettings.overseerrUrl.isEmpty {
            return ("exclamationmark.triangle.fill", .orange, String(localized: "Configuration Required"), String(localized: "Enter your Overseerr server URL"))
        }
        if authMethod == .apiKey && apiKey.isEmpty {
            return ("exclamationmark.triangle.fill", .orange, String(localized: "API Key Required"), String(localized: "Enter your Overseerr API key"))
        }
        if let result = testResult {
            if result.valid {
                return ("checkmark.circle.fill", .green, String(localized: "Connected as \(result.username ?? String(localized: "user"))"), String(localized: "You can now request movies and shows"))
            } else {
                return ("xmark.circle.fill", .red, String(localized: "Connection Failed"), result.error ?? String(localized: "Check your settings"))
            }
        }
        if isConfigured && isSaved {
            let displayName = authMethod == .plex ? defaults.overseerrPlexUsername : ""
            return ("checkmark.circle.fill", .green, displayName.isEmpty ? String(localized: "Connected") : String(localized: "Connected as \(displayName)"), String(localized: "Request movies and shows from Details screen"))
        }
        if authMethod == .plex {
            return ("exclamationmark.triangle.fill", .orange, String(localized: "Sign In Required"), String(localized: "Sign in with your Plex account"))
        }
        return ("exclamationmark.triangle.fill", .orange, String(localized: "Test Connection"), String(localized: "Test your connection to save settings"))
    }

    private func testApiKeyConnection() {
        guard canTestApiKey else { return }

        isTesting = true
        testResult = nil
        isSaved = false

        Task {
            let result = await OverseerrService.shared.validateConnection(
                url: profileSettings.overseerrUrl.trimmingCharacters(in: .whitespacesAndNewlines),
                apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            )

            await MainActor.run {
                testResult = result

                if result.valid {
                    profileSettings.overseerrUrl = profileSettings.overseerrUrl.trimmingCharacters(in: .whitespacesAndNewlines)
                    UserDefaults.standard.overseerrApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    UserDefaults.standard.overseerrAuthMethod = .apiKey
                    OverseerrService.shared.clearCache()
                    isSaved = true
                }

                isTesting = false
            }
        }
    }

    private func signInWithPlex() {
        guard canTestPlex else { return }

        isTesting = true
        testResult = nil
        isSaved = false

        Task {
            // Save URL first
            profileSettings.overseerrUrl = profileSettings.overseerrUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.overseerrAuthMethod = .plex

            let result = await OverseerrService.shared.authenticateWithPlex(
                url: profileSettings.overseerrUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            )

            await MainActor.run {
                testResult = result

                if result.valid {
                    OverseerrService.shared.clearCache()
                    isSaved = true
                }

                isTesting = false
            }
        }
    }

    private func handleSignOut() {
        OverseerrService.shared.signOut()
        isSaved = false
        testResult = nil
    }
}

// MARK: - Auth Method Row

private struct AuthMethodRow: View {
    let icon: String
    let iconColor: Color
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s12) {
                Image(systemName: icon)
                    .font(.flixorIcon(DS.Icon.md))
                    .foregroundStyle(isSelected ? iconColor : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    Text(title)
                        .font(.flixor(.callout, weight: .medium))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                    Text(subtitle)
                        .font(.flixor(.caption))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.flixorIcon(DS.Icon.md))
                        .foregroundStyle(.green)
                }
            }
            .padding(DS.Space.s10)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.r8, style: .continuous)
                    .fill(isSelected ? iconColor.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.r8, style: .continuous)
                    .strokeBorder(isSelected ? iconColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

// MARK: - Instruction Step Row

private struct InstructionStepRow: View {
    @Environment(\.flixorTheme) private var theme
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.s10) {
            Text("\(number)")
                .font(.flixor(.caption, weight: .bold))
                .foregroundStyle(theme.onAccent)
                .frame(width: 20, height: 20)
                .background(theme.accent)
                .clipShape(Circle())
            Text(text)
                .font(.flixor(.footnote))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Feature Check Row

private struct FeatureCheckRow: View {
    let text: LocalizedStringKey

    var body: some View {
        HStack(spacing: DS.Space.s8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.flixorIcon(DS.Icon.sm))
                .foregroundStyle(.green)
            Text(text)
                .font(.flixor(.footnote))
                .foregroundStyle(.secondary)
        }
    }
}
