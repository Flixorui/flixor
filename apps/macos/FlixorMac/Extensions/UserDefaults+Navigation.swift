//
//  UserDefaults+Navigation.swift
//  FlixorMac
//
//  Profile-scoped navigation layout settings. Read and write through
//  `NavigationStyleStore.shared` in UI code so views update.
//

import Foundation

/// Where the main tabs live.
enum NavigationStyle: String, CaseIterable, Identifiable {
    /// Floating pill at the top of the window.
    case topBar
    /// Left icon rail that expands on hover.
    case sidebar

    static let `default`: NavigationStyle = .topBar

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .topBar: return String(localized: "Top Bar")
        case .sidebar: return String(localized: "Sidebar")
        }
    }
}

/// How the floating top bar shows its labels.
enum NavigationBarStyle: String, CaseIterable, Identifiable {
    /// Collapses on scroll and expands on hover.
    case adaptive
    case expanded
    case compact

    static let `default`: NavigationBarStyle = .adaptive

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .adaptive: return String(localized: "Adaptive")
        case .expanded: return String(localized: "Always Expanded")
        case .compact: return String(localized: "Always Compact")
        }
    }
}

extension UserDefaults {
    private enum NavigationKeys {
        static let style = "navigationStyle"
        static let sidebarPinned = "navigationSidebarPinned"
        static let barStyle = "navigationBarStyle"
        static let barGlow = "navigationBarGlow"
    }

    var navigationBarStyle: NavigationBarStyle {
        get {
            guard let raw = string(forKey: profileKey(NavigationKeys.barStyle)),
                  let style = NavigationBarStyle(rawValue: raw) else {
                return .default
            }
            return style
        }
        set { set(newValue.rawValue, forKey: profileKey(NavigationKeys.barStyle)) }
    }

    var navigationBarGlowEnabled: Bool {
        get { object(forKey: profileKey(NavigationKeys.barGlow)) as? Bool ?? true }
        set { set(newValue, forKey: profileKey(NavigationKeys.barGlow)) }
    }

    /// Navigation layout for the current profile. Defaults to the top bar.
    var navigationStyle: NavigationStyle {
        get {
            guard let raw = string(forKey: profileKey(NavigationKeys.style)),
                  let style = NavigationStyle(rawValue: raw) else {
                return .default
            }
            return style
        }
        set { set(newValue.rawValue, forKey: profileKey(NavigationKeys.style)) }
    }

    /// Keep the sidebar expanded instead of expanding on hover. Default off.
    var navigationSidebarPinned: Bool {
        get { object(forKey: profileKey(NavigationKeys.sidebarPinned)) as? Bool ?? false }
        set { set(newValue, forKey: profileKey(NavigationKeys.sidebarPinned)) }
    }
}
