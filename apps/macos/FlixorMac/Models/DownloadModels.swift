//
//  DownloadModels.swift
//  FlixorMac
//
//  Data models for the Downloads feature
//

import Foundation

// MARK: - Download Status

enum DownloadStatus: String, Codable {
    case queued
    case downloading
    case paused
    case completed
    case failed
}

// MARK: - Media Type

enum DownloadMediaType: String, Codable {
    case movie
    case episode
}

// MARK: - Download Task (Active/In-Progress)

/// Represents an active download task (queued, downloading, paused, or failed)
struct DownloadTask: Identifiable, Codable {
    let id: String                    // Format: serverId:ratingKey
    let serverId: String
    let ratingKey: String
    let type: DownloadMediaType
    var status: DownloadStatus
    var progress: Double              // 0.0 - 1.0
    var downloadedBytes: Int64
    var totalBytes: Int64
    var errorMessage: String?

    // Metadata for display
    let title: String
    let year: Int?
    let thumb: String?                // Plex thumb path
    let grandparentTitle: String?     // Show title for episodes
    let grandparentRatingKey: String? // Show ratingKey for episodes
    let parentIndex: Int?             // Season number
    let index: Int?                   // Episode number

    var formattedProgress: String {
        let percent = Int(progress * 100)
        return "\(percent)%"
    }

    var formattedSize: String {
        guard totalBytes > 0 else { return "" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        let downloaded = formatter.string(fromByteCount: downloadedBytes)
        let total = formatter.string(fromByteCount: totalBytes)
        return "\(downloaded) / \(total)"
    }

    var displayTitle: String {
        if type == .episode, let show = grandparentTitle {
            let season = parentIndex ?? 1
            let episode = index ?? 1
            return "\(show) - S\(season)E\(episode)"
        }
        return title
    }
}

// MARK: - Downloaded Item (Completed)

/// Represents a completed download with local file paths
struct DownloadedItem: Identifiable, Codable {
    let id: String                    // Format: serverId:ratingKey
    let serverId: String
    let ratingKey: String
    let type: DownloadMediaType

    // Metadata
    let title: String
    let year: Int?
    let summary: String?
    let duration: Int?
    let grandparentTitle: String?     // Show title for episodes
    let grandparentRatingKey: String? // Show ratingKey for episodes
    let parentIndex: Int?             // Season number
    let index: Int?                   // Episode number

    // Local paths (RELATIVE to downloads directory - prevents double file:// issues)
    var videoPath: String             // Relative path to video file
    var artworkPath: String?          // Relative path to artwork

    let downloadedAt: Date
    var fileSize: Int64

    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    var displayTitle: String {
        if type == .episode, grandparentTitle != nil {
            let season = parentIndex ?? 1
            let episode = index ?? 1
            return "S\(season)E\(episode) - \(title)"
        }
        return title
    }

    var episodeNumber: String? {
        guard type == .episode else { return nil }
        let season = parentIndex ?? 1
        let episode = index ?? 1
        return "S\(season):E\(episode)"
    }
}

// MARK: - Downloaded Show (TV Show Grouping)

/// Groups downloaded episodes by TV show for display
struct DownloadedShow: Identifiable {
    var id: String { "\(serverId):\(grandparentRatingKey)" }
    let serverId: String
    let grandparentRatingKey: String
    let title: String
    let year: Int?
    var artworkPath: String?
    var episodes: [DownloadedItem]

    var downloadedEpisodeCount: Int { episodes.count }

    var totalSize: Int64 {
        episodes.reduce(0) { $0 + $1.fileSize }
    }

    var formattedTotalSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalSize)
    }

    /// Episodes sorted by season and episode number
    var sortedEpisodes: [DownloadedItem] {
        episodes.sorted {
            let key1 = ($0.parentIndex ?? 0, $0.index ?? 0)
            let key2 = ($1.parentIndex ?? 0, $1.index ?? 0)
            return key1 < key2
        }
    }
}

// MARK: - Download Error

// MARK: - Offline Media Item (for Navigation)

/// Used for navigating to the player with a downloaded/offline media file
struct OfflineMediaItem: Hashable {
    let ratingKey: String
    let title: String
    let type: String  // "movie" or "episode"
    let year: Int?
    let grandparentTitle: String?
    let grandparentRatingKey: String?
    let parentIndex: Int?
    let index: Int?
    let filePath: String  // Absolute file path to the video

    var displayTitle: String {
        if type == "episode", let show = grandparentTitle {
            let season = parentIndex ?? 1
            let episode = index ?? 1
            return "\(show) S\(season):E\(episode) - \(title)"
        }
        return title
    }
}

// MARK: - Download Error

enum DownloadError: LocalizedError {
    case noServer
    case invalidUrl
    case downloadFailed(String)
    case insufficientSpace
    case fileSystemError(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noServer:
            return "No Plex server connected"
        case .invalidUrl:
            return "Invalid download URL"
        case .downloadFailed(let msg):
            return "Download failed: \(msg)"
        case .insufficientSpace:
            return "Not enough disk space"
        case .fileSystemError(let msg):
            return "File system error: \(msg)"
        case .cancelled:
            return "Download was cancelled"
        }
    }
}
