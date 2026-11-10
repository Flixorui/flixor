//
//  TMDBSettingsView.swift
//  FlixorMac
//
//  TMDB integration settings - macOS System Settings style
//

import SwiftUI

struct TMDBSettingsView: View {
    @Environment(\.flixorTheme) private var theme
    @ObservedObject private var profileSettings = ProfileSettings.shared
    private let defaults = UserDefaults.standard

    private let tmdbColor = Color(hex: "01B4E4")

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            SettingsSectionHeader(title: "API Key")
            SettingsGroupCard {
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    TextField("Optional: your own TMDB API key", text: Binding(get: { defaults.tmdbApiKey }, set: { defaults.tmdbApiKey = $0 }))
                        .textFieldStyle(.settings)
                    Text("Leave empty to use Flixor's key.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, DS.Space.s12)
                .padding(.vertical, DS.Space.s10)
            }

            // Language
            SettingsSectionHeader(title: "Language")
            SettingsGroupCard {
                SettingsRow(icon: "globe", iconColor: .blue, title: "Metadata Language", showDivider: false) {
                    Picker("", selection: $profileSettings.tmdbLanguage) {
                        Text("English").tag("en")
                        Text("Spanish").tag("es")
                        Text("French").tag("fr")
                        Text("German").tag("de")
                        Text("Japanese").tag("ja")
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
            }

            // Metadata Options
            SettingsSectionHeader(title: "Metadata")
            SettingsGroupCard {
                SettingsRow(icon: "sparkles", iconColor: tmdbColor, title: "Enrich Metadata", subtitle: "Fetch cast, logos, and extras from TMDB") {
                    Toggle("", isOn: $profileSettings.tmdbEnrichMetadata).labelsHidden()
                }
                SettingsRow(icon: "character.bubble.fill", iconColor: .purple, title: "Localized Metadata", subtitle: "Prefer localized titles and summaries", showDivider: false) {
                    Toggle("", isOn: $profileSettings.tmdbLocalizedMetadata).labelsHidden()
                }
            }

        }
    }
}
