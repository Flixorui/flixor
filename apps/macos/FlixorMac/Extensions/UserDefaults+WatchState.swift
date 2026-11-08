//
//  UserDefaults+WatchState.swift
//  FlixorMac
//
//  Profile-scoped persistence for titles marked watched on this Mac.
//

import Foundation

extension UserDefaults {
    private enum WatchStateKeys {
        static let localWatched = "localWatchedItems"
    }

    func getLocalWatched() -> [String: LocalWatchedEntry] {
        guard let data = data(forKey: profileKey(WatchStateKeys.localWatched)) else { return [:] }
        return (try? JSONDecoder().decode([String: LocalWatchedEntry].self, from: data)) ?? [:]
    }

    func setLocalWatched(_ entries: [String: LocalWatchedEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        set(data, forKey: profileKey(WatchStateKeys.localWatched))
    }
}
