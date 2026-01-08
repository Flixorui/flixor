//
//  RowsSettingsView.swift
//  FlixorMac
//
//  Configure which content rows to display on the home screen
//

import SwiftUI

struct RowsSettingsView: View {
    @AppStorage("showContinueWatching") private var showContinueWatching: Bool = true
    @AppStorage("showTrendingRows") private var showTrendingRows: Bool = true
    @AppStorage("showTraktRows") private var showTraktRows: Bool = true
    @AppStorage("showPlexPopular") private var showPlexPopular: Bool = true
    @AppStorage("showWatchlist") private var showWatchlist: Bool = true

    @State private var showContinueWatchingOptions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Row Visibility
            SettingsSectionHeader(title: "Row Visibility")
            SettingsGroupCard {
                SettingsRow(icon: "play.circle.fill", iconColor: .green, title: "Continue Watching") {
                    Toggle("", isOn: $showContinueWatching).labelsHidden()
                }
                SettingsRow(icon: "bookmark.fill", iconColor: .blue, title: "Watchlist") {
                    Toggle("", isOn: $showWatchlist).labelsHidden()
                }
                SettingsRow(icon: "flame.fill", iconColor: .orange, title: "Trending") {
                    Toggle("", isOn: $showTrendingRows).labelsHidden()
                }
                SettingsRow(icon: "chart.bar.fill", iconColor: Color(hex: "ED1C24"), title: "Trakt Rows") {
                    Toggle("", isOn: $showTraktRows).labelsHidden()
                }
                SettingsRow(icon: "play.square.stack.fill", iconColor: Color(hex: "E5A00D"), title: "Popular on Plex", showDivider: false) {
                    Toggle("", isOn: $showPlexPopular).labelsHidden()
                }
            }

            Text("Toggle which content rows appear on your home screen.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            // Continue Watching Options
            if showContinueWatching {
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
