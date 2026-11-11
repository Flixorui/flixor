//
//  DetailsEpisodesSection.swift
//  FlixorMac
//
//  Episodes tab: season selector, episode cards and rows
//

import SwiftUI
import FlixorKit

struct EpisodesTabContent: View {
    @ObservedObject var vm: DetailsViewModel
    let layout: DetailsLayoutMetrics
    @ObservedObject var episodeState: DetailsEpisodeStateModel
    let onPlayEpisode: (DetailsViewModel.Episode) -> Void
    let onStremioEpisode: (DetailsViewModel.Episode) -> Void

    @ObservedObject private var profileSettings = ProfileSettings.shared
    @ObservedObject private var sectionsStore = DetailsSectionsStore.shared
    @ObservedObject private var watchState = WatchStateService.shared
    @State private var preferStremioEpisodeTap = false

    private let cardWidth: CGFloat = 340
    private var cardHeight: CGFloat { 180 }
    private var stremioEnabled: Bool { profileSettings.stremioPlaybackEnabled }

    private var currentSeasonUsesTMDBSource: Bool {
        vm.selectedSeasonKey?.hasPrefix("tmdb:season:") == true
    }

    private func episodeRowHasPlexSource(_ episode: DetailsViewModel.Episode) -> Bool {
        episode.id.hasPrefix("plex:")
    }

    private var episodeListHasPlexSource: Bool {
        if !vm.episodes.isEmpty {
            return vm.episodes.contains { episodeRowHasPlexSource($0) }
        }
        return !currentSeasonUsesTMDBSource && (vm.plexRatingKey != nil || (vm.playableId?.hasPrefix("plex:") == true))
    }

    private func rowTapDisabled(for episode: DetailsViewModel.Episode) -> Bool {
        !episodeRowHasPlexSource(episode) && !stremioEnabled
    }

    private func showsExplicitStremioButton(for episode: DetailsViewModel.Episode) -> Bool {
        episodeRowHasPlexSource(episode) && stremioEnabled && !preferStremioEpisodeTap
    }

    private func showsStremioActiveBadge(for episode: DetailsViewModel.Episode) -> Bool {
        let episodeHasPlexSource = episodeRowHasPlexSource(episode)
        if !episodeHasPlexSource && stremioEnabled {
            return true
        }
        return episodeHasPlexSource && stremioEnabled && preferStremioEpisodeTap
    }

    // Computed show info for downloads
    private var showTitle: String {
        // If viewing a show, use vm.title; if viewing a season/episode, use vm.showTitle
        vm.showTitle ?? vm.title
    }

    private var showRatingKey: String? {
        // If viewing a show, use vm.plexRatingKey; if viewing a season, use parentShowKey
        vm.showRatingKey ?? vm.parentShowKey ?? vm.plexRatingKey
    }

    private var serverId: String? {
        FlixorCore.shared.server?.id
    }

    private var episodeTapModeTitle: String {
        preferStremioEpisodeTap ? String(localized: "Stremio sources") : String(localized: "Plex playback")
    }

    private func handleEpisodeSelection(_ episode: DetailsViewModel.Episode) {
        let episodeHasPlexSource = episodeRowHasPlexSource(episode)

        if !episodeHasPlexSource && !stremioEnabled {
            return
        }

        if !episodeHasPlexSource && stremioEnabled {
            onStremioEpisode(episode)
            return
        }

        if stremioEnabled && preferStremioEpisodeTap {
            onStremioEpisode(episode)
        } else {
            onPlayEpisode(episode)
        }
    }

    // MARK: - Episode extras (ratings, watched state, spoilers)

    private func rating(for episode: DetailsViewModel.Episode) -> Double? {
        sectionsStore.showEpisodeRatings ? episodeState.rating(for: episode) : nil
    }

