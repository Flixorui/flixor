//
//  DownloadsView.swift
//  FlixorMac
//
//  Downloads in the Library style: Movies and TV Shows as title tabs with
//  counts, storage used and Show in Finder on the right, in the frosted header
//  the content scrolls under. Movies are a poster grid; shows group their
//  episodes. Downloads in progress sit at the top.
//

import SwiftUI
import AppKit

struct DownloadsView: View {
    @StateObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var profileSettings = ProfileSettings.shared
    @ObservedObject private var librarySettings = LibraryScreenSettings.shared
    @Environment(\.windowMetrics) private var metrics
    @Environment(\.flixorTheme) private var theme
    @State private var selectedTab: DownloadTab = .movies
    @State private var contentWidth: CGFloat = 1200
    @EnvironmentObject private var router: NavigationRouter

    enum DownloadTab: String, CaseIterable {
        case movies = "Movies"
        case shows = "TV Shows"
    }

    private let horizontalPadding: CGFloat = 64
    private var gridSpacing: CGFloat { librarySettings.density.spacing }
    private var minGridItemWidth: CGFloat {
        let size = librarySettings.posterSize.resolved(homeSize: profileSettings.posterSize)
        return metrics.posterWidth(designWidth: 180, storedSize: size.rawValue)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.Space.s32) {
                if !downloadManager.activeTasks.isEmpty {
                    activeDownloadsSection
                }
                completedDownloadsSection
            }
            .background(TabScrollObserver(tab: .downloads))
            .padding(.horizontal, horizontalPadding)
            .padding(.top, DS.Space.s24)
            .padding(.bottom, DS.Space.s48)
            .background(widthReader)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .background(HomeBackground())
    }

    private var widthReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { contentWidth = proxy.size.width }
                .onChange(of: proxy.size.width) { contentWidth = $0 }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: DS.Space.s10) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s20) {
                tab(.movies, count: downloadManager.downloadedMovies.count)
                tab(.shows, count: downloadManager.downloadedShows.reduce(0) { $0 + $1.downloadedEpisodeCount })
            }
            Spacer(minLength: DS.Space.s16)
            if !downloadManager.downloadedItems.isEmpty {
                Text(storageSummary)
                    .flixorFont(.callout)
                    .foregroundStyle(theme.textTertiary)
                    .monospacedDigit()
            }
            BrowsePillButton(title: String(localized: "Show in Finder"), systemImage: "folder") {
                let folder = DownloadFileService.shared.downloadsDirectory
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                NSWorkspace.shared.activateFileViewerSelecting([folder])
            }
        }
        .frame(minHeight: 36)
        .browseHeaderInset()
    }

    private func tab(_ tab: DownloadTab, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s8) {
            LibraryTitleTab(title: tab.localizedRawValue, selected: selectedTab == tab) {
                withAnimation(DS.Motion.quick) { selectedTab = tab }
            }
            if selectedTab == tab {
                BrowseTabCount(text: "\(count)")
            }
        }
    }

    private var storageSummary: String {
        let totalSize = downloadManager.downloadedItems.reduce(0) { $0 + $1.fileSize }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        let count = downloadManager.downloadedItems.count
        return String(localized: "\(count) downloaded · \(formatter.string(fromByteCount: totalSize))")
    }

    // MARK: - Active Downloads

    private var activeDownloadsSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s12) {
            DownloadsSectionTitle(title: String(localized: "Downloading"), detail: "\(downloadManager.activeTasks.count)")
            DownloadsGroup {
                ForEach(Array(downloadManager.activeTasks.enumerated()), id: \.element.id) { index, task in
                    DownloadProgressRow(task: task)
                    if index < downloadManager.activeTasks.count - 1 { DownloadsDivider() }
                }
            }
        }
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
                subtitle: "Use the ⋯ menu on a movie's details page to download it."
            )
        } else {
            let available = max(320, contentWidth)
            let columnsCount = max(2, Int((available + gridSpacing) / (minGridItemWidth + gridSpacing)))
            let cardWidth = (available - CGFloat(columnsCount - 1) * gridSpacing) / CGFloat(columnsCount)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: columnsCount),
                      alignment: .leading, spacing: gridSpacing) {
                ForEach(downloadManager.downloadedMovies) { item in
                    DownloadedMovieCard(item: item, width: cardWidth,
                                        showTitle: librarySettings.titleDisplay != .none)
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
                subtitle: "Download episodes from a show's details page."
            )
        } else {
            VStack(alignment: .leading, spacing: DS.Space.s28) {
                ForEach(downloadManager.downloadedShows) { show in
                    DownloadedShowSection(show: show)
                }
            }
        }
    }
}

// MARK: - Shared pieces

