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


    // Computed properties for convenience
    private var isEnabled: Bool { profileSettings.overseerrEnabled }
    private var apiKey: String { defaults.overseerrApiKey }

    /// Mirrors `defaults.overseerrAuthMethod` so the page redraws when it changes.
    @State private var authMethod: OverseerrAuthMethod = UserDefaults.standard.overseerrAuthMethod

    private var hasChanges: Bool {
        false // Simplified - changes are saved immediately
    }

    private var canTestApiKey: Bool {
        !profileSettings.overseerrUrl.isEmpty && !defaults.overseerrApiKey.isEmpty && !isSaved
    }

    private var canTestPlex: Bool {
        !profileSettings.overseerrUrl.isEmpty
    }

    /// Signed in (Plex) or a key saved, whether or not requests are turned on.
    private var hasCredentials: Bool {
        guard !profileSettings.overseerrUrl.isEmpty else { return false }
        return authMethod == .apiKey ? (!defaults.overseerrApiKey.isEmpty && isSaved) : !defaults.overseerrSessionCookie.isEmpty
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
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            SettingsGroupCard {
                let info = statusInfo
                SettingsStatusRow(info.state, title: info.title, subtitle: info.description) {
                    if isPlexSignedIn {
                        Button("Sign Out", action: handleSignOut)
                            .buttonStyle(.settingsDestructive)
                    }
                }
                SettingsRow(title: "Server") {
                    TextField("Server address", text: $profileSettings.overseerrUrl, prompt: Text(verbatim: "https://overseerr.example.com"))
                        .textFieldStyle(.settings)
                        .frame(width: 280)
                        .onChange(of: profileSettings.overseerrUrl) { _ in
                            testResult = nil
                            isSaved = false
                        }
                }
                SettingsRow(title: "Sign In With", showDivider: authMethod == .apiKey || hasCredentials) {
                    Picker("", selection: Binding(
                        get: { authMethod },
                        set: { newValue in
                            authMethod = newValue
                            defaults.overseerrAuthMethod = newValue
                            testResult = nil
                            isSaved = false
                        }
                    )) {
                        Text("Plex Account").tag(OverseerrAuthMethod.plex)
                        Text("API Key").tag(OverseerrAuthMethod.apiKey)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                if authMethod == .apiKey {
                    SettingsRow(title: "API Key", showDivider: hasCredentials) {
                        SecureField("Paste your Overseerr API key", text: Binding(
                            get: { defaults.overseerrApiKey },
                            set: { defaults.overseerrApiKey = $0; testResult = nil; isSaved = false }
                        ))
                        .textFieldStyle(.settings)
                        .frame(width: 280)
                    }
                }
                if hasCredentials {
                    SettingsRow(title: "Requests", subtitle: "Request buttons and status on details pages", showDivider: false) {
                        Toggle("", isOn: $profileSettings.overseerrEnabled)
                            .labelsHidden()
                            .onChange(of: profileSettings.overseerrEnabled) { newValue in
                                if !newValue {
                                    Task { @MainActor in OverseerrService.shared.clearCache() }
                                }
                            }
                    }
                }
            }

            if authMethod == .plex && !isPlexSignedIn {
                Button(action: signInWithPlex) {
                    HStack(spacing: DS.Space.s6) {
                        if isTesting { ProgressView().controlSize(.small) }
                        Text("Sign in with Plex")
                    }
                }
                .buttonStyle(.settingsPrimary)
                .disabled(!canTestPlex || isTesting)
            } else if authMethod == .apiKey && !(isSaved && hasCredentials) {
                Button(action: testApiKeyConnection) {
                    HStack(spacing: DS.Space.s6) {
                        if isTesting { ProgressView().controlSize(.small) }
                        Text("Test & Save")
                    }
                }
                .buttonStyle(.settingsPrimary)
                .disabled(!canTestApiKey || isTesting)
            }

            Text(authMethod == .plex
                 ? "Your Plex account must have access to the Overseerr server. Requests show on details pages and go to Radarr and Sonarr."
                 : "Find the key in Overseerr under Settings → General. Requests show on details pages and go to Radarr and Sonarr.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, DS.Space.s10)
        }
        .onAppear {
            authMethod = defaults.overseerrAuthMethod
            loadSavedState()
        }
    }

    // MARK: - Load Saved State

    private func loadSavedState() {
        // Check if we already have saved configuration
        let savedUrl = UserDefaults.standard.overseerrUrl

        if !savedUrl.isEmpty {
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

    private var statusInfo: (state: SettingsStatus, title: String, description: String) {
        if let result = testResult, !result.valid {
            return (.error, String(localized: "Couldn't connect"), result.error ?? String(localized: "Check the server address and sign-in"))
        }
        if hasCredentials {
            let name = testResult?.username ?? (authMethod == .plex ? defaults.overseerrPlexUsername : "")
            let title = name.isEmpty ? String(localized: "Connected") : String(localized: "Connected as \(name)")
            return (.connected, title, profileSettings.overseerrEnabled
                    ? String(localized: "Request movies and shows from details pages")
                    : String(localized: "Requests are turned off"))
        }
        if profileSettings.overseerrUrl.isEmpty {
            return (.notSetUp, String(localized: "Not connected"), String(localized: "Enter your server, then sign in"))
        }
        return (.notSetUp, String(localized: "Not connected"), authMethod == .plex
                ? String(localized: "Sign in with your Plex account")
                : String(localized: "Add your API key, then test it"))
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
                    profileSettings.overseerrEnabled = true
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
                    profileSettings.overseerrEnabled = true
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

