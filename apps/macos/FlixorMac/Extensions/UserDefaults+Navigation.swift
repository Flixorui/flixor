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
    /// Tabs in the window toolbar (the original layout).
    case topBar
    /// Left icon rail that expands on hover.
    case sidebar

    static let `default`: NavigationStyle = .topBar

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .topBar: return "Top Bar"
        case .sidebar: return "Sidebar"
        }
    }
}

extension UserDefaults {
    private enum NavigationKeys {
        static let style = "navigationStyle"
        static let sidebarPinned = "navigationSidebarPinned"
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
