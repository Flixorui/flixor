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
                showDivider: true
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
            } else {
                SettingsRow(
                    icon: "capsule.fill",
                    iconColor: .indigo,
                    title: "Bar Style",
                    subtitle: "How the bar shows its labels",
                    showDivider: true
                ) {
                    Picker("Bar Style", selection: $store.barStyle) {
                        ForEach(NavigationBarStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityLabel("Bar Style")
                }

                SettingsRow(
                    icon: "sparkles",
                    iconColor: .purple,
                    title: "Glass Glow",
                    subtitle: "Adds soft light around the selected tab",
                    showDivider: true
                ) {
                    Toggle("Glass Glow", isOn: $store.barGlowEnabled)
                        .labelsHidden()
                }

                FloatingNavigationPreview()
                    .padding(DS.Space.s12)
            }
        }
    }
}

/// Live example of the bar. Click a tab to try it.
private struct FloatingNavigationPreview: View {
    @ObservedObject private var store = NavigationStyleStore.shared
    @Environment(\.flixorTheme) private var theme
    @State private var selected: NavItem = .home
    @State private var isHovered = false

    private var showsLabels: Bool {
        switch store.barStyle {
        case .expanded: return true
        case .compact: return false
        case .adaptive: return isHovered
        }
    }

    var body: some View {
        FloatingNavigationTrack(
            items: [.home, .search, .library],
            selectedTab: selected,
            showsLabels: showsLabels,
            isFrosted: isHovered,
            glowEnabled: store.barGlowEnabled,
            avatarInitials: "F",
            avatarColor: theme.accent,
            onSelect: { selected = $0 },
            onProfile: {}
        )
        .onHover { isHovered = $0 }
        .padding(.vertical, DS.Space.s20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.r12, style: .continuous)
                .fill(LinearGradient(colors: [theme.accent.opacity(0.35), theme.background], startPoint: .top, endPoint: .bottom))
        )
    }
}
