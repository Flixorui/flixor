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
        VStack(alignment: .leading, spacing: DS.Space.s24) {
            SettingsSectionHeader(title: "Playback")
            SettingsGroupCard {
                SettingsRow(
                    icon: "play.fill",
                    iconColor: .orange,
                    title: "Enable Stremio Playback",
                    subtitle: "Show alternate Stremio source buttons on supported details screens"
                ) {
                    Toggle("", isOn: $profileSettings.stremioPlaybackEnabled)
                        .labelsHidden()
                }

                SettingsNavigationRow(
                    icon: "puzzlepiece.extension.fill",
                    iconColor: .orange,
                    title: "Manage Addons",
                    subtitle: installedAddonCount == 0
                        ? "Install stream and subtitle addons"
                        : "\(installedAddonCount) installed • \(streamAddonCount) stream • \(subtitleAddonCount) subtitle",
                    showDivider: true
                ) {
                    showAddonManager = true
                }

                StreamPlayActionRows(store: streamSelection)

                SettingsRow(
                    icon: "film.stack",
                    iconColor: .blue,
                    title: "Show On TMDB Details",
                    subtitle: "Allow Stremio playback for TMDB-backed titles when IDs can be resolved"
                ) {
                    Toggle("", isOn: $profileSettings.stremioShowOnTmdbDetails)
                        .labelsHidden()
                }

                SettingsRow(
                    icon: "arrow.triangle.2.circlepath.circle.fill",
                    iconColor: .cyan,
                    title: "Prefer Cached Source Resume",
                    subtitle: "Offer resume from the last selected Stremio source when cache is valid"
                ) {
                    Toggle("", isOn: $profileSettings.stremioPreferCachedSourceResume)
                        .labelsHidden()
                }

                SettingsRow(
                    icon: "captions.bubble.fill",
                    iconColor: .purple,
                    title: "Enable Subtitle Addons",
                    subtitle: "Fetch external subtitles from Stremio subtitle addons"
                ) {
                    Toggle("", isOn: $profileSettings.stremioSubtitleAddonsEnabled)
                        .labelsHidden()
                }

                SettingsRow(
                    icon: "square.grid.2x2.fill",
                    iconColor: .teal,
                    title: "Catalog Rows On Home",
                    subtitle: "Show a home row for each catalog your addons provide"
                ) {
                    Toggle("", isOn: $profileSettings.showStremioCatalogRows)
                        .labelsHidden()
                }

                SettingsRow(
                    icon: "magnifyingglass",
                    iconColor: .teal,
                    title: "Search Addon Catalogs",
                    subtitle: "Include addon catalog matches in search results"
                ) {
                    Toggle("", isOn: $profileSettings.stremioCatalogSearchEnabled)
                        .labelsHidden()
                }

                SettingsRow(
                    icon: "eye.slash.fill",
                    iconColor: .gray,
                    title: "Unsupported Sources",
                    subtitle: "Choose whether unsupported Stremio stream types stay visible",
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

            SettingsSectionHeader(title: "Status")
            SettingsGroupCard {
                VStack(alignment: .leading, spacing: DS.Space.s12) {
                    HStack(spacing: DS.Space.s12) {
                        Image(systemName: isStremioOnlyMode ? "puzzlepiece.extension.fill" : "server.rack")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(isStremioOnlyMode ? "Running without Plex" : "Works alongside Plex")
                                .font(.flixor(.callout, weight: .semibold))
                            Text(isStremioOnlyMode
                                 ? "Your addons provide catalogs, metadata and streams. Watch history and My List are stored on this Mac (and synced with Trakt if connected)."
                                 : "Addon streams are offered next to your Plex library. You can also use Flixor without Plex by choosing Stremio-only mode.")
                                .font(.flixor(.caption))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    Divider()

                    HStack(spacing: DS.Space.s12) {
                        Image(systemName: "play.rectangle.fill")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Playback engine is fixed to MPV")
                                .font(.flixor(.callout, weight: .semibold))
                            Text("Direct URL streams, custom headers, advanced codecs, and external subtitles all rely on MPV.")
                                .font(.flixor(.caption))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                .padding(DS.Space.s12)
            }

            if isLoadingAddons {
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity, alignment: .center)
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
