//
//  FloatingNavigationBar.swift
//  FlixorMac
//
//  The main tabs as a floating pill at the top of the window. Labels collapse
//  to icons on scroll and return on hover, depending on the bar style.
//

import AppKit
import SwiftUI

enum FloatingNavMetrics {
    /// Puts the pill fully on the Home hero, below the window controls.
    static let topPadding: CGFloat = 28
    static let barHeight: CGFloat = 48
    /// Space a tab's own content leaves below the window's title bar safe area,
    /// so it starts just under the pill.
    static let contentInset: CGFloat = 54
    static let scrollThreshold: CGFloat = 35
}

// MARK: - Scroll tracking

/// Which tabs are scrolled away from the top. Only publishes when one flips.
@MainActor
final class TabScrollState: ObservableObject {
    static let shared = TabScrollState()

    @Published private(set) var scrolledTabs: Set<NavItem> = []

    func update(tab: NavItem, offset: CGFloat) {
        let isScrolled = offset > FloatingNavMetrics.scrollThreshold
        if isScrolled != scrolledTabs.contains(tab) {
            if isScrolled {
                scrolledTabs.insert(tab)
            } else {
                scrolledTabs.remove(tab)
            }
        }
    }
}

/// Reports a tab's scroll position. Place it on the content inside the ScrollView.
/// Watches the scroll view directly, so scrolling doesn't re-render the page.
struct TabScrollObserver: NSViewRepresentable {
    let tab: NavItem

    func makeCoordinator() -> Coordinator { Coordinator(tab: tab) }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { context.coordinator.attach(from: nsView) }
    }

    final class Coordinator: @unchecked Sendable {
        private let tab: NavItem
        private weak var scrollView: NSScrollView?
        private var observer: NSObjectProtocol?
        private var topOffset: CGFloat = 0

        init(tab: NavItem) {
            self.tab = tab
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }

        @MainActor
        func attach(from view: NSView) {
            guard let found = view.enclosingScrollView, found !== scrollView else { return }
            if let observer { NotificationCenter.default.removeObserver(observer) }
            scrollView = found
            topOffset = found.contentView.bounds.minY
            found.contentView.postsBoundsChangedNotifications = true
            let tab = tab
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: found.contentView,
                queue: .main
            ) { [weak self] _ in
                guard let self, let scrollView = self.scrollView else { return }
                let offset = scrollView.contentView.bounds.minY - self.topOffset
                MainActor.assumeIsolated {
                    TabScrollState.shared.update(tab: tab, offset: offset)
                    if tab == .home { HomeHeroScrollOffset.shared.update(offset) }
                }
            }
            TabScrollState.shared.update(tab: tab, offset: 0)
        }
    }
}

extension View {
    /// Keeps a tab's first content clear of the floating bar.
    func floatingNavContentInset(_ isActive: Bool) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: isActive ? FloatingNavMetrics.contentInset : 0)
        }
    }
}

// MARK: - Bar

struct FloatingNavigationBar: View {
    let items: [NavItem]
    let selectedTab: NavItem
    let onSelect: (NavItem) -> Void
    let profile: SidebarProfileMenu

    @ObservedObject private var store = NavigationStyleStore.shared
    @ObservedObject private var scroll = TabScrollState.shared
    @ObservedObject private var profileSettings = ProfileSettings.shared
    @State private var isHovered = false
    @State private var isProfileMenuOpen = false
    @State private var menuAnchor = MenuAnchor()

    private var isScrolled: Bool { scroll.scrolledTabs.contains(selectedTab) }

    /// Over the full-bleed carousel the bar stays compact until hovered.
    private var carouselHeroIsOn: Bool {
        profileSettings.showHeroSection && profileSettings.heroLayout == "carousel"
    }

    private var showsLabels: Bool {
        switch store.barStyle {
        case .expanded: return true
        case .compact: return false
        case .adaptive:
            if isHovered || isProfileMenuOpen { return true }
            return !(selectedTab == .home && (isScrolled || carouselHeroIsOn))
        }
    }

    private var isFrosted: Bool {
        isHovered || isProfileMenuOpen || isScrolled
    }

    var body: some View {
        FloatingNavigationTrack(
            items: items,
            selectedTab: selectedTab,
            showsLabels: showsLabels,
            isFrosted: isFrosted,
            glowEnabled: store.barGlowEnabled,
            avatarInitials: profile.initials,
            avatarColor: profile.avatarColor,
            menuAnchor: menuAnchor,
            onSelect: onSelect,
            onProfile: showProfileMenu
        )
        .onHover { isHovered = $0 }
        .padding(.top, FloatingNavMetrics.topPadding)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func showProfileMenu() {
        guard let view = menuAnchor.view else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false

        let name = NSMenuItem(title: profile.name, action: nil, keyEquivalent: "")
        name.isEnabled = false
        menu.addItem(name)
        menu.addItem(.separator())

        if profile.canSwitchProfile {
            menu.addItem(MenuActionItem(title: String(localized: "Switch Profile"), systemImage: "person.2", handler: profile.onSwitchProfile))
            menu.addItem(.separator())
        }
        menu.addItem(MenuActionItem(title: String(localized: "Settings"), systemImage: "gear", handler: profile.onOpenSettings))
        menu.addItem(.separator())
        if profile.isStremioOnly {
            menu.addItem(MenuActionItem(title: String(localized: "Connect Plex"), systemImage: "link", handler: profile.onConnectPlex))
        } else {
            menu.addItem(MenuActionItem(title: String(localized: "Sign Out"), systemImage: "rectangle.portrait.and.arrow.right", handler: profile.onSignOut))
        }

        isProfileMenuOpen = true
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -DS.Space.s8), in: view)
        isProfileMenuOpen = false
    }
}

