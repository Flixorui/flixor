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

    @State private var showHowTo = false

    private var hasKey: Bool { !profileSettings.mdblistApiKey.trimmingCharacters(in: .whitespaces).isEmpty }
    private var isReady: Bool { profileSettings.mdblistEnabled && hasKey }

    private var status: (SettingsStatus, String, String) {
        if isReady { return (.connected, String(localized: "On"), String(localized: "Extra ratings show on details pages")) }
        if hasKey { return (.notSetUp, String(localized: "Off"), String(localized: "Turn on ratings below")) }
        if profileSettings.mdblistEnabled { return (.warning, String(localized: "API key needed"), String(localized: "Add a key to show ratings")) }
        return (.notSetUp, String(localized: "Not set up"), String(localized: "Add an API key to show more ratings on details pages"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            SettingsGroupCard {
                SettingsStatusRow(status.0, title: status.1, subtitle: status.2)
                divider
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    Text("API Key").font(.system(size: 13))
                    SecureField("Paste your MDBList API key", text: $profileSettings.mdblistApiKey)
                        .textFieldStyle(.settings)
                    HStack(spacing: DS.Space.s4) {
                        Text("Free at").foregroundStyle(.secondary)
                        Link("mdblist.com ↗", destination: URL(string: "https://mdblist.com/preferences/")!)
                    }
                    .font(.system(size: 11.5))
                }
                .padding(.horizontal, DS.Space.s12)
                .padding(.vertical, DS.Space.s10)
                divider
                SettingsRow(
                    title: "Show MDBList Ratings",
                    subtitle: hasKey ? nil : "Add a key first",
                    showDivider: false
                ) {
                    Toggle("", isOn: $profileSettings.mdblistEnabled)
                        .labelsHidden()
                        .disabled(!hasKey && !profileSettings.mdblistEnabled)
                        .onChange(of: profileSettings.mdblistEnabled) { newValue in
                            if !newValue {
                                Task { @MainActor in
                                    MDBListService.shared.clearCache()
                                }
                            }
                        }
                }
            }

            DisclosureGroup(isExpanded: $showHowTo) {
                VStack(alignment: .leading, spacing: DS.Space.s8) {
                    InstructionRow(number: 1, text: "Create a free account at mdblist.com")
                    InstructionRow(number: 2, text: "Open Preferences and find the API section")
                    InstructionRow(number: 3, text: "Copy your API key and paste it above")
                }
                .padding(.top, DS.Space.s8)
            } label: {
                Text("How to get a key").font(.system(size: 12.5))
            }
            .padding(.horizontal, DS.Space.s10)

            SettingsSectionHeader(title: "Ratings Shown")
            SettingsGroupCard {
                HStack(spacing: DS.Space.s12) {
                    RatingProviderBadge(name: "IMDb", color: Color(hex: "F5C518"))
                    RatingProviderBadge(name: "TMDB", color: Color(hex: "01B4E4"))
                    RatingProviderBadge(name: "Trakt", color: Color(hex: "ED1C24"))
                    RatingProviderBadge(name: "Letterboxd", color: Color(hex: "00E054"))
                    RatingProviderBadge(name: "RT Critics", color: Color(hex: "FA320A"))
                    RatingProviderBadge(name: "Metacritic", color: Color(hex: "FFCC33"))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DS.Space.s12)
                .padding(.vertical, DS.Space.s12)
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.horizontal, DS.Space.s12)
    }
}

// MARK: - Rating Provider Badge

private struct RatingProviderBadge: View {
    @Environment(\.flixorTheme) private var theme
    let name: String
    let color: Color

    var body: some View {
        HStack(spacing: DS.Space.s4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(name)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
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
                .font(.system(size: 11, weight: .bold))
                .frame(width: 18, height: 18)
                .background(Color.white.opacity(0.14), in: Circle())
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
        }
    }
}
