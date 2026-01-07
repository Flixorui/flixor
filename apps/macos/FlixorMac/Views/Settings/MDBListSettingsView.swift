//
//  MDBListSettingsView.swift
//  FlixorMac
//
//  MDBList integration settings for multi-source ratings
//

import SwiftUI
import AppKit

struct MDBListSettingsView: View {
    @AppStorage("mdblistEnabled") private var isEnabled: Bool = false
    @AppStorage("mdblistApiKey") private var apiKey: String = ""

    @State private var statusMessage: String?
    @State private var errorMessage: String?

    private var isReady: Bool {
        isEnabled && !apiKey.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            headerSection
            statusCard
            enableSection
            apiKeySection
            ratingsSection
            instructionsSection
        }
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: "F5C518").opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color(hex: "F5C518"))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("MDBList")
                    .font(.headline)
                Text("Multi-source ratings aggregator")
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
        HStack(spacing: 12) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(isReady ? Color.green : Color.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(statusDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(14)
        .background(
            (isReady ? Color.green : Color.orange).opacity(0.12),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder((isReady ? Color.green : Color.orange).opacity(0.2), lineWidth: 1)
        )
    }

    private var statusTitle: String {
        if !isEnabled { return "MDBList Disabled" }
        if apiKey.isEmpty { return "API Key Required" }
        return "MDBList Active"
    }

    private var statusDescription: String {
        if !isEnabled { return "Enable MDBList to fetch ratings from multiple sources." }
        if apiKey.isEmpty { return "Enter your MDBList API key to start fetching ratings." }
        return "Fetching ratings from IMDb, TMDB, Trakt, RT, and more."
    }

    private var enableSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Enable MDBList Integration", isOn: $isEnabled)
                .onChange(of: isEnabled) { newValue in
                    if !newValue {
                        Task { @MainActor in
                            MDBListService.shared.clearCache()
                        }
                    }
                }

            Text("Fetch ratings from multiple sources")
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

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("API Key (Required)")
                .font(.headline)

            SecureField("Enter your MDBList API key", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .disabled(!isEnabled)
                .opacity(isEnabled ? 1 : 0.5)

            Text("MDBList requires your own API key. Get one free at mdblist.com.")
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

    private var ratingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Available Ratings")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(Array(RATING_PROVIDERS.keys.sorted()), id: \.self) { key in
                    if let provider = RATING_PROVIDERS[key] {
                        ratingBadge(name: provider.name, color: provider.color)
                    }
                }
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func ratingBadge(name: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(name)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Get Your API Key")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                instructionStep(number: 1, text: "Create an account at mdblist.com")
                instructionStep(number: 2, text: "Go to Settings > API")
                instructionStep(number: 3, text: "Copy your API key and paste above")
            }

            Button(action: {
                if let url = URL(string: "https://mdblist.com/preferences/") {
                    NSWorkspace.shared.open(url)
                }
            }) {
                HStack(spacing: 6) {
                    Text("Go to MDBList")
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
}
