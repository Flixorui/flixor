//
//  DetailsView.swift
//  FlixorMac
//
//  Minimal details page to enable navigation from Home
//

import SwiftUI
import FlixorKit

struct DetailsView: View {
    let item: MediaItem
    @StateObject var vm = DetailsViewModel()
    @State var activeTab: String = "SUGGESTED"
    @EnvironmentObject private var router: NavigationRouter
    @EnvironmentObject private var mainView: MainViewState

    // Version picker state
    @State private var showVersionPicker = false
    @State private var pendingPlayItem: MediaItem?
    @State private var episodeVersions: [DetailsViewModel.VersionDetail] = []
    @State private var isLoadingVersions = false
    @State private var stremioAlertMessage: String?
    @State private var stremioAlertOffersSettings = false
    @State private var showStremioSettings = false
    @StateObject private var streamAutoPlay = StreamAutoPlayController()

    // Profile-scoped layout preference
    @ObservedObject var profileSettings = ProfileSettings.shared

    // Title watch state / Trakt rating (hero action row)
    @StateObject private var titleActions = DetailsTitleActionsModel()

    // Hero position in the scroll view (floating header, inline trailer)
    @StateObject private var heroScroll = DetailsHeroScrollState()
    @Environment(\.windowMetrics) private var windowMetrics

    // Inline hero trailer
    @StateObject private var heroTrailer = DetailsHeroTrailerController()

    // Owned here because the comment popup covers the whole page.
    @StateObject var commentsModel = DetailsCommentsModel()

    @Environment(\.controlActiveState) private var controlActiveState
    @State private var ownTab: NavItem?

    // Loading skeleton
    @State private var initialLoadFinished = false
    @State private var initialTabApplied = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Hero skeleton until the title's core metadata is in (or the load ends).
    private var showsLoadingSkeleton: Bool {
        vm.title.isEmpty && (vm.isLoading || !initialLoadFinished)
    }

    private var isPageObscured: Bool {
        commentsModel.selectedIndex != nil
    }

    private var showsFloatingHeader: Bool {
        heroScroll.isHeroScrolledAway && !showsLoadingSkeleton
    }

    /// Same primary action as the hero: Plex when there is a copy, else addons.
    private var floatingHeaderPlayAction: (() -> Void)? {
        if vm.isSeason { return nil }
        if hasResolvedPlexSource { return playContent }
        if canShowStremioAction { return openHeroStremioSources }
        return nil
    }

    private var resolvedPlexPlayableId: String? {
        if let playableId = vm.playableId, playableId.hasPrefix("plex:") {
            return playableId
        }
        if let ratingKey = vm.plexRatingKey {
            return "plex:\(ratingKey)"
        }
        return nil
    }

    private var hasResolvedPlexSource: Bool {
        resolvedPlexPlayableId != nil
    }

    var canShowStremioAction: Bool {
        guard profileSettings.stremioPlaybackEnabled else { return false }
        if item.id.hasPrefix("tmdb:") && !profileSettings.stremioShowOnTmdbDetails {
            return false
        }
        return item.type == "movie" || item.type == "show" || item.type == "episode" || vm.mediaKind == "movie" || vm.mediaKind == "tv" || vm.isSeason || vm.isEpisode
    }

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                let width = max(proxy.size.width, 640)
                let layout = DetailsLayoutMetrics(width: width)

