//
//  UserDefaults+Appearance.swift
//  FlixorMac
//
//  Profile-scoped appearance settings (accent palette, pure black background).
//  Read and write through `AppearanceStore.shared` in UI code so views update.
//

import Foundation

extension UserDefaults {
    private enum AppearanceKeys {
        static let accentPalette = "appearanceAccentPalette"
        static let pureBlack = "appearancePureBlack"
    }

    /// Accent palette for the current profile. Defaults to Flixor red.
    var appearanceAccentPalette: AccentPalette {
        get {
            guard let raw = string(forKey: profileKey(AppearanceKeys.accentPalette)),
                  let palette = AccentPalette(rawValue: raw) else {
                return .default
            }
            return palette
        }
        set { set(newValue.rawValue, forKey: profileKey(AppearanceKeys.accentPalette)) }
    }

    /// True black (#000) backgrounds for the current profile. Default off.
    var appearancePureBlack: Bool {
        get { object(forKey: profileKey(AppearanceKeys.pureBlack)) as? Bool ?? false }
        set { set(newValue, forKey: profileKey(AppearanceKeys.pureBlack)) }
    }
}
