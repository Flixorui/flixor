//
//  TMDBSettingsView.swift
//  FlixorMac
//
//  TMDB integration settings - macOS System Settings style
//

import SwiftUI

struct TMDBSettingsView: View {
    @ObservedObject private var profileSettings = ProfileSettings.shared
    private let defaults = UserDefaults.standard

    private let tmdbColor = Color(hex: "01B4E4")

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s24) {
            // API Key
            SettingsSectionHeader(title: "API Configuration")
            SettingsGroupCard {
                VStack(alignment: .leading, spacing: DS.Space.s12) {
                    Text("Custom API Key")
                        .font(.flixor(.callout, weight: .medium))
                        .padding(.horizontal, DS.Space.s12)
                        .padding(.top, DS.Space.s12)

                    TextField("Enter your TMDB API key (optional)", text: Binding(get: { defaults.tmdbApiKey }, set: { defaults.tmdbApiKey = $0 }))
                        .textFieldStyle(.plain)
                        .padding(DS.Space.s10)
                        .background(Color(NSColor.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r8, style: .continuous))
                        .padding(.horizontal, DS.Space.s12)

                    Text("Leave empty to use the default app key")
                        .font(.flixor(.caption))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, DS.Space.s12)
                        .padding(.bottom, DS.Space.s12)
                }
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

            // Info
            Text("TMDB provides movie and TV show metadata, artwork, cast information, and logos.")
                .font(.flixor(.caption))
                .foregroundStyle(.secondary)
                .padding(.horizontal, DS.Space.s4)
        }
    }
}