private struct DownloadsSectionTitle: View {
    let title: String
    var detail: String? = nil
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s8) {
            Text(title).flixorFont(.title3, weight: .bold)
            if let detail { Text(detail).flixorFont(.callout).foregroundStyle(theme.textTertiary) }
        }
    }
}

/// A filled, rounded group of rows (the Settings group look).
private struct DownloadsGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: DS.Radius.r12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.r12, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }
}

private struct DownloadsDivider: View {
    var body: some View {
        Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.leading, DS.Space.s14)
    }
}

/// 30pt round icon button used on download rows.
private struct DownloadsIconButton: View {
    let systemImage: String
    let help: String
    var tint: Color? = nil
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.flixorIcon(DS.Icon.xs, weight: .bold))
                .foregroundStyle(tint ?? theme.textPrimary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.18 : 0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Artwork from the downloads folder (works offline).
private struct LocalArtwork: View {
    let relativePath: String?
    let placeholderIcon: String

    var body: some View {
        if let relativePath {
            AsyncImage(url: DownloadFileService.shared.absolutePath(for: relativePath)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                placeholder
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Color.white.opacity(0.06)
            Image(systemName: placeholderIcon).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Download Progress Row

struct DownloadProgressRow: View {
    let task: DownloadTask
    @StateObject private var downloadManager = DownloadManager.shared
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        HStack(spacing: DS.Space.s14) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.r8, style: .continuous).fill(Color.white.opacity(0.08))
                Image(systemName: task.type == .movie ? "film" : "tv").foregroundStyle(.secondary)
            }
            .frame(width: 64, height: 36)

            VStack(alignment: .leading, spacing: DS.Space.s6) {
                Text(task.displayTitle)
                    .flixorFont(.callout, weight: .semibold)
                    .lineLimit(1)
                HStack(spacing: DS.Space.s10) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.15))
                            Capsule().fill(task.status == .paused ? Color.white.opacity(0.5) : theme.accent)
                                .frame(width: proxy.size.width * max(0, min(task.progress, 1)))
                        }
                    }
                    .frame(width: 180, height: 4)
                    Text(statusText)
                        .flixorFont(.caption)
                        .foregroundStyle(task.status == .failed ? SettingsChrome.destructive : theme.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: DS.Space.s8)
            actions
        }
        .padding(.horizontal, DS.Space.s14)
        .padding(.vertical, DS.Space.s10)
    }

    private var statusText: String {
        switch task.status {
        case .queued: return String(localized: "Queued")
        case .paused: return String(localized: "Paused · \(task.formattedProgress)")
        case .failed: return task.errorMessage ?? String(localized: "Failed")
        case .completed: return String(localized: "Done")
        case .downloading:
            return task.formattedSize.isEmpty ? task.formattedProgress : "\(task.formattedProgress) · \(task.formattedSize)"
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: DS.Space.s8) {
            switch task.status {
            case .downloading:
                DownloadsIconButton(systemImage: "pause.fill", help: String(localized: "Pause")) { downloadManager.pauseDownload(task.id) }
            case .paused:
                DownloadsIconButton(systemImage: "play.fill", help: String(localized: "Resume")) { downloadManager.resumeDownload(task.id) }
            case .failed:
                DownloadsIconButton(systemImage: "arrow.clockwise", help: String(localized: "Retry")) { downloadManager.retryDownload(task.id) }
            case .queued, .completed:
                EmptyView()
            }
            if task.status != .completed {
                DownloadsIconButton(systemImage: "xmark", help: String(localized: "Cancel download")) { downloadManager.cancelDownload(task.id) }
            }
        }
    }
}

// MARK: - Movie card

/// Poster like the Library grid; hover shows Play and Delete. Click plays.
private struct DownloadedMovieCard: View {
    let item: DownloadedItem
    let width: CGFloat
    let showTitle: Bool

    @StateObject private var downloadManager = DownloadManager.shared
    @EnvironmentObject private var router: NavigationRouter
    @ObservedObject private var cardStyle = CardStyleStore.shared
    @State private var hovering = false
    @State private var showDeleteConfirmation = false

