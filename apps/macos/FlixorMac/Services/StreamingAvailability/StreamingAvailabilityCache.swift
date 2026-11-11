//
//  StreamingAvailabilityCache.swift
//  FlixorMac
//
//  Responses saved on disk with their fetch time, so lists show from the Mac
//  and the API is only asked again once an entry is due.
//

import Foundation
import CryptoKit

struct StreamingAvailabilityCache {
    struct Entry {
        let data: Data
        let fetchedAt: Date
    }

    static let shared = StreamingAvailabilityCache()

    let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Flixor/StreamingAvailability", isDirectory: true)
    }()

    /// Entries already read or written, so repeated reads skip the disk.
    /// This type is the only writer of the directory, so the copies stay current.
    private final class Memory: @unchecked Sendable {
        let lock = NSLock()
        var entries: [String: Entry] = [:]
        var generation = 0
    }
    private let memory = Memory()
    private static let memoryLimit = 64

    /// Changes on every write and clear (lets callers memoise work built from entries).
    var generation: Int {
        memory.lock.lock(); defer { memory.lock.unlock() }
        return memory.generation
    }

    private func remember(_ entry: Entry, for key: String) {
        memory.lock.lock(); defer { memory.lock.unlock() }
        if memory.entries[key] == nil, memory.entries.count >= Self.memoryLimit {
            memory.entries.removeAll()
        }
        memory.entries[key] = entry
    }

    private func fileURL(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined().prefix(32)
        return directory.appendingPathComponent("\(digest).json")
    }

    func read(_ key: String) -> Entry? {
        memory.lock.lock()
        let remembered = memory.entries[key]
        memory.lock.unlock()
        if let remembered { return remembered }
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attributes[.modificationDate] as? Date else { return nil }
        let entry = Entry(data: data, fetchedAt: date)
        remember(entry, for: key)
        return entry
    }

    func write(_ data: Data, for key: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = fileURL(for: key)
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }
        memory.lock.lock()
        memory.generation += 1
        memory.lock.unlock()
        remember(Entry(data: data, fetchedAt: Date()), for: key)
    }

    func clear() {
        try? FileManager.default.removeItem(at: directory)
        memory.lock.lock(); defer { memory.lock.unlock() }
        memory.entries.removeAll()
        memory.generation += 1
    }

    /// Bytes on disk, for Settings.
    var sizeOnDisk: Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
}
