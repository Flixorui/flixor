//
//  TMDBSettingsView.swift
//  FlixorMac
//
//  TMDB integration settings
//

import SwiftUI

struct TMDBSettingsView: View {
    @AppStorage("tmdbApiKey") private var apiKey: String = ""
    @AppStorage("tmdbLanguage") private var language: String = "en"
    @AppStorage("tmdbEnrichMetadata") private var enrichMetadata: Bool = true
    @AppStorage("tmdbLocalizedMetadata") private var localizedMetadata: Bool = false

    private let languageOptions = [
        ("en", "English"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("ja", "Japanese")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            headerSection
            apiKeySection
            languageSection
            metadataSection
        }
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: "01B4E4").opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: "film.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color(hex: "01B4E4"))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("The Movie Database")
                    .font(.headline)
                Text("Metadata and artwork provider")
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

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("API Key")
                .font(.headline)

            TextField("Enter your TMDB API key", text: $apiKey)
                .textFieldStyle(.roundedBorder)

            Text("Leave empty to use the default app key.")
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

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Language")
                .font(.headline)

            HStack(spacing: 8) {
                ForEach(languageOptions, id: \.0) { code, name in
                    Button(action: { language = code }) {
                        Text(name)
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                language == code
                                    ? Color.white
                                    : Color.white.opacity(0.06)
                            )
                            .foregroundStyle(language == code ? Color.black : Color.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Applies to TMDB requests and logo localization.")
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

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Metadata")
                .font(.headline)

            Toggle("Enrich Metadata", isOn: $enrichMetadata)
            Text("Fetch cast, logos, and extras from TMDB")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 20)

            Divider()
                .padding(.vertical, 4)

            Toggle("Localized Metadata", isOn: $localizedMetadata)
            Text("Prefer localized titles and summaries")
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
}
