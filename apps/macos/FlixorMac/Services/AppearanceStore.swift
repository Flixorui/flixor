//
//  AppearanceStore.swift
//  FlixorMac
//
//  Observable owner of the per-profile appearance settings. The root of each
//  window applies it with `.flixorAppearance()`; settings UI binds to it.
//

import Combine
import SwiftUI

@MainActor
final class AppearanceStore: ObservableObject {
    static let shared = AppearanceStore()

    private let defaults = UserDefaults.standard
    private var profileObserver: AnyCancellable?
    private var isLoading = false

    @Published var palette: AccentPalette {
        didSet {
            guard !isLoading, palette != oldValue else { return }
            defaults.appearanceAccentPalette = palette
        }
    }

    @Published var pureBlack: Bool {
        didSet {
            guard !isLoading, pureBlack != oldValue else { return }
            defaults.appearancePureBlack = pureBlack
        }
    }

    /// The resolved theme for the current profile.
    var theme: FlixorTheme { FlixorTheme(palette: palette, pureBlack: pureBlack) }

    private init() {
        palette = defaults.appearanceAccentPalette
        pureBlack = defaults.appearancePureBlack

        // Profile switches call ProfileSettings.reloadFromStorage(), which
        // republishes every setting. Follow it so the accent changes with the
        // profile. Reloading is two UserDefaults reads and only publishes
        // when a value actually differs.
        profileObserver = ProfileSettings.shared.objectWillChange
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.reload()
                }
            }
    }

    /// Re-reads the settings for the current profile (call after the active
    /// profile changes).
    func reload() {
        let newPalette = defaults.appearanceAccentPalette
        let newPureBlack = defaults.appearancePureBlack
        isLoading = true
        if newPalette != palette { palette = newPalette }
        if newPureBlack != pureBlack { pureBlack = newPureBlack }
        isLoading = false
    }

    /// Restores the default accent and background for the current profile.
    func resetToDefaults() {
        palette = .default
        pureBlack = false
    }
}