                ZStack(alignment: .top) {
                    ScrollView {
                        pageContent(layout: layout)
                    }
                    .coordinateSpace(name: DetailsScrollSpace.name)
                    .onPreferenceChange(DetailsHeroFramePreferenceKey.self) { frame in
                        heroScroll.update(heroFrame: frame)
                    }
                    .opacity(showsLoadingSkeleton ? 0 : 1)

                    if showsLoadingSkeleton {
                        DetailsHeroSkeleton(layout: layout)
                            .transition(.opacity)
                            .allowsHitTesting(false)
                    }
                }
                .animation(reduceMotion ? nil : DS.Motion.slow, value: showsLoadingSkeleton)
            }
            .frame(maxWidth: .infinity, alignment: .top)

        }
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .top) {
            // Outside ignoresSafeArea, so it sits just below the window toolbar.
            if showsFloatingHeader {
                DetailsFloatingHeader(
                    vm: vm,
                    onPlay: floatingHeaderPlayAction,
                    playsFromPlex: hasResolvedPlexSource,
                    horizontalPadding: DetailsLayoutMetrics(width: max(windowMetrics.width, 640)).heroHorizontalPadding
                )
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay { DetailsCommentPopup(model: commentsModel) }
        .overlay { StreamAutoPlayOverlay(controller: streamAutoPlay) }
        .animation(reduceMotion ? DS.Motion.quick : DS.Motion.standard, value: showsFloatingHeader)
        .environment(\.detailsTitleActions, titleActions)
        .environment(\.detailsHeroTrailer, heroTrailer)
        .onReceive(heroScroll.scrollActivity) { _ in
            heroTrailer.noteActivity()
        }
        .onReceive(heroScroll.$isHeroMostlyVisible.removeDuplicates()) { visible in
            heroTrailer.update { $0.isHeroVisible = visible }
        }
        .onChange(of: controlActiveState) { state in
            heroTrailer.update { $0.isWindowFocused = state == .key }
        }
        .onChange(of: mainView.selectedTab) { tab in
            heroTrailer.update { $0.isTabActive = ownTab == nil || tab == ownTab }
            // Tabs stay alive when hidden, so the overlay's onDisappear doesn't fire.
            if let ownTab, tab != ownTab { streamAutoPlay.cancel() }
        }
        .onChange(of: reduceMotion) { value in
            heroTrailer.update { $0.isReduceMotion = value }
        }
        .onChange(of: isPageObscured) { obscured in
            heroTrailer.update { $0.isObscured = obscured }
        }
        .onAppear {
            if ownTab == nil { ownTab = mainView.selectedTab }
            heroTrailer.update {
                $0.isPageVisible = true
                $0.isWindowFocused = controlActiveState == .key
                $0.isTabActive = mainView.selectedTab == ownTab
                $0.isReduceMotion = reduceMotion
            }
        }
        .onDisappear {
            // Leaving the page (including starting playback) stops the trailer.
            heroTrailer.update { $0.isPageVisible = false }
        }
        .background(
            DetailsPersistentBackdrop(
                imageURL: vm.backdropURL,
                scroll: heroScroll.backdrop,
                heroTrailer: heroTrailer
            )
        )
        .navigationTitle("")
        .task {
            // Coming back from the player or a pushed page only refreshes.
            let refreshing = vm.hasLoadedContent(for: item)
            await vm.load(for: item)
            initialLoadFinished = true
            if refreshing {
                titleActions.scheduleRefresh()
                heroTrailer.configure(tmdbId: vm.tmdbId, mediaKind: vm.mediaKind)
            }
        }
        // Both counters move when a load starts (ids cleared) and again once the
        // ids are known, well before the whole load ends.
        .onChange(of: vm.identityGeneration) { _ in
            heroTrailer.configure(tmdbId: vm.tmdbId, mediaKind: vm.mediaKind)
            applyInitialTabIfNeeded()
        }
        .onChange(of: vm.titleIdsGeneration) { _ in
            if vm.titleIdsReady { titleActions.configure(with: vm) }
        }
        .onChange(of: vm.seasons.map(\.id)) { _ in
            titleActions.updateSeasonOptions(with: vm)
        }
        .sheet(isPresented: $showVersionPicker) {
            VersionPickerSheet(
                versions: episodeVersions.isEmpty ? vm.versions : episodeVersions,
                title: pendingPlayItem?.title ?? vm.title,
                onSelect: { version in
                    playWithVersion(version)
                },
                onCancel: {
                    showVersionPicker = false
                    pendingPlayItem = nil
                    episodeVersions = []
                }
            )
        }
        .sheet(isPresented: $showStremioSettings) {
            StremioSettingsView()
        }
        .alert("Stremio", isPresented: Binding(get: { stremioAlertMessage != nil }, set: { if !$0 { stremioAlertMessage = nil } })) {
            if stremioAlertOffersSettings {
                Button("Open Settings") {
                    showStremioSettings = true
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(stremioAlertMessage ?? "")
        }
        // Destination for PlayerView is handled at root via NavigationStack(path:)
    }

    /// Initial tab for the page's own item: DETAILS for episodes, EPISODES for
    /// TV shows/seasons. Titles opened in place keep the current tab.
    private func applyInitialTabIfNeeded() {
        // A failed load also signals identity; wait until the kind is known.
        guard !initialTabApplied, vm.identityReady,
              vm.isEpisode || vm.isSeason || vm.mediaKind != nil else { return }
        initialTabApplied = true
        if vm.isEpisode {
            activeTab = "DETAILS"
        } else if vm.mediaKind == "tv" || vm.isSeason {
            activeTab = "EPISODES"
        }
    }

    /// The episode the hero Play button starts on a show or season page: On Deck,
    /// else one in progress, else the first one listed.
    private var heroPlayEpisode: DetailsViewModel.Episode? {
        let plexEpisodes = vm.episodes.filter { $0.id.hasPrefix("plex:") }
        if let onDeck = vm.onDeck, onDeck.id.hasPrefix("plex:") {
            if let listed = plexEpisodes.first(where: { $0.id == onDeck.id }) { return listed }
            if !vm.isSeason { return onDeck }
        }
        return plexEpisodes.first { ($0.viewOffset ?? 0) > 0 } ?? plexEpisodes.first
    }

    func playContent() {
        guard hasResolvedPlexSource, let playableId = resolvedPlexPlayableId else { return }

        // A show or season is not playable itself; start its next episode.
        if !vm.isEpisode, item.type != "episode", vm.mediaKind == "tv" {
            if let episode = heroPlayEpisode { playEpisode(episode) }
            return
        }

        // CRITICAL: Preserve episode type from original item
        // vm.mediaKind only stores "movie" or "tv", but episodes need type="episode"
        let mediaType: String = {
            if item.type == "episode" {
                return "episode"
            }
            return vm.mediaKind ?? item.type
        }()

        // For episodes, use original episode title (not the formatted display title)
        // and ensure grandparentTitle/parentIndex/index are properly set for player formatting
        let playerTitle: String
        let playerGrandparentTitle: String?
        let playerParentIndex: Int?
        let playerIndex: Int?

        if vm.isEpisode {
            // Use original episode title to avoid duplication in player
            playerTitle = vm.episodeTitle ?? item.title
            playerGrandparentTitle = vm.showTitle ?? item.grandparentTitle
            playerParentIndex = vm.seasonNumber ?? item.parentIndex
            playerIndex = vm.episodeNumber ?? item.index
        } else {
            playerTitle = vm.title.isEmpty ? item.title : vm.title
            playerGrandparentTitle = item.grandparentTitle
            playerParentIndex = item.parentIndex
            playerIndex = item.index
        }

        let playerItem = MediaItem(
            id: playableId,
            title: playerTitle,
            type: mediaType,
            thumb: item.thumb,
            art: item.art,
            year: vm.year.flatMap { Int($0) },
            rating: nil,
            duration: vm.runtime.map { $0 * 60000 },
            viewOffset: nil,
            summary: vm.overview.isEmpty ? nil : vm.overview,
            grandparentTitle: playerGrandparentTitle,
            grandparentThumb: item.grandparentThumb,
            grandparentArt: item.grandparentArt,
            grandparentRatingKey: vm.showRatingKey ?? item.grandparentRatingKey,
            parentIndex: playerParentIndex,
            index: playerIndex,
            parentRatingKey: item.parentRatingKey,
            parentTitle: item.parentTitle,
            leafCount: item.leafCount,
            viewedLeafCount: item.viewedLeafCount
        )

        // For movies - use existing vm.versions
        if vm.mediaKind == "movie" {
            if vm.versions.count > 1 {
                pendingPlayItem = playerItem
                showVersionPicker = true
            } else {
                appendToCurrentTabPath(.plex(playerItem))
            }
        }
        // For episodes/TV shows - fetch versions for the specific playable item
        else if item.type == "episode" || vm.mediaKind == "tv" {
            Task {
                isLoadingVersions = true
                let versions = await vm.fetchVersionsForItem(ratingKey: playableId)
                isLoadingVersions = false

                if versions.count > 1 {
                    episodeVersions = versions
                    pendingPlayItem = playerItem
                    showVersionPicker = true
                } else {
                    appendToCurrentTabPath(.plex(playerItem))
                }
            }
        } else {
            appendToCurrentTabPath(.plex(playerItem))
        }
    }

    private func playWithVersion(_ version: DetailsViewModel.VersionDetail) {
        guard var playerItem = pendingPlayItem else { return }
        // Find the index of the selected version in the appropriate array
        let versionsArray = episodeVersions.isEmpty ? vm.versions : episodeVersions
        if let index = versionsArray.firstIndex(where: { $0.id == version.id }) {
            playerItem.mediaIndex = index
        }
        showVersionPicker = false
        pendingPlayItem = nil
        episodeVersions = []
        appendToCurrentTabPath(.plex(playerItem))
    }

    private func appendToCurrentTabPath(_ destination: PlayerDestination) {
        switch mainView.selectedTab {
        case .home: router.homePath.append(destination)
        case .search: router.searchPath.append(destination)
        case .library: router.libraryPath.append(destination)
        case .myList: router.myListPath.append(destination)
        case .newPopular: router.newPopularPath.append(destination)
        case .downloads: router.downloadsPath.append(destination)
        }
    }

    func viewParentShow() {
        // Navigate to the parent TV show for episodes
        guard item.type == "episode", let showKey = item.grandparentRatingKey else { return }
        let showItem = MediaItem(
            id: "plex:\(showKey)",
            title: item.grandparentTitle ?? String(localized: "TV Show"),
            type: "show",
            thumb: item.grandparentThumb,
            art: item.grandparentArt,
            year: nil,
            rating: nil,
            duration: nil,
            viewOffset: nil,
            summary: nil,
            grandparentTitle: nil,
            grandparentThumb: nil,
            grandparentArt: nil,
            grandparentRatingKey: nil,
            parentIndex: nil,
            index: nil,
            parentRatingKey: nil,
            parentTitle: nil,
            leafCount: nil,
            viewedLeafCount: nil
        )
        // Use DetailsNavigationItem to navigate to details screen, not player
        let navItem = DetailsNavigationItem(item: showItem)
        switch mainView.selectedTab {
        case .home: router.homePath.append(navItem)
        case .search: router.searchPath.append(navItem)
        case .library: router.libraryPath.append(navItem)
        case .myList: router.myListPath.append(navItem)
        case .newPopular: router.newPopularPath.append(navItem)
        case .downloads: router.downloadsPath.append(navItem)
        }
    }

    /// Opens the Browse page for More Like This (pushed on the current tab).
    func presentBrowse(_ context: BrowseContext) {
        router.push(BrowseRoute(context: context, title: String(localized: "More Like This")), on: mainView.selectedTab)
    }

    func presentPerson(_ person: CastCrewCard.Person) {
        // TMDB cast carries numeric ids; Plex cast only names, which the person
        // page resolves with a TMDB name search.
        let tmdbId = Int(person.id).map { $0 > 0 ? String($0) : "" } ?? ""
        guard !tmdbId.isEmpty || !person.name.isEmpty else { return }
        let route = PersonRoute(tmdbId: tmdbId, name: person.name, profilePath: person.image?.absoluteString)
        router.push(route, on: mainView.selectedTab)
    }

    func playEpisode(_ episode: DetailsViewModel.Episode) {
        // TMDB-sourced episodes have no Plex ratingKey; they can only play via Stremio.
        guard episode.id.hasPrefix("plex:") else {
            if canShowStremioAction {
                openEpisodeStremioSources(episode)
            }
            return
        }

        let ratingKey = String(episode.id.dropFirst(5))
        let playerItem = MediaItem(
            id: episode.id,
            title: episode.title,
            type: "episode",
            thumb: episode.image?.absoluteString,
            art: nil,
            year: nil,
            rating: nil,
            duration: episode.durationMin.map { $0 * 60000 },
            viewOffset: episode.viewOffset,
            summary: episode.overview,
            grandparentTitle: vm.title.isEmpty ? nil : vm.title,
            grandparentThumb: nil,
            grandparentArt: nil,
            grandparentRatingKey: vm.plexRatingKey,
            parentIndex: episode.seasonNumber,
            index: episode.episodeNumber,
            parentRatingKey: nil,
            parentTitle: nil,
            leafCount: nil,
            viewedLeafCount: nil
        )

        // Fetch versions for this episode
        Task {
            isLoadingVersions = true
            let versions = await vm.fetchVersionsForItem(ratingKey: ratingKey)
            isLoadingVersions = false

            if versions.count > 1 {
                episodeVersions = versions
                pendingPlayItem = playerItem
                showVersionPicker = true
            } else {
                appendToCurrentTabPath(.plex(playerItem))
            }
        }
    }

    func openHeroStremioSources() {
        openHeroStremio(forcePicker: StreamAutoPlayController.isPickerModifierHeld)
    }

    /// "Choose Source…": the sources page regardless of the Play setting.
    func chooseHeroStremioSource() {
        openHeroStremio(forcePicker: true)
    }

    private func openHeroStremio(forcePicker: Bool) {
        if item.type == "movie" || vm.mediaKind == "movie" {
            Task { await openStremioSources(for: nil, forcePicker: forcePicker) }
            return
        }

        if vm.isEpisode {
            let episode = DetailsViewModel.Episode(
                id: item.id.replacingOccurrences(of: "plex:", with: ""),
                title: vm.episodeTitle ?? item.title,
                overview: vm.overview,
                image: vm.posterURL,
                durationMin: vm.runtime,
                progressPct: nil,
                viewOffset: item.viewOffset,
                seasonNumber: vm.seasonNumber,
                episodeNumber: vm.episodeNumber
            )
            Task { await openStremioSources(for: episode, forcePicker: forcePicker) }
            return
        }

        // Continue Watching card: the show page, opened for one specific episode.
        if item.type == "episode", let season = item.parentIndex, let number = item.index {
            let episode = vm.episodes.first { $0.seasonNumber == season && $0.episodeNumber == number }
                ?? DetailsViewModel.Episode(
                    id: "\(item.id):\(season):\(number)",
                    title: item.title,
                    overview: nil,
                    image: nil,
                    durationMin: item.duration.map { $0 / 60_000 },
                    progressPct: nil,
                    viewOffset: item.viewOffset,
                    seasonNumber: season,
                    episodeNumber: number
                )
            Task { await openStremioSources(for: episode, forcePicker: forcePicker) }
            return
        }

        if let onDeck = vm.onDeck {
            Task { await openStremioSources(for: onDeck, forcePicker: forcePicker) }
            return
        }

        if let firstEpisode = vm.episodes.first {
            Task { await openStremioSources(for: firstEpisode, forcePicker: forcePicker) }
            return
        }

        stremioAlertOffersSettings = false
        stremioAlertMessage = String(localized: "Choose an episode to use Stremio playback.")
        if profileSettings.detailsScreenLayout == "tabbed" {
            activeTab = "EPISODES"
        }
    }

    func openEpisodeStremioSources(_ episode: DetailsViewModel.Episode) {
        let forcePicker = StreamAutoPlayController.isPickerModifierHeld
        Task { await openStremioSources(for: episode, forcePicker: forcePicker) }
    }

    private func openStremioSources(for episode: DetailsViewModel.Episode?, forcePicker: Bool) async {
        AppLogger.shared.info("[Stremio] Details CTA tapped", data: [
            "itemId": item.id,
            "episodeId": episode?.id ?? "",
            "title": vm.title,
        ])

        // Everything below lands on the tab Play was pressed on.
        let originTab = mainView.selectedTab
        let playAction = forcePicker ? StremioPlayAction.showSources : UserDefaults.standard.stremioPlayAction
        if playAction.isAutomatic {
            streamAutoPlay.begin(title: vm.title.isEmpty ? item.title : vm.title)
        }

        let result = await StremioContentResolver.resolve(item: item, details: vm, episode: episode)
        guard let identity = result.identity else {
            streamAutoPlay.cancel()
            switch result.error {
            case .noStreamAddons:
                stremioAlertOffersSettings = true
                stremioAlertMessage = String(localized: "No stream-capable Stremio addons are installed for this profile.")
            case .unsupportedID:
                stremioAlertOffersSettings = false
                stremioAlertMessage = String(localized: "No installed Stremio addon supports this title’s resolved ID.")
            default:
                stremioAlertOffersSettings = false
                stremioAlertMessage = String(localized: "No compatible Stremio ID could be resolved for this title.")
            }
            return
        }

        let mediaType: StreamMediaType = episode != nil || vm.isEpisode ? .episode : .movie
        let destination = StremioSourcesDestination(
            identity: identity,
            title: vm.title.isEmpty ? item.title : vm.title,
            backdropURL: vm.backdropURL?.absoluteString ?? item.art,
            posterURL: vm.posterURL?.absoluteString ?? item.thumb,
            mediaType: mediaType,
            imdbId: identity.imdbId,
            tmdbId: identity.tmdbId,
            seasonNumber: identity.seasonNumber,
            episodeNumber: identity.episodeNumber,
            episodeTitle: episode?.title ?? vm.episodeTitle
        )
        guard playAction.isAutomatic else {
            router.push(destination, on: originTab)
            return
        }
        streamAutoPlay.run(
            destination: destination,
            action: playAction,
            onPlay: { router.push($0, on: originTab) },
            onShowSources: { router.push($0, on: originTab) }
        )
    }
}

#if DEBUG && canImport(PreviewsMacros)
#Preview {
    DetailsView(item: MediaItem(
        id: "plex:1",
        title: "Sample Title",
        type: "movie",
        thumb: nil,
        art: nil,
        year: 2024,
        rating: 8.1,
        duration: 7200000,
        viewOffset: nil,
        summary: "A minimal details preview",
        grandparentTitle: nil,
        grandparentThumb: nil,
        grandparentArt: nil,
        parentIndex: nil,
        index: nil
    ))
}
#endif