    private func hidesSpoilers(for episode: DetailsViewModel.Episode) -> Bool {
        sectionsStore.hideEpisodeSpoilers && !episodeState.isWatched(episode) && !episodeState.isRevealed(episode)
    }

    /// Builds the episode's target only while some watch action is running.
    private func isWatchActionInFlight(_ episode: DetailsViewModel.Episode) -> Bool {
        let inFlight = watchState.inFlight
        return !inFlight.isEmpty && inFlight.contains(vm.watchTarget(for: episode).actionKey)
    }

    private func toggleWatched(_ episode: DetailsViewModel.Episode) {
        let watched = episodeState.isWatched(episode)
        Task { await episodeState.setWatched(episode, watched: !watched, vm: vm) }
    }

    @ViewBuilder
    private func episodeMenu(for episode: DetailsViewModel.Episode) -> some View {
        let watched = episodeState.isWatched(episode)
        let busy = isWatchActionInFlight(episode)
        Button {
            Task { await episodeState.setWatched(episode, watched: !watched, vm: vm) }
        } label: {
            Label(watched ? "Mark as Unwatched" : "Mark as Watched", systemImage: watched ? "eye.slash" : "checkmark.circle")
        }
        .disabled(busy)

        if episodeState.seasonTarget(vm: vm) != nil {
            Divider()
            Button {
                Task { await episodeState.setSeasonWatched(true, vm: vm) }
            } label: {
                Label("Mark Season as Watched", systemImage: "checkmark.circle.fill")
            }
            .disabled(episodeState.seasonActionInFlight)
            Button {
                Task { await episodeState.setSeasonWatched(false, vm: vm) }
            } label: {
                Label("Mark Season as Unwatched", systemImage: "circle")
            }
            .disabled(episodeState.seasonActionInFlight)
        }

        if sectionsStore.hideEpisodeSpoilers && !watched {
            Divider()
            Button {
                episodeState.toggleRevealed(episode)
            } label: {
                Label(episodeState.isRevealed(episode) ? "Hide Spoilers" : "Reveal Spoilers",
                      systemImage: episodeState.isRevealed(episode) ? "eye.slash" : "eye")
            }
        }
    }

    private var contextTaskKey: String {
        [vm.tmdbId ?? "-", vm.plexRatingKey ?? "-", vm.selectedSeasonKey ?? "-",
         vm.currentSeasonNumber.map(String.init) ?? "-", vm.isSeason ? "season" : "show",
         "\(vm.episodes.count)"].joined(separator: "|")
    }

