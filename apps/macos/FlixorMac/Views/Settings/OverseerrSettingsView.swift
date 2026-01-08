//
//  OverseerrSettingsView.swift
//  FlixorMac
//
//  Overseerr integration settings - macOS System Settings style
//

import SwiftUI
import AppKit

struct OverseerrSettingsView: View {
    @AppStorage("overseerrEnabled") private var isEnabled: Bool = false
    @AppStorage("overseerrUrl") private var serverUrl: String = ""
    @AppStorage("overseerrApiKey") private var apiKey: String = ""

    @State private var isTesting: Bool = false
    @State private var isSaved: Bool = false
    @State private var testResult: OverseerrConnectionResult?

    private let overseerrColor = Color(hex: "6366F1")

    private var hasChanges: Bool {
        serverUrl != UserDefaults.standard.overseerrUrl ||
        apiKey != UserDefaults.standard.overseerrApiKey
    }

    private var canTest: Bool {
        isEnabled && !serverUrl.isEmpty && !apiKey.isEmpty && (!isSaved || hasChanges)
    }

    private var isConfigured: Bool {
        isEnabled && !serverUrl.isEmpty && !apiKey.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Status
            SettingsSectionHeader(title: "Status")
            statusCard

            // Enable
            SettingsSectionHeader(title: "Integration")
            SettingsGroupCard {
                SettingsRow(icon: "arrow.down.circle.fill", iconColor: overseerrColor, title: "Enable Overseerr", subtitle: "Request movies and TV shows", showDivider: false) {
                    Toggle("", isOn: $isEnabled)
                        .labelsHidden()
                        .onChange(of: isEnabled) { newValue in
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

            // Server Configuration
            SettingsSectionHeader(title: "Server Configuration")
            SettingsGroupCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Server URL")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.top, 12)

                    TextField("https://overseerr.example.com", text: $serverUrl)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Color(NSColor.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(.horizontal, 12)
                        .disabled(!isEnabled)
                        .opacity(isEnabled ? 1 : 0.5)
                        .onChange(of: serverUrl) { _ in
                            testResult = nil
                            isSaved = false
                        }

                    Divider().padding(.horizontal, 12)

                    Text("API Key")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 12)

                    SecureField("Enter your Overseerr API key", text: $apiKey)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Color(NSColor.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(.horizontal, 12)
                        .disabled(!isEnabled)
                        .opacity(isEnabled ? 1 : 0.5)
                        .onChange(of: apiKey) { _ in
                            testResult = nil
                            isSaved = false
                        }

                    Button(action: testConnection) {
                        HStack(spacing: 6) {
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
                    .disabled(!canTest || isTesting || (isSaved && !hasChanges))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }

            // Instructions
            SettingsSectionHeader(title: "Setup Instructions")
            SettingsGroupCard {
                VStack(alignment: .leading, spacing: 12) {
                    InstructionStepRow(number: 1, text: "Open your Overseerr web interface")
                    InstructionStepRow(number: 2, text: "Go to Settings → General")
                    InstructionStepRow(number: 3, text: "Copy the API Key and paste above")

                    Divider()

                    Button(action: {
                        if let url = URL(string: "https://docs.overseerr.dev/") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Text("Overseerr Documentation")
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10))
                        }
                        .font(.system(size: 13))
                    }
                    .buttonStyle(.link)
                }
                .padding(12)
            }

            // Features
            SettingsSectionHeader(title: "Features")
            SettingsGroupCard {
                VStack(alignment: .leading, spacing: 10) {
                    FeatureCheckRow(text: "Request movies and TV shows")
                    FeatureCheckRow(text: "See request status on details page")
                    FeatureCheckRow(text: "Works with Radarr and Sonarr")
                }
                .padding(12)
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
        let savedKey = UserDefaults.standard.overseerrApiKey

        if isEnabled && !savedUrl.isEmpty && !savedKey.isEmpty {
            // Configuration exists, mark as saved
            isSaved = true

            // Optionally validate the connection in the background
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
    }

    private var statusCard: some View {
        let info = statusInfo

        return SettingsGroupCard {
            HStack(spacing: 12) {
                Image(systemName: info.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(info.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(info.description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
        }
    }

    private var statusInfo: (icon: String, color: Color, title: String, description: String) {
        if !isEnabled {
            return ("exclamationmark.circle.fill", .gray, "Disabled", "Enable Overseerr to request movies and shows")
        }
        if serverUrl.isEmpty || apiKey.isEmpty {
            return ("exclamationmark.triangle.fill", .orange, "Configuration Required", "Enter your Overseerr URL and API key")
        }
        if let result = testResult {
            if result.valid {
                return ("checkmark.circle.fill", .green, "Connected as \(result.username ?? "user")", "You can now request movies and shows")
            } else {
                return ("xmark.circle.fill", .red, "Connection Failed", result.error ?? "Check your settings")
            }
        }
        if isConfigured && isSaved {
            return ("checkmark.circle.fill", .green, "Active", "Request movies and shows from Details screen")
        }
        return ("exclamationmark.triangle.fill", .orange, "Test Connection", "Test your connection to save settings")
    }

    private func testConnection() {
        guard canTest else { return }

        isTesting = true
        testResult = nil
        isSaved = false

        Task {
            let result = await OverseerrService.shared.validateConnection(
                url: serverUrl.trimmingCharacters(in: .whitespacesAndNewlines),
                apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            )

            await MainActor.run {
                testResult = result

                if result.valid {
                    UserDefaults.standard.overseerrUrl = serverUrl.trimmingCharacters(in: .whitespacesAndNewlines)
                    UserDefaults.standard.overseerrApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    OverseerrService.shared.clearCache()
                    isSaved = true
                }

                isTesting = false
            }
        }
    }
}

// MARK: - Instruction Step Row

private struct InstructionStepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor)
                .clipShape(Circle())
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Feature Check Row

private struct FeatureCheckRow: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.green)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}
