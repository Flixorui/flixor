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
    /// The value as it was stored or last decoded, so a hit doesn't decode again.
    var value: Any?
    /// Encoded JSON, kept when the entry came from disk (or was re-encoded for a
    /// read with a different type).
    var data: Data?
    let expiresAt: Date

    var isExpired: Bool {
        return Date() > expiresAt
    }
}

// MARK: - Disk Format

/// Disk file layout: "FXC1\n<expiresAt seconds since 1970>\n<key>\n<JSON payload>".
/// The header lets the launch sweep read only the first bytes of each file.
private enum DiskFormat {
    static let magic = "FXC1"
    static let fileExtension = "fxc"
    static let headerReadLimit = 4096
    static let maxKeyBytes = 2048
    static let newline = UInt8(ascii: "\n")

    static func encode(key: String, expiresAt: Date, payload: Data) -> Data {
        var out = Data("\(magic)\n\(expiresAt.timeIntervalSince1970)\n\(key)\n".utf8)
        out.append(payload)
        return out
    }

    /// Parses the header. Returns the key, expiry and offset of the payload.
    static func parseHeader(_ data: Data) -> (key: String, expiresAt: Date, payloadOffset: Int)? {
        var lineStarts: [Int] = [data.startIndex]
        var index = data.startIndex
        while index < data.endIndex, lineStarts.count < 4 {
            if data[index] == newline {
                lineStarts.append(index + 1)
            }
            index += 1
        }
        guard lineStarts.count == 4 else { return nil }

        func line(_ n: Int) -> String? {
            String(data: data[lineStarts[n]..<(lineStarts[n + 1] - 1)], encoding: .utf8)
        }
        guard line(0) == magic,
              let seconds = line(1).flatMap(TimeInterval.init),
              let key = line(2) else { return nil }
        return (key, Date(timeIntervalSince1970: seconds), lineStarts[3])
    }
}

// MARK: - In-flight Requests

private struct InFlightRequest {
    let id: Int
    let epoch: Int
    let task: Task<Any, Error>
}

