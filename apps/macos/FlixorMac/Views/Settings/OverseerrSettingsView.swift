//
//  OverseerrSettingsView.swift
//  FlixorMac
//
//  Overseerr integration settings for media requests
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
    @State private var connectedUsername: String?

    private var hasChanges: Bool {
        return serverUrl != UserDefaults.standard.overseerrUrl ||
               apiKey != UserDefaults.standard.overseerrApiKey
    }

    private var canTest: Bool {
        return isEnabled && !serverUrl.isEmpty && !apiKey.isEmpty && (!isSaved || hasChanges)
    }

    private var isConfigured: Bool {
        return isEnabled && !serverUrl.isEmpty && !apiKey.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            headerSection
            statusCard
            enableSection
            serverUrlSection
            apiKeySection
            instructionsSection
            aboutSection
        }
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: "6366F1").opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color(hex: "6366F1"))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Overseerr")
                    .font(.headline)
                Text("Media request management")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var statusCard: some View {
        let info = statusInfo

        return HStack(spacing: 12) {
            Image(systemName: info.icon)
                .font(.system(size: 22))
                .foregroundStyle(info.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(info.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(info.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(14)
        .background(info.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(info.color.opacity(0.2), lineWidth: 1)
        )
    }

    private var statusInfo: (icon: String, color: Color, title: String, description: String) {
        if !isEnabled {
            return ("exclamationmark.circle.fill", .gray, "Overseerr Disabled", "Enable Overseerr to request movies and shows.")
        }
        if serverUrl.isEmpty || apiKey.isEmpty {
            return ("exclamationmark.triangle.fill", .orange, "Configuration Required", "Enter your Overseerr URL and API key.")
        }
        if let result = testResult {
            if result.valid {
                return ("checkmark.circle.fill", .green, "Connected as \(result.username ?? "user")", "You can now request movies and shows.")
            } else {
                return ("xmark.circle.fill", .red, "Connection Failed", result.error ?? "Check your settings.")
            }
        }
        if isConfigured && isSaved {
            return ("checkmark.circle.fill", .green, "Overseerr Active", "Request movies and shows from Details screen.")
        }
        return ("exclamationmark.triangle.fill", .orange, "Test Connection", "Test your connection to save settings.")
    }

    private var enableSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Enable Overseerr Integration", isOn: $isEnabled)
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

            Text("Request movies and TV shows")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 20)
        }
        .padding(18)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var serverUrlSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Server URL")
                .font(.headline)

            TextField("https://overseerr.example.com", text: $serverUrl)
                .textFieldStyle(.roundedBorder)
                .disabled(!isEnabled)
                .opacity(isEnabled ? 1 : 0.5)
                .onChange(of: serverUrl) { _ in
                    testResult = nil
                    isSaved = false
                }

            Text("Enter your Overseerr server URL (including https://)")
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

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("API Key")
                .font(.headline)

            SecureField("Enter your Overseerr API key", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .disabled(!isEnabled)
                .opacity(isEnabled ? 1 : 0.5)
                .onChange(of: apiKey) { _ in
                    testResult = nil
                    isSaved = false
                }

            Button(action: testConnection) {
                HStack {
                    if isTesting {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                    Text(isSaved && !hasChanges ? "Saved" : "Test & Save")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(isSaved && !hasChanges ? .green : .accentColor)
            .disabled(!canTest || isTesting || (isSaved && !hasChanges))

            Text("Find your API key in Overseerr Settings > General > API Key")
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

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How to Get Your API Key")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                instructionStep(number: 1, text: "Open your Overseerr web interface")
                instructionStep(number: 2, text: "Go to Settings > General")
                instructionStep(number: 3, text: "Copy the API Key and paste above")
            }

            Button(action: {
                if let url = URL(string: "https://docs.overseerr.dev/") {
                    NSWorkspace.shared.open(url)
                }
            }) {
                HStack(spacing: 6) {
                    Text("Overseerr Documentation")
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                }
            }
            .buttonStyle(.link)
        }
        .padding(18)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About Overseerr")
                .font(.headline)

            Text("Overseerr is a request management and media discovery tool for your Plex ecosystem. When enabled, you can request movies and TV shows directly from Flixor when they're not available in your library.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                featureItem("Request movies and TV shows")
                featureItem("See request status")
                featureItem("Works with Radarr/Sonarr")
            }
            .padding(.top, 4)
        }
        .padding(18)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func instructionStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(text)
                .font(.caption)
        }
    }

    private func featureItem(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.caption)
                .foregroundStyle(.green)
            Text(text)
                .font(.caption)
        }
    }

    private func testConnection() {
        guard canTest else { return }

        isTesting = true
        testResult = nil
        isSaved = false

        Task {
            let result = await OverseerrService.shared.validateConnection(url: serverUrl.trimmingCharacters(in: .whitespacesAndNewlines), apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines))

            await MainActor.run {
                testResult = result

                if result.valid {
                    // Save settings on successful test
                    UserDefaults.standard.overseerrUrl = serverUrl.trimmingCharacters(in: .whitespacesAndNewlines)
                    UserDefaults.standard.overseerrApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    OverseerrService.shared.clearCache()
                    isSaved = true
                    connectedUsername = result.username
                }

                isTesting = false
            }
        }
    }
}