    private var seasonArtTaskKey: String {
        sectionsStore.seasonPickerStyle == .posters ? vm.seasons.map(\.id).joined(separator: ",") : ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DetailsSectionStyle.headingGap) {
            HStack(alignment: .center, spacing: DS.Space.s12) {
                DetailsSectionHeading("Episodes")

                Spacer(minLength: 12)

                if episodeListHasPlexSource && stremioEnabled {
                    Menu {
                        Button {
                            preferStremioEpisodeTap = false
                        } label: {
                            if !preferStremioEpisodeTap {
                                Label("Plex playback", systemImage: "checkmark")
                            } else {
                                Text("Plex playback")
                            }
                        }

                        Button {
                            preferStremioEpisodeTap = true
                        } label: {
                            if preferStremioEpisodeTap {
                                Label("Stremio sources", systemImage: "checkmark")
                            } else {
                                Text("Stremio sources")
                            }
                        }
                    } label: {
                        HStack(spacing: DS.Space.s8) {
                            Image(systemName: "puzzlepiece.extension.fill")
                                .font(.flixorIcon(DS.Icon.xs, weight: .semibold))
                                .foregroundStyle(Color.orange.opacity(0.95))
                            Text(episodeTapModeTitle)
                                .font(.flixor(.footnote, weight: .semibold))
                                .foregroundStyle(.white)
                            Image(systemName: "chevron.down")
                                .font(.flixor(.caption, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .padding(.horizontal, DS.Space.s12)
                        .padding(.vertical, DS.Space.s8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.08))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                )
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }

            // Season selector (hide in season-only mode)
            if !vm.isSeason && vm.seasons.count > 1 {
                if sectionsStore.seasonPickerStyle == .posters {
                    SeasonPosterPicker(
                        seasons: vm.seasons,
                        selectedKey: vm.selectedSeasonKey ?? "",
                        art: episodeState.seasonArt,
                        fallbackPoster: vm.posterURL,
                        onSelect: { key in
                            Task { await vm.selectSeason(key) }
                        }
                    )
                } else {
                    SeasonSelector(
                        seasons: vm.seasons,
                        selectedKey: vm.selectedSeasonKey ?? "",
                        onSelect: { key in
                            Task { await vm.selectSeason(key) }
                        }
                    )
                }
            } else if let season = vm.seasons.first(where: { $0.id == vm.selectedSeasonKey }) {
                Text(season.title)
                    .font(.flixor(.title3, weight: .semibold))
                    .foregroundStyle(.white)
            }

            if vm.episodesLoading {
                HStack {
                    Spacer()
                    ProgressView().progressViewStyle(.circular)
                    Spacer()
                }
                .padding(.vertical, DS.Space.s40)
            } else if vm.episodes.isEmpty {
                Text("No episodes found").foregroundStyle(.secondary)
            } else if profileSettings.episodeLayout == "horizontal" {
                // Horizontal scroll of episode cards (like mobile)
                DetailsHorizontalRow {
                    LazyHStack(spacing: DS.Space.s14) {
                        ForEach(Array(vm.episodes.enumerated()), id: \.element.id) { index, episode in
                            HorizontalEpisodeCard(
                                episode: episode,
                                episodeNumber: index + 1,
                                width: cardWidth,
                                height: cardHeight,
                                isDisabled: rowTapDisabled(for: episode),
                                showsStremioButton: showsExplicitStremioButton(for: episode),
                                showsStremioActiveBadge: showsStremioActiveBadge(for: episode),
                                showTitle: showTitle,
                                showRatingKey: showRatingKey,
                                serverId: episodeRowHasPlexSource(episode) ? serverId : nil,
                                isWatched: episodeState.isWatched(episode),
                                rating: rating(for: episode),
                                hidesSpoilers: hidesSpoilers(for: episode),
                                isWatchActionDisabled: isWatchActionInFlight(episode),
                                onPlay: { handleEpisodeSelection(episode) },
                                onStremio: { onStremioEpisode(episode) },
                                onToggleWatched: { toggleWatched(episode) }
                            )
                            .contextMenu { episodeMenu(for: episode) }
                        }
                    }
                }
            } else {
                // Vertical list layout (original)
                LazyVStack(spacing: DS.Space.s12) {
                    ForEach(Array(vm.episodes.enumerated()), id: \.element.id) { index, episode in
                        VerticalEpisodeRow(
                            episode: episode,
                            episodeNumber: index + 1,
                            layout: layout,
                            isDisabled: rowTapDisabled(for: episode),
                            showsStremioButton: showsExplicitStremioButton(for: episode),
                            showsStremioActiveBadge: showsStremioActiveBadge(for: episode),
                            showTitle: showTitle,
                            showRatingKey: showRatingKey,
                            serverId: episodeRowHasPlexSource(episode) ? serverId : nil,
                            isWatched: episodeState.isWatched(episode),
                            rating: rating(for: episode),
                            hidesSpoilers: hidesSpoilers(for: episode),
                            isWatchActionDisabled: isWatchActionInFlight(episode),
                            onPlay: { handleEpisodeSelection(episode) },
                            onStremio: { onStremioEpisode(episode) },
                            onToggleWatched: { toggleWatched(episode) }
                        )
                        .contextMenu { episodeMenu(for: episode) }
                    }
                }
            }
        }
        .task(id: contextTaskKey) {
            await episodeState.refreshContext(vm: vm)
        }
        .task(id: seasonArtTaskKey) {
            guard !seasonArtTaskKey.isEmpty else { return }
            await episodeState.loadSeasonArt(vm: vm)
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchStateDidChange)) { notification in
            episodeState.handleWatchStateChange(WatchStateChange(notification: notification), vm: vm)
        }
    }
}

// MARK: - Season Selector

private struct SeasonSelector: View {
    let seasons: [DetailsViewModel.Season]
    let selectedKey: String
    let onSelect: (String) -> Void

