//
//  RowsSettingsView.swift
//  FlixorMac
//
//  Configure which content rows to display on the home screen
//

import SwiftUI

struct RowsSettingsView: View {
    @ObservedObject private var profileSettings = ProfileSettings.shared

    @State private var showContinueWatchingOptions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
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
                    title: "Popular on Plex",
                    subtitle: profileSettings.discoveryDisabled ? "Disabled by Library Only Mode" : nil,
                    showDivider: false
                ) {
                    Toggle("", isOn: $profileSettings.showPlexPopular)
                        .labelsHidden()
                        .disabled(profileSettings.discoveryDisabled)
                }
            }

            Text("Toggle which content rows appear on your home screen.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            // Continue Watching Options
            if profileSettings.showContinueWatching {
                SettingsSectionHeader(title: "Continue Watching")
                SettingsGroupCard {
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
        .sheet(isPresented: $showContinueWatchingOptions) {
            ContinueWatchingSettingsView()
                .frame(width: 500, height: 580)
        }
    }
}
