//
//  DownloadsView.swift
//  FlixorMac
//
//  Main downloads screen with Movies and TV Shows tabs
//

import SwiftUI

struct DownloadsView: View {
    @StateObject private var downloadManager = DownloadManager.shared
    @State private var selectedTab: DownloadTab = .movies
    @EnvironmentObject private var router: NavigationRouter

    enum DownloadTab: String, CaseIterable {
        case movies = "Movies"
        case shows = "TV Shows"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            // Tab picker
            tabPicker

            // Content
            ScrollView {
                LazyVStack(spacing: 16) {
                    // Active downloads section
                    if !downloadManager.activeTasks.isEmpty {
                        activeDownloadsSection
                    }

                    // Completed downloads
                    completedDownloadsSection
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .background(Color.black)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Text("Downloads")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
            Spacer()

            // Storage info
            if downloadManager.downloadedItems.count > 0 {
                storageInfo
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    private var storageInfo: some View {
        let totalSize = downloadManager.downloadedItems.reduce(0) { $0 + $1.fileSize }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file

        return Text("\(downloadManager.downloadedItems.count) items • \(formatter.string(fromByteCount: totalSize))")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        Picker("", selection: $selectedTab) {
            ForEach(DownloadTab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Active Downloads

    private var activeDownloadsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Downloading")
                .font(.headline)
                .foregroundStyle(.secondary)

            ForEach(downloadManager.activeTasks) { task in
                DownloadProgressRow(task: task)
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Completed Downloads

    @ViewBuilder
    private var completedDownloadsSection: some View {
        switch selectedTab {
        case .movies:
            moviesSection
        case .shows:
            showsSection
        }
    }

    @ViewBuilder
    private var moviesSection: some View {
        if downloadManager.downloadedMovies.isEmpty {
            EmptyDownloadsView(
                icon: "film",
                title: "No Movies Downloaded",
                subtitle: "Download movies to watch offline"
            )
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(downloadManager.downloadedMovies) { item in
                    DownloadedItemRow(item: item)
                }
            }
        }
    }

    @ViewBuilder
    private var showsSection: some View {
        if downloadManager.downloadedShows.isEmpty {
            EmptyDownloadsView(
                icon: "tv",
                title: "No TV Shows Downloaded",
                subtitle: "Download episodes to watch offline"
            )
        } else {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(downloadManager.downloadedShows) { show in
                    DownloadedShowSection(show: show)
                }
            }
        }
    }
}

// MARK: - Download Progress Row

struct DownloadProgressRow: View {
    let task: DownloadTask
    @StateObject private var downloadManager = DownloadManager.shared

    var body: some View {
        HStack(spacing: 16) {
            // Thumbnail placeholder
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.1))
                .frame(width: 80, height: 45)
                .overlay(
                    Image(systemName: task.type == .movie ? "film" : "tv")
                        .foregroundStyle(.secondary)
                )

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(task.displayTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    // Progress bar
                    ProgressView(value: task.progress)
                        .progressViewStyle(.linear)
                        .frame(width: 120)

                    Text(task.formattedProgress)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !task.formattedSize.isEmpty {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(task.formattedSize)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Status/Actions
            statusButtons
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }

    @ViewBuilder
    private var statusButtons: some View {
        switch task.status {
        case .queued:
            HStack(spacing: 8) {
                Text("Queued")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(action: { downloadManager.cancelDownload(task.id) }) {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

        case .downloading:
            HStack(spacing: 8) {
                Button(action: { downloadManager.pauseDownload(task.id) }) {
                    Image(systemName: "pause.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)

                Button(action: { downloadManager.cancelDownload(task.id) }) {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

        case .paused:
            HStack(spacing: 8) {
                Button(action: { downloadManager.resumeDownload(task.id) }) {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)

                Button(action: { downloadManager.cancelDownload(task.id) }) {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

        case .failed:
            HStack(spacing: 8) {
                Text(task.errorMessage ?? "Failed")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)

                Button(action: { downloadManager.retryDownload(task.id) }) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)

                Button(action: { downloadManager.cancelDownload(task.id) }) {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
}

// MARK: - Downloaded Item Row

struct DownloadedItemRow: View {
    let item: DownloadedItem
    @StateObject private var downloadManager = DownloadManager.shared
    @EnvironmentObject private var router: NavigationRouter
    @State private var showDeleteConfirmation = false
    @State private var isHovered = false

    private let fileService = DownloadFileService.shared

    var body: some View {
        Button(action: playItem) {
            HStack(spacing: 16) {
                // Artwork
                artworkView

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        if let year = item.year {
                            Text(String(year))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Text("•")
                            .foregroundStyle(.secondary)

                        Text(item.formattedFileSize)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Actions
                HStack(spacing: 12) {
                    // Play button
                    Image(systemName: "play.circle.fill")
                        .font(.title)
                        .foregroundStyle(.white)

                    // Delete button
                    Button(action: { showDeleteConfirmation = true }) {
                        Image(systemName: "trash")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(isHovered ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .confirmationDialog(
            "Delete Download?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                downloadManager.deleteDownload(item.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove \"\(item.title)\" from your downloads.")
        }
    }

    @ViewBuilder
    private var artworkView: some View {
        if let artworkPath = item.artworkPath {
            let absoluteUrl = fileService.absolutePath(for: artworkPath)
            AsyncImage(url: absoluteUrl) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                artworkPlaceholder
            }
            .frame(width: 80, height: 45)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            artworkPlaceholder
        }
    }

    private var artworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.white.opacity(0.1))
            .frame(width: 80, height: 45)
            .overlay(
                Image(systemName: item.type == .movie ? "film" : "tv")
                    .foregroundStyle(.secondary)
            )
    }

    private func playItem() {
        // Create an OfflineMediaItem for navigation to PlayerView
        let absolutePath = fileService.absolutePath(for: item.videoPath)

        let offlineItem = OfflineMediaItem(
            ratingKey: item.ratingKey,
            title: item.title,
            type: item.type == .movie ? "movie" : "episode",
            year: item.year,
            grandparentTitle: item.grandparentTitle,
            grandparentRatingKey: item.grandparentRatingKey,
            parentIndex: item.parentIndex,
            index: item.index,
            filePath: absolutePath.path
        )

        // Use downloadsPath since we're on the Downloads tab
        router.downloadsPath.append(offlineItem)
    }
}

// MARK: - Downloaded Show Section

struct DownloadedShowSection: View {
    let show: DownloadedShow
    @State private var isExpanded = true
    @StateObject private var downloadManager = DownloadManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Show header
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack(spacing: 12) {
                    // Show artwork
                    showArtwork

                    // Show info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(show.title)
                            .font(.headline)
                            .foregroundStyle(.white)

                        Text("\(show.downloadedEpisodeCount) episode\(show.downloadedEpisodeCount == 1 ? "" : "s") • \(show.formattedTotalSize)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Expand/collapse indicator
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            // Episodes
            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(show.sortedEpisodes) { episode in
                        EpisodeRow(episode: episode)
                    }
                }
                .padding(.leading, 16)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }

    @ViewBuilder
    private var showArtwork: some View {
        let fileService = DownloadFileService.shared

        if let artworkPath = show.artworkPath {
            let absoluteUrl = fileService.absolutePath(for: artworkPath)
            AsyncImage(url: absoluteUrl) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                showArtworkPlaceholder
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            showArtworkPlaceholder
        }
    }

    private var showArtworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.white.opacity(0.1))
            .frame(width: 60, height: 60)
            .overlay(
                Image(systemName: "tv")
                    .foregroundStyle(.secondary)
            )
    }
}

// MARK: - Episode Row

struct EpisodeRow: View {
    let episode: DownloadedItem
    @StateObject private var downloadManager = DownloadManager.shared
    @EnvironmentObject private var router: NavigationRouter
    @State private var showDeleteConfirmation = false
    @State private var isHovered = false

    private let fileService = DownloadFileService.shared

    var body: some View {
        Button(action: playEpisode) {
            HStack(spacing: 12) {
                // Episode number badge
                Text(episode.episodeNumber ?? "")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.3))
                    .cornerRadius(4)

                // Episode title
                Text(episode.title)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                // Size
                Text(episode.formattedFileSize)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Play indicator
                Image(systemName: "play.fill")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))

                // Delete button
                Button(action: { showDeleteConfirmation = true }) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(isHovered ? Color.white.opacity(0.08) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .confirmationDialog(
            "Delete Episode?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                downloadManager.deleteDownload(episode.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove this episode from your downloads.")
        }
    }

    private func playEpisode() {
        let absolutePath = fileService.absolutePath(for: episode.videoPath)

        let offlineItem = OfflineMediaItem(
            ratingKey: episode.ratingKey,
            title: episode.title,
            type: "episode",
            year: episode.year,
            grandparentTitle: episode.grandparentTitle,
            grandparentRatingKey: episode.grandparentRatingKey,
            parentIndex: episode.parentIndex,
            index: episode.index,
            filePath: absolutePath.path
        )

        // Use downloadsPath since we're on the Downloads tab
        router.downloadsPath.append(offlineItem)
    }
}

// MARK: - Empty State View

struct EmptyDownloadsView: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.title3.bold())
                .foregroundStyle(.white)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}