/// Resumes a continuation once, with whichever comes first: the result or a cancellation.
private final class InFlightWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Any, Error>?
    private var result: Result<Any, Error>?

    func install(_ continuation: CheckedContinuation<Any, Error>) {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(with: result)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func finish(_ result: Result<Any, Error>) {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

// MARK: - CacheManager

public actor CacheManager: CacheProtocol {
    // MARK: - Properties

    /// In-memory cache for fast access
    private var memoryCache: [String: CacheEntry] = [:]

    /// Keys with a live disk file, and their expiry. Filled by the launch sweep and
    /// kept current by writes and removals, so a miss never touches the disk.
    private var diskIndex: [String: Date] = [:]
    private var diskIndexLoaded = false

    /// Changes made before the launch sweep finished, applied when it does.
    private var removedBeforeIndexLoad: Set<String> = []
    private var patternsBeforeIndexLoad: [NSRegularExpression] = []
    private var clearedBeforeIndexLoad = false

    /// Bumped on every mutation, so a disk read that raced with one doesn't
    /// repopulate memory with a stale value.
    private var mutationEpoch = 0

    /// Bumped by remove, clear and invalidatePattern. A request started before the
    /// latest bump is neither joined nor allowed to write its result to the cache.
    private var invalidationEpoch = 0

    /// Requests currently running, keyed by request identity (see `deduplicated`).
    private var inFlight: [String: InFlightRequest] = [:]
    private var nextInFlightID = 0

    /// Background cleanup task
    private var cleanupTask: Task<Void, Never>?

    /// Disk cache directory
    private let diskCacheURL: URL?

    /// Serial queue for disk writes, removals and sweeps, so they apply in order.
    private let diskQueue = DispatchQueue(label: "com.flixor.cache.disk", qos: .utility)

    /// Maximum memory cache entries (to prevent memory bloat)
    private let maxMemoryEntries = 500

    /// Entries with a shorter TTL are kept in memory only.
    private let minDiskTTL: TimeInterval = 10 * 60

    // MARK: - Initialization

    public init(subdirectory: String = "FlixorCache") {
        let fileManager = FileManager.default
        if let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let url = cacheDir.appendingPathComponent(subdirectory, isDirectory: true)
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            self.diskCacheURL = url
        } else {
            self.diskCacheURL = nil
        }

        cleanupTask = Task { [weak self] in
            var sweeps = 0
            while !Task.isCancelled {
                // Memory every 5 minutes, disk index every hour
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
                sweeps += 1
                await self?.removeExpiredEntries(includeDisk: sweeps % 12 == 0)
            }
        }

        let directory = diskCacheURL
        diskQueue.async { [weak self] in
            let scanned = directory.map(CacheManager.scanDisk) ?? [:]
            Task { await self?.applyDiskScan(scanned) }
        }
    }

    deinit {
        cleanupTask?.cancel()
    }

    // MARK: - CacheProtocol

    public func get<T: Decodable>(_ key: String) async -> T? {
        // 1. Memory
        if let entry = memoryCache[key] {
            if entry.isExpired {
                memoryCache.removeValue(forKey: key)
            } else if let value = entry.value as? T {
                return value
            } else if let data = entry.data ?? encodedData(of: entry.value) {
                // Stored under a different type: decode the bytes.
                if let value = try? JSONDecoder().decode(T.self, from: data) {
                    return value
                }
                print("⚠️ [Cache] Decode error (memory): \(key)")
                return nil
            }
        }

        // 2. Disk
        guard let fileURL = diskFileURL(for: key), mayReadDisk(key) else { return nil }

        let epoch = mutationEpoch
        let read: (T, Data, Date)? = await Task.detached(priority: .userInitiated) {
            guard let fileData = try? Data(contentsOf: fileURL),
                  let header = DiskFormat.parseHeader(fileData),
                  header.key == key,
                  header.expiresAt > Date() else { return nil }
            let payload = fileData.subdata(in: header.payloadOffset..<fileData.endIndex)
            guard let value = try? JSONDecoder().decode(T.self, from: payload) else { return nil }
            return (value, payload, header.expiresAt)
        }.value

        guard let read else {
            if epoch == mutationEpoch, diskIndexLoaded, diskIndex[key] != nil {
                // Unreadable, expired or of another shape: drop it.
                diskIndex.removeValue(forKey: key)
                enqueueDiskRemoval(fileURL)
            }
            return nil
        }
        let (value, payload, expiresAt) = read

        if epoch == mutationEpoch {
            memoryCache[key] = CacheEntry(value: value, data: payload, expiresAt: expiresAt)
            trimMemoryCacheIfNeeded()
        } else if let entry = memoryCache[key], !entry.isExpired, let current = entry.value as? T {
            return current
        }
        return value
    }

    public func set<T: Encodable>(_ key: String, value: T, ttl: TimeInterval) async {
        guard ttl > 0 else { return }

        let expiresAt = Date().addingTimeInterval(ttl)
        mutationEpoch += 1
        memoryCache[key] = CacheEntry(value: value, data: nil, expiresAt: expiresAt)
        trimMemoryCacheIfNeeded()

        guard let fileURL = diskFileURL(for: key) else { return }

        guard ttl >= minDiskTTL,
              key.utf8.count <= DiskFormat.maxKeyBytes,
              !key.contains("\n") else {
            // Memory-only now: drop any older disk copy so it can't be served later.
            if diskIndex.removeValue(forKey: key) != nil || !diskIndexLoaded {
                if !diskIndexLoaded {
                    removedBeforeIndexLoad.insert(key)
                }
                enqueueDiskRemoval(fileURL)
            }
            return
        }

        // Disk write happens in the background; the caller doesn't wait for it.
        diskIndex[key] = expiresAt
        diskQueue.async {
            guard let payload = try? JSONEncoder().encode(value) else { return }
            let fileData = DiskFormat.encode(key: key, expiresAt: expiresAt, payload: payload)
            try? fileData.write(to: fileURL, options: .atomic)
        }
    }

    public func remove(_ key: String) async {
        mutationEpoch += 1
        invalidationEpoch += 1
        memoryCache.removeValue(forKey: key)
        diskIndex.removeValue(forKey: key)
        if !diskIndexLoaded {
            removedBeforeIndexLoad.insert(key)
        }
        if let fileURL = diskFileURL(for: key) {
            enqueueDiskRemoval(fileURL)
        }
    }

    public func clear() async {
        mutationEpoch += 1
        invalidationEpoch += 1
        memoryCache.removeAll()
        diskIndex.removeAll()
        if !diskIndexLoaded {
            clearedBeforeIndexLoad = true
        }
        guard let diskCacheURL = diskCacheURL else { return }
        diskQueue.async {
            let fileManager = FileManager.default
            let contents = (try? fileManager.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: nil)) ?? []
            for fileURL in contents {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }

    public func invalidatePattern(_ pattern: String) async {
        // Glob pattern: * is a wildcard, everything else is literal
        let regexPattern = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*")

        guard let regex = try? NSRegularExpression(pattern: "^\(regexPattern)$", options: []) else {
            return
        }

        mutationEpoch += 1
        invalidationEpoch += 1

        for key in memoryCache.keys where Self.matches(regex, key) {
            memoryCache.removeValue(forKey: key)
        }

        for key in diskIndex.keys where Self.matches(regex, key) {
            diskIndex.removeValue(forKey: key)
            if let fileURL = diskFileURL(for: key) {
                enqueueDiskRemoval(fileURL)
            }
        }

        if !diskIndexLoaded {
            patternsBeforeIndexLoad.append(regex)
        }
    }

    // MARK: - Request De-duplication

    /// Runs `operation` unless an identical request (same `key`) is already running,
    /// in which case the caller shares that request's result. `key` must identify the
    /// request and the result type. A request started before the latest remove, clear
    /// or invalidatePattern is not joined. `operation` receives the epoch it started
    /// in, to pass to `set(_:value:ttl:ifUnchangedSince:)`.
    /// A cancelled caller gets `CancellationError`; the shared request keeps running.
    func deduplicated<T>(_ key: String, operation: @escaping (_ epoch: Int) async throws -> T) async throws -> T {
        let task: Task<Any, Error>
        if let existing = inFlight[key], existing.epoch == invalidationEpoch {
            task = existing.task
        } else {
            let epoch = invalidationEpoch
            let id = nextInFlightID
            nextInFlightID += 1
            task = Task<Any, Error> {
                do {
                    let value = try await operation(epoch)
                    self.finishInFlight(key, id: id)
                    return value
                } catch {
                    self.finishInFlight(key, id: id)
                    throw error
                }
            }
            inFlight[key] = InFlightRequest(id: id, epoch: epoch, task: task)
        }

        guard let value = try await Self.wait(for: task) as? T else {
            throw CancellationError()
        }
        return value
    }

    /// Stores `value` only if nothing was removed or invalidated since `epoch`.
    func set<T: Encodable>(_ key: String, value: T, ttl: TimeInterval, ifUnchangedSince epoch: Int) async {
        guard epoch == invalidationEpoch else { return }
        await set(key, value: value, ttl: ttl)
    }

    private func finishInFlight(_ key: String, id: Int) {
        if inFlight[key]?.id == id {
            inFlight[key] = nil
        }
    }

    /// Waits for `task`, but throws `CancellationError` as soon as the caller is cancelled.
    private static func wait(for task: Task<Any, Error>) async throws -> Any {
        let waiter = InFlightWaiter()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Any, Error>) in
                waiter.install(continuation)
                Task.detached {
                    waiter.finish(await task.result)
                }
            }
        } onCancel: {
            waiter.finish(.failure(CancellationError()))
        }
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
            let contents = try FileManager.default.contentsOfDirectory(at: diskCacheURL, includingPropertiesForKeys: [.fileSizeKey])
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

        // Drop to 90% so the sort doesn't run on every insert
        let target = maxMemoryEntries * 9 / 10
        let sortedKeys = memoryCache
            .sorted { $0.value.expiresAt < $1.value.expiresAt }
            .prefix(memoryCache.count - target)
            .map { $0.key }

        for key in sortedKeys {
            memoryCache.removeValue(forKey: key)
        }
    }

    private func encodedData(of value: Any?) -> Data? {
        guard let encodable = value as? Encodable else { return nil }
        return try? JSONEncoder().encode(encodable)
    }

    private static func matches(_ regex: NSRegularExpression, _ key: String) -> Bool {
        let range = NSRange(key.startIndex..<key.endIndex, in: key)
        return regex.firstMatch(in: key, options: [], range: range) != nil
    }

    // MARK: - Disk Cache Operations

    private func hashKey(_ key: String) -> String {
        // Use SHA256 to create safe filenames
        let hash = SHA256.hash(data: Data(key.utf8))
        let digits = Array("0123456789abcdef".utf8)
        var hex = [UInt8]()
        hex.reserveCapacity(64)
        for byte in hash {
            hex.append(digits[Int(byte >> 4)])
            hex.append(digits[Int(byte & 0x0f)])
        }
        return String(decoding: hex, as: UTF8.self)
    }

    private func diskFileURL(for key: String) -> URL? {
        guard let diskCacheURL = diskCacheURL else { return nil }
        return diskCacheURL.appendingPathComponent(hashKey(key) + "." + DiskFormat.fileExtension)
    }

    /// Whether a disk read for `key` can return a live entry.
    private func mayReadDisk(_ key: String) -> Bool {
        if diskIndexLoaded {
            guard let expiresAt = diskIndex[key] else { return false }
            return expiresAt > Date()
        }
        if diskIndex[key] != nil { return true }
        if clearedBeforeIndexLoad || removedBeforeIndexLoad.contains(key) { return false }
        return !patternsBeforeIndexLoad.contains { Self.matches($0, key) }
    }

    private func enqueueDiskRemoval(_ fileURL: URL) {
        diskQueue.async {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    /// Reads the header of every cache file, deleting expired, malformed and
    /// old-format files. Runs on `diskQueue`.
    private static func scanDisk(_ directory: URL) -> [String: Date] {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return [:]
        }

        let now = Date()
        var index: [String: Date] = [:]
        for fileURL in contents {
            guard fileURL.pathExtension == DiskFormat.fileExtension,
                  let handle = try? FileHandle(forReadingFrom: fileURL) else {
                try? fileManager.removeItem(at: fileURL)
                continue
            }
            let head = handle.readData(ofLength: DiskFormat.headerReadLimit)
            try? handle.close()

            guard let header = DiskFormat.parseHeader(head), header.expiresAt > now else {
                try? fileManager.removeItem(at: fileURL)
                continue
            }
            index[header.key] = header.expiresAt
        }
        return index
    }

    private func applyDiskScan(_ scanned: [String: Date]) {
        defer {
            diskIndexLoaded = true
            removedBeforeIndexLoad.removeAll()
            patternsBeforeIndexLoad.removeAll()
            clearedBeforeIndexLoad = false
        }
        // A clear() queued after the scan has already deleted these files.
        guard !clearedBeforeIndexLoad else { return }

        for (key, expiresAt) in scanned {
            // Rewritten this session: the newer entry is already indexed.
            if diskIndex[key] != nil { continue }
            // Removed this session: the removal is queued behind the scan.
            if removedBeforeIndexLoad.contains(key) { continue }
            if patternsBeforeIndexLoad.contains(where: { Self.matches($0, key) }) {
                if let fileURL = diskFileURL(for: key) {
                    enqueueDiskRemoval(fileURL)
                }
                continue
            }
            diskIndex[key] = expiresAt
        }
    }

    // MARK: - Cleanup

    private func removeExpiredEntries(includeDisk: Bool) {
        let now = Date()
        memoryCache = memoryCache.filter { $0.value.expiresAt > now }

        guard includeDisk, diskIndexLoaded else { return }
        for (key, expiresAt) in diskIndex where expiresAt <= now {
            diskIndex.removeValue(forKey: key)
            if let fileURL = diskFileURL(for: key) {
                enqueueDiskRemoval(fileURL)
            }
        }
    }
}

// MARK: - Global Cache Instance

public let sharedCache = CacheManager()
