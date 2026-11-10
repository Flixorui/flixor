//
//  SidebarNavigationRail.swift
//  FlixorMac
//
//  Optional left navigation rail (Settings > NavBar > Navigation Style).
//  Collapsed it shows icons only; it expands over the content on hover to
//  show labels, or stays expanded when pinned (the content then makes room).
//  The profile menu, settings and the pin live at the bottom.
//

import SwiftUI

/// Rail sizes. The collapsed width fits one icon slot with even margins.
enum SidebarMetrics {
    static let collapsedWidth: CGFloat = 68
    static let expandedWidth: CGFloat = 200
    static let iconSlot: CGFloat = 38
    static let rowHeight: CGFloat = 46
    static let avatarSize: CGFloat = 28
    /// Horizontal inset of each row inside the rail.
    static let rowInset: CGFloat = DS.Space.s8
    /// Leading padding inside a row that centres the icon slot in the collapsed rail.
    static let iconLeading: CGFloat = (collapsedWidth - iconSlot) / 2 - rowInset
    static let profileMenuWidth: CGFloat = 220
}

extension NavItem {
    /// SF Symbol for the sidebar.
    /// Nav icon in Assets.xcassets/NavIcons (Phosphor; Library and New &
    /// Popular from Heroicons). Each has a "-fill" variant for the selected tab.
    var navIconAsset: String {
        switch self {
        case .home: return "nav-home"
        case .library: return "nav-library"
        case .myList: return "nav-mylist"
        case .newPopular: return "nav-newpopular"
        case .downloads: return "nav-downloads"
        case .search: return "nav-search"
        }
    }
}

/// A navigation icon from the NavIcons asset set: outline normally, filled
/// when selected. Template images, so they take the surrounding colour.
struct FlixorNavIcon: View {
    let asset: String
    var selected = false
    var size: CGFloat = 22

    var body: some View {
        Image(selected ? asset + "-fill" : asset)
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}

/// The Live TV nav icon: a plain television, styled like the other tabs.
struct FlixorLiveTVNavIcon: View {
    var size: CGFloat = 22

    var body: some View {
        FlixorNavIcon(asset: "nav-livetv", size: size)
    }
}

/// Profile identity and actions shown at the bottom of the rail. Mirrors the
/// toolbar's profile menu.
struct SidebarProfileMenu {
    let name: String
    let initials: String
    let avatarColor: Color
    let canSwitchProfile: Bool
    let isStremioOnly: Bool
    let onSwitchProfile: () -> Void
    let onOpenSettings: () -> Void
    let onConnectPlex: () -> Void
    let onSignOut: () -> Void
}

struct SidebarNavigationRail: View {
    let items: [NavItem]
    let selectedTab: NavItem
    let onSelect: (NavItem) -> Void
    let profile: SidebarProfileMenu

    @ObservedObject private var store = NavigationStyleStore.shared
    #if FLIXOR_LIVE_TV
    @ObservedObject private var liveTV = LiveTVStore.shared
    #endif
    @Environment(\.flixorTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var showingProfileMenu = false

    private var isExpanded: Bool {
        store.sidebarPinned || isHovered || showingProfileMenu
    }

    /// Floating over the content (hover-expanded, not pinned).
    private var isFloating: Bool {
        isExpanded && !store.sidebarPinned
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            ForEach(items) { item in
                SidebarRow(
                    title: item.localizedRawValue,
                    isSelected: item == selectedTab,
                    isExpanded: isExpanded,
                    action: { onSelect(item) }
                ) {
                    FlixorNavIcon(asset: item.navIconAsset, selected: item == selectedTab)
                }
            }

            #if FLIXOR_LIVE_TV
            if liveTV.featureEnabled {
                SidebarRow(
                    title: "Live TV",
                    isSelected: false,
                    isExpanded: isExpanded,
                    accentIcon: true,
                    action: { liveTV.enter() }
                ) {
                    FlixorLiveTVNavIcon()
                }
                .help("Live TV (⌘L)")
            }
            #endif

            Spacer(minLength: DS.Space.s16)

            Rectangle()
                .fill(theme.separator)
                .frame(height: DS.Border.hairline)
                .padding(.horizontal, SidebarMetrics.rowInset + DS.Space.s4)
                .padding(.bottom, DS.Space.s4)

            SidebarRow(
                title: store.sidebarPinned ? String(localized: "Collapse Sidebar") : String(localized: "Keep Expanded"),
                isSelected: false,
                isExpanded: isExpanded,
                accentIcon: store.sidebarPinned,
                action: { store.sidebarPinned.toggle() }
            ) {
                FlixorNavIcon(asset: "nav-pin", selected: store.sidebarPinned, size: 18)
            }

            SidebarRow(
                title: String(localized: "Settings"),
                isSelected: false,
                isExpanded: isExpanded,
                action: profile.onOpenSettings
            ) {
                FlixorNavIcon(asset: "nav-settings")
            }

            SidebarRow(
                title: profile.name,
                isSelected: false,
                isExpanded: isExpanded,
                accessibilityLabel: String(localized: "Profile: \(profile.name)"),
                action: { showingProfileMenu.toggle() }
            ) {
                Circle()
                    .fill(profile.avatarColor)
                    .frame(width: SidebarMetrics.avatarSize, height: SidebarMetrics.avatarSize)
                    .overlay(
                        Text(profile.initials)
                            .font(.flixor(.caption, weight: .bold))
                            .foregroundStyle(theme.textPrimary)
                    )
            }
            .popover(isPresented: $showingProfileMenu, arrowEdge: .trailing) {
                SidebarProfileMenuView(profile: profile) { action in
                    showingProfileMenu = false
                    // Let the popover close before a sheet or dialog opens.
                    DispatchQueue.main.asyncAfter(deadline: .now() + DS.Motion.quickDuration) {
                        action()
                    }
                }
            }
        }
        .padding(.vertical, DS.Space.s12)
        .frame(width: isExpanded ? SidebarMetrics.expandedWidth : SidebarMetrics.collapsedWidth, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
        .background(
            theme.surface
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(theme.separator)
                        .frame(width: DS.Border.hairline)
                }
                .flixorShadow(isFloating ? .floating : .none)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(reduceMotion ? nil : DS.Motion.standard, value: isExpanded)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Navigation")
    }
}

// MARK: - Row

private struct SidebarRow<Icon: View>: View {
    let title: String
    let isSelected: Bool
    let isExpanded: Bool
    var accentIcon: Bool = false
    var accessibilityLabel: String? = nil
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    @Environment(\.flixorTheme) private var theme
    @State private var isHovered = false