    private var height: CGFloat { width * 1.5 }
    private var radius: CGFloat { cardStyle.cornerStyle.posterRadius }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s8) {
            Button(action: play) {
                LocalArtwork(relativePath: item.artworkPath, placeholderIcon: "film")
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .overlay {
                        if hovering {
                            ZStack {
                                Color.black.opacity(0.35)
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 44))
                                    .foregroundStyle(.white)
                                    .shadow(radius: 8)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(Color.white.opacity(hovering ? 0.9 : 0.15), lineWidth: hovering ? 2 : 1)
                    )
                    .overlay(alignment: .topTrailing) {
                        if hovering {
                            DownloadsIconButton(systemImage: "trash", help: String(localized: "Delete download")) {
                                showDeleteConfirmation = true
                            }
                            .padding(DS.Space.s8)
                        }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Play") { play() }
                Button("Show in Finder") { revealInFinder() }
                Divider()
                Button("Delete Download", role: .destructive) { showDeleteConfirmation = true }
            }

            if showTitle {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    Text(item.title)
                        .flixorFont(.callout, weight: .medium)
                        .lineLimit(2)
                    Text([item.year.map(String.init), item.formattedFileSize].compactMap { $0 }.joined(separator: " · "))
                        .flixorFont(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(width: width, alignment: .leading)
            }
        }
        .onHover { hovering = $0 }
        .animation(DS.Motion.quick, value: hovering)
        .confirmationDialog("Delete Download?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { downloadManager.deleteDownload(item.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes \"\(item.title)\" from this Mac.")
        }
    }

    private func play() {
        router.downloadsPath.append(PlayerDestination.offline(offlineItem(for: item)))
    }

    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([DownloadFileService.shared.absolutePath(for: item.videoPath)])
    }
}

private func offlineItem(for item: DownloadedItem) -> OfflineMediaItem {
    OfflineMediaItem(
        ratingKey: item.ratingKey,
        title: item.title,
        type: item.type == .movie ? "movie" : "episode",
        year: item.year,
        grandparentTitle: item.grandparentTitle,
        grandparentRatingKey: item.grandparentRatingKey,
        parentIndex: item.parentIndex,
        index: item.index,
        filePath: DownloadFileService.shared.absolutePath(for: item.videoPath).path
    )
}

// MARK: - Show section

struct DownloadedShowSection: View {
    let show: DownloadedShow
    @State private var isExpanded = true
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s12) {
            Button(action: { withAnimation(DS.Motion.quick) { isExpanded.toggle() } }) {
                HStack(spacing: DS.Space.s14) {
                    LocalArtwork(relativePath: show.artworkPath, placeholderIcon: "tv")
                        .frame(width: 48, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r6, style: .continuous))
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        Text(show.title).flixorFont(.title3, weight: .bold)
                        Text("\(show.downloadedEpisodeCount) episodes · \(show.formattedTotalSize)")
                            .flixorFont(.callout)
                            .foregroundStyle(theme.textTertiary)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.flixorIcon(DS.Icon.xs, weight: .bold))
                        .foregroundStyle(theme.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(show.title), \(show.downloadedEpisodeCount) episodes"))
            .accessibilityHint(isExpanded ? "Collapse" : "Expand")

            if isExpanded {
                DownloadsGroup {
                    ForEach(Array(show.sortedEpisodes.enumerated()), id: \.element.id) { index, episode in
                        EpisodeRow(episode: episode)
                        if index < show.sortedEpisodes.count - 1 { DownloadsDivider() }
                    }
                }
            }
        }
    }
}

// MARK: - Episode Row

struct EpisodeRow: View {
    let episode: DownloadedItem
    @StateObject private var downloadManager = DownloadManager.shared
    @EnvironmentObject private var router: NavigationRouter
    @Environment(\.flixorTheme) private var theme
    @State private var showDeleteConfirmation = false
    @State private var isHovered = false

    var body: some View {
        Button(action: play) {
            HStack(spacing: DS.Space.s12) {
                Text(episode.episodeNumber ?? "")
                    .flixorFont(.caption, weight: .semibold)
                    .foregroundStyle(theme.textSecondary)
                    .monospacedDigit()
                    .frame(minWidth: 58, alignment: .leading)

                Text(episode.title)
                    .flixorFont(.callout)
                    .lineLimit(1)

                Spacer(minLength: DS.Space.s8)

                Text(episode.formattedFileSize)
                    .flixorFont(.caption)
                    .foregroundStyle(theme.textTertiary)
                    .monospacedDigit()

                HStack(spacing: DS.Space.s6) {
                    DownloadsIconButton(systemImage: "play.fill", help: String(localized: "Play")) { play() }
                    DownloadsIconButton(systemImage: "trash", help: String(localized: "Delete episode")) { showDeleteConfirmation = true }
                }
                .opacity(isHovered ? 1 : 0)
            }
            .padding(.horizontal, DS.Space.s14)
            .padding(.vertical, DS.Space.s8)
            .background(isHovered ? Color.white.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Play") { play() }
            Divider()
            Button("Delete Episode", role: .destructive) { showDeleteConfirmation = true }
        }
        .confirmationDialog("Delete Episode?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { downloadManager.deleteDownload(episode.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes this episode from this Mac.")
        }
    }

    private func play() {
        router.downloadsPath.append(PlayerDestination.offline(offlineItem(for: episode)))
    }
}

// MARK: - Empty State View

struct EmptyDownloadsView: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(spacing: DS.Space.s12) {
            Image(systemName: icon)
                .font(.flixorIcon(DS.Icon.huge))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.bold())
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.s80)
    }
}
