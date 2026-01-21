//
//  MDBListSettingsView.swift
//  FlixorMac
//
//  MDBList integration settings - macOS System Settings style
//

import SwiftUI
import AppKit

struct MDBListSettingsView: View {
    @ObservedObject private var profileSettings = ProfileSettings.shared

    private let mdblistColor = Color(hex: "F5C518")

    private var isReady: Bool {
        profileSettings.mdblistEnabled && !profileSettings.mdblistApiKey.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Status
            SettingsSectionHeader(title: "Status")
            SettingsGroupCard {
                HStack(spacing: 12) {
                    Image(systemName: isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(isReady ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isReady ? "Active" : (profileSettings.mdblistEnabled ? "API Key Required" : "Disabled"))
                            .font(.system(size: 13, weight: .semibold))
                        Text(isReady ? "Fetching ratings from multiple sources" : "Enable and add API key to activate")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
            }

            // Enable
            SettingsSectionHeader(title: "Integration")
            SettingsGroupCard {
                SettingsRow(icon: "star.fill", iconColor: mdblistColor, title: "Enable MDBList", subtitle: "Fetch ratings from multiple sources", showDivider: false) {
                    Toggle("", isOn: $profileSettings.mdblistEnabled)
                        .labelsHidden()
                        .onChange(of: profileSettings.mdblistEnabled) { newValue in
                            if !newValue {
                                Task { @MainActor in
                                    MDBListService.shared.clearCache()
                                }
                            }
                        }
                }
            }

            // API Key
            SettingsSectionHeader(title: "API Configuration")
            SettingsGroupCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("API Key")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.top, 12)

                    SecureField("Enter your MDBList API key", text: $profileSettings.mdblistApiKey)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Color(NSColor.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(.horizontal, 12)
                        .disabled(!profileSettings.mdblistEnabled)
                        .opacity(profileSettings.mdblistEnabled ? 1 : 0.5)

                    Text("Get your free API key from mdblist.com")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                }
            }

            // Rating Providers
            SettingsSectionHeader(title: "Available Ratings")
            SettingsGroupCard {
                VStack(alignment: .leading, spacing: 12) {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 8) {
                        RatingProviderBadge(name: "IMDb", color: Color(hex: "F5C518"))
                        RatingProviderBadge(name: "TMDB", color: Color(hex: "01B4E4"))
                        RatingProviderBadge(name: "Trakt", color: Color(hex: "ED1C24"))
                        RatingProviderBadge(name: "Letterboxd", color: Color(hex: "00E054"))
                        RatingProviderBadge(name: "RT Critics", color: Color(hex: "FA320A"))
                        RatingProviderBadge(name: "Metacritic", color: Color(hex: "FFCC33"))
                    }
                    .padding(12)
                }
            }

            // Instructions
            SettingsSectionHeader(title: "Setup Instructions")
            SettingsGroupCard {
                VStack(alignment: .leading, spacing: 12) {
                    InstructionRow(number: 1, text: "Create a free account at mdblist.com")
                    InstructionRow(number: 2, text: "Go to Settings → API")
                    InstructionRow(number: 3, text: "Copy your API key and paste above")

                    Divider()

                    Button(action: {
                        if let url = URL(string: "https://mdblist.com/preferences/") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Text("Open MDBList")
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10))
                        }
                        .font(.system(size: 13))
                    }
                    .buttonStyle(.link)
                }
                .padding(12)
            }
        }
    }
}

// MARK: - Rating Provider Badge

private struct RatingProviderBadge: View {
    let name: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(name)
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - Instruction Row

private struct InstructionRow: View {
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
