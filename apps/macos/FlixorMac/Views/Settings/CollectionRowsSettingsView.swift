//
//  CollectionRowsSettingsView.swift
//  FlixorMac
//
//  Manage which Plex collections appear on the home screen
//

import SwiftUI
import FlixorKit

struct CollectionRowsSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var profileSettings = ProfileSettings.shared

    @State private var collections: [PlexCollection] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Collection Rows")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            // Content
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading collections...")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if collections.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No Plex collections found")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        SettingsGroupCard {
                            ForEach(Array(collections.enumerated()), id: \.element.id) { index, collection in
                                let isVisible = !profileSettings.hiddenCollectionKeys.contains(collection.ratingKey)
                                SettingsRow(
                                    icon: "sparkles",
                                    iconColor: .purple,
                                    title: collection.title ?? "Untitled Collection",
                                    subtitle: collection.childCount != nil ? "\(collection.childCount!) items" : "Collection",
                                    showDivider: index < collections.count - 1
                                ) {
                                    Toggle("", isOn: Binding(
                                        get: { isVisible },
                                        set: { newValue in
                                            toggleCollection(collection.ratingKey, visible: newValue)
                                        }
                                    ))
                                    .labelsHidden()
                                }
                            }
                        }

                        Text("Toggle collections to show or hide them on the home screen. Only the top 5 visible collections are displayed.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }
                    .padding(20)
                }
            }
        }
        .task {
            await loadCollections()
        }
    }

    private func loadCollections() async {
        guard let plexServer = FlixorCore.shared.plexServer else {
            errorMessage = "Plex server not connected"
            isLoading = false
            return
        }

        do {
            let allCollections = try await plexServer.getAllCollections()
            // Sort by childCount descending (largest collections first)
            let sorted = allCollections
                .filter { ($0.childCount ?? 0) > 0 }
                .sorted { ($0.childCount ?? 0) > ($1.childCount ?? 0) }

            await MainActor.run {
                self.collections = sorted
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load collections: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    private func toggleCollection(_ ratingKey: String, visible: Bool) {
        var currentHidden = profileSettings.hiddenCollectionKeys

        if visible {
            // Remove from hidden list
            currentHidden.removeAll { $0 == ratingKey }
        } else {
            // Add to hidden list
            if !currentHidden.contains(ratingKey) {
                currentHidden.append(ratingKey)
            }
        }

        profileSettings.hiddenCollectionKeys = currentHidden
    }
}

#if DEBUG
#Preview {
    CollectionRowsSettingsView()
        .frame(width: 500, height: 600)
}
#endif
