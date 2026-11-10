//
//  StremioSettingsView.swift
//  FlixorMac
//
//  Stremio playback and addon settings for macOS.
//

import SwiftUI

struct StremioSettingsView: View {
    @ObservedObject private var profileSettings = ProfileSettings.shared
    @StateObject private var streamSelection = StreamSelectionSettingsStore()
    @State private var addonSummaries: [StremioAddonSummary] = []
    @State private var isLoadingAddons = false
    @State private var showAddonManager = false

    private var installedAddonCount: Int { addonSummaries.count }
    private var streamAddonCount: Int { addonSummaries.filter(\.streamCapable).count }
    private var subtitleAddonCount: Int { addonSummaries.filter(\.subtitleCapable).count }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            SettingsGroupCard {
                SettingsStatusRow(
                    installedAddonCount == 0 ? .notSetUp : .connected,
                    title: installedAddonCount == 0
                        ? String(localized: "No addons")
                        : String(localized: "\(installedAddonCount) addons installed"),
                    subtitle: installedAddonCount == 0
                        ? String(localized: "Install stream and subtitle addons to play from Stremio")
                        : String(localized: "\(streamAddonCount) for streams, \(subtitleAddonCount) for subtitles")
                ) {
                    if isLoadingAddons {
                        ProgressView().controlSize(.small)
                    }
                    Button("Manage Addons…") { showAddonManager = true }
                        .buttonStyle(.settingsSecondary)
                }
            }
            SettingsFootnote(isStremioOnlyMode
                 ? "Running without Plex: addons provide catalogs, metadata and streams. Watch history and My List stay on this Mac (and sync with Trakt if connected)."
                 : "Addon streams are offered next to your Plex library.")

            SettingsSectionHeader(title: "Playback")
            SettingsGroupCard {
                SettingsRow(
                    icon: "play.fill",
                    iconColor: .orange,
                    title: "Stremio Playback",
                    subtitle: "Show Stremio source buttons on details pages"
                ) {
                    Toggle("", isOn: $profileSettings.stremioPlaybackEnabled)
                        .labelsHidden()
                }

                StreamPlayActionRows(store: streamSelection)

                SettingsRow(
                    icon: "film.stack",
                    iconColor: .blue,
                    title: "On TMDB Details",
                    subtitle: "Allow Stremio playback for TMDB titles when their IDs can be matched"
                ) {
                    Toggle("", isOn: $profileSettings.stremioShowOnTmdbDetails)
                        .labelsHidden()
                }

                SettingsRow(
                    icon: "arrow.triangle.2.circlepath.circle.fill",
                    iconColor: .cyan,
                    title: "Resume From Last Source",
                    subtitle: "Offer the last Stremio source again while it's still cached"
                ) {
                    Toggle("", isOn: $profileSettings.stremioPreferCachedSourceResume)
                        .labelsHidden()
                }

                SettingsRow(
                    icon: "eye.slash.fill",
                    iconColor: .gray,
                    title: "Unsupported Sources",
                    subtitle: "Stream types Flixor can't play",
                    showDivider: false
                ) {
                    Picker("", selection: $profileSettings.stremioUnsupportedSourceVisibility) {
                        ForEach(StremioUnsupportedSourceVisibility.allCases, id: \.self) { visibility in
                            Text(visibility.description).tag(visibility)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
            }

            if streamSelection.action == .matchRules {
                SettingsSectionHeader(title: "Source Rules")
                StreamRulesEditor(store: streamSelection, addons: addonSummaries)
            }

            SettingsSectionHeader(title: "Addons")
            SettingsGroupCard {
                SettingsRow(
                    icon: "captions.bubble.fill",
                    iconColor: .purple,
                    title: "Subtitle Addons",
                    subtitle: "Fetch subtitles from Stremio subtitle addons"
                ) {
                    Toggle("", isOn: $profileSettings.stremioSubtitleAddonsEnabled)
                        .labelsHidden()
                }

                SettingsRow(
                    icon: "square.grid.2x2.fill",
                    iconColor: .teal,
                    title: "Catalog Rows on Home",
                    subtitle: "A Home row for each catalog your addons provide"
                ) {
                    Toggle("", isOn: $profileSettings.showStremioCatalogRows)
                        .labelsHidden()
                }

                SettingsRow(
                    icon: "magnifyingglass",
                    iconColor: .teal,
                    title: "Search Addon Catalogs",
                    subtitle: "Include addon catalog matches in search"
                ) {
                    Toggle("", isOn: $profileSettings.stremioCatalogSearchEnabled)
                        .labelsHidden()
                }

                SettingsRow(
                    icon: "photo.on.rectangle",
                    iconColor: .indigo,
                    title: "Addon Posters",
                    subtitle: "Use the posters addons supply (some show ratings on the artwork) instead of TMDB posters",
                    showDivider: false
                ) {
                    Toggle("", isOn: Binding(
                        get: { UserDefaults.standard.stremioUseAddonPosters },
                        set: { UserDefaults.standard.stremioUseAddonPosters = $0; profileSettings.objectWillChange.send() }
                    ))
                    .labelsHidden()
                }
            }
        }
        .task {
            await refreshAddons()
        }
        .onChange(of: profileSettings.stremioPlaybackEnabled) { enabled in
            Task {
                await StremioService.shared.ensureInitialized(installDefaults: enabled)
                await refreshAddons()
            }
        }
        .sheet(isPresented: $showAddonManager) {
            StremioAddonsView()
        }
    }

    @MainActor
    private func refreshAddons() async {
        isLoadingAddons = true
        await StremioService.shared.ensureInitialized(installDefaults: profileSettings.stremioPlaybackEnabled)
        addonSummaries = await StremioService.shared.getAddonSummary()
        isLoadingAddons = false
    }
}
