//
//  RowsSettingsView.swift
//  FlixorMac
//
//  Home row sections shown on Settings > Home (Rows Settings used to be its
//  own page): which families of rows load, and Continue Watching options.
//  Single rows are turned on and off in HomeRowsEditor.
//

import SwiftUI
import FlixorKit

/// Families of rows. Turning one off stops those rows loading at all, so they
/// also leave the row list; single rows are hidden in the list instead.
struct HomeRowSourcesSection: View {
    @ObservedObject private var profileSettings = ProfileSettings.shared
    @ObservedObject private var appMode = AppModeStore.shared
    @State private var showCollectionRowsSettings = false

    private var libraryOnlyNote: LocalizedStringKey? {
        profileSettings.discoveryDisabled ? "Off while Library Only is on" : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            SettingsSectionHeader(title: "Row Sources")
            SettingsGroupCard {
                SettingsRow(icon: "bookmark.fill", iconColor: .blue, title: "Watchlist") {
                    Toggle("", isOn: $profileSettings.showWatchlist).labelsHidden()
                }
                SettingsRow(icon: "flame.fill", iconColor: .orange, title: "Trending", subtitle: libraryOnlyNote ?? "From TMDB") {
                    Toggle("", isOn: $profileSettings.showTrendingRows)
                        .labelsHidden()
                        .disabled(profileSettings.discoveryDisabled)
                }
                SettingsRow(icon: "chart.bar.fill", iconColor: Color(hex: "ED1C24"), title: "Trakt", subtitle: libraryOnlyNote ?? "Trending, popular and recommended on Trakt") {
                    Toggle("", isOn: $profileSettings.showTraktRows)
                        .labelsHidden()
                        .disabled(profileSettings.discoveryDisabled)
                }
                SettingsRow(
                    icon: "play.square.stack.fill",
                    iconColor: Color(hex: "E5A00D"),
                    title: appMode.isStremioOnly ? "Popular" : "Popular on Plex",
                    subtitle: libraryOnlyNote,
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
                        subtitle: "Plex collections as rows",
                        showDivider: profileSettings.showCollectionRows
                    ) {
                        Toggle("", isOn: $profileSettings.showCollectionRows).labelsHidden()
                    }
                    if profileSettings.showCollectionRows {
                        SettingsNavigationRow(title: "Choose Collections…", showDivider: false) {
                            showCollectionRowsSettings = true
                        }
                    }
                }
            }
            SettingsFootnote("Turns a whole set of rows on or off. Hide single rows in the list above.")

            // The Recently Added row is backed by the Plex library.
            if !appMode.isStremioOnly {
                SettingsSectionHeader(title: "Recently Added")
                SettingsGroupCard {
                    SettingsRow(
                        icon: "square.stack.fill",
                        iconColor: .cyan,
                        title: "Group Episodes by Series",
                        subtitle: "Show series posters instead of single episodes",
                        showDivider: false
                    ) {
                        Toggle("", isOn: $profileSettings.groupRecentlyAddedEpisodes).labelsHidden()
                    }
                }
            }
        }
        .sheet(isPresented: $showCollectionRowsSettings) {
            CollectionRowsSettingsView()
                .frame(width: 500, height: 600)
                .pureBlackSheetBackground()
        }
    }
}

/// Where Continue Watching comes from, how its cards look, and caching.
struct HomeContinueWatchingSection: View {
    @ObservedObject private var profileSettings = ProfileSettings.shared
    @State private var showContinueWatchingOptions = false
    @State private var continueWatchingSource = UserDefaults.standard.continueWatchingSource

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            SettingsSectionHeader(title: "Continue Watching")
            SettingsGroupCard {
                if profileSettings.showContinueWatching {
                    SettingsRow(
                        title: "Source",
                        subtitle: FlixorCore.shared.isTraktAuthenticated
                            ? "Automatic combines your library with Trakt progress and next episodes"
                            : "Connect Trakt to include your Trakt progress"
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
                }
                VStack(alignment: .leading, spacing: DS.Space.s8) {
                    Text("Card Style").font(.system(size: 13))
                    ContinueWatchingStylePicker()
                }
                .padding(.horizontal, DS.Space.s12)
                .padding(.vertical, DS.Space.s10)
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.horizontal, DS.Space.s12)
                SettingsNavigationRow(
                    title: "Display & Caching…",
                    subtitle: "Layout and stream caching options",
                    showDivider: false
                ) {
                    showContinueWatchingOptions = true
                }
            }
            if !profileSettings.showContinueWatching {
                SettingsFootnote("Continue Watching is turned off in the row list above.")
            }
        }
        .sheet(isPresented: $showContinueWatchingOptions, onDismiss: {
            // The sheet has the same picker; show what was chosen there.
            continueWatchingSource = UserDefaults.standard.continueWatchingSource
        }) {
            ContinueWatchingSettingsView()
                .frame(width: 500, height: 580)
        }
    }
}
