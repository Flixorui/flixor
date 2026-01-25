//
//  DownloadFileService.swift
//  FlixorMac
//
//  File system operations for downloads
//
//  Directory Structure:
//  ~/Documents/Flixor/
//  ├── Movies/
//  │   └── {Title} ({Year})/
//  │       ├── {Title}.{ext}
//  │       └── artwork.jpg
//  ├── TV Shows/
//  │   └── {Show}/
//  │       ├── artwork.jpg
//  │       └── Season {NN}/
//  │           └── S{NN}E{NN} - {Episode}.{ext}
//  └── artwork/
//      └── {hash}.jpg
//

import Foundation
import CryptoKit

class DownloadFileService {
    static let shared = DownloadFileService()

    private let fileManager = FileManager.default

    private init() {
        // Ensure base directories exist on init
        _ = try? ensureBaseDirectoriesExist()
    }

    // MARK: - Base Directory

    /// Base downloads directory (absolute path) - ~/Documents/Flixor/
    var downloadsDirectory: URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("Flixor")
    }

    /// Movies directory
    var moviesDirectory: URL {
        downloadsDirectory.appendingPathComponent("Movies")
    }

    /// TV Shows directory
    var tvShowsDirectory: URL {
        downloadsDirectory.appendingPathComponent("TV Shows")
    }

    /// Artwork cache directory
    var artworkDirectory: URL {
        downloadsDirectory.appendingPathComponent("artwork")
    }

    // MARK: - Path Conversion

    /// Convert relative path to absolute URL
    func absolutePath(for relativePath: String) -> URL {
        downloadsDirectory.appendingPathComponent(relativePath)
    }

    /// Convert absolute URL to relative path
    func relativePath(for absoluteUrl: URL) -> String? {
        let basePath = downloadsDirectory.path
        let fullPath = absoluteUrl.path
        guard fullPath.hasPrefix(basePath) else { return nil }
        var relative = String(fullPath.dropFirst(basePath.count))
        if relative.hasPrefix("/") {
            relative = String(relative.dropFirst())
        }
        return relative
    }

    // MARK: - Path Generation

    /// Compute movie path (returns RELATIVE path)
    func moviePath(title: String, year: Int?, ext: String) -> String {
        let sanitized = sanitizeFilename(title)
        let folder = year != nil ? "\(sanitized) (\(year!))" : sanitized
        return "Movies/\(folder)/\(sanitized).\(ext)"
    }

    /// Compute episode path (returns RELATIVE path)
    func episodePath(show: String, season: Int, episode: Int, title: String, ext: String) -> String {
        let showSanitized = sanitizeFilename(show)
        let episodeSanitized = sanitizeFilename(title)
        let seasonFolder = String(format: "Season %02d", season)
        let filename = String(format: "S%02dE%02d - %@.%@", season, episode, episodeSanitized, ext)
        return "TV Shows/\(showSanitized)/\(seasonFolder)/\(filename)"
    }

    /// Compute movie artwork path (returns RELATIVE path)
    func movieArtworkPath(title: String, year: Int?) -> String {
        let sanitized = sanitizeFilename(title)
        let folder = year != nil ? "\(sanitized) (\(year!))" : sanitized
        return "Movies/\(folder)/artwork.jpg"
    }

    /// Compute show artwork path (returns RELATIVE path)
    func showArtworkPath(show: String) -> String {
        let showSanitized = sanitizeFilename(show)
        return "TV Shows/\(showSanitized)/artwork.jpg"
    }

    /// Hash-based artwork path for deduplication (returns RELATIVE path)
    func artworkPath(for thumbUrl: String) -> String {
        let hash = sha256Hash(thumbUrl).prefix(16)
        return "artwork/\(hash).jpg"
    }

    // MARK: - Directory Operations

    /// Ensure base directories exist
    func ensureBaseDirectoriesExist() throws {
        try fileManager.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: moviesDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: tvShowsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)
    }

    /// Ensure directory exists for a relative path (creates all intermediate directories)
    func ensureDirectoryExists(for relativePath: String) throws {
        let fullPath = absolutePath(for: relativePath)
        let directory = fullPath.deletingLastPathComponent()
        // CRITICAL: Use withIntermediateDirectories: true to prevent failures
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - File Operations

    /// Check if file exists at relative path
    func fileExists(at relativePath: String) -> Bool {
        let fullPath = absolutePath(for: relativePath)
        return fileManager.fileExists(atPath: fullPath.path)
    }

    /// Get file size at relative path
    func fileSize(at relativePath: String) -> Int64? {
        let fullPath = absolutePath(for: relativePath)
        guard let attrs = try? fileManager.attributesOfItem(atPath: fullPath.path),
              let size = attrs[.size] as? Int64 else {
            return nil
        }
        return size
    }

    /// Delete file at relative path
    func deleteFile(at relativePath: String) throws {
        let fullPath = absolutePath(for: relativePath)
        if fileManager.fileExists(atPath: fullPath.path) {
            try fileManager.removeItem(at: fullPath)
        }
    }

    /// Move temporary file to final destination (relative path)
    func moveFile(from tempUrl: URL, to relativePath: String) throws {
        let destUrl = absolutePath(for: relativePath)

        // CRITICAL: Ensure the destination directory exists before moving
        let destDirectory = destUrl.deletingLastPathComponent()
        try fileManager.createDirectory(at: destDirectory, withIntermediateDirectories: true)

        // Remove existing file if present
        if fileManager.fileExists(atPath: destUrl.path) {
            try fileManager.removeItem(at: destUrl)
        }

        try fileManager.moveItem(at: tempUrl, to: destUrl)
    }

    // MARK: - Download Cleanup

    /// Delete a downloaded item and cleanup empty directories
    func deleteDownload(_ item: DownloadedItem) throws {
        // Delete video file
        let videoURL = absolutePath(for: item.videoPath)
        try? fileManager.removeItem(at: videoURL)

        // Cleanup empty parent directories
        cleanupEmptyDirectories(from: videoURL.deletingLastPathComponent())
    }

    /// Recursively cleanup empty directories up to the downloads root
    private func cleanupEmptyDirectories(from directory: URL) {
        var current = directory

        while current != downloadsDirectory && current.path != "/" {
            do {
                let contents = try fileManager.contentsOfDirectory(at: current, includingPropertiesForKeys: nil)
                if contents.isEmpty {
                    try fileManager.removeItem(at: current)
                    current = current.deletingLastPathComponent()
                } else {
                    break
                }
            } catch {
                break
            }
        }
    }

    // MARK: - Disk Space

    /// Get available disk space in bytes
    func availableSpace() -> Int64 {
        do {
            let values = try downloadsDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return values.volumeAvailableCapacityForImportantUsage ?? 0
        } catch {
            return 0
        }
    }

    /// Format bytes to human-readable string
    func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Helpers

    /// Sanitize filename by removing invalid characters
    private func sanitizeFilename(_ filename: String) -> String {
        // Characters not allowed in filenames
        let invalidChars = CharacterSet(charactersIn: "/\\:*?\"<>|")
        var sanitized = filename.components(separatedBy: invalidChars).joined(separator: "")

        // Remove leading/trailing whitespace and dots
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "."))

        // Replace multiple spaces with single space
        while sanitized.contains("  ") {
            sanitized = sanitized.replacingOccurrences(of: "  ", with: " ")
        }

        // Limit length
        if sanitized.count > 200 {
            sanitized = String(sanitized.prefix(200))
        }

        // Fallback if empty
        if sanitized.isEmpty {
            sanitized = "Untitled"
        }

        return sanitized
    }

    /// SHA256 hash of a string
    private func sha256Hash(_ string: String) -> String {
        let data = Data(string.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Extract file extension from URL
    func extractExtension(from urlString: String) -> String {
        guard let url = URL(string: urlString) else { return "mp4" }

        let pathExtension = url.pathExtension.lowercased()
        if !pathExtension.isEmpty && ["mp4", "mkv", "avi", "mov", "m4v", "webm"].contains(pathExtension) {
            return pathExtension
        }

        // Default to mp4
        return "mp4"
    }
}
