//
//  DownloadButton.swift
//  FlixorMac
//
//  Reusable download button component for Details view
//

import SwiftUI
import FlixorKit

struct DownloadButton: View {
    let ratingKey: String
    let serverId: String
    let type: DownloadMediaType
    let title: String
    let year: Int?
    let thumb: String?
    let grandparentTitle: String?
    let grandparentRatingKey: String?
    let parentIndex: Int?
    let index: Int?

    @StateObject private var downloadManager = DownloadManager.shared
    @State private var isHovered = false

    private var globalKey: String {
        "\(serverId):\(ratingKey)"
    }

    private var downloadState: DownloadButtonState {
        if downloadManager.isDownloaded(globalKey) {
            return .downloaded
        }
        if let task = downloadManager.getProgress(globalKey) {
            switch task.status {
            case .downloading: return .downloading(task.progress)
            case .queued: return .queued
            case .paused: return .paused
            case .failed: return .failed
            case .completed: return .downloaded
            }
        }
        return .none
    }

    enum DownloadButtonState {
        case none
        case queued
        case downloading(Double)
        case paused
        case downloaded
        case failed
    }

    var body: some View {
        Button(action: handleTap) {
            HStack(spacing: 8) {
                iconView
                textView
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(backgroundColor)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    @ViewBuilder
    private var iconView: some View {
        switch downloadState {
        case .none:
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)

        case .queued:
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 16, height: 16)

        case .downloading(let progress):
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.white, lineWidth: 2)
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 16, height: 16)

        case .paused:
            Image(systemName: "pause.circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.orange)

        case .downloaded:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.green)

        case .failed:
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var textView: some View {
        switch downloadState {
        case .none:
            Text("Download")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)

        case .queued:
            Text("Queued")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))

        case .downloading(let progress):
            Text("\(Int(progress * 100))%")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)

        case .paused:
            Text("Paused")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.orange)

        case .downloaded:
            Text("Downloaded")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.green)

        case .failed:
            Text("Retry")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.red)
        }
    }

    private var backgroundColor: Color {
        switch downloadState {
        case .downloaded:
            return .green.opacity(isHovered ? 0.3 : 0.2)
        case .failed:
            return .red.opacity(isHovered ? 0.3 : 0.2)
        case .paused:
            return .orange.opacity(isHovered ? 0.3 : 0.2)
        default:
            return .white.opacity(isHovered ? 0.2 : 0.1)
        }
    }

    private func handleTap() {
        switch downloadState {
        case .none:
            // Start download
            downloadManager.queueDownload(
                ratingKey: ratingKey,
                serverId: serverId,
                type: type,
                title: title,
                year: year,
                thumb: thumb,
                grandparentTitle: grandparentTitle,
                grandparentRatingKey: grandparentRatingKey,
                parentIndex: parentIndex,
                index: index
            )

        case .downloading:
            // Pause download
            downloadManager.pauseDownload(globalKey)

        case .paused:
            // Resume download
            downloadManager.resumeDownload(globalKey)

        case .queued:
            // Cancel queued download
            downloadManager.cancelDownload(globalKey)

        case .downloaded:
            // Already downloaded - could show in Finder or offer delete
            showInFinder()

        case .failed:
            // Retry failed download
            downloadManager.retryDownload(globalKey)
        }
    }

    private func showInFinder() {
        guard let item = downloadManager.getDownloadedItem(globalKey) else { return }
        let fileService = DownloadFileService.shared
        let absoluteUrl = fileService.absolutePath(for: item.videoPath)
        NSWorkspace.shared.activateFileViewerSelecting([absoluteUrl])
    }
}

// MARK: - Convenience Initializers

extension DownloadButton {
    /// Initialize from a MediaItem (local model)
    init(mediaItem: MediaItem, serverId: String) {
        self.ratingKey = mediaItem.id  // MediaItem uses `id` for ratingKey
        self.serverId = serverId
        self.type = mediaItem.type == "movie" ? .movie : .episode
        self.title = mediaItem.title
        self.year = mediaItem.year
        self.thumb = mediaItem.thumb
        self.grandparentTitle = mediaItem.grandparentTitle
        self.grandparentRatingKey = mediaItem.grandparentRatingKey
        self.parentIndex = mediaItem.parentIndex
        self.index = mediaItem.index
    }
}

// MARK: - Compact Download Button (Icon Only)

struct CompactDownloadButton: View {
    let ratingKey: String
    let serverId: String
    let type: DownloadMediaType
    let title: String
    let year: Int?
    let thumb: String?
    let grandparentTitle: String?
    let grandparentRatingKey: String?
    let parentIndex: Int?
    let index: Int?

    @StateObject private var downloadManager = DownloadManager.shared
    @State private var isHovered = false

    private var globalKey: String {
        "\(serverId):\(ratingKey)"
    }

    private var isDownloaded: Bool {
        downloadManager.isDownloaded(globalKey)
    }

