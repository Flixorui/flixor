//
//  RowsSettingsView.swift
//  FlixorMac
//
//  Configure which content rows to display on the home screen
//

import SwiftUI
import FlixorKit

struct RowsSettingsView: View {
    @ObservedObject private var profileSettings = ProfileSettings.shared
    @ObservedObject private var appMode = AppModeStore.shared

    @State private var showContinueWatchingOptions = false
    @State private var continueWatchingSource = UserDefaults.standard.continueWatchingSource
    @State private var showCollectionRowsSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s24) {
            // Row Visibility
            SettingsSectionHeader(title: "Row Visibility")
            SettingsGroupCard {
                SettingsRow(icon: "play.circle.fill", iconColor: .green, title: "Continue Watching") {
                    Toggle("", isOn: $profileSettings.showContinueWatching).labelsHidden()
                }
                SettingsRow(icon: "bookmark.fill", iconColor: .blue, title: "Watchlist") {
                    Toggle("", isOn: $profileSettings.showWatchlist).labelsHidden()
                }
                SettingsRow(
                    icon: "flame.fill",
                    iconColor: .orange,
                    title: "Trending",
                    subtitle: profileSettings.discoveryDisabled ? "Disabled by Library Only Mode" : nil
                ) {
                    Toggle("", isOn: $profileSettings.showTrendingRows)
                        .labelsHidden()
                        .disabled(profileSettings.discoveryDisabled)
                }
                SettingsRow(
                    icon: "chart.bar.fill",
                    iconColor: Color(hex: "ED1C24"),
                    title: "Trakt Rows",
                    subtitle: profileSettings.discoveryDisabled ? "Disabled by Library Only Mode" : nil
                ) {
                    Toggle("", isOn: $profileSettings.showTraktRows)
                        .labelsHidden()
                        .disabled(profileSettings.discoveryDisabled)
                }
                SettingsRow(
                    icon: "play.square.stack.fill",
                    iconColor: Color(hex: "E5A00D"),
                    title: appMode.isStremioOnly ? "Popular" : "Popular on Plex",
                    subtitle: profileSettings.discoveryDisabled ? "Disabled by Library Only Mode" : nil,
                    showDivider: !appMode.isStremioOnly
                ) {
                    Toggle("", isOn: $profileSettings.showPlexPopular)
                        .labelsHidden()
                        .disabled(profileSettings.discoveryDisabled)
                }
                // Collections come from a Plex server.
                if !appMode.isStremioOnly {
                    SettingsRow(
                        icon: "sparkles",
                        iconColor: .purple,
                        title: "Collections",
                        subtitle: "Show Plex collection rows on home",
                        showDivider: false
                    ) {
                        Toggle("", isOn: $profileSettings.showCollectionRows)
                            .labelsHidden()
                    }
                }
            }

            Text("Toggle which content rows appear on your home screen.")
                .font(.flixor(.caption))
                .foregroundStyle(.secondary)
                .padding(.horizontal, DS.Space.s4)

            // Reorder, rename and hide individual rows
            HomeRowsEditor()

            // Recently Added Options - the row itself is Plex-library-backed
            if !appMode.isStremioOnly {
                SettingsSectionHeader(title: "Recently Added")
                SettingsGroupCard {
                    SettingsRow(
                        icon: "square.stack.fill",
                        iconColor: .cyan,
                        title: "Group Episodes by Series",
                        subtitle: "Show series posters instead of individual episodes",
                        showDivider: false
                    ) {
                        Toggle("", isOn: $profileSettings.groupRecentlyAddedEpisodes)
                            .labelsHidden()
                    }
                }
            }

            // Collection Rows Options
            if profileSettings.showCollectionRows && !appMode.isStremioOnly {
                SettingsSectionHeader(title: "Collections")
                SettingsGroupCard {
                    SettingsNavigationRow(
                        icon: "sparkles",
                        iconColor: .purple,
                        title: "Manage Collections",
                        subtitle: "Choose which collections appear",
                        showDivider: false
                    ) {
                        showCollectionRowsSettings = true
                    }
                }
            }

            // Continue Watching Options
            if profileSettings.showContinueWatching {
                SettingsSectionHeader(title: "Continue Watching")
                SettingsGroupCard {
                    SettingsRow(
                        icon: "arrow.triangle.merge",
                        iconColor: .red,
                        title: "Continue Watching From",
                        subtitle: FlixorCore.shared.isTraktAuthenticated
                            ? "Automatic combines your library with Trakt progress and next episodes"
                            : "Connect Trakt in Settings to include your Trakt progress"
                    ) {
                        Picker("", selection: $continueWatchingSource) {
                            ForEach(ContinueWatchingSource.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 170)
                        .accessibilityLabel(Text("Continue Watching source"))
                        .onChange(of: continueWatchingSource) { newValue in
                            UserDefaults.standard.continueWatchingSource = newValue
                            NotificationCenter.default.post(name: .continueWatchingSourceDidChange, object: nil)
                        }
                    }
                    SettingsNavigationRow(
                        icon: "gearshape.fill",
                        iconColor: .gray,
                        title: "Display & Caching",
                        subtitle: "Layout style, stream caching options",
                        showDivider: false
                    ) {
                        showContinueWatchingOptions = true
                    }
                }
            }
        }
        .sheet(isPresented: $showContinueWatchingOptions, onDismiss: {
            // The sheet has the same picker; show what was chosen there.
            continueWatchingSource = UserDefaults.standard.continueWatchingSource
        }) {
            ContinueWatchingSettingsView()
                .frame(width: 500, height: 580)
        }
        .sheet(isPresented: $showCollectionRowsSettings) {
            CollectionRowsSettingsView()
                .frame(width: 500, height: 600)
                .pureBlackSheetBackground()
        }
    }
}
