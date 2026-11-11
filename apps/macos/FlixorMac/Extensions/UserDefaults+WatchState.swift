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
        decodedBlob([String: LocalWatchedEntry].self, forKey: profileKey(WatchStateKeys.localWatched)) ?? [:]
    }

    func setLocalWatched(_ entries: [String: LocalWatchedEntry]) {
        storeBlob(entries, forKey: profileKey(WatchStateKeys.localWatched))
    }
}
