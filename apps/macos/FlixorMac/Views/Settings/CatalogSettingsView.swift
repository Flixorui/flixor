//
//  CatalogSettingsView.swift
//  FlixorMac
//
//  Catalog settings - macOS System Settings style
//

import SwiftUI
import FlixorKit

struct CatalogSettingsView: View {
    @AppStorage("enabledLibraryKeys") private var enabledLibraryKeysString: String = ""

    @State private var libraries: [PlexLibrary] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var enabledLibraryKeys: Set<String> {
        Set(enabledLibraryKeysString.split(separator: ",").map { String($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if isLoading {
                loadingSection
            } else if let error = errorMessage {
                errorSection(error)
            } else if libraries.isEmpty {
                emptySection
            } else {
                librariesSection
            }
        }
        .task { await loadLibraries() }
    }

    private var loadingSection: some View {
        SettingsGroupCard {
            HStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Loading libraries...")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(16)
        }
    }

    private func errorSection(_ error: String) -> some View {
        VStack(spacing: 16) {
            SettingsGroupCard {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.orange)

                    Text("Failed to load libraries")
                        .font(.system(size: 15, weight: .semibold))

                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Retry") {
                        Task { await loadLibraries() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
            }
        }
    }

    private var emptySection: some View {
        SettingsGroupCard {
            VStack(spacing: 12) {
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)

                Text("No libraries found")
                    .font(.system(size: 15, weight: .semibold))

                Text("Connect to a Plex server to see your libraries.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
    }

    private var librariesSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Movies
            let movieLibraries = libraries.filter { $0.type.lowercased() == "movie" }
            if !movieLibraries.isEmpty {
                SettingsSectionHeader(title: "Movie Libraries")
                SettingsGroupCard {
                    ForEach(Array(movieLibraries.enumerated()), id: \.element.key) { index, library in
                        libraryRow(library, showDivider: index < movieLibraries.count - 1)
                    }
                }
            }

            // TV Shows
            let showLibraries = libraries.filter { $0.type.lowercased() == "show" }
            if !showLibraries.isEmpty {
                SettingsSectionHeader(title: "TV Show Libraries")
                SettingsGroupCard {
                    ForEach(Array(showLibraries.enumerated()), id: \.element.key) { index, library in
                        libraryRow(library, showDivider: index < showLibraries.count - 1)
                    }
                }
            }

            // Other
            let otherLibraries = libraries.filter { !["movie", "show"].contains($0.type.lowercased()) }
            if !otherLibraries.isEmpty {
                SettingsSectionHeader(title: "Other Libraries")
                SettingsGroupCard {
                    ForEach(Array(otherLibraries.enumerated()), id: \.element.key) { index, library in
                        libraryRow(library, showDivider: index < otherLibraries.count - 1)
                    }
                }
            }

            // Info
            Text("Disabled libraries will be hidden from the sidebar and home screen.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private func libraryRow(_ library: PlexLibrary, showDivider: Bool) -> some View {
        let isEnabled = enabledLibraryKeys.isEmpty || enabledLibraryKeys.contains(library.key)

        return SettingsRow(
            icon: libraryIcon(for: library.type),
            iconColor: libraryColor(for: library.type),
            title: library.title ?? "Unknown Library",
            subtitle: library.type.capitalized,
            showDivider: showDivider
        ) {
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { enabled in toggleLibrary(library.key, enabled: enabled) }
            ))
            .labelsHidden()
        }
    }

    private func libraryIcon(for type: String) -> String {
        switch type.lowercased() {
        case "movie": return "film.fill"
        case "show": return "tv.fill"
        case "artist": return "music.note"
        case "photo": return "photo.fill"
        default: return "folder.fill"
        }
    }

    private func libraryColor(for type: String) -> Color {
        switch type.lowercased() {
        case "movie": return .orange
        case "show": return .blue
        case "artist": return .pink
        case "photo": return .green
        default: return .gray
        }
    }

    private func toggleLibrary(_ key: String, enabled: Bool) {
        var keys = enabledLibraryKeys

        if enabled {
            if !keys.isEmpty {
                keys.insert(key)
            }
        } else {
            if keys.isEmpty {
                keys = Set(libraries.map { $0.key })
            }
            keys.remove(key)
        }

        if keys.count == libraries.count {
            enabledLibraryKeysString = ""
        } else {
            enabledLibraryKeysString = keys.sorted().joined(separator: ",")
        }
    }

    @MainActor
    private func loadLibraries() async {
        isLoading = true
        errorMessage = nil

        do {
            let libs: [PlexLibrary] = try await APIClient.shared.get("/api/plex/libraries")
            libraries = libs
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
