//
//  TMDBSettingsView.swift
//  FlixorMac
//
//  TMDB integration settings - macOS System Settings style
//

import SwiftUI

struct TMDBSettingsView: View {
    @AppStorage("tmdbApiKey") private var apiKey: String = ""
    @AppStorage("tmdbLanguage") private var language: String = "en"
    @AppStorage("tmdbEnrichMetadata") private var enrichMetadata: Bool = true
    @AppStorage("tmdbLocalizedMetadata") private var localizedMetadata: Bool = false

    private let tmdbColor = Color(hex: "01B4E4")

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // API Key
            SettingsSectionHeader(title: "API Configuration")
            SettingsGroupCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Custom API Key")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.top, 12)

                    TextField("Enter your TMDB API key (optional)", text: $apiKey)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Color(NSColor.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(.horizontal, 12)

                    Text("Leave empty to use the default app key")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                }
            }

            // Language
            SettingsSectionHeader(title: "Language")
            SettingsGroupCard {
                SettingsRow(icon: "globe", iconColor: .blue, title: "Metadata Language", showDivider: false) {
                    Picker("", selection: $language) {
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
                    Toggle("", isOn: $enrichMetadata).labelsHidden()
                }
                SettingsRow(icon: "character.bubble.fill", iconColor: .purple, title: "Localized Metadata", subtitle: "Prefer localized titles and summaries", showDivider: false) {
                    Toggle("", isOn: $localizedMetadata).labelsHidden()
                }
            }

            // Info
            Text("TMDB provides movie and TV show metadata, artwork, cast information, and logos.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }
}