// MARK: - Track

/// The pill itself, shared by the window and the preview in Settings.
struct FloatingNavigationTrack: View {
    let items: [NavItem]
    let selectedTab: NavItem?
    let showsLabels: Bool
    let isFrosted: Bool
    let glowEnabled: Bool
    let avatarInitials: String
    let avatarColor: Color
    var menuAnchor: MenuAnchor? = nil
    let onSelect: (NavItem) -> Void
    let onProfile: () -> Void

    @Environment(\.flixorTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selection
    @State private var labelWidths: [String: CGFloat] = [:]

    private let settingsKey = "floating-nav-settings"

    private var labelAnimation: Animation? {
        reduceMotion ? nil : .timingCurve(0.4, 0, 0.2, 1, duration: 0.32)
    }

    private var selectionAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.68)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                FloatingNavButton(
                    title: item.localizedRawValue,
                    isSelected: item == selectedTab,
                    showsLabel: showsLabels,
                    labelWidth: labelWidths[item.rawValue],
                    glowEnabled: glowEnabled,
                    selection: selection,
                    onLabelWidth: { labelWidths[item.rawValue] = $0 },
                    action: { onSelect(item) }
                ) {
                    Image(systemName: item.sidebarSymbol(selected: item == selectedTab))
                        .font(.flixorIcon(DS.Icon.lg, weight: .medium))
                }
            }

            FloatingNavButton(
                title: String(localized: "Settings"),
                isSelected: false,
                showsLabel: showsLabels,
                labelWidth: labelWidths[settingsKey],
                glowEnabled: glowEnabled,
                selection: selection,
                onLabelWidth: { labelWidths[settingsKey] = $0 },
                action: onProfile
            ) {
                Circle()
                    .fill(avatarColor)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Text(verbatim: avatarInitials)
                            .font(.flixor(.caption, weight: .bold))
                            .foregroundStyle(.white)
                    )
                    .overlay(Circle().strokeBorder(theme.accent, lineWidth: 2))
                    .background { if let menuAnchor { MenuAnchorReader(anchor: menuAnchor) } }
            }
        }
        .padding(DS.Space.s4)
        .frame(height: FloatingNavMetrics.barHeight)
        .background(surface)
        .clipShape(Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: DS.Border.thin))
        .contentShape(Capsule(style: .continuous))
        .animation(labelAnimation, value: showsLabels)
        .animation(labelAnimation, value: isFrosted)
        .animation(selectionAnimation, value: selectedTab)
    }

    private var surface: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(isFrosted ? 1 : 0)
            (isFrosted ? Color(hex: 0x1C1C1E).opacity(0.30) : Color(hex: 0x0F0F11).opacity(0.20))
            LinearGradient(
                colors: [Color.white.opacity(0.14), Color.white.opacity(0.03), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(isFrosted ? 1 : 0)
        }
    }
}

private struct FloatingNavLabelWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct FloatingNavButton<Icon: View>: View {
    let title: String
    let isSelected: Bool
    let showsLabel: Bool
    let labelWidth: CGFloat?
    let glowEnabled: Bool
    let selection: Namespace.ID
    let onLabelWidth: (CGFloat) -> Void
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    @Environment(\.flixorTheme) private var theme
    @State private var isHovered = false

    private let iconBox: CGFloat = 28
    private let labelGap: CGFloat = DS.Space.s6

    private var foreground: Color {
        if isSelected { return theme.textPrimary }
        return isHovered ? theme.textPrimary : theme.textSecondary
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                icon()
                    .frame(width: iconBox, height: iconBox)

                Text(verbatim: title)
                    .font(.flixor(.callout, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .fixedSize()
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: FloatingNavLabelWidthKey.self, value: geo.size.width)
                        }
                    )
                    .padding(.leading, labelGap)
                    .frame(width: showsLabel ? labelWidth.map { $0 + labelGap } : 0, alignment: .leading)
                    .clipped()
                    .opacity(showsLabel ? 1 : 0)
                    .onPreferenceChange(FloatingNavLabelWidthKey.self, perform: onLabelWidth)
            }
            .foregroundStyle(foreground)
            .padding(.leading, showsLabel ? DS.Space.s10 : DS.Space.s6)
            .padding(.trailing, showsLabel ? DS.Space.s14 : DS.Space.s6)
            .frame(height: FloatingNavMetrics.barHeight - DS.Space.s4 * 2)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(theme.accentSoft)
                        .shadow(color: theme.accent.opacity(glowEnabled ? 0.55 : 0), radius: 12)
                        .matchedGeometryEffect(id: "selection", in: selection)
                } else if isHovered {
                    Capsule(style: .continuous)
                        .fill(theme.hoverFill)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(showsLabel ? "" : title)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
