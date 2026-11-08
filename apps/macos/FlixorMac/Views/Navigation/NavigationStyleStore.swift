//
//  NavigationStyleStore.swift
//  FlixorMac
//
//  Observable owner of the per-profile navigation layout (top bar or
//  sidebar) and the sidebar "keep expanded" pin.
//

import Combine
import SwiftUI

@MainActor
final class NavigationStyleStore: ObservableObject {
    static let shared = NavigationStyleStore()

    private let defaults = UserDefaults.standard
    private var profileObserver: AnyCancellable?
    private var isLoading = false

    @Published var style: NavigationStyle {
        didSet {
            guard !isLoading, style != oldValue else { return }
            defaults.navigationStyle = style
        }
    }

    @Published var sidebarPinned: Bool {
        didSet {
            guard !isLoading, sidebarPinned != oldValue else { return }
            defaults.navigationSidebarPinned = sidebarPinned
        }
    }

    @Published var barStyle: NavigationBarStyle {
        didSet {
            guard !isLoading, barStyle != oldValue else { return }
            defaults.navigationBarStyle = barStyle
        }
    }

    @Published var barGlowEnabled: Bool {
        didSet {
            guard !isLoading, barGlowEnabled != oldValue else { return }
            defaults.navigationBarGlowEnabled = barGlowEnabled
        }
    }

    var usesSidebar: Bool { style == .sidebar }

    private init() {
        style = defaults.navigationStyle
        sidebarPinned = defaults.navigationSidebarPinned
        barStyle = defaults.navigationBarStyle
        barGlowEnabled = defaults.navigationBarGlowEnabled

        // Profile switches call ProfileSettings.reloadFromStorage(), which
        // republishes every setting. Follow it so the layout follows the profile.
        profileObserver = ProfileSettings.shared.objectWillChange
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.reload()
                }
            }
    }

    /// Re-reads the settings for the current profile.
    func reload() {
        let newStyle = defaults.navigationStyle
        let newPinned = defaults.navigationSidebarPinned
        let newBarStyle = defaults.navigationBarStyle
        let newBarGlow = defaults.navigationBarGlowEnabled
        isLoading = true
        if newStyle != style { style = newStyle }
        if newPinned != sidebarPinned { sidebarPinned = newPinned }
        if newBarStyle != barStyle { barStyle = newBarStyle }
        if newBarGlow != barGlowEnabled { barGlowEnabled = newBarGlow }
        isLoading = false
    }
}
