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
    @AppStorage("discoveryDisabled") private var discoveryDisabled: Bool = false

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
                SettingsRow(
                    icon: "flame.fill",
                    iconColor: .orange,
                    title: "Trending",
                    subtitle: discoveryDisabled ? "Disabled by Library Only Mode" : nil
                ) {
                    Toggle("", isOn: $showTrendingRows)
                        .labelsHidden()
                        .disabled(discoveryDisabled)
                }
                SettingsRow(
                    icon: "chart.bar.fill",
                    iconColor: Color(hex: "ED1C24"),
                    title: "Trakt Rows",
                    subtitle: discoveryDisabled ? "Disabled by Library Only Mode" : nil
                ) {
                    Toggle("", isOn: $showTraktRows)
                        .labelsHidden()
                        .disabled(discoveryDisabled)
                }
                SettingsRow(
                    icon: "play.square.stack.fill",
                    iconColor: Color(hex: "E5A00D"),
                    title: "Popular on Plex",
                    subtitle: discoveryDisabled ? "Disabled by Library Only Mode" : nil,
                    showDivider: false
                ) {
                    Toggle("", isOn: $showPlexPopular)
                        .labelsHidden()
                        .disabled(discoveryDisabled)
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
