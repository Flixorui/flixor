//
//  StremioStreamCache.swift
//  FlixorMac
//
//  Cached playback source store for generic stream playback.
//

import Foundation

actor StremioStreamCache {
    static let shared = StremioStreamCache()

    private let storage = StremioStorage.shared

    func save(_ source: CachedPlaybackSource) async {
        var index = await storage.streamCacheIndex()
        index[source.contentKey] = source
        await storage.setStreamCacheIndex(index)
    }

    func get(contentKey: String) async -> CachedPlaybackSource? {
        var index = await storage.streamCacheIndex()
        guard let source = index[contentKey] else { return nil }
        if source.expiresAt < Date() {
            index.removeValue(forKey: contentKey)
            await storage.setStreamCacheIndex(index)
            return nil
        }
        return source
    }

    func remove(contentKey: String) async {
        var index = await storage.streamCacheIndex()
        index.removeValue(forKey: contentKey)
        await storage.setStreamCacheIndex(index)
    }
}
