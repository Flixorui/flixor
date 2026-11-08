//
//  UserDefaults+ContinueWatchingSource.swift
//  FlixorMac
//
//  Where the Continue Watching row gets its items, and Trakt items the user
//  removed from the row. Both are per profile.
//

import Foundation

enum ContinueWatchingSource: String, CaseIterable, Identifiable {
    /// Plex or this Mac's history, plus Trakt when it's connected.
    case automatic
    /// Plex or this Mac's history only.
    case library
    /// Trakt only (falls back to the library when Trakt isn't connected).
    case trakt

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return String(localized: "Automatic")
        case .library: return isStremioOnlyMode ? String(localized: "This Mac Only") : String(localized: "Plex Only")
        case .trakt: return String(localized: "Trakt Only")
        }
    }
}

extension Notification.Name {
    static let continueWatchingSourceDidChange = Notification.Name("continueWatchingSourceDidChange")
}

extension UserDefaults {
    private enum ContinueWatchingSourceKeys {
        static let source = "continueWatchingSource"
        static let traktDismissals = "continueWatchingTraktDismissals"
    }

    var continueWatchingSource: ContinueWatchingSource {
        get {
            string(forKey: profileKey(ContinueWatchingSourceKeys.source))
                .flatMap(ContinueWatchingSource.init(rawValue:)) ?? .automatic
        }
        set { set(newValue.rawValue, forKey: profileKey(ContinueWatchingSourceKeys.source)) }
    }

    /// Row keys of Trakt items the user removed, with when they did. An item comes
    /// back only if it has newer activity than that.
    var continueWatchingTraktDismissals: [String: Double] {
        get { dictionary(forKey: profileKey(ContinueWatchingSourceKeys.traktDismissals)) as? [String: Double] ?? [:] }
        set { set(newValue, forKey: profileKey(ContinueWatchingSourceKeys.traktDismissals)) }
    }
}
