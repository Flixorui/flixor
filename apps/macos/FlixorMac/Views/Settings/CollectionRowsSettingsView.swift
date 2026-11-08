//
//  CollectionRowsSettingsView.swift
//  FlixorMac
//
//  Manage which collections (the user's own and Plex) appear on the home screen
//

import SwiftUI
import FlixorKit

struct CollectionRowsSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var profileSettings = ProfileSettings.shared
    @ObservedObject private var userCollections = UserCollectionsStore.shared

    @State private var collections: [PlexCollection] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Collection Rows")
                    .font(.flixor(.headline, weight: .semibold))
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, DS.Space.s20)
            .padding(.top, DS.Space.s20)
            .padding(.bottom, DS.Space.s16)

            Divider()

            userCollectionToggles

            // Content
            if isLoading {
                VStack(spacing: DS.Space.s12) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading collections...")
                        .font(.flixor(.callout))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: DS.Space.s12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.flixorIcon(DS.Icon.xxl))
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.flixor(.callout))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if collections.isEmpty {
                VStack(spacing: DS.Space.s12) {
                    Image(systemName: "tray")
                        .font(.flixorIcon(DS.Icon.xxl))
                        .foregroundStyle(.secondary)
                    Text("No Plex collections found")
                        .font(.flixor(.callout))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: DS.Space.s16) {
                        SettingsGroupCard {
                            ForEach(Array(collections.enumerated()), id: \.element.id) { index, collection in
                                let isVisible = !profileSettings.hiddenCollectionKeys.contains(collection.ratingKey)
                                SettingsRow(
                                    icon: "sparkles",
                                    iconColor: .purple,
                                    title: .verbatim(collection.title ?? String(localized: "Untitled Collection")),
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
                            .font(.flixor(.caption))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, DS.Space.s4)
                    }
                    .padding(DS.Space.s20)
                }
            }
        }
        .task {
            await loadCollections()
        }
    }

    /// The user's own collections; available without Plex.
    @ViewBuilder
    private var userCollectionToggles: some View {
        if !userCollections.collections.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s8) {
                SettingsSectionHeader(title: "My Collections")
                SettingsGroupCard {
                    ForEach(Array(userCollections.collections.enumerated()), id: \.element.id) { index, collection in
                        SettingsRow(
                            icon: "rectangle.stack.fill",
                            iconColor: .blue,
                            title: .verbatim(collection.name),
                            subtitle: .verbatim(collection.sourceSummary),
                            showDivider: index < userCollections.collections.count - 1
                        ) {
                            Toggle("", isOn: Binding(
                                get: { collection.showOnHome },
                                set: { userCollections.setShowOnHome($0, id: collection.id) }
                            ))
                            .labelsHidden()
                            .accessibilityLabel("Show \(collection.name) on Home")
                        }
                    }
                }
            }
            .padding(.horizontal, DS.Space.s20)
            .padding(.top, DS.Space.s16)
        }
    }

    private func loadCollections() async {
        guard let plexServer = FlixorCore.shared.plexServer else {
            errorMessage = String(localized: "Plex server not connected")
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
                self.errorMessage = String(localized: "Failed to load collections: \(error.localizedDescription)")
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
