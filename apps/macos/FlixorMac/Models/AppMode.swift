//
//  AppMode.swift
//  FlixorMac
//
//  Which content backbone the app is running on.
//  `plex` is the original experience. `stremio` runs standalone with no Plex
//  account or server: TMDB/Trakt supply discovery, Stremio addons supply streams.
//

import Foundation
import SwiftUI

enum AppMode: String, Codable, CaseIterable, Identifiable {
    case plex
    case stremio

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .plex:
            return "Plex"
        case .stremio:
            return "Stremio"
        }
    }

    var description: String {
        switch self {
        case .plex:
            return String(localized: "Stream your Plex library, with Stremio available as an extra source.")
        case .stremio:
            return String(localized: "No Plex account. Discovery comes from TMDB and Trakt, streams from your Stremio addons.")
        }
    }
}

// MARK: - Persistence

// Deliberately NOT profile-scoped: profile scoping is keyed by Plex Home profile
// (see ProfileStorage.getProfileKey), and the mode decides whether a Plex profile
// exists in the first place.
extension UserDefaults {
    private enum AppModeKeys {
        static let appMode = "appMode"
    }

    /// `nil` means the user has not chosen a mode yet - show the mode chooser.
    var appMode: AppMode? {
        get {
            guard let rawValue = string(forKey: AppModeKeys.appMode) else { return nil }
            return AppMode(rawValue: rawValue)
        }
        set {
            if let newValue {
                set(newValue.rawValue, forKey: AppModeKeys.appMode)
            } else {
                removeObject(forKey: AppModeKeys.appMode)
            }
        }
    }
}

// MARK: - Observable Store

/// Publishes the current mode so views re-render when it changes.
@MainActor
final class AppModeStore: ObservableObject {
    static let shared = AppModeStore()

    @Published private(set) var mode: AppMode?

    private init() {
        mode = UserDefaults.standard.appMode
    }

    /// True when running standalone with no Plex. Used to skip Plex work entirely
    /// rather than letting it fail, and to hide Plex-only surfaces.
    var isStremioOnly: Bool { mode == .stremio }

    /// True when Plex data may be available. Callers still need to check for a
    /// connected server - this only says the mode permits it.
    var isPlexMode: Bool { mode == .plex }

    func select(_ newMode: AppMode) {
        guard mode != newMode else { return }
        UserDefaults.standard.appMode = newMode
        mode = newMode

        if newMode == .stremio {
            // Stremio is the only playback path in this mode, so the opt-in toggle
            // (which defaults to off) has to be on or nothing is playable.
            // The ProfileSettings setter writes through to UserDefaults.
            ProfileSettings.shared.stremioPlaybackEnabled = true
        }

        AppLogger.shared.info("[AppMode] Switched to \(newMode.rawValue)")
    }

    func clear() {
        UserDefaults.standard.appMode = nil
        mode = nil
    }
}

// MARK: - Convenience

/// Non-view code reads the mode straight from UserDefaults so it doesn't have to
/// hop to the main actor just to branch.
var isStremioOnlyMode: Bool {
    UserDefaults.standard.appMode == .stremio
}
