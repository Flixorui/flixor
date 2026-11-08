//
//  MDBListSettingsView.swift
//  FlixorMac
//
//  MDBList integration settings - macOS System Settings style
//

import SwiftUI
import AppKit

struct MDBListSettingsView: View {
    @Environment(\.flixorTheme) private var theme
    @ObservedObject private var profileSettings = ProfileSettings.shared

    private let mdblistColor = Color(hex: "F5C518")

    private var isReady: Bool {
        profileSettings.mdblistEnabled && !profileSettings.mdblistApiKey.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s24) {
            // Status
            SettingsSectionHeader(title: "Status")
            SettingsGroupCard {
                HStack(spacing: DS.Space.s12) {
                    Image(systemName: isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.flixorIcon(DS.Icon.lg))
                        .foregroundStyle(isReady ? .green : .orange)
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        Text(isReady ? "Active" : (profileSettings.mdblistEnabled ? "API Key Required" : "Disabled"))
                            .font(.flixor(.callout, weight: .semibold))
                        Text(isReady ? "Fetching ratings from multiple sources" : "Enable and add API key to activate")
                            .font(.flixor(.caption))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(DS.Space.s12)
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
                VStack(alignment: .leading, spacing: DS.Space.s12) {
                    Text("API Key")
                        .font(.flixor(.callout, weight: .medium))
                        .padding(.horizontal, DS.Space.s12)
                        .padding(.top, DS.Space.s12)

                    SecureField("Enter your MDBList API key", text: $profileSettings.mdblistApiKey)
                        .textFieldStyle(.plain)
                        .padding(DS.Space.s10)
                        .background(theme.settingsFieldBackground)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r8, style: .continuous))
                        .padding(.horizontal, DS.Space.s12)
                        .disabled(!profileSettings.mdblistEnabled)
                        .opacity(profileSettings.mdblistEnabled ? 1 : 0.5)

                    Text("Get your free API key from mdblist.com")
                        .font(.flixor(.caption))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, DS.Space.s12)
                        .padding(.bottom, DS.Space.s12)
                }
            }

            // Rating Providers
            SettingsSectionHeader(title: "Available Ratings")
            SettingsGroupCard {
                VStack(alignment: .leading, spacing: DS.Space.s12) {
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
                    .padding(DS.Space.s12)
                }
            }

            // Instructions
            SettingsSectionHeader(title: "Setup Instructions")
            SettingsGroupCard {
                VStack(alignment: .leading, spacing: DS.Space.s12) {
                    InstructionRow(number: 1, text: "Create a free account at mdblist.com")
                    InstructionRow(number: 2, text: "Go to Settings → API")
                    InstructionRow(number: 3, text: "Copy your API key and paste above")

                    Divider()

                    Button(action: {
                        if let url = URL(string: "https://mdblist.com/preferences/") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: DS.Space.s6) {
                            Text("Open MDBList")
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
    }
}

// MARK: - Rating Provider Badge

private struct RatingProviderBadge: View {
    @Environment(\.flixorTheme) private var theme
    let name: String
    let color: Color

    var body: some View {
        HStack(spacing: DS.Space.s6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(name)
                .font(.flixor(.caption, weight: .medium))
        }
        .padding(.horizontal, DS.Space.s10)
        .padding(.vertical, DS.Space.s6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.chromeColor(default: Color(NSColor.controlBackgroundColor).opacity(0.5), pureBlack: theme.surface))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r6, style: .continuous))
    }
}

// MARK: - Instruction Row

private struct InstructionRow: View {
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