    var body: some View {
        DetailsHorizontalRow {
            LazyHStack(spacing: DS.Space.s10) {
                ForEach(seasons) { season in
                    Button(action: { onSelect(season.id) }) {
                        Text(season.title)
                            .font(.system(size: 14, weight: selectedKey == season.id ? .bold : .medium))
                            .foregroundStyle(selectedKey == season.id ? .black : .white)
                            .padding(.horizontal, DS.Space.s16)
                            .padding(.vertical, DS.Space.s10)
                            .background(selectedKey == season.id ? Color.white : Color.white.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Horizontal Episode Card (like mobile)

private struct HorizontalEpisodeCard: View {
    let episode: DetailsViewModel.Episode
    let episodeNumber: Int
    let width: CGFloat
    let height: CGFloat
    var isDisabled: Bool = false
    var showsStremioButton: Bool = true
    var showsStremioActiveBadge: Bool = false
    var showTitle: String = ""
    var showRatingKey: String?
    var serverId: String?
    var isWatched: Bool = false
    var rating: Double?
    var hidesSpoilers: Bool = false
    var isWatchActionDisabled: Bool = false
    let onPlay: () -> Void
    let onStremio: () -> Void
    var onToggleWatched: () -> Void = {}

    @State private var isHovered = false

    private var progressPct: Double {
        Double(episode.progressPct ?? 0)
    }

    private var showProgress: Bool {
        progressPct > 0 && progressPct < 85
    }

    private var isCompleted: Bool {
        isWatched
    }

    /// Spoiler protection is on for this (unwatched) episode and it isn't hovered.
    private var spoilerHidden: Bool {
        hidesSpoilers && !isHovered
    }

    var body: some View {
        Button(action: onPlay) {
            ZStack(alignment: .bottomLeading) {
                // Thumbnail background
                if let imgURL = episode.image {
                    CachedAsyncImage(url: imgURL)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: width, height: height)
                        .clipped()
                        .blur(radius: spoilerHidden ? 24 : 0, opaque: true)
                } else {
                    Rectangle()
                        .fill(Color(white: 0.15))
                        .frame(width: width, height: height)
                }

                // Gradient overlay
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.05), location: 0),
                        .init(color: .black.opacity(0.2), location: 0.25),
                        .init(color: .black.opacity(0.6), location: 0.6),
                        .init(color: .black.opacity(0.9), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Hover play overlay
                if isHovered {
                    ZStack {
                        Color.black.opacity(0.3)
                        Image(systemName: "play.circle.fill")
                            .font(.flixorIcon(DS.Icon.huge))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 8)
                    }
                }

                // Content
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    // Episode badge (+ rating chip)
                    HStack(spacing: DS.Space.s6) {
                        Text("EPISODE \(episodeNumber)")
                            .font(.flixor(.micro, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(Color(white: 0.9))
                            .padding(.horizontal, DS.Space.s8)
                            .padding(.vertical, DS.Space.s4)
                            .background(Color.black.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r6))

                        if let rating {
                            EpisodeRatingChip(rating: rating)
                        }
                    }

                    // Title
                    Text(episode.title)
                        .font(.flixor(.bodyLarge, weight: .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    // Overview (hidden while spoiler protection applies)
                    if let overview = episode.overview, !overview.isEmpty {
                        if spoilerHidden {
                            EpisodeSpoilerNotice()
                        } else {
                            Text(overview)
                                .font(.flixor(.footnote))
                                .foregroundStyle(.white.opacity(0.82))
                                .lineLimit(3)
                        }
                    }

                    // Meta info
                    if let duration = episode.durationMin {
                        HStack(spacing: DS.Space.s4) {
                            Image(systemName: "clock")
                                .font(.flixor(.caption))
                            Text("\(duration)m")
                                .font(.flixor(.caption))
                        }
                        .foregroundStyle(Color(white: 0.6))
                    }
                }
                .padding(DS.Space.s12)

                // Progress bar
                if showProgress {
                    VStack {
                        Spacer()
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.33))
                                    .frame(height: 4)

                                Rectangle()
                                    .fill(Color.white)
                                    .frame(width: geo.size.width * CGFloat(min(100, max(0, progressPct))) / 100.0, height: 4)
                            }
                        }
                        .frame(height: 4)
                    }
                }

                // Top-right buttons overlay
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: DS.Space.s6) {
                            // Download button
                            if let serverId = serverId {
                                EpisodeDownloadButton(
                                    ratingKey: episode.id,
                                    serverId: serverId,
                                    title: episode.title,
                                    seasonNumber: episode.seasonNumber ?? 1,
                                    episodeNumber: episode.episodeNumber ?? episodeNumber,
                                    showTitle: showTitle,
                                    showRatingKey: showRatingKey,
                                    thumb: episode.image?.absoluteString
                                )
                            }

                            if showsStremioButton {
                                Button(action: onStremio) {
                                    Image(systemName: "puzzlepiece.extension.fill")
                                        .font(.flixorIcon(DS.Icon.xs, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 22, height: 22)
                                        .background(Color.orange.opacity(0.75), in: Circle())
                                }
                                .buttonStyle(.plain)
                            }

                            if showsStremioActiveBadge {
                                EpisodeSourceBadge(compact: true)
                            }

                            // Watched indicator; doubles as the watched toggle
                            if isCompleted || isHovered {
                                EpisodeWatchedButton(
                                    isWatched: isCompleted,
                                    style: .compact,
                                    isDisabled: isWatchActionDisabled,
                                    action: onToggleWatched
                                )
                            }
                        }
                        .padding(DS.Space.s10)
                    }
                    Spacer()
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.r16, style: .continuous)
                    .strokeBorder(Color.white.opacity(isHovered ? 0.5 : 0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: isHovered ? 12 : 6, y: isHovered ? 6 : 3)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1.0)
        .animation(.easeOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            if !isDisabled {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Vertical Episode Row (original list layout)

private struct VerticalEpisodeRow: View {
    let episode: DetailsViewModel.Episode
    let episodeNumber: Int
    let layout: DetailsLayoutMetrics
    var isDisabled: Bool = false
    var showsStremioButton: Bool = true
    var showsStremioActiveBadge: Bool = false
    var showTitle: String = ""
    var showRatingKey: String?
    var serverId: String?
    var isWatched: Bool = false
    var rating: Double?
    var hidesSpoilers: Bool = false
    var isWatchActionDisabled: Bool = false
    let onPlay: () -> Void
    let onStremio: () -> Void
    var onToggleWatched: () -> Void = {}

    @State private var isHovered = false

    private var progressPct: Double {
        Double(episode.progressPct ?? 0)
    }

    private var showProgress: Bool {
        progressPct > 0 && progressPct < 85
    }

    private var isCompleted: Bool {
        isWatched
    }

    /// Spoiler protection is on for this (unwatched) episode and it isn't hovered.
    private var spoilerHidden: Bool {
        hidesSpoilers && !isHovered
    }

    var body: some View {
        Button(action: onPlay) {
            HStack(alignment: .top, spacing: DS.Space.s16) {
                // Thumbnail
                ZStack(alignment: .bottomLeading) {
                    if let imgURL = episode.image {
                        CachedAsyncImage(url: imgURL)
                            .aspectRatio(16/9, contentMode: .fill)
                            .frame(width: layout.episodeThumbnailWidth)
                            .clipped()
                            .blur(radius: spoilerHidden ? 18 : 0, opaque: true)
                    } else {
                        Rectangle()
                            .fill(Color(white: 0.15))
                            .aspectRatio(16/9, contentMode: .fill)
                            .frame(width: layout.episodeThumbnailWidth)
                    }

                    // Progress bar
                    if showProgress {
                        GeometryReader { geo in
                            VStack {
                                Spacer()
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.33))
                                        .frame(height: 4)

                                    Rectangle()
                                        .fill(Color.white)
                                        .frame(width: geo.size.width * CGFloat(min(100, max(0, progressPct))) / 100.0, height: 4)
                                }
                            }
                        }
                    }

                    // Hover play overlay
                    if isHovered {
                        ZStack {
                            Color.black.opacity(0.4)
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.r10, style: .continuous)
                        .stroke(Color.white.opacity(isHovered ? 0.4 : 0.12), lineWidth: 1)
                )

                // Info
                VStack(alignment: .leading, spacing: DS.Space.s8) {
                    HStack {
                        Text("\(episodeNumber). \(episode.title)")
                            .font(.flixor(.headline, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        Spacer()

                        HStack(spacing: DS.Space.s8) {
                            // Download button
                            if let serverId = serverId {
                                EpisodeDownloadButton(
                                    ratingKey: episode.id,
                                    serverId: serverId,
                                    title: episode.title,
                                    seasonNumber: episode.seasonNumber ?? 1,
                                    episodeNumber: episode.episodeNumber ?? episodeNumber,
                                    showTitle: showTitle,
                                    showRatingKey: showRatingKey,
                                    thumb: episode.image?.absoluteString
                                )
                            }

                            if showsStremioButton {
                                Button(action: onStremio) {
                                    Label("Stremio", systemImage: "puzzlepiece.extension.fill")
                                        .font(.flixor(.caption, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, DS.Space.s10)
                                        .padding(.vertical, 5)
                                        .background(Color.orange.opacity(0.24), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }

                            if showsStremioActiveBadge {
                                EpisodeSourceBadge()
                            }

                            if isCompleted || isHovered {
                                EpisodeWatchedButton(
                                    isWatched: isCompleted,
                                    style: .regular,
                                    isDisabled: isWatchActionDisabled,
                                    action: onToggleWatched
                                )
                            }
                        }
                    }

                    if let overview = episode.overview, !overview.isEmpty {
                        if spoilerHidden {
                            EpisodeSpoilerNotice()
                        } else {
                            Text(overview)
                                .font(.flixor(.callout))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(3)
                        }
                    }

                    if episode.durationMin != nil || rating != nil {
                        HStack(spacing: DS.Space.controlGap) {
                            if let duration = episode.durationMin {
                                Text("\(duration) min")
                                    .font(.flixor(.footnote))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            if let rating {
                                EpisodeRatingChip(rating: rating)
                            }
                        }
                    }
                }
            }
            .padding(DS.Space.s12)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.r12, style: .continuous)
                    .fill(Color.white.opacity(isHovered ? 0.06 : 0.03))
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1.0)
        .onHover { hovering in
            if !isDisabled {
                isHovered = hovering
            }
        }
    }
}

private struct EpisodeSourceBadge: View {
    var compact: Bool = false

    var body: some View {
        Label("Stremio", systemImage: "puzzlepiece.extension.fill")
            .font(.system(size: compact ? 10 : 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 8 : 10)
            .padding(.vertical, compact ? 4 : 5)
            .background(Color.orange.opacity(compact ? 0.5 : 0.24), in: Capsule())
    }
}