    private var iconColor: Color {
        if isSelected { return theme.onAccent }
        if accentIcon { return theme.accent }
        return isHovered ? theme.textPrimary : theme.textSecondary
    }

    private var labelColor: Color {
        isSelected || isHovered ? theme.textPrimary : theme.textSecondary
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s12) {
                icon()
                    .foregroundStyle(iconColor)
                    .frame(width: SidebarMetrics.iconSlot, height: SidebarMetrics.iconSlot)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.poster, style: .continuous)
                            .fill(isSelected ? theme.accent : Color.clear)
                    )

                Text(title)
                    .flixorFont(.body, weight: isSelected ? .semibold : .medium)
                    .foregroundStyle(labelColor)
                    .lineLimit(1)
                    .fixedSize()
                    .opacity(isExpanded ? 1 : 0)

                Spacer(minLength: 0)
            }
            .padding(.leading, SidebarMetrics.iconLeading)
            .frame(height: SidebarMetrics.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.poster, style: .continuous)
                    .fill(isHovered && !isSelected ? theme.hoverFill : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, SidebarMetrics.rowInset)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(isExpanded ? "" : title)
        .accessibilityLabel(accessibilityLabel ?? title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Profile menu

private struct SidebarProfileMenuView: View {
    let profile: SidebarProfileMenu
    /// Runs an action after closing the popover.
    let perform: (@escaping () -> Void) -> Void

    @Environment(\.flixorTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Label(profile.name, systemImage: "person.circle.fill")
                .flixorFont(.callout, weight: .semibold)
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, DS.Space.s10)
                .padding(.vertical, DS.Space.s8)

            divider

            if profile.canSwitchProfile {
                SidebarMenuRow(title: "Switch Profile", systemImage: "person.2") {
                    perform(profile.onSwitchProfile)
                }
                divider
            }

            SidebarMenuRow(title: "Settings", systemImage: "gear") {
                perform(profile.onOpenSettings)
            }

            divider

            if profile.isStremioOnly {
                // No Plex session to sign out of - offer to connect one instead.
                SidebarMenuRow(title: "Connect Plex", systemImage: "link") {
                    perform(profile.onConnectPlex)
                }
            } else {
                SidebarMenuRow(title: "Sign Out", systemImage: "rectangle.portrait.and.arrow.right", isDestructive: true) {
                    perform(profile.onSignOut)
                }
            }
        }
        .padding(DS.Space.s6)
        .frame(width: SidebarMetrics.profileMenuWidth)
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.separator)
            .frame(height: DS.Border.hairline)
            .padding(.vertical, DS.Space.s4)
    }
}

private struct SidebarMenuRow: View {
    let title: String
    let systemImage: String
    var isDestructive: Bool = false
    let action: () -> Void

    @Environment(\.flixorTheme) private var theme
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.controlGap) {
                Image(systemName: systemImage)
                    .font(.flixorIcon(DS.Icon.sm))
                    .frame(width: DS.Icon.lg)
                Text(title)
                    .flixorFont(.callout, weight: .medium)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isDestructive ? theme.danger : theme.textPrimary)
            .padding(.horizontal, DS.Space.s10)
            .padding(.vertical, DS.Space.s6)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .fill(isHovered ? theme.hoverFill : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityLabel(title)
    }
}
