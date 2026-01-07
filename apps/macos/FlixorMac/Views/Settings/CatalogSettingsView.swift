//
//  CatalogSettingsView.swift
//  FlixorMac
//
//  Catalog settings for managing which Plex libraries appear in the app
//

import SwiftUI
import FlixorKit

struct CatalogSettingsView: View {
    @AppStorage("enabledLibraryKeys") private var enabledLibraryKeysString: String = ""

    @State private var libraries: [PlexLibrary] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var enabledLibraryKeys: Set<String> {
        get {
            Set(enabledLibraryKeysString.split(separator: ",").map { String($0) })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            headerSection

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

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: "folder.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.purple)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Catalog")
                        .font(.headline)
                    Text("Choose which Plex libraries appear in the app")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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

    private var loadingSection: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading libraries...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private func errorSection(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)

            Text("Failed to load libraries")
                .font(.headline)

            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Retry") {
                Task { await loadLibraries() }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private var emptySection: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.questionmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("No libraries found")
                .font(.headline)

            Text("Connect to a Plex server to see your libraries.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private var librariesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Libraries")
                .font(.headline)

            ForEach(libraries, id: \.key) { library in
                libraryRow(library)
            }

            Text("Disabled libraries will be hidden from the sidebar and home screen.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
        .padding(18)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func libraryRow(_ library: PlexLibrary) -> some View {
        let isEnabled = enabledLibraryKeys.isEmpty || enabledLibraryKeys.contains(library.key)

        return Toggle(isOn: Binding(
            get: { isEnabled },
            set: { enabled in toggleLibrary(library.key, enabled: enabled) }
        )) {
            HStack(spacing: 10) {
                Image(systemName: libraryIcon(for: library.type))
                    .foregroundStyle(libraryColor(for: library.type))

                VStack(alignment: .leading, spacing: 2) {
                    Text(library.title ?? "Unknown Library")
                        .font(.subheadline)
                    Text(library.type.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
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
            // If enabling and we have keys set, add this one
            // If enabling and no keys set (all enabled), keep it empty
            if !keys.isEmpty {
                keys.insert(key)
            }
        } else {
            // If disabling, we need to set explicit keys
            if keys.isEmpty {
                // All were enabled, now set all except this one
                keys = Set(libraries.map { $0.key })
            }
            keys.remove(key)
        }

        // Convert to string
        if keys.count == libraries.count {
            // All enabled - use empty string
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