    private var isDownloading: Bool {
        downloadManager.isDownloading(globalKey)
    }

    private var progress: Double? {
        downloadManager.getProgress(globalKey)?.progress
    }

    var body: some View {
        Button(action: handleTap) {
            ZStack {
                if isDownloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if isDownloading {
                    if let progress = progress {
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.3), lineWidth: 2)
                            Circle()
                                .trim(from: 0, to: progress)
                                .stroke(Color.blue, lineWidth: 2)
                                .rotationEffect(.degrees(-90))
                        }
                        .frame(width: 20, height: 20)
                    } else {
                        ProgressView()
                            .scaleEffect(0.6)
                    }
                } else {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(isHovered ? .white : .white.opacity(0.7))
                }
            }
            .font(.system(size: 20))
            .frame(width: 32, height: 32)
            .background(isHovered && !isDownloaded ? Color.white.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(isDownloaded ? "Downloaded" : isDownloading ? "Downloading..." : "Download for offline")
    }

    private func handleTap() {
        if isDownloaded {
            // Show in Finder
            if let item = downloadManager.getDownloadedItem(globalKey) {
                let fileService = DownloadFileService.shared
                let absoluteUrl = fileService.absolutePath(for: item.videoPath)
                NSWorkspace.shared.activateFileViewerSelecting([absoluteUrl])
            }
        } else if isDownloading {
            // Toggle pause/resume
            if let task = downloadManager.getProgress(globalKey) {
                if task.status == .paused {
                    downloadManager.resumeDownload(globalKey)
                } else {
                    downloadManager.pauseDownload(globalKey)
                }
            }
        } else {
            // Start download
            downloadManager.queueDownload(
                ratingKey: ratingKey,
                serverId: serverId,
                type: type,
                title: title,
                year: year,
                thumb: thumb,
                grandparentTitle: grandparentTitle,
                grandparentRatingKey: grandparentRatingKey,
                parentIndex: parentIndex,
                index: index
            )
        }
    }
}

extension CompactDownloadButton {
    /// Initialize from a MediaItem (local model)
    init(mediaItem: MediaItem, serverId: String) {
        self.ratingKey = mediaItem.id
        self.serverId = serverId
        self.type = mediaItem.type == "movie" ? .movie : .episode
        self.title = mediaItem.title
        self.year = mediaItem.year
        self.thumb = mediaItem.thumb
        self.grandparentTitle = mediaItem.grandparentTitle
        self.grandparentRatingKey = mediaItem.grandparentRatingKey
        self.parentIndex = mediaItem.parentIndex
        self.index = mediaItem.index
    }
}

// MARK: - Details Download Button (Circle Style for Details Hero)

/// Circular download button matching the Apple TV+ style used in DetailsView
struct DetailsDownloadButton: View {
    let ratingKey: String
    let serverId: String
    let type: DownloadMediaType
    let title: String
    let year: Int?
    let thumb: String?
    let grandparentTitle: String?
    let grandparentRatingKey: String?
    let parentIndex: Int?
    let index: Int?

    @StateObject private var downloadManager = DownloadManager.shared
    @State private var isHovered = false

    private var globalKey: String {
        "\(serverId):\(ratingKey)"
    }

    private var isDownloaded: Bool {
        downloadManager.isDownloaded(globalKey)
    }

    private var isDownloading: Bool {
        downloadManager.isDownloading(globalKey)
    }

    private var progress: Double? {
        downloadManager.getProgress(globalKey)?.progress
    }

    private var downloadTask: DownloadTask? {
        downloadManager.getProgress(globalKey)
    }

    var body: some View {
        Button(action: handleTap) {
            ZStack {
                if isDownloaded {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.green)
                } else if isDownloading {
                    if let progress = progress {
                        // Progress ring
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.3), lineWidth: 2.5)
                            Circle()
                                .trim(from: 0, to: progress)
                                .stroke(Color.white, lineWidth: 2.5)
                                .rotationEffect(.degrees(-90))
                        }
                        .frame(width: 22, height: 22)
                    } else {
                        ProgressView()
                            .scaleEffect(0.6)
                    }
                } else if downloadTask?.status == .failed {
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.red)
                } else {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 44, height: 44)
            .background(
                Circle()
                    .fill(backgroundColor)
            )
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(helpText)
    }

    private var backgroundColor: Color {
        if isDownloaded {
            return Color.green.opacity(isHovered ? 0.4 : 0.3)
        } else if downloadTask?.status == .failed {
            return Color.red.opacity(isHovered ? 0.4 : 0.3)
        }
        return Color.white.opacity(isHovered ? 0.25 : 0.15)
    }

    private var helpText: String {
        if isDownloaded {
            return "Downloaded - Click to show in Finder"
        } else if let task = downloadTask {
            switch task.status {
            case .downloading: return "Downloading \(task.formattedProgress) - Click to pause"
            case .queued: return "Queued - Click to cancel"
            case .paused: return "Paused - Click to resume"
            case .failed: return "Failed - Click to retry"
            case .completed: return "Downloaded"
            }
        }
        return "Download for offline viewing"
    }

    private func handleTap() {
        if isDownloaded {
            // Show in Finder
            if let item = downloadManager.getDownloadedItem(globalKey) {
                let fileService = DownloadFileService.shared
                let absoluteUrl = fileService.absolutePath(for: item.videoPath)
                NSWorkspace.shared.activateFileViewerSelecting([absoluteUrl])
            }
        } else if let task = downloadTask {
            switch task.status {
            case .downloading:
                downloadManager.pauseDownload(globalKey)
            case .paused:
                downloadManager.resumeDownload(globalKey)
            case .queued:
                downloadManager.cancelDownload(globalKey)
            case .failed:
                downloadManager.retryDownload(globalKey)
            case .completed:
                break
            }
        } else {
            // Start download
            downloadManager.queueDownload(
                ratingKey: ratingKey,
                serverId: serverId,
                type: type,
                title: title,
                year: year,
                thumb: thumb,
                grandparentTitle: grandparentTitle,
                grandparentRatingKey: grandparentRatingKey,
                parentIndex: parentIndex,
                index: index
            )
        }
    }
}

