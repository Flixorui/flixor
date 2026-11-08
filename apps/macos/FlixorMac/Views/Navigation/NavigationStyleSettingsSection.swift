//
//  NavigationStyleSettingsSection.swift
//  FlixorMac
//
//  "Navigation Style" group on the Settings > NavBar page.
//

import SwiftUI

struct NavigationStyleSettingsSection: View {
    @ObservedObject private var store = NavigationStyleStore.shared

    var body: some View {
        SettingsGroupCard {
            SettingsRow(
                icon: "sidebar.left",
                iconColor: .cyan,
                title: "Navigation Style",
                subtitle: "Show tabs in the top bar or in a sidebar",
                showDivider: store.usesSidebar
            ) {
                Picker("Navigation Style", selection: $store.style) {
                    ForEach(NavigationStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Navigation Style")
            }

            if store.usesSidebar {
                SettingsRow(
                    icon: "pin.fill",
                    iconColor: .orange,
                    title: "Keep Sidebar Expanded",
                    subtitle: "Always show labels instead of expanding on hover",
                    showDivider: false
                ) {
                    Toggle("Keep Sidebar Expanded", isOn: $store.sidebarPinned)
                        .labelsHidden()
                }
            }
        }
    }
}
