//
//  CacheManager.swift
//  FlixorKit
//
//  Two-tier cache with memory + disk persistence and TTL support
//  Reference: packages/core/src/storage/ICache.ts
//

import Foundation
import CryptoKit

// MARK: - Cache Entry (Memory)

private struct CacheEntry {
    let data: Data
    let expiresAt: Date

    var isExpired: Bool {
        return Date() > expiresAt
    }
}

// MARK: - Disk Cache Entry

private struct DiskCacheEntry: Codable {
    let data: Data
    let expiresAt: Date

    var isExpired: Bool {
        return Date() > expiresAt
    }
}

// MARK: - CacheManager

public actor CacheManager: CacheProtocol {
    // MARK: - Properties

    /// In-memory cache for fast access
    private var memoryCache: [String: CacheEntry] = [:]

    /// Background cleanup task
    private var cleanupTask: Task<Void, Never>?

    /// Disk cache directory
    private let diskCacheURL: URL?

    /// File manager for disk operations
    private let fileManager = FileManager.default

    /// Maximum memory cache entries (to prevent memory bloat)
    private let maxMemoryEntries = 500

    // MARK: - Initialization

    public init(subdirectory: String = "FlixorCache") {
        // Set up disk cache directory
        if let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let url = cacheDir.appendingPathComponent(subdirectory, isDirectory: true)
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            self.diskCacheURL = url
        } else {
            self.diskCacheURL = nil
        }

        startCleanupTimer()
    }

    deinit {
        cleanupTask?.cancel()
    }

    // MARK: - CacheProtocol

    public func get<T: Decodable>(_ key: String) async -> T? {
        // 1. Check memory cache first (fastest)
        if let entry = memoryCache[key] {
            if !entry.isExpired {
                do {
                    let result = try JSONDecoder().decode(T.self, from: entry.data)
                    print("✅ [Cache] HIT (memory): \(key)")
                    return result
                } catch {
                    // Decoding failed, remove corrupted entry
                    memoryCache.removeValue(forKey: key)
                    print("⚠️ [Cache] Decode error (memory): \(key)")
                }
            } else {
                // Remove expired entry from memory
                memoryCache.removeValue(forKey: key)
                print("⏰ [Cache] EXPIRED (memory): \(key)")
            }
        }

        // 2. Check disk cache (slower but persistent)
        if let diskEntry = await getDiskEntry(key: key) {
            if !diskEntry.isExpired {
                // Restore to memory cache for faster future access
                memoryCache[key] = CacheEntry(data: diskEntry.data, expiresAt: diskEntry.expiresAt)
                trimMemoryCacheIfNeeded()

                do {
                    let result = try JSONDecoder().decode(T.self, from: diskEntry.data)
                    print("✅ [Cache] HIT (disk): \(key)")
                    return result
                } catch {
                    // Decoding failed, remove corrupted entry
                    await removeDiskEntry(key: key)
                    print("⚠️ [Cache] Decode error (disk): \(key)")
                }
            } else {
                // Remove expired entry from disk
                await removeDiskEntry(key: key)
                print("⏰ [Cache] EXPIRED (disk): \(key)")
            }
        }

        print("❌ [Cache] MISS: \(key)")
        return nil
    }

    public func set<T: Encodable>(_ key: String, value: T, ttl: TimeInterval) async {
        guard ttl > 0 else { return }

        do {
            let data = try JSONEncoder().encode(value)
            let expiresAt = Date().addingTimeInterval(ttl)

            // Save to memory cache
            memoryCache[key] = CacheEntry(data: data, expiresAt: expiresAt)
            trimMemoryCacheIfNeeded()

            // Save to disk cache asynchronously
            await setDiskEntry(key: key, data: data, expiresAt: expiresAt)

            print("💾 [Cache] SET: \(key) (TTL: \(Int(ttl))s, Size: \(data.count) bytes)")
        } catch {
            print("⚠️ [Cache] Failed to encode value for key: \(key) - \(error)")
        }
    }

    public func remove(_ key: String) async {
        memoryCache.removeValue(forKey: key)
        await removeDiskEntry(key: key)
    }

    public func clear() async {
        memoryCache.removeAll()
        await clearDiskCache()
    }

    public func invalidatePattern(_ pattern: String) async {
        // Convert glob pattern to regex-like matching
        // Supports * as wildcard
        let regexPattern = pattern
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "*", with: ".*")

        guard let regex = try? NSRegularExpression(pattern: "^\(regexPattern)$", options: []) else {
            return
        }

        // Invalidate memory cache
        let memoryKeysToRemove = memoryCache.keys.filter { key in
            let range = NSRange(key.startIndex..<key.endIndex, in: key)
            return regex.firstMatch(in: key, options: [], range: range) != nil
        }

        for key in memoryKeysToRemove {
            memoryCache.removeValue(forKey: key)
        }

        // Invalidate disk cache
        await invalidateDiskPattern(regex: regex)
    }

    // MARK: - Stats

    public var count: Int {
        memoryCache.count
    }

    public var keys: [String] {
        Array(memoryCache.keys)
    }

    /// Get disk cache size in bytes
    public func diskCacheSize() async -> Int {
        guard let diskCacheURL = diskCacheURL else { return 0 }

        do {
            let contents = try fileManager.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: [.fileSizeKey])
            var totalSize = 0
            for fileURL in contents {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                totalSize += resourceValues.fileSize ?? 0
            }
            return totalSize
        } catch {
            return 0
        }
    }

    // MARK: - Memory Cache Management

    private func trimMemoryCacheIfNeeded() {
        guard memoryCache.count > maxMemoryEntries else { return }

        // Remove oldest/expired entries first
        let sortedKeys = memoryCache
            .sorted { $0.value.expiresAt < $1.value.expiresAt }
            .prefix(memoryCache.count - maxMemoryEntries)
            .map { $0.key }

        for key in sortedKeys {
            memoryCache.removeValue(forKey: key)
        }
    }

    // MARK: - Disk Cache Operations

    private func hashKey(_ key: String) -> String {
        // Use SHA256 to create safe filenames
        let data = Data(key.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func diskFileURL(for key: String) -> URL? {
        guard let diskCacheURL = diskCacheURL else { return nil }
        return diskCacheURL.appendingPathComponent(hashKey(key) + ".cache")
    }

    private func getDiskEntry(key: String) async -> DiskCacheEntry? {
        guard let fileURL = diskFileURL(for: key) else { return nil }

        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(DiskCacheEntry.self, from: data)
        } catch {
            return nil
        }
    }

    private func setDiskEntry(key: String, data: Data, expiresAt: Date) async {
        guard let fileURL = diskFileURL(for: key) else { return }

        let entry = DiskCacheEntry(data: data, expiresAt: expiresAt)

        do {
            let encoded = try JSONEncoder().encode(entry)
            try encoded.write(to: fileURL, options: .atomic)
        } catch {
            // Silently fail on disk write errors
        }
    }

    private func removeDiskEntry(key: String) async {
        guard let fileURL = diskFileURL(for: key) else { return }
        try? fileManager.removeItem(at: fileURL)
    }

    private func clearDiskCache() async {
        guard let diskCacheURL = diskCacheURL else { return }

        do {
            let contents = try fileManager.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: nil)
            for fileURL in contents {
                try? fileManager.removeItem(at: fileURL)
            }
        } catch {
            // Silently fail
        }
    }

    private func invalidateDiskPattern(regex: NSRegularExpression) async {
        guard let diskCacheURL = diskCacheURL else { return }

        // We need to read each file to check the original key
        // This is expensive, so we store a key mapping file

        // For now, we'll skip disk pattern invalidation for performance
        // The entries will expire naturally via TTL
        // If pattern invalidation becomes critical, we can add a key index file
    }

    // MARK: - Cleanup

    private func startCleanupTimer() {
        cleanupTask = Task { [weak self] in
            while !Task.isCancelled {
                // Run cleanup every 5 minutes
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
                await self?.removeExpiredEntries()
            }
        }
    }

    private func removeExpiredEntries() async {
        // Clean memory cache
        memoryCache = memoryCache.filter { !$0.value.isExpired }

        // Clean disk cache
        await cleanExpiredDiskEntries()
    }

    private func cleanExpiredDiskEntries() async {
        guard let diskCacheURL = diskCacheURL else { return }

        do {
            let contents = try fileManager.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: nil)

            for fileURL in contents {
                guard fileURL.pathExtension == "cache" else { continue }

                do {
                    let data = try Data(contentsOf: fileURL)
                    let entry = try JSONDecoder().decode(DiskCacheEntry.self, from: data)

                    if entry.isExpired {
                        try? fileManager.removeItem(at: fileURL)
                    }
                } catch {
                    // Corrupted file, remove it
                    try? fileManager.removeItem(at: fileURL)
                }
            }
        } catch {
            // Silently fail
        }
    }
}

// MARK: - Global Cache Instance

public let sharedCache = CacheManager()
