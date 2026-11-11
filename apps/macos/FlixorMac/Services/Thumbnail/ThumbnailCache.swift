//
//  ThumbnailCache.swift
//  FlixorMac
//
//  LRU cache for video thumbnails
//

import Foundation
import AppKit

/// Thread-safe LRU cache for thumbnail images
class ThumbnailCache {
    // MARK: - Properties

    private var cache: [Int: NSImage] = [:]
    private var accessOrder: [Int] = []
    private let maxSize: Int
    private let queue = DispatchQueue(label: "com.flixor.thumbnail.cache", attributes: .concurrent)

    // MARK: - Initialization

    init(maxSize: Int = 30) {
        self.maxSize = maxSize
    }

    // MARK: - Public Methods

    /// Get a cached thumbnail for a specific timestamp
    /// - Parameter time: Time in seconds
    /// - Returns: Cached NSImage if available, nil otherwise
    func get(at time: Double) -> NSImage? {
        let key = makeKey(from: time)

        // Barrier: a hit reorders `accessOrder`.
        return queue.sync(flags: .barrier) {
            if let image = cache[key] {
                // Update access order (move to end = most recently used)
                updateAccessOrder(key)
                return image
            }
            return nil
        }
    }

    /// Store a thumbnail for a specific timestamp
    /// - Parameters:
    ///   - image: NSImage to cache
    ///   - time: Time in seconds
    func set(image: NSImage, at time: Double) {
        let key = makeKey(from: time)

        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            // If cache is full, evict least recently used
            if self.cache.count >= self.maxSize, !self.cache.keys.contains(key) {
                if let lruKey = self.accessOrder.first {
                    self.cache.removeValue(forKey: lruKey)
                    self.accessOrder.removeFirst()
                    print("🗑️ [ThumbnailCache] Evicted LRU thumbnail (key: \(lruKey))")
                }
            }

            // Add or update thumbnail
            self.cache[key] = image
            self.updateAccessOrder(key)

            print("💾 [ThumbnailCache] Cached thumbnail at \(time)s (total: \(self.cache.count)/\(self.maxSize))")
        }
    }

    /// Clear all cached thumbnails
    func clearAll() {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.cache.removeAll()
            self.accessOrder.removeAll()
            print("🗑️ [ThumbnailCache] Cleared all thumbnails")
        }
    }

    /// Get current cache size
    var count: Int {
        return queue.sync {
            return cache.count
        }
    }

    // MARK: - Private Methods

    /// Create a cache key from a timestamp (rounded to nearest second)
    private func makeKey(from time: Double) -> Int {
        return Int(time.rounded())
    }

    /// Update the access order for LRU eviction
    /// Assumes the caller is already in a barrier block
    private func updateAccessOrder(_ key: Int) {
        // Remove existing entry
        accessOrder.removeAll { $0 == key }
        // Add to end (most recently used)
        accessOrder.append(key)
    }
}
