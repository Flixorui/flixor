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

    private func fileURL(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined().prefix(32)
        return directory.appendingPathComponent("\(digest).json")
    }

    func read(_ key: String) -> Entry? {
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attributes[.modificationDate] as? Date else { return nil }
        return Entry(data: data, fetchedAt: date)
    }

    func write(_ data: Data, for key: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: key), options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Bytes on disk, for Settings.
    var sizeOnDisk: Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
}