// MARK: - Episode Download Button (Icon-only for Episode Cards)

/// Small icon-only download button designed for episode cards
struct EpisodeDownloadButton: View {
    let ratingKey: String
    let serverId: String
    let title: String
    let seasonNumber: Int
    let episodeNumber: Int
    let showTitle: String
    let showRatingKey: String?
    let thumb: String?

    @StateObject private var downloadManager = DownloadManager.shared
    @State private var isHovered = false

    /// Clean rating key without plex: prefix
    private var cleanRatingKey: String {
        ratingKey.hasPrefix("plex:") ? String(ratingKey.dropFirst(5)) : ratingKey
    }

    /// Clean show rating key without plex: prefix
    private var cleanShowRatingKey: String? {
        guard let key = showRatingKey else { return nil }
        return key.hasPrefix("plex:") ? String(key.dropFirst(5)) : key
    }

    private var globalKey: String {
        "\(serverId):\(cleanRatingKey)"
    }

    private var isDownloaded: Bool {
        downloadManager.isDownloaded(globalKey)
    }

    private var isDownloading: Bool {
        downloadManager.isDownloading(globalKey)
    }

    private var progress: Double? {
        downloadManager.getProgress(globalKey)?.progress
    }

    private var downloadTask: DownloadTask? {
        downloadManager.getProgress(globalKey)
    }

    var body: some View {
        Button(action: handleTap) {
            ZStack {
                if isDownloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.green)
                } else if isDownloading {
                    if let progress = progress {
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.3), lineWidth: 2)
                            Circle()
                                .trim(from: 0, to: progress)
                                .stroke(Color.white, lineWidth: 2)
                                .rotationEffect(.degrees(-90))
                        }
                        .frame(width: 18, height: 18)
                    } else {
                        ProgressView()
                            .scaleEffect(0.5)
                    }
                } else if downloadTask?.status == .failed {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.red)
                } else if downloadTask?.status == .paused {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.orange)
                } else {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isHovered ? .white : .white.opacity(0.8))
                }
            }
            .frame(width: 28, height: 28)
            .background(
                Circle()
                    .fill(Color.black.opacity(isHovered ? 0.7 : 0.5))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(helpText)
    }

    private var helpText: String {
        if isDownloaded {
            return "Downloaded - Click to show in Finder"
        } else if let task = downloadTask {
            switch task.status {
            case .downloading: return "Downloading \(task.formattedProgress)"
            case .queued: return "Queued"
            case .paused: return "Paused - Click to resume"
            case .failed: return "Failed - Click to retry"
            case .completed: return "Downloaded"
            }
        }
        return "Download for offline"
    }

    private func handleTap() {
        if isDownloaded {
            // Show in Finder
            if let item = downloadManager.getDownloadedItem(globalKey) {
                let fileService = DownloadFileService.shared
                let absoluteUrl = fileService.absolutePath(for: item.videoPath)
                NSWorkspace.shared.activateFileViewerSelecting([absoluteUrl])
            }
        } else if let task = downloadTask {
            switch task.status {
            case .downloading:
                downloadManager.pauseDownload(globalKey)
            case .paused:
                downloadManager.resumeDownload(globalKey)
            case .queued:
                downloadManager.cancelDownload(globalKey)
            case .failed:
                downloadManager.retryDownload(globalKey)
            case .completed:
                break
            }
        } else {
            // Start download - use clean rating keys without plex: prefix
            downloadManager.queueDownload(
                ratingKey: cleanRatingKey,
                serverId: serverId,
                type: .episode,
                title: title,
                year: nil,
                thumb: thumb,
                grandparentTitle: showTitle,
                grandparentRatingKey: cleanShowRatingKey,
                parentIndex: seasonNumber,
                index: episodeNumber
            )
        }
    }
}
