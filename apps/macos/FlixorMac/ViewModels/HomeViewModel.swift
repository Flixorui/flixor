//
//  HomeViewModel.swift
//  FlixorMac
//
//  View model for home screen using FlixorCore
//

import Foundation
import SwiftUI
import FlixorKit

// Use types from FlixorKit directly

// MARK: - Section Load State

enum SectionLoadState: Equatable {
    case idle
    case loading
    case loaded
    case empty
    case error(String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

@MainActor
class HomeViewModel: ObservableObject {
    // MARK: - Settings (Profile-Scoped)
    private var enabledLibraryKeys: Set<String> {
        Set(UserDefaults.standard.enabledLibraryKeys)
    }

    private func isLibraryEnabled(_ key: String) -> Bool {
        // Empty means all libraries are enabled
        return enabledLibraryKeys.isEmpty || enabledLibraryKeys.contains(key)
    }

    // MARK: - Global State
    @Published var isLoading = false  // Initial full-page loading
    @Published var error: String?

    // MARK: - Per-Section Loading States
    @Published var continueWatchingState: SectionLoadState = .idle
    @Published var onDeckState: SectionLoadState = .idle
    @Published var recentlyAddedState: SectionLoadState = .idle
    @Published var recentlyAddedPerLibraryState: SectionLoadState = .idle
    @Published var librariesState: SectionLoadState = .idle
    @Published var extraSectionsState: SectionLoadState = .idle
    @Published var collectionSectionsState: SectionLoadState = .idle
    /// Terminal state for the hero. Without this the view can't tell "still loading"
    /// from "nothing will ever populate it" and shows a skeleton indefinitely.
    @Published var heroState: SectionLoadState = .loading

    // Expected number of extra section rows (for skeleton placeholders)
    let expectedExtraSectionCount = 8

    // MARK: - Polling Configuration
    private var pollTimer: Timer?
    /// Bumped per Continue Watching publish so a slow Trakt fetch can't overwrite newer data.
    private var continueWatchingPublishGeneration = 0
    private let pollInterval: TimeInterval = 30 // Poll every 30 seconds
    private var isPolling = false

    // MARK: - Data
    @Published var billboardItems: [MediaItem] = []
    @Published var continueWatchingItems: [MediaItem] = []
    @Published var continueWatchingVersions: Set<String> = []  // ratingKeys with multiple versions across libraries
    /// Continue Watching item ids with a watch-state action in flight.
    @Published var continueWatchingBusyIds: Set<String> = []
    /// Items leaving the row whose action is still running; a refresh that
    /// lands meanwhile must not bring them back.
    var continueWatchingPendingRemovalIds: Set<String> = []
    @Published var onDeckItems: [MediaItem] = []
    @Published var recentlyAddedItems: [MediaItem] = [] // Global recently added (legacy, kept for billboard fallback)
    @Published var recentlyAddedSections: [LibrarySection] = [] // Per-library recently added rows
    @Published var librarySections: [LibrarySection] = []
    /// TMDB/Trakt/Watchlist/Genres/Stremio catalogs, with failed rows in place.
    @Published var extraSlots: [HomeRowSlot] = []
    /// Loaded discovery / catalog rows (failures left out).
    var extraSections: [LibrarySection] { extraSlots.compactMap(\.section) }
    @Published var collectionSections: [LibrarySection] = [] // Plex Collections

    /// Addon name per Stremio catalog row id, for the duplicate-title caption.
    private(set) var catalogAddonNames: [String: String] = [:]

    @Published var currentBillboardIndex = 0
    @Published var pendingAction: HomeAction?

    // MARK: - Load Progress / Hero Source

    /// True once every row group of the current load has finished.
    @Published private(set) var isInitialLoadComplete = false
    /// Row ids being retried from their error card.
    @Published private(set) var retryingRowIds: Set<String> = []
    /// Row groups of the current load still running.
    private var pendingGroupCount = 0
    /// The hero source chosen in settings has been tried (found or given up).
    private var preferredHeroSettled = false
    /// Watchlist fetched only for the "My List" hero source (row hidden or off).
    private var onDemandWatchlistItems: [MediaItem]?
    private var onDemandWatchlistRequested = false

    // MARK: - UltraBlur Colors
    @Published var heroColors: PlexUltraBlurColors?
    private var ultraBlurCache: [String: PlexUltraBlurColors] = [:]
    private var lastHeroColorKey: String?

    private var billboardTimer: Timer?
    private var loadTask: Task<Void, Never>?

    // MARK: - Mode

    /// Standalone Stremio mode: there is no Plex server, so every Plex-backed row is
    /// skipped rather than dispatched and failed.
    private var isStremioOnly: Bool { AppModeStore.shared.isStremioOnly }

    /// Row count used for skeleton placeholders while extra sections load.
    var expectedExtraSectionCountForMode: Int {
        isStremioOnly ? 6 : expectedExtraSectionCount
    }

    // MARK: - Load Data

    func loadHomeScreen() async {
        // Guard against duplicate loads
        if isLoading || loadTask != nil || pendingGroupCount > 0 {
            print("⚠️ [Home] Already loading, skipping duplicate request")
            return
        }
        loadTask = Task {} // mark in-progress

        print("🏠 [Home] Starting home screen load...")
        isLoading = true
        error = nil
        isInitialLoadComplete = false
        preferredHeroSettled = HomeRowsStore.shared.heroSource == .automatic
        onDemandWatchlistItems = nil
        onDemandWatchlistRequested = false

        // Set all sections to loading state
        continueWatchingState = .loading
        onDeckState = .loading
        recentlyAddedState = .loading
        recentlyAddedPerLibraryState = .loading
        librariesState = .loading
        extraSectionsState = .loading
        collectionSectionsState = .loading

        if isStremioOnly {
            await loadStremioHomeScreen()
            return
        }

        // Continue Watching, On Deck, Recently Added, per-library rows,
        // libraries, extra rows, collections.
        pendingGroupCount = 7

        // Fire-and-forget each section; update UI as each finishes
        Task { @MainActor in
            await self.loadPlexContinueWatching()
            // Mark initial loading complete after first section
            self.isLoading = false
            self.finishGroup()
        }

        Task { @MainActor in
            do {
                let data = try await self.fetchOnDeck()
                self.onDeckItems = data
                self.onDeckState = data.isEmpty ? .empty : .loaded
                self.offerDefaultHero(data)
                print("✅ [Home] On Deck loaded: \(data.count) items")
            } catch {
                print("⚠️ [Home] On Deck failed: \(error)")
                self.onDeckState = .error(error.localizedDescription)
            }
            self.finishGroup()
        }

        Task { @MainActor in
            do {
                let data = try await self.fetchRecentlyAdded()
                self.recentlyAddedItems = data
                self.recentlyAddedState = data.isEmpty ? .empty : .loaded
                self.offerDefaultHero(data)
                print("✅ [Home] Recently Added loaded: \(data.count) items")
            } catch {
                print("⚠️ [Home] Recently Added failed: \(error)")
                self.recentlyAddedState = .error(error.localizedDescription)
            }
            self.finishGroup()
        }

        // Per-library Recently Added rows
        Task { @MainActor in
            do {
                let sections = try await self.fetchRecentlyAddedPerLibrary()
                self.recentlyAddedSections = sections
                self.recentlyAddedPerLibraryState = sections.isEmpty ? .empty : .loaded
                self.registerRecentlyAddedRows()
                print("✅ [Home] Recently Added per library loaded: \(sections.count) sections")
            } catch {
                print("⚠️ [Home] Recently Added per library failed: \(error)")
                self.recentlyAddedPerLibraryState = .error(error.localizedDescription)
            }
            self.finishGroup()
        }

        Task { @MainActor in
            do {
                let libs = try await self.fetchLibrarySections()
                self.librarySections = libs
                self.librariesState = libs.isEmpty ? .empty : .loaded
                print("✅ [Home] Libraries loaded: \(libs.count) sections")
            } catch {
                print("⚠️ [Home] Libraries failed: \(error)")
                self.librariesState = .error(error.localizedDescription)
            }
            self.finishGroup()
        }

        // Load additional content sections (TMDB/Trakt/Genres/Watchlist) without blocking
        Task { @MainActor in
            await self.loadAdditionalRows()
            // Last resort for the hero when the Plex rows came back empty, so it
            // resolves instead of shimmering forever.
            self.seedBillboardFromExtraSections()
            self.finishGroup()
        }

        // Load collection sections (Plex Collections) without blocking
        Task { @MainActor in
            await self.loadCollectionRows()
            self.finishGroup()
        }

        // Start polling for dynamic rows (Continue Watching, Recently Added)
        startPolling()

        loadTask = nil
    }

    // MARK: - Stremio-Only Load

    /// Home screen for standalone Stremio mode. Every Plex-backed row is marked empty
    /// up front (so it collapses instead of shimmering), and discovery comes from TMDB
    /// and Trakt.
    private func loadStremioHomeScreen() async {
        onDeckState = .empty
        recentlyAddedState = .empty
        recentlyAddedPerLibraryState = .empty
        librariesState = .empty
        collectionSectionsState = .empty
        recentlyAddedSections = []
        librarySections = []
        collectionSections = []
        onDeckItems = []
        recentlyAddedItems = []

        registerRows([], group: .recentlyAdded)
        registerRows([], group: .collections)
        // Extra rows; local Continue Watching is awaited below.
        pendingGroupCount = 1

        await loadLocalContinueWatching(showLocalFirst: true)
        isLoading = false

        Task { @MainActor in
            await self.loadAdditionalRows()
            // Local history seeds the hero first; otherwise fall back to discovery rows.
            self.seedBillboardFromExtraSections()
            self.finishGroup()
        }

        loadTask = nil
    }

    /// Continue Watching from the local watch history written during stream playback.
    func loadLocalContinueWatching(showLocalFirst: Bool = false) async {
        let entries = await LocalLibraryStore.shared.watchHistory()
        let items = entries.compactMap(makeMediaItem(from:))
            .filter { !continueWatchingPendingRemovalIds.contains($0.id) }
        var activity: [String: Date] = [:]
        for entry in entries {
            guard let id = entry.mediaItemId else { continue }
            activity[id] = max(activity[id] ?? entry.updatedAt, entry.updatedAt)
        }

        continueWatchingVersions = []
        publishContinueWatching(primary: items, activity: activity, showPrimaryFirst: showLocalFirst)

        print("✅ [Home] Local Continue Watching loaded: \(items.count) items")
    }

    private func makeMediaItem(from entry: WatchHistoryEntry) -> MediaItem? {
        // Without a TMDB id there's nothing the details screen can open.
        guard let itemId = entry.mediaItemId else {
            print("⚠️ [Home] Skipping history entry '\(entry.title)' - no TMDB id")
            return nil
        }

        let isEpisode = entry.mediaType == .episode
        return MediaItem(
            id: itemId,
            title: isEpisode ? (entry.episodeTitle ?? entry.title) : entry.title,
            type: isEpisode ? "episode" : "movie",
            thumb: entry.posterURL,
            art: entry.backdropURL,
            year: nil,
            rating: nil,
            duration: entry.durationMs,
            viewOffset: entry.positionMs,
            summary: nil,
            grandparentTitle: isEpisode ? entry.title : nil,
            grandparentThumb: isEpisode ? entry.posterURL : nil,
            grandparentArt: isEpisode ? entry.backdropURL : nil,
            grandparentRatingKey: nil,
            parentIndex: entry.seasonNumber,
            index: entry.episodeNumber,
            parentRatingKey: nil,
            parentTitle: nil,
            leafCount: nil,
            viewedLeafCount: nil
        )
    }

    /// Uses the first usable discovery row for the hero when there's no local library.
    private func seedBillboardFromExtraSections() {
        guard billboardItems.isEmpty else {
            heroState = .loaded
            return
        }
        // A hero source picked in settings is still loading; don't fill in yet.
        guard preferredHeroSettled else { return }

        // Prefer a row with backdrop art so the billboard isn't a flat poster crop.
        let candidate = extraSections.first { section in
            section.items.contains { ($0.art?.isEmpty == false) }
        } ?? extraSections.first

        let items = (candidate?.items ?? []).filter { $0.art?.isEmpty == false }
        guard !items.isEmpty else {
            // Nothing left to try - let the view drop the hero instead of shimmering.
            heroState = .empty
            print("ℹ️ [Home] Hero has no source; hiding it")
            return
        }

        billboardItems = normalizeForHero(Array(items.prefix(5)))
        heroState = .loaded
        startBillboardRotation()
        print("✅ [Home] Hero seeded from '\(candidate?.title ?? "?")': \(billboardItems.count) items")
    }

    // MARK: - Continue Watching Publishing

    /// Shows the Plex or local items and folds in Trakt per the Source setting.
    /// - Parameter showPrimaryFirst: Show the local items while Trakt loads (first
    ///   load). Refreshes leave the row alone until the merged list is ready.
    private func publishContinueWatching(
        primary: [MediaItem],
        activity: [String: Date] = [:],
        showPrimaryFirst: Bool
    ) {
        let source = UserDefaults.standard.continueWatchingSource
        let usesTrakt = source != .library && FlixorCore.shared.isTraktAuthenticated
        continueWatchingPublishGeneration += 1
        let generation = continueWatchingPublishGeneration

        guard usesTrakt else {
            applyContinueWatching(primary)
            return
        }
        if showPrimaryFirst && source == .automatic {
            applyContinueWatching(primary)
        }

        Task { @MainActor [weak self] in
            do {
                let entries = try await TraktContinueWatchingService.shared.entries()
                guard let self, generation == self.continueWatchingPublishGeneration else { return }
                let merged = ContinueWatchingMerger.merge(
                    primary: source == .trakt ? [] : primary,
                    activity: activity,
                    trakt: entries,
                    dismissals: UserDefaults.standard.continueWatchingTraktDismissals
                )
                self.applyContinueWatching(merged)
            } catch {
                print("⚠️ [Home] Trakt Continue Watching failed: \(error)")
                guard let self, generation == self.continueWatchingPublishGeneration else { return }
                self.applyContinueWatching(primary)
            }
        }
    }

    private func applyContinueWatching(_ items: [MediaItem]) {
        let visible = items.filter { !continueWatchingPendingRemovalIds.contains($0.id) }
        let isUnchanged = visible.map { [TraktContinueWatchingService.rowKey(for: $0), String($0.viewOffset ?? -1)] }
            == continueWatchingItems.map { [TraktContinueWatchingService.rowKey(for: $0), String($0.viewOffset ?? -1)] }
        if !isUnchanged { continueWatchingItems = visible }
        continueWatchingState = visible.isEmpty ? .empty : .loaded
        registerContinueWatchingRow()
        offerDefaultHero(visible)
        resolvePreferredHero()
    }

    /// Reloads the row after the Source setting or Trakt progress changed.
    func reloadContinueWatchingSources() async {
        await TraktContinueWatchingService.shared.invalidate()
        await refreshContinueWatching()
    }

    // MARK: - Group Bookkeeping

    private func loadPlexContinueWatching() async {
        do {
            let data = try await fetchContinueWatching()
            publishContinueWatching(primary: data, showPrimaryFirst: true)
            print("✅ [Home] Continue Watching loaded: \(data.count) items")
        } catch {
            print("⚠️ [Home] Continue Watching failed: \(error)")
            continueWatchingState = .error(error.localizedDescription)
        }
    }

    /// One row group of the current load finished.
    private func finishGroup() {
        pendingGroupCount = max(0, pendingGroupCount - 1)
        resolvePreferredHero()
        guard pendingGroupCount == 0 else { return }

        isInitialLoadComplete = true
        let watchlistInFlight = onDemandWatchlistRequested && onDemandWatchlistItems == nil
        if !preferredHeroSettled && !watchlistInFlight {
            settleHeroWithFallback()
        }
        if billboardItems.isEmpty && preferredHeroSettled {
            heroState = .empty
        }
        evaluateTotalFailure()
    }

    private func registerRows(_ descriptors: [HomeRowDescriptor], group: HomeRowGroup) {
        HomeRowsStore.shared.register(descriptors, group: group)
    }

    private func registerContinueWatchingRow() {
        registerRows([
            HomeRowDescriptor(
                id: homeContinueWatchingRowId,
                defaultTitle: String(localized: "Continue Watching"),
                kind: .continueWatching,
                group: .continueWatching
            )
        ], group: .continueWatching)
    }

    private func registerRecentlyAddedRows() {
        registerRows(recentlyAddedSections.map {
            HomeRowDescriptor(id: $0.id, defaultTitle: $0.title, kind: .recentlyAdded, group: .recentlyAdded)
        }, group: .recentlyAdded)
        resolvePreferredHero()
    }

    // MARK: - Hero Source

    /// Fills the hero from a default source, unless a source picked in settings
    /// is still loading.
    private func offerDefaultHero(_ items: [MediaItem]) {
        guard billboardItems.isEmpty, !items.isEmpty, preferredHeroSettled else { return }
        setHero(items)
    }

    private func setHero(_ items: [MediaItem]) {
        stopBillboardRotation()
        currentBillboardIndex = 0
        billboardItems = normalizeForHero(Array(items.prefix(5)))
        heroState = .loaded
        startBillboardRotation()
    }

    /// Prefers items with backdrop art so the billboard isn't a flat poster crop.
    private func preferringArt(_ items: [MediaItem]) -> [MediaItem] {
        let withArt = items.filter { $0.art?.isEmpty == false || $0.grandparentArt?.isEmpty == false }
        return withArt.isEmpty ? items : withArt
    }

    /// Items for a hero source; nil when its row isn't available.
    private func itemsForHeroSource(_ source: HomeHeroSource) -> [MediaItem]? {
        switch source {
        case .automatic:
            return nil
        case .continueWatching:
            return continueWatchingItems
        case .myList:
            return extraSections.first { $0.id == homeWatchlistRowId }?.items ?? onDemandWatchlistItems
        case .row(let id):
            if id == homeContinueWatchingRowId { return continueWatchingItems }
            return (recentlyAddedSections + collectionSections + extraSections).first { $0.id == id }?.items
        }
    }

    /// Whether the loader that feeds a hero source has finished.
    private func isHeroSourceSettled(_ source: HomeHeroSource) -> Bool {
        func settled(_ state: SectionLoadState) -> Bool { state != .idle && !state.isLoading }
        switch source {
        case .automatic:
            return true
        case .continueWatching:
            return settled(continueWatchingState)
        case .myList:
            return settled(extraSectionsState)
        case .row(let id):
            if id == homeContinueWatchingRowId { return settled(continueWatchingState) }
            if id.hasPrefix("recently-added-") { return settled(recentlyAddedPerLibraryState) }
            if id.hasPrefix("collection-") { return settled(collectionSectionsState) }
            return settled(extraSectionsState)
        }
    }

    /// What the hero shows with the default source.
    private func defaultHeroCandidates() -> [MediaItem]? {
        for candidate in [continueWatchingItems, onDeckItems, recentlyAddedItems] where !candidate.isEmpty {
            return candidate
        }
        let section = extraSections.first { $0.items.contains { $0.art?.isEmpty == false } }
        let items = section?.items.filter { $0.art?.isEmpty == false } ?? []
        return items.isEmpty ? nil : items
    }

    /// Tries the hero source picked in settings; called as row groups finish.
    private func resolvePreferredHero() {
        guard !preferredHeroSettled else { return }
        let source = HomeRowsStore.shared.heroSource
        if source == .automatic {
            preferredHeroSettled = true
            return
        }
        if let items = itemsForHeroSource(source), !items.isEmpty {
            preferredHeroSettled = true
            setHero(preferringArt(items))
            return
        }
        guard isHeroSourceSettled(source) else { return }
        if source == .myList, onDemandWatchlistItems == nil {
            requestWatchlistForHero()
            return
        }
        settleHeroWithFallback()
    }

    /// The chosen source is empty: fall back to the default.
    private func settleHeroWithFallback() {
        preferredHeroSettled = true
        guard billboardItems.isEmpty else { return }
        if let items = defaultHeroCandidates() {
            setHero(items)
        } else if pendingGroupCount == 0 {
            heroState = .empty
        }
    }

    /// The watchlist row can be off or hidden while My List feeds the hero.
    private func requestWatchlistForHero() {
        guard !onDemandWatchlistRequested else { return }
        onDemandWatchlistRequested = true
        Task { @MainActor in
            let section = await self.fetchPlexTvWatchlistSection()
            self.onDemandWatchlistItems = section?.items ?? []
            self.resolvePreferredHero()
        }
    }

    /// The hero source was changed in settings while Home is alive.
    func applyHeroSourceChange() {
        let source = HomeRowsStore.shared.heroSource
        preferredHeroSettled = false

        if let items = itemsForHeroSource(source), !items.isEmpty {
            preferredHeroSettled = true
            setHero(preferringArt(items))
            return
        }
        let watchlistPending = source == .myList && onDemandWatchlistItems == nil
        if isHeroSourceSettled(source) && !watchlistPending {
            preferredHeroSettled = true
            if let items = defaultHeroCandidates() { setHero(items) }
            return
        }
        resolvePreferredHero()
    }

    // MARK: - Failures and Retry

    /// Something failed to load (a group or a single row).
    var hasRowFailures: Bool {
        !rowFailureMessages.isEmpty
    }

    private var rowFailureMessages: [String] {
        var messages: [String] = []
        for state in [continueWatchingState, recentlyAddedPerLibraryState, collectionSectionsState] {
            if case .error(let message) = state { messages.append(message) }
        }
        messages.append(contentsOf: extraSlots.compactMap { $0.failure?.message })
        return messages
    }

    /// Nothing at all to show on the page.
    var hasNoContent: Bool {
        continueWatchingItems.isEmpty
            && recentlyAddedSections.isEmpty
            && collectionSections.isEmpty
            && extraSections.isEmpty
            && billboardItems.isEmpty
    }

    /// The full-page error is only for total failure: every source failed and
    /// nothing loaded while the network is up. Offline has its own card.
    private func evaluateTotalFailure() {
        guard hasNoContent, NetworkMonitor.shared.isOnline, let first = rowFailureMessages.first else { return }
        error = first
    }

    /// Re-fetches the discovery / catalog rows after their settings or addons changed.
    func reloadExtraRows() {
        guard extraSectionsState != .idle, !extraSectionsState.isLoading else { return }
        Task { @MainActor in
            await self.loadAdditionalRows()
            self.seedBillboardFromExtraSections()
        }
    }

    /// Retries a failed row from its error card. The rest of the page stays put.
    func retry(_ failure: HomeRowFailure) {
        guard !retryingRowIds.contains(failure.id) else { return }
        retryingRowIds.insert(failure.id)
        Task { @MainActor in
            defer { self.retryingRowIds.remove(failure.id) }
            switch failure.retry {
            case .continueWatching:
                if self.isStremioOnly {
                    await self.loadLocalContinueWatching()
                } else {
                    await self.loadPlexContinueWatching()
                }
            case .recentlyAdded:
                await self.refreshRecentlyAddedSections()
            case .collections:
                await self.loadCollectionRows()
            case .extras:
                await self.loadAdditionalRows()
                self.seedBillboardFromExtraSections()
            case .stremioCatalog(let ref):
                let slot = await Self.fetchStremioCatalogSlot(ref)
                var slots = self.extraSlots
                if let index = slots.firstIndex(where: { $0.id == failure.id }) {
                    if let slot {
                        slots[index] = slot
                    } else {
                        slots.remove(at: index)
                    }
                    self.setExtraSlots(slots)
                }
            }
        }
    }

    // MARK: - Refresh

    func refresh() async {
        await loadHomeScreen()
    }

    /// Refresh only the Recently Added per-library sections (used when grouping setting changes)
    func refreshRecentlyAddedSections() async {
        print("🔄 [Home] Refreshing Recently Added sections...")
        recentlyAddedPerLibraryState = .loading
        do {
            // Bypass cache to get fresh data after setting change
            let sections = try await fetchRecentlyAddedPerLibrary(bypassCache: true)
            recentlyAddedSections = sections
            recentlyAddedPerLibraryState = sections.isEmpty ? .empty : .loaded
            registerRecentlyAddedRows()
            print("✅ [Home] Recently Added sections refreshed: \(sections.count) sections")
        } catch {
            print("⚠️ [Home] Recently Added refresh failed: \(error)")
            recentlyAddedPerLibraryState = .error(error.localizedDescription)
        }
    }

    // MARK: - Additional Sections

    private func loadAdditionalRows() async {
        if isStremioOnly {
            await loadStremioAdditionalRows()
            return
        }

        // Gather. The Rows Settings group toggles apply in Plex mode too.
        let settings = UserDefaults.standard
        var all: [String: HomeRowSlot] = [:]
        var genres: [LibrarySection] = []
        var trakt: [String: HomeRowSlot] = [:]

        // TMDB: Popular on Plex / Trending Now
        if settings.showPlexPopular || settings.showTrendingRows {
            do {
                let (popular, trending) = try await fetchTMDBTrendingTVSections()
                if settings.showPlexPopular, let p = popular.first { all[String(localized: "Popular on Plex")] = .section(p) }
                if settings.showTrendingRows, let t = trending.first { all[String(localized: "Trending Now")] = .section(t) }
            } catch {
                print("⚠️ [Home] TMDB trending failed: \(error)")
                let failure = HomeRowFailure(
                    id: settings.showPlexPopular ? "tmdb-popular" : "tmdb-trending",
                    title: settings.showPlexPopular ? String(localized: "Popular on Plex") : String(localized: "Trending Now"),
                    source: "TMDB",
                    message: error.localizedDescription,
                    retry: .extras
                )
                all[failure.title] = .failure(failure)
            }
        }

        // Plex.tv Watchlist
        if settings.showWatchlist, let wl = await fetchPlexTvWatchlistSection() { all[String(localized: "Watchlist")] = .section(wl) }

        // Genres
        do { genres = try await fetchGenreSections() } catch { print("⚠️ [Home] Genre sections failed: \(error)") }

        // Trakt
        if settings.showTraktRows {
            for slot in await fetchTraktSections() { trakt[slot.title] = slot }
        }

        // Order exactly as requested
        var ordered: [HomeRowSlot] = []
        func push(_ title: String) { if let s = all[title] { ordered.append(s) } }
        push(String(localized: "Popular on Plex"))
        // Continue Watching is rendered separately with its own card style
        push(String(localized: "Trending Now"))
        push(String(localized: "Watchlist"))

        // Specific genre labels in desired order
        let desiredGenres = [
            String(localized: "TV Shows - Children"),
            String(localized: "Movie - Music"),
            String(localized: "Movies - Documentary"),
            String(localized: "Movies - History"),
            String(localized: "TV Shows - Reality"),
            String(localized: "Movies - Drama"),
            String(localized: "TV Shows - Suspense"),
            String(localized: "Movies - Animation"),
        ]
        for label in desiredGenres {
            if let g = genres.first(where: { $0.title == label }) { ordered.append(.section(g)) }
        }

        // Trakt: Trending Movies, Trending TV Shows, Your Watchlist, Recently Watched, Recommended, Popular TV Shows
        let desiredTrakt = [
            String(localized: "Trending Movies on Trakt"),
            String(localized: "Trending TV Shows on Trakt"),
            String(localized: "Your Trakt Watchlist"),
            String(localized: "Recently Watched"),
            String(localized: "Recommended for You"),
            String(localized: "Popular TV Shows on Trakt"),
        ]
        for label in desiredTrakt { if let s = trakt[label] { ordered.append(s) } }

        print("✅ [Home] Extra sections prepared: \(ordered.map { $0.title }.joined(separator: ", "))")
        setExtraSlots(ordered)
    }

    /// Publishes the extra rows and records them for Rows Settings.
    private func setExtraSlots(_ slots: [HomeRowSlot]) {
        extraSlots = slots
        extraSectionsState = slots.isEmpty ? .empty : .loaded
        // Only replace the known rows when something loaded, so a fully
        // failed (e.g. offline) load doesn't wipe them from Rows Settings.
        if slots.contains(where: { $0.section != nil }) {
            registerRows(slots.map(descriptor(for:)), group: .extras)
        }
        resolvePreferredHero()
    }

    // MARK: - Collection Rows

    private func loadCollectionRows() async {
        // Check if collections are enabled in settings
        guard UserDefaults.standard.showCollectionRows else {
            await MainActor.run {
                self.collectionSections = []
                self.collectionSectionsState = .empty
                self.registerRows([], group: .collections)
                self.resolvePreferredHero()
            }
            return
        }

        guard let plexServer = FlixorCore.shared.plexServer else {
            await MainActor.run {
                self.collectionSections = []
                self.collectionSectionsState = .empty
                self.registerRows([], group: .collections)
                self.resolvePreferredHero()
            }
            return
        }

        do {
            let collections = try await plexServer.getAllCollections()

            // Get hidden collection keys from settings
            let hiddenKeys = Set(UserDefaults.standard.hiddenCollectionKeys)

            // Sort by childCount descending and filter out hidden collections
            let sortedCollections = collections
                .filter { !hiddenKeys.contains($0.ratingKey) }
                .sorted { ($0.childCount ?? 0) > ($1.childCount ?? 0) }

            // Fetch 10 collections but only show 5 (in case some are hidden)
            let limitedCollections = Array(sortedCollections.prefix(10))

            var sections: [LibrarySection] = []

            for collection in limitedCollections.prefix(5) {
                do {
                    let items = try await plexServer.getCollectionItems(ratingKey: collection.ratingKey, size: 15)
                    if !items.isEmpty {
                        let mediaItems = items.map { toMediaItem($0) }
                        sections.append(LibrarySection(
                            id: "collection-\(collection.ratingKey)",
                            title: collection.title ?? String(localized: "Untitled Collection"),
                            items: mediaItems,
                            totalCount: collection.childCount ?? items.count,
                            libraryKey: nil,
                            browseContext: .plexCollection(ratingKey: collection.ratingKey, title: collection.title ?? String(localized: "Collection")),
                            isCollection: true
                        ))
                    }
                } catch {
                    // Continue with other collections
                }
            }

            await MainActor.run {
                self.collectionSections = sections
                self.collectionSectionsState = sections.isEmpty ? .empty : .loaded
                self.registerRows(sections.map {
                    HomeRowDescriptor(id: $0.id, defaultTitle: $0.title, kind: .collection, group: .collections)
                }, group: .collections)
                self.resolvePreferredHero()
            }
        } catch {
            await MainActor.run {
                self.collectionSections = []
                self.collectionSectionsState = .error(error.localizedDescription)
            }
        }
    }

    // MARK: - Helpers

    private func normalizeForHero(_ items: [MediaItem]) -> [MediaItem] {
        return items.map { m in
            if m.id.hasPrefix("plex:") || m.id.hasPrefix("tmdb:") { return m }
            return MediaItem(
                id: "plex:\(m.id)",
                title: m.title,
                type: m.type,
                thumb: m.thumb,
                art: m.art,
                year: m.year,
                rating: m.rating,
                duration: m.duration,
                viewOffset: m.viewOffset,
                summary: m.summary,
                grandparentTitle: m.grandparentTitle,
                grandparentThumb: m.grandparentThumb,
                grandparentArt: m.grandparentArt,
                grandparentRatingKey: m.grandparentRatingKey,
                parentIndex: m.parentIndex,
                index: m.index,
                parentRatingKey: m.parentRatingKey,
                parentTitle: m.parentTitle,
                leafCount: m.leafCount,
                viewedLeafCount: m.viewedLeafCount
            )
        }
    }

    // MARK: - Convert PlexMediaItem to MediaItem

    private func toMediaItem(_ plex: FlixorKit.PlexMediaItem) -> MediaItem {
        return MediaItem(
            id: plex.ratingKey ?? plex.key ?? "",
            title: plex.title ?? String(localized: "Unknown"),
            type: plex.type ?? "unknown",
            thumb: plex.thumb,
            art: plex.art,
            year: plex.year,
            rating: plex.viewCount.map { Double($0) },
            duration: plex.duration,
            viewOffset: plex.viewOffset,
            summary: plex.summary,
            grandparentTitle: plex.grandparentTitle,
            grandparentThumb: plex.grandparentThumb,
            grandparentArt: plex.grandparentArt,
            grandparentRatingKey: plex.grandparentRatingKey,
            parentIndex: plex.parentIndex,
            index: plex.index,
            parentRatingKey: plex.parentRatingKey,
            parentTitle: plex.parentTitle,
            leafCount: plex.leafCount,
            viewedLeafCount: plex.viewedLeafCount,
            media: plex.Media
        )
    }

    // MARK: - Stremio-Only Discovery Rows

    /// Genre rows for standalone mode, replacing the Plex-library genre rows.
    /// Ids are TMDB genre ids.
    private static let stremioGenreRows: [(title: String, media: TMDBMediaType, genreId: String)] = [
        (String(localized: "Action Movies"), .movie, "28"),
        (String(localized: "Comedy Movies"), .movie, "35"),
        (String(localized: "Sci-Fi & Fantasy Shows"), .tv, "10765"),
        (String(localized: "Thriller Movies"), .movie, "53"),
        (String(localized: "Animated Shows"), .tv, "16"),
        (String(localized: "Documentaries"), .movie, "99"),
    ]

    private func loadStremioAdditionalRows() async {
        var ordered: [HomeRowSlot] = []
        let settings = UserDefaults.standard

        // Addon catalogs first when present - they're the user's own configured
        // sources, so they outrank generic TMDB discovery.
        if settings.showStremioCatalogRows {
            ordered.append(contentsOf: await fetchStremioCatalogSections())
        }

        // Trending is the headline row and also seeds the hero, so it goes first.
        if settings.showTrendingRows {
            if let s = await fetchTMDBListSection(
                id: "tmdb-trending-movies", title: String(localized: "Trending Movies"),
                media: .movie, kind: .trending
            ) { ordered.append(s) }
            if let s = await fetchTMDBListSection(
                id: "tmdb-trending-tv", title: String(localized: "Trending TV Shows"),
                media: .tv, kind: .trending
            ) { ordered.append(s) }
        }

        // Watchlist: the Plex.tv half is skipped automatically when plexTv is nil,
        // so this is the Trakt watchlist (plus local entries once Phase 3 lands).
        if settings.showWatchlist, let wl = await fetchPlexTvWatchlistSection() {
            ordered.append(.section(wl))
        }

        if settings.showPlexPopular {
            if let s = await fetchTMDBListSection(
                id: "tmdb-popular-movies", title: String(localized: "Popular Movies"),
                media: .movie, kind: .popular
            ) { ordered.append(s) }
            if let s = await fetchTMDBListSection(
                id: "tmdb-popular-tv", title: String(localized: "Popular TV Shows"),
                media: .tv, kind: .popular
            ) { ordered.append(s) }
        }

        for row in Self.stremioGenreRows {
            if let s = await fetchTMDBListSection(
                id: "tmdb-genre-\(row.media.rawValue)-\(row.genreId)",
                title: row.title,
                media: row.media,
                kind: .genre,
                genreId: row.genreId
            ) { ordered.append(s) }
        }

        if let s = await fetchTMDBListSection(
            id: "tmdb-top-rated-movies", title: String(localized: "Top Rated Movies"),
            media: .movie, kind: .topRated
        ) { ordered.append(s) }

        if let s = await fetchTMDBListSection(
            id: "tmdb-upcoming", title: String(localized: "Coming Soon"),
            media: .movie, kind: .upcoming
        ) { ordered.append(s) }

        // Trakt rows require a linked account; they no-op otherwise.
        if settings.showTraktRows {
            let traktSections = await fetchTraktSections()
            let desiredTrakt = [
                String(localized: "Trending Movies on Trakt"),
                String(localized: "Trending TV Shows on Trakt"),
                String(localized: "Your Trakt Watchlist"),
                String(localized: "Recently Watched"),
                String(localized: "Recommended for You"),
                String(localized: "Popular TV Shows on Trakt"),
            ]
            for label in desiredTrakt {
                if let s = traktSections.first(where: { $0.title == label }) { ordered.append(s) }
            }
        }

        print("✅ [Home] Stremio sections prepared: \(ordered.map { $0.title }.joined(separator: ", "))")
        setExtraSlots(ordered)
    }

    /// One row per browsable catalog advertised by the installed Stremio addons.
    /// Rows are fetched concurrently but keep the addon priority order.
    private func fetchStremioCatalogSections(maxRows: Int = 8) async -> [HomeRowSlot] {
        let catalogs = await StremioService.shared.getBrowsableCatalogs()
        guard !catalogs.isEmpty else { return [] }

        let selected = Array(catalogs.prefix(maxRows))
        if catalogs.count > maxRows {
            print("ℹ️ [Home] \(catalogs.count) catalogs available, showing first \(maxRows)")
        }

        var byIndex: [Int: HomeRowSlot] = [:]
        await withTaskGroup(of: (Int, HomeRowSlot?).self) { group in
            for (index, entry) in selected.enumerated() {
                let ref = StremioCatalogRef(
                    entryId: entry.id,
                    installationId: entry.installationId,
                    type: entry.catalog.type,
                    catalogId: entry.catalog.catalogId,
                    displayName: entry.catalog.displayName,
                    addonName: entry.addonName
                )
                group.addTask {
                    (index, await Self.fetchStremioCatalogSlot(ref))
                }
            }
            for await (index, slot) in group {
                if let slot { byIndex[index] = slot }
            }
        }

        let sections = selected.indices.compactMap { byIndex[$0] }
        for entry in selected {
            catalogAddonNames["stremio-catalog-\(entry.id)"] = entry.addonName
        }
        print("✅ [Home] Stremio catalog rows: \(sections.count)")
        return sections
    }

    /// One catalog row: the loaded row, a failure card when the addon request
    /// failed, or nil when the catalog is simply empty.
    nonisolated private static func fetchStremioCatalogSlot(_ ref: StremioCatalogRef) async -> HomeRowSlot? {
        let rowId = "stremio-catalog-\(ref.entryId)"
        let previews: [StremioMetaPreview]
        do {
            previews = try await StremioService.shared.fetchCatalog(
                installationId: ref.installationId,
                type: ref.type,
                catalogId: ref.catalogId,
                limit: 20
            )
        } catch {
            return .failure(HomeRowFailure(
                id: rowId,
                title: ref.displayName,
                source: ref.addonName,
                message: error.localizedDescription,
                retry: .stremioCatalog(ref)
            ))
        }
        guard !previews.isEmpty else { return nil }

        let items = await StremioCatalogMapper.shared.mediaItems(from: previews)
        guard !items.isEmpty else { return nil }

        return .section(LibrarySection(
            id: rowId,
            // Addon name is not part of the title; it is shown as a
            // caption only when two rows would share a title.
            title: ref.displayName,
            items: items,
            totalCount: items.count,
            libraryKey: nil,
            // No browse context: paging a catalog needs the `skip` extra,
            // which the browse modal doesn't model yet.
            browseContext: nil
        ))
    }

    /// Fetches one TMDB list and wraps it in a LibrarySection whose browse context
    /// matches, so "Browse all" paginates the same list.
    private func fetchTMDBListSection(
        id: String,
        title: String,
        media: TMDBMediaType,
        kind: TMDBBrowseKind,
        genreId: String? = nil
    ) async -> HomeRowSlot? {
        do {
            let tmdb = FlixorCore.shared.tmdb
            let response: TMDBResultsResponse
            switch kind {
            case .trending:
                response = media == .movie
                    ? try await tmdb.getTrendingMovies(timeWindow: "week")
                    : try await tmdb.getTrendingTV(timeWindow: "week")
            case .popular:
                response = media == .movie
                    ? try await tmdb.getPopularMovies()
                    : try await tmdb.getPopularTV()
            case .topRated:
                response = media == .movie
                    ? try await tmdb.getTopRatedMovies()
                    : try await tmdb.getTopRatedTV()
            case .upcoming:
                response = try await tmdb.getUpcomingMovies()
            case .genre:
                guard let genreId else { return nil }
                response = media == .movie
                    ? try await tmdb.discoverMovies(withGenres: genreId)
                    : try await tmdb.discoverTV(withGenres: genreId)
            case .recommendations, .similar:
                return nil
            }

            let items = response.results.prefix(20).map { makeTMDBMediaItem($0, media: media) }
            guard !items.isEmpty else { return nil }

            return .section(LibrarySection(
                id: id,
                title: title,
                items: Array(items),
                totalCount: response.totalResults ?? items.count,
                libraryKey: nil,
                browseContext: .tmdb(kind: kind, media: media, id: genreId, displayTitle: title)
            ))
        } catch {
            print("⚠️ [Home] TMDB row '\(title)' failed: \(error)")
            return .failure(HomeRowFailure(id: id, title: title, source: "TMDB", message: error.localizedDescription, retry: .extras))
        }
    }

    private func makeTMDBMediaItem(_ r: TMDBMedia, media: TMDBMediaType) -> MediaItem {
        let dateString = media == .movie ? r.releaseDate : r.firstAirDate
        let year = dateString.flatMap { Int($0.prefix(4)) }

        return MediaItem(
            id: "tmdb:\(media.rawValue):\(r.id)",
            title: r.title ?? r.name ?? "",
            type: media == .movie ? "movie" : "show",
            thumb: FlixorCore.shared.tmdb.getPosterUrl(path: r.posterPath, size: "w500"),
            art: FlixorCore.shared.tmdb.getBackdropUrl(path: r.backdropPath, size: "original"),
            year: year,
            rating: r.voteAverage,
            duration: nil,
            viewOffset: nil,
            summary: r.overview,
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
    }

    // MARK: - TMDB Trending (TV)

    private func fetchTMDBTrendingTVSections() async throws -> ([LibrarySection], [LibrarySection]) {
        print("📦 [Home] Fetching TMDB trending TV (week)...")
        let response = try await FlixorCore.shared.tmdb.getTrendingTV(timeWindow: "week")
        let items = response.results.prefix(16)

        var mapped: [MediaItem] = []
        for r in items {
            let title = r.name ?? r.title ?? ""
            let art = FlixorCore.shared.tmdb.getBackdropUrl(path: r.backdropPath, size: "original")
            let thumb = FlixorCore.shared.tmdb.getPosterUrl(path: r.posterPath, size: "w500")
            let m = MediaItem(
                id: "tmdb:tv:\(r.id)",
                title: title,
                type: "show",
                thumb: thumb,
                art: art,
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
            mapped.append(m)
        }
        let first = Array(mapped.prefix(8))
        let second = Array(mapped.dropFirst(8).prefix(8))
        let popular = LibrarySection(
            id: "tmdb-popular",
            title: String(localized: "Popular on Plex"),
            items: first,
            totalCount: first.count,
            libraryKey: nil,
            browseContext: .tmdb(kind: .trending, media: .tv, id: nil, displayTitle: String(localized: "Popular on Plex"))
        )
        let trending = LibrarySection(
            id: "tmdb-trending",
            title: String(localized: "Trending Now"),
            items: second,
            totalCount: second.count,
            libraryKey: nil,
            browseContext: .tmdb(kind: .trending, media: .tv, id: nil, displayTitle: String(localized: "Trending Now"))
        )
        return ([popular], [trending])
    }

    // MARK: - Combined Watchlist (Plex + Trakt)

    private func fetchPlexTvWatchlistSection() async -> LibrarySection? {
        var allItems: [String: MediaItem] = [:] // Use dict to dedupe by ID

        // Fetch Plex.tv watchlist
        if let plexTv = FlixorCore.shared.plexTv {
            do {
                print("📦 [Home] Fetching Plex.tv watchlist...")
                let meta = try await plexTv.getWatchlist()

                for m in meta.prefix(20) {
                    let mediaType = (m.type ?? "show") == "movie" ? "movie" : "show"

                    // Try to extract TMDB ID from Plex GUIDs array
                    var itemId: String
                    var tmdbIdFound: String?
                    for guidStr in m.guids {
                        if let tmdbId = extractTMDBId(from: guidStr) {
                            tmdbIdFound = tmdbId
                            break
                        }
                    }

                    if let tmdbId = tmdbIdFound {
                        itemId = "tmdb:\(mediaType):\(tmdbId)"
                        print("✅ [Home Watchlist] Plex item \(m.title ?? "Unknown") using TMDB ID: \(itemId)")
                    } else if m.key != nil {
                        // Fallback: try to resolve TMDB ID via PlexTv metadata lookup
                        // Note: getTMDBIdForWatchlistItem returns full ID like "tmdb:movie:123"
                        if let fullTmdbId = await plexTv.getTMDBIdForWatchlistItem(m) {
                            itemId = fullTmdbId
                            print("✅ [Home Watchlist] Plex item \(m.title ?? "Unknown") resolved TMDB ID via metadata: \(itemId)")
                        } else if let ratingKey = m.ratingKey {
                            itemId = "plex:\(ratingKey)"
                            print("⚠️ [Home Watchlist] Plex item \(m.title ?? "Unknown") using Plex rating key")
                        } else {
                            continue
                        }
                    } else if let ratingKey = m.ratingKey {
                        itemId = "plex:\(ratingKey)"
                        print("⚠️ [Home Watchlist] Plex item \(m.title ?? "Unknown") using Plex rating key (no key)")
                    } else {
                        continue
                    }

                    let item = MediaItem(
                        id: itemId,
                        title: m.title ?? String(localized: "Unknown"),
                        type: mediaType,
                        thumb: m.thumb,
                        art: m.art,
                        year: m.year,
                        rating: nil,
                        duration: m.duration,
                        viewOffset: m.viewOffset,
                        summary: m.summary,
                        grandparentTitle: m.grandparentTitle,
                        grandparentThumb: m.grandparentThumb,
                        grandparentArt: m.grandparentArt,
                        grandparentRatingKey: m.grandparentRatingKey,
                        parentIndex: m.parentIndex,
                        index: m.index,
                        parentRatingKey: m.parentRatingKey,
                        parentTitle: m.parentTitle,
                        leafCount: m.leafCount,
                        viewedLeafCount: m.viewedLeafCount
                    )
                    allItems[itemId] = item
                }
                print("✅ [Home] Plex watchlist loaded: \(meta.count) items")
            } catch {
                print("⚠️ [Home] Plex.tv watchlist failed: \(error)")
            }
        }

        // Fetch Trakt watchlist if authenticated
        let trakt = FlixorCore.shared.trakt
        if trakt.isAuthenticated {
            do {
                print("📦 [Home] Fetching Trakt watchlist...")
                let watchlist = try await trakt.getWatchlist()

                for wlItem in watchlist.prefix(20) {
                    if let movie = wlItem.movie, let tmdbId = movie.ids.tmdb {
                        let itemId = "tmdb:movie:\(tmdbId)"
                        if allItems[itemId] == nil { // Don't overwrite Plex items (they may have more metadata)
                            let backdrop = await fetchTMDBBackdrop(mediaType: "movie", id: tmdbId)
                            let poster = await fetchTMDBPoster(mediaType: "movie", id: tmdbId)
                            let item = MediaItem(
                                id: itemId,
                                title: movie.title,
                                type: "movie",
                                thumb: poster,
                                art: backdrop,
                                year: movie.year,
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
                            allItems[itemId] = item
                            print("✅ [Home Watchlist] Trakt movie \(movie.title) added: \(itemId)")
                        }
                    } else if let show = wlItem.show, let tmdbId = show.ids.tmdb {
                        let itemId = "tmdb:tv:\(tmdbId)"
                        if allItems[itemId] == nil {
                            let backdrop = await fetchTMDBBackdrop(mediaType: "tv", id: tmdbId)
                            let poster = await fetchTMDBPoster(mediaType: "tv", id: tmdbId)
                            let item = MediaItem(
                                id: itemId,
                                title: show.title,
                                type: "show",
                                thumb: poster,
                                art: backdrop,
                                year: show.year,
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
                            allItems[itemId] = item
                            print("✅ [Home Watchlist] Trakt show \(show.title) added: \(itemId)")
                        }
                    }
                }
                print("✅ [Home] Trakt watchlist loaded")
            } catch {
                print("⚠️ [Home] Trakt watchlist failed: \(error)")
            }
        }

        let items = Array(allItems.values)
        if items.isEmpty { return nil }

        return LibrarySection(
            id: "combined-watchlist",
            title: String(localized: "Watchlist"),
            items: Array(items.prefix(12)),
            totalCount: items.count,
            libraryKey: nil,
            browseContext: .plexWatchlist
        )
    }

    private func fetchTMDBPoster(mediaType: String, id: Int) async -> String? {
        do {
            if mediaType == "movie" {
                let detail = try await FlixorCore.shared.tmdb.getMovieDetails(id: id)
                return FlixorCore.shared.tmdb.getPosterUrl(path: detail.posterPath, size: "w500")
            } else {
                let detail = try await FlixorCore.shared.tmdb.getTVDetails(id: id)
                return FlixorCore.shared.tmdb.getPosterUrl(path: detail.posterPath, size: "w500")
            }
        } catch {
            return nil
        }
    }

    private func extractTMDBId(from guid: String) -> String? {
        // Extract digits from tmdb://... or themoviedb://...
        let prefixes = ["tmdb://", "themoviedb://"]
        for p in prefixes {
            if let range = guid.range(of: p) {
                let tail = String(guid[range.upperBound...])
                let digits = String(tail.filter { $0.isNumber })
                if digits.count >= 3 { return digits }
            }
        }
        return nil
    }

    // MARK: - Plex Genre Sections

    private func fetchGenreSections() async throws -> [LibrarySection] {
        guard let plexServer = FlixorCore.shared.plexServer else { return [] }

        let genreRows: [(label: String, type: String, genre: String)] = [
            (String(localized: "TV Shows - Children"), "show", "Children"),
            (String(localized: "Movie - Music"), "movie", "Music"),
            (String(localized: "Movies - Documentary"), "movie", "Documentary"),
            (String(localized: "Movies - History"), "movie", "History"),
            (String(localized: "TV Shows - Reality"), "show", "Reality"),
            (String(localized: "Movies - Drama"), "movie", "Drama"),
            (String(localized: "TV Shows - Suspense"), "show", "Suspense"),
            (String(localized: "Movies - Animation"), "movie", "Animation"),
        ]

        print("📦 [Home] Fetching libraries for genre rows...")
        let libraries = try await plexServer.getLibraries()

        // Only use libraries that are enabled in settings
        let enabledLibs = libraries.filter { isLibraryEnabled($0.key) }
        let movieLib = enabledLibs.first { $0.type == "movie" }
        let showLib = enabledLibs.first { $0.type == "show" }

        var out: [LibrarySection] = []
        for spec in genreRows {
            let lib = (spec.type == "movie") ? movieLib : showLib
            guard let libKey = lib?.key else { continue }
            do {
                // Fetch items with genre filter
                let plexItems = try await plexServer.getLibraryItems(key: libKey, limit: 20, genre: spec.genre)
                let items = plexItems.map { toMediaItem($0) }
                if !items.isEmpty {
                    out.append(LibrarySection(
                        id: "genre-\(spec.genre.lowercased())",
                        title: spec.label,
                        items: Array(items.prefix(12)),
                        totalCount: items.count,
                        libraryKey: libKey,
                        browseContext: .plexDirectory(path: "/library/sections/\(libKey)/all?genre=\(spec.genre)", title: spec.label)
                    ))
                }
            } catch {
                print("⚠️ [Home] Genre fetch failed for \(spec.label): \(error)")
            }
        }
        return out
    }

    // MARK: - Trakt Sections

    /// Trakt rows; a row that fails becomes a failure slot under its own id and title.
    private func fetchTraktSections() async -> [HomeRowSlot] {
        var sections: [HomeRowSlot] = []
        let trakt = FlixorCore.shared.trakt

        func fail(_ id: String, _ title: String, _ error: Error) {
            print("⚠️ [Home] Trakt row '\(title)' failed: \(error)")
            sections.append(.failure(HomeRowFailure(id: id, title: title, source: "Trakt", message: error.localizedDescription, retry: .extras)))
        }

        // Trending Movies (public)
        do {
            let trendingMovies = try await trakt.getTrendingMovies(limit: 12)
            let items = await mapTraktMoviesToMediaItems(trendingMovies.map { $0.movie })
            if !items.isEmpty {
                sections.append(.section(LibrarySection(
                    id: "trakt-trending-movies",
                    title: String(localized: "Trending Movies on Trakt"),
                    items: items,
                    totalCount: items.count,
                    libraryKey: nil,
                    browseContext: .trakt(kind: .trendingMovies)
                )))
            }
        } catch { fail("trakt-trending-movies", String(localized: "Trending Movies on Trakt"), error) }

        // Trending TV Shows (public)
        do {
            let trendingShows = try await trakt.getTrendingShows(limit: 12)
            let items = await mapTraktShowsToMediaItems(trendingShows.map { $0.show })
            if !items.isEmpty {
                sections.append(.section(LibrarySection(
                    id: "trakt-trending-shows",
                    title: String(localized: "Trending TV Shows on Trakt"),
                    items: items,
                    totalCount: items.count,
                    libraryKey: nil,
                    browseContext: .trakt(kind: .trendingShows)
                )))
            }
        } catch { fail("trakt-trending-shows", String(localized: "Trending TV Shows on Trakt"), error) }

        // Your Trakt Watchlist (auth)
        if trakt.isAuthenticated {
            do {
                let watchlist = try await trakt.getWatchlist()
                var items: [MediaItem] = []
                for wlItem in watchlist.prefix(12) {
                    if let movie = wlItem.movie {
                        if let item = await mapTraktMovieToMediaItem(movie) {
                            items.append(item)
                        }
                    } else if let show = wlItem.show {
                        if let item = await mapTraktShowToMediaItem(show) {
                            items.append(item)
                        }
                    }
                }
                if !items.isEmpty {
                    sections.append(.section(LibrarySection(
                        id: "trakt-watchlist",
                        title: String(localized: "Your Trakt Watchlist"),
                        items: items,
                        totalCount: items.count,
                        libraryKey: nil,
                        browseContext: .trakt(kind: .watchlist)
                    )))
                }
            } catch { fail("trakt-watchlist", String(localized: "Your Trakt Watchlist"), error) }

            // Recently Watched (auth) - fetch movies and shows separately like mobile
            do {
                async let moviesTask = trakt.getHistory(type: "movies", page: 1, limit: 20)
                async let showsTask = trakt.getHistory(type: "shows", page: 1, limit: 20)
                let (moviesHistory, showsHistory) = try await (moviesTask, showsTask)

                // Combine and deduplicate by TMDB ID
                var seenIds = Set<String>()
                var items: [MediaItem] = []

                // Process movies
                for histItem in moviesHistory {
                    if let movie = histItem.movie, let tmdbId = movie.ids.tmdb {
                        let id = "tmdb:movie:\(tmdbId)"
                        if !seenIds.contains(id) {
                            seenIds.insert(id)
                            if let item = await mapTraktMovieToMediaItem(movie) {
                                items.append(item)
                            }
                        }
                    }
                }

                // Process shows
                for histItem in showsHistory {
                    if let show = histItem.show, let tmdbId = show.ids.tmdb {
                        let id = "tmdb:tv:\(tmdbId)"
                        if !seenIds.contains(id) {
                            seenIds.insert(id)
                            if let item = await mapTraktShowToMediaItem(show) {
                                items.append(item)
                            }
                        }
                    }
                }

                // Limit to 12 items
                let limitedItems = Array(items.prefix(12))

                if !limitedItems.isEmpty {
                    sections.append(.section(LibrarySection(
                        id: "trakt-history",
                        title: String(localized: "Recently Watched"),
                        items: limitedItems,
                        totalCount: limitedItems.count,
                        libraryKey: nil,
                        browseContext: .trakt(kind: .history)
                    )))
                }
            } catch { fail("trakt-history", String(localized: "Recently Watched"), error) }

            // Recommended for You (auth)
            do {
                let recommended = try await trakt.getRecommendedMovies(limit: 12)
                let items = await mapTraktMoviesToMediaItems(recommended)
                if !items.isEmpty {
                    sections.append(.section(LibrarySection(
                        id: "trakt-recs",
                        title: String(localized: "Recommended for You"),
                        items: items,
                        totalCount: items.count,
                        libraryKey: nil,
                        browseContext: .trakt(kind: .recommendations)
                    )))
                }
            } catch { fail("trakt-recs", String(localized: "Recommended for You"), error) }
        }

        // Popular TV Shows on Trakt (public)
        do {
            let popularShows = try await trakt.getPopularShows(limit: 12)
            let items = await mapTraktShowsToMediaItems(popularShows)
            if !items.isEmpty {
                sections.append(.section(LibrarySection(
                    id: "trakt-popular-shows",
                    title: String(localized: "Popular TV Shows on Trakt"),
                    items: items,
                    totalCount: items.count,
                    libraryKey: nil,
                    browseContext: .trakt(kind: .popularShows)
                )))
            }
        } catch { fail("trakt-popular-shows", String(localized: "Popular TV Shows on Trakt"), error) }

        return sections
    }

    // Helpers: Trakt mappers
    private func mapTraktMoviesToMediaItems(_ movies: [FlixorKit.TraktMovie]) async -> [MediaItem] {
        var out: [MediaItem] = []
        await withTaskGroup(of: MediaItem?.self) { group in
            for movie in movies {
                group.addTask {
                    return await self.mapTraktMovieToMediaItem(movie)
                }
            }
            for await maybe in group {
                if let m = maybe { out.append(m) }
            }
        }
        return out
    }

    private func mapTraktMovieToMediaItem(_ movie: FlixorKit.TraktMovie) async -> MediaItem? {
        guard let tmdb = movie.ids.tmdb else { return nil }
        async let backdropTask = fetchTMDBBackdrop(mediaType: "movie", id: tmdb)
        async let posterTask = fetchTMDBPoster(mediaType: "movie", id: tmdb)
        let (backdrop, poster) = await (backdropTask, posterTask)
        return MediaItem(
            id: "tmdb:movie:\(tmdb)",
            title: movie.title,
            type: "movie",
            thumb: poster,
            art: backdrop,
            year: movie.year,
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
    }

    private func mapTraktShowsToMediaItems(_ shows: [FlixorKit.TraktShow]) async -> [MediaItem] {
        var out: [MediaItem] = []
        await withTaskGroup(of: MediaItem?.self) { group in
            for show in shows {
                group.addTask {
                    return await self.mapTraktShowToMediaItem(show)
                }
            }
            for await maybe in group {
                if let m = maybe { out.append(m) }
            }
        }
        return out
    }

    private func mapTraktShowToMediaItem(_ show: FlixorKit.TraktShow) async -> MediaItem? {
        guard let tmdb = show.ids.tmdb else { return nil }
        async let backdropTask = fetchTMDBBackdrop(mediaType: "tv", id: tmdb)
        async let posterTask = fetchTMDBPoster(mediaType: "tv", id: tmdb)
        let (backdrop, poster) = await (backdropTask, posterTask)
        return MediaItem(
            id: "tmdb:tv:\(tmdb)",
            title: show.title,
            type: "show",
            thumb: poster,
            art: backdrop,
            year: show.year,
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
    }

    private func fetchTMDBBackdrop(mediaType: String, id: Int) async -> String? {
        do {
            if mediaType == "movie" {
                let detail = try await FlixorCore.shared.tmdb.getMovieDetails(id: id)
                return FlixorCore.shared.tmdb.getBackdropUrl(path: detail.backdropPath, size: "original")
            } else {
                let detail = try await FlixorCore.shared.tmdb.getTVDetails(id: id)
                return FlixorCore.shared.tmdb.getBackdropUrl(path: detail.backdropPath, size: "original")
            }
        } catch {
            return nil
        }
    }

    // MARK: - Fetch Methods

    private func fetchOnDeck() async throws -> [MediaItem] {
        guard let plexServer = FlixorCore.shared.plexServer else { return [] }
        print("📦 [Home] Fetching on deck items...")
        let items = try await plexServer.getOnDeck()
        print("✅ [Home] Received \(items.count) on deck items")
        return items.map { toMediaItem($0) }
    }

    private func fetchContinueWatching(bypassCache: Bool = false) async throws -> [MediaItem] {
        guard let plexServer = FlixorCore.shared.plexServer else { return [] }
        print("📦 [Home] Fetching continue watching items\(bypassCache ? " (bypass cache)" : "")...")
        let result = try await plexServer.getContinueWatching(bypassCache: bypassCache)
        print("✅ [Home] Received \(result.items.count) continue watching items (deduplicated)")

        // Store which items have multiple editions
        self.continueWatchingVersions = result.itemsWithMultipleVersions

        // Enrich with TMDB backdrop URLs before returning
        let baseItems = result.items.map { toMediaItem($0) }
        let enriched = await enrichWithTMDBBackdrops(baseItems)
        return enriched.filter { !continueWatchingPendingRemovalIds.contains($0.id) }
    }

    private func enrichWithTMDBBackdrops(_ items: [MediaItem]) async -> [MediaItem] {
        print("🎨 [Home] Enriching \(items.count) items with TMDB backdrops...")

        return await withTaskGroup(of: (Int, MediaItem).self) { group in
            for (index, item) in items.enumerated() {
                group.addTask {
                    // Try to fetch TMDB backdrop
                    if let backdropURL = try? await self.resolveTMDBBackdropForItem(item) {
                        // Create new MediaItem with TMDB backdrop
                        let enriched = MediaItem(
                            id: item.id,
                            title: item.title,
                            type: item.type,
                            thumb: item.thumb,
                            art: backdropURL, // Replace with TMDB backdrop
                            year: item.year,
                            rating: item.rating,
                            duration: item.duration,
                            viewOffset: item.viewOffset,
                            summary: item.summary,
                            grandparentTitle: item.grandparentTitle,
                            grandparentThumb: item.grandparentThumb,
                            grandparentArt: item.grandparentArt,
                            grandparentRatingKey: item.grandparentRatingKey,
                            parentIndex: item.parentIndex,
                            index: item.index,
                            parentRatingKey: item.parentRatingKey,
                            parentTitle: item.parentTitle,
                            leafCount: item.leafCount,
                            viewedLeafCount: item.viewedLeafCount
                        )
                        return (index, enriched)
                    }
                    // Return original item if TMDB fetch fails
                    return (index, item)
                }
            }

            // Collect results and maintain order
            var enrichedItems: [(Int, MediaItem)] = []
            for await result in group {
                enrichedItems.append(result)
            }

            // Sort by original index and return just the items
            let sorted = enrichedItems.sorted { $0.0 < $1.0 }.map { $0.1 }
            print("✅ [Home] Enriched \(sorted.count) items with TMDB backdrops")
            return sorted
        }
    }

    private func resolveTMDBBackdropForItem(_ item: MediaItem) async throws -> String? {
        guard let plexServer = FlixorCore.shared.plexServer else { return nil }

        print("🔍 [Home] Resolving TMDB backdrop for: \(item.title) (id: \(item.id), type: \(item.type))")

        // Handle plain numeric IDs (assume they're Plex rating keys)
        let normalizedId: String
        if item.id.hasPrefix("plex:") || item.id.hasPrefix("tmdb:") {
            normalizedId = item.id
        } else {
            // Plain numeric ID - treat as Plex rating key
            normalizedId = "plex:\(item.id)"
        }

        if normalizedId.hasPrefix("tmdb:") {
            let parts = normalizedId.split(separator: ":")
            if parts.count == 3 {
                let media = (parts[1] == "movie") ? "movie" : "tv"
                let id = String(parts[2])
                let url = try await fetchTMDBBestBackdropURLString(mediaType: media, id: id)
                print("✅ [Home] TMDB backdrop resolved for \(item.title): \(url ?? "nil")")
                return url
            }
        }

        if normalizedId.hasPrefix("plex:") {
            let rk = String(normalizedId.dropFirst(5))

            do {
                let fullItem = try await plexServer.getMetadata(ratingKey: rk)

                // For TV episodes, fetch the parent series metadata instead
                if fullItem.type == "episode", let grandparentRatingKey = fullItem.grandparentRatingKey {
                    print("📺 [Home] Episode detected, fetching parent series metadata for \(item.title)")
                    let seriesItem = try await plexServer.getMetadata(ratingKey: grandparentRatingKey)

                    // Extract TMDB ID from series Guid array
                    for guidId in seriesItem.guids {
                        if guidId.contains("tmdb://") || guidId.contains("themoviedb://") {
                            if let tmdbId = extractTMDBId(from: guidId) {
                                let url = try await fetchTMDBBestBackdropURLString(mediaType: "tv", id: tmdbId)
                                print("✅ [Home] TMDB backdrop resolved for \(item.title) from series Guid array: \(url ?? "nil")")
                                return url
                            }
                        }
                    }
                    print("⚠️ [Home] No TMDB ID found in series metadata for \(item.title)")
                    return nil
                }

                // For movies and shows, extract TMDB ID from Guid array
                for guidId in fullItem.guids {
                    if guidId.contains("tmdb://") || guidId.contains("themoviedb://") {
                        if let tmdbId = extractTMDBId(from: guidId) {
                            let mediaType = (fullItem.type == "movie") ? "movie" : "tv"
                            let url = try await fetchTMDBBestBackdropURLString(mediaType: mediaType, id: tmdbId)
                            print("✅ [Home] TMDB backdrop resolved for \(item.title) from Guid array: \(url ?? "nil")")
                            return url
                        }
                    }
                }
                print("⚠️ [Home] No TMDB ID found in Guid array for \(item.title)")
            } catch {
                print("❌ [Home] Failed to fetch metadata for \(item.title): \(error)")
            }
        }

        return nil
    }

    private func fetchTMDBBestBackdropURLString(mediaType: String, id: String) async throws -> String? {
        guard let tmdbId = Int(id) else { return nil }

        let imgs = try await FlixorCore.shared.tmdb.getImages(mediaType: mediaType, id: tmdbId)
        let backs = imgs.backdrops
        if backs.isEmpty { return nil }

        let pick: ([FlixorKit.TMDBImage]) -> FlixorKit.TMDBImage? = { arr in
            return arr.sorted(by: { ($0.voteAverage ?? 0) > ($1.voteAverage ?? 0) }).first
        }

        // Priority 1: English backdrops (with title text burned in)
        if let en = pick(backs.filter { $0.iso6391 == "en" }), let path = en.filePath {
            return FlixorCore.shared.tmdb.getBackdropUrl(path: path, size: "original")
        }

        // Priority 2: Any language with title (iso_639_1 is not null)
        if let withLang = pick(backs.filter { $0.iso6391 != nil }), let path = withLang.filePath {
            return FlixorCore.shared.tmdb.getBackdropUrl(path: path, size: "original")
        }

        // Priority 3: Fallback to any backdrop (including textless)
        guard let any = pick(backs), let path = any.filePath else { return nil }
        return FlixorCore.shared.tmdb.getBackdropUrl(path: path, size: "original")
    }

    private func fetchRecentlyAdded() async throws -> [MediaItem] {
        guard let plexServer = FlixorCore.shared.plexServer else { return [] }
        print("📦 [Home] Fetching recently added items...")
        let items = try await plexServer.getRecentlyAdded()
        print("✅ [Home] Received \(items.count) recently added items")
        return items.map { toMediaItem($0) }
    }

    /// Fetch "Recently Added in {LibraryName}" for each enabled library
    /// - Parameter bypassCache: If true, skip cache and fetch fresh data (useful for polling)
    private func fetchRecentlyAddedPerLibrary(bypassCache: Bool = false) async throws -> [LibrarySection] {
        guard let plexServer = FlixorCore.shared.plexServer else { return [] }

        // Check if episode grouping is enabled
        let shouldGroupEpisodes = UserDefaults.standard.groupRecentlyAddedEpisodes

        print("📦 [Home] Fetching recently added per library (grouping: \(shouldGroupEpisodes))\(bypassCache ? " (bypass cache)" : "")...")
        let libraries = try await plexServer.getLibraries()

        // Filter libraries based on enabled settings
        let filteredLibraries = libraries.filter { isLibraryEnabled($0.key) }

        var sections: [LibrarySection] = []

        for library in filteredLibraries {
            do {
                // Fetch recently added for this specific library
                let allItems = try await plexServer.getRecentlyAdded(libraryKey: library.key, bypassCache: bypassCache)
                // Fetch more items if grouping is enabled to account for consolidation
                let fetchLimit = shouldGroupEpisodes ? 30 : 20
                let rawItems = Array(allItems.prefix(fetchLimit))

                if !rawItems.isEmpty {
                    let finalItems: [MediaItem]
                    if shouldGroupEpisodes {
                        // Group TV episodes by series, keep movies/shows as-is
                        let processedItems = groupEpisodesBySeries(rawItems.map { toMediaItem($0) })
                        finalItems = Array(processedItems.prefix(20))
                        print("✅ [Home] Recently Added in \(library.title): \(rawItems.count) raw → \(finalItems.count) grouped items")
                    } else {
                        // Show individual items without grouping
                        finalItems = Array(rawItems.prefix(20).map { toMediaItem($0) })
                        print("✅ [Home] Recently Added in \(library.title): \(finalItems.count) items (ungrouped)")
                    }

                    sections.append(LibrarySection(
                        id: "recently-added-\(library.key)",
                        title: String(localized: "Recently Added in \(library.title)"),
                        items: finalItems,
                        totalCount: finalItems.count,
                        libraryKey: library.key,
                        browseContext: .plexDirectory(
                            path: "/library/sections/\(library.key)/recentlyAdded",
                            title: String(localized: "Recently Added in \(library.title)")
                        )
                    ))
                }
            } catch {
                print("⚠️ [Home] Failed to load recently added for \(library.title): \(error)")
                // Continue with other libraries
            }
        }

        return sections
    }

    /// Group TV episodes by their parent series, preserving order of first appearance
    /// Non-episode items (movies, shows) are kept as-is
    private func groupEpisodesBySeries(_ items: [MediaItem]) -> [MediaItem] {
        var result: [MediaItem] = []
        var seenSeriesKeys = Set<String>()
        var seriesEpisodeCounts: [String: Int] = [:]

        // First pass: count episodes per series
        for item in items {
            if item.type == "episode", let seriesKey = item.grandparentRatingKey {
                seriesEpisodeCounts[seriesKey, default: 0] += 1
            }
        }

        // Second pass: build result list, replacing episodes with series representative
        for item in items {
            if item.type == "episode", let seriesKey = item.grandparentRatingKey {
                // Skip if we've already added this series
                if seenSeriesKeys.contains(seriesKey) {
                    continue
                }
                seenSeriesKeys.insert(seriesKey)

                let episodeCount = seriesEpisodeCounts[seriesKey] ?? 1

                // Create a series representative item
                var seriesItem = MediaItem(
                    id: seriesKey, // Use series rating key so clicking navigates to series details
                    title: item.grandparentTitle ?? item.title,
                    type: "show", // Render as show poster
                    thumb: item.grandparentThumb ?? item.thumb,
                    art: item.grandparentArt ?? item.art,
                    year: item.year,
                    rating: item.rating,
                    duration: nil,
                    viewOffset: nil,
                    summary: String(localized: "\(episodeCount) new episodes"),
                    grandparentTitle: nil,
                    grandparentThumb: nil,
                    grandparentArt: nil,
                    grandparentRatingKey: nil,
                    parentIndex: nil,
                    index: nil,
                    parentRatingKey: nil,
                    parentTitle: nil,
                    leafCount: episodeCount, // Store episode count
                    viewedLeafCount: nil
                )
                seriesItem.isNewEpisodesGroup = true
                result.append(seriesItem)
            } else {
                // Non-episode items (movies, shows) - keep as-is
                result.append(item)
            }
        }

        return result
    }

    // MARK: - Polling for Dynamic Rows

    /// Start polling for Continue Watching and Recently Added rows
    func startPolling() {
        guard !isPolling else { return }
        isPolling = true

        print("🔄 [Home] Starting polling for dynamic rows (every \(Int(pollInterval))s)")

        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.pollDynamicRows()
            }
        }
    }

    /// Stop polling
    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        isPolling = false
        print("⏹️ [Home] Polling stopped")
    }

    /// Poll only dynamic rows (Continue Watching, Recently Added per library)
    /// This is a light refresh - doesn't reload the entire home screen
    private func pollDynamicRows() async {
        print("🔄 [Home] Polling dynamic rows (bypassing cache)...")

        // Poll Continue Watching (bypass cache to get fresh data)
        Task { @MainActor in
            // Stremio-only has no Plex row to poll; an empty result would blank the row.
            if self.isStremioOnly {
                await self.loadLocalContinueWatching()
                return
            }
            do {
                let data = try await self.fetchContinueWatching(bypassCache: true)
                // Merges Trakt too; the row only changes if the result differs.
                self.publishContinueWatching(primary: data, showPrimaryFirst: false)
            } catch {
                print("⚠️ [Home] Poll Continue Watching failed: \(error)")
            }
        }

        // Poll Recently Added per library (bypass cache to get fresh data)
        Task { @MainActor in
            do {
                let sections = try await self.fetchRecentlyAddedPerLibrary(bypassCache: true)
                // Only update if data changed
                let existingIds = Set(self.recentlyAddedSections.flatMap { $0.items.map { $0.id } })
                let newIds = Set(sections.flatMap { $0.items.map { $0.id } })
                if existingIds != newIds || sections.count != self.recentlyAddedSections.count {
                    self.recentlyAddedSections = sections
                    self.recentlyAddedPerLibraryState = sections.isEmpty ? .empty : .loaded
                    self.registerRecentlyAddedRows()
                    print("✅ [Home] Recently Added per library updated: \(sections.count) sections")
                } else {
                    print("ℹ️ [Home] Recently Added per library unchanged")
                }
            } catch {
                print("⚠️ [Home] Poll Recently Added per library failed: \(error)")
            }
        }
    }

    private func fetchLibrarySections() async throws -> [LibrarySection] {
        guard let plexServer = FlixorCore.shared.plexServer else { return [] }

        print("📦 [Home] Fetching libraries...")
        let libraries = try await plexServer.getLibraries()
        print("✅ [Home] Received \(libraries.count) libraries")

        // Filter libraries based on enabled settings
        let filteredLibraries = libraries.filter { isLibraryEnabled($0.key) }
        print("📋 [Home] Enabled libraries: \(filteredLibraries.count) of \(libraries.count)")

        // Fetch items for each enabled library (limit to first 20)
        var sections: [LibrarySection] = []

        for library in filteredLibraries {
            do {
                print("📦 [Home] Fetching items for library: \(library.title)")
                let items = try await plexServer.getLibraryItems(key: library.key, limit: 20)

                if !items.isEmpty {
                    print("✅ [Home] Received \(items.count) items for \(library.title)")
                    sections.append(LibrarySection(
                        id: library.key,
                        title: library.title,
                        items: items.map { toMediaItem($0) },
                        totalCount: items.count,
                        libraryKey: library.key,
                        browseContext: .plexLibrary(key: library.key, title: library.title)
                    ))
                }
            } catch {
                print("⚠️ [Home] Failed to load library \(library.title): \(error)")
                // Continue with other libraries
            }
        }

        return sections
    }

    // MARK: - Billboard Rotation

    private var heroAutoRotate: Bool {
        UserDefaults.standard.heroAutoRotate
    }

    private func startBillboardRotation() {
        guard !billboardItems.isEmpty else { return }

        // Fetch colors for initial item
        Task {
            await fetchHeroColors(for: currentBillboardIndex)
        }

        // Only start timer if auto-rotate is enabled
        guard heroAutoRotate else { return }

        billboardTimer?.invalidate()
        billboardTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                let newIndex = (self.currentBillboardIndex + 1) % self.billboardItems.count
                withAnimation {
                    self.currentBillboardIndex = newIndex
                }
                await self.fetchHeroColors(for: newIndex)
            }
        }
    }

    func stopBillboardRotation() {
        billboardTimer?.invalidate()
        billboardTimer = nil
    }

    func resumeBillboardRotation() {
        guard heroAutoRotate, !billboardItems.isEmpty else { return }

        billboardTimer?.invalidate()
        billboardTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                let newIndex = (self.currentBillboardIndex + 1) % self.billboardItems.count
                withAnimation {
                    self.currentBillboardIndex = newIndex
                }
                await self.fetchHeroColors(for: newIndex)
            }
        }
    }

    // MARK: - UltraBlur Colors

    /// Fetch UltraBlur colors for the current hero/billboard item
    func fetchHeroColors(for index: Int) async {
        guard index >= 0 && index < billboardItems.count else { return }
        let item = billboardItems[index]

        // Get the backdrop URL for this item
        guard let backdropUrl = await resolveHeroBackdropURL(for: item) else {
            print("⚠️ [Home] No backdrop URL for hero colors: \(item.title)")
            return
        }

        let colorKey = "hero:\(backdropUrl)"

        // Skip if already showing colors for this item
        if colorKey == lastHeroColorKey && heroColors != nil {
            return
        }

        // Check cache first
        if let cached = ultraBlurCache[colorKey] {
            lastHeroColorKey = colorKey
            withAnimation(.easeInOut(duration: 0.8)) {
                self.heroColors = cached
            }
            return
        }

        // Fetch from Plex server
        guard let plexServer = FlixorCore.shared.plexServer else { return }

        do {
            if let colors = try await plexServer.getUltraBlurColors(imageUrl: backdropUrl) {
                ultraBlurCache[colorKey] = colors
                lastHeroColorKey = colorKey
                withAnimation(.easeInOut(duration: 0.8)) {
                    self.heroColors = colors
                }
                print("✅ [Home] UltraBlur colors fetched for: \(item.title)")
            }
        } catch {
            print("❌ [Home] Failed to fetch UltraBlur colors: \(error)")
        }
    }

    /// Manually trigger color update (e.g., when user changes billboard)
    func updateHeroColorsForCurrentItem() {
        Task {
            await fetchHeroColors(for: currentBillboardIndex)
        }
    }

    /// Resolve backdrop URL for hero/billboard item (for UltraBlur)
    /// Prefers TMDB backdrop (matches displayed hero image) over Plex art
    private func resolveHeroBackdropURL(for item: MediaItem) async -> String? {
        // Determine cache key (same logic as BillboardView)
        let cacheKey: String
        if item.type == "episode", let seriesKey = item.grandparentRatingKey {
            cacheKey = "series:\(seriesKey)"
        } else if item.type == "season", let seriesKey = item.parentRatingKey {
            cacheKey = "series:\(seriesKey)"
        } else {
            cacheKey = item.id
        }

        // Check BillboardImageCache for TMDB backdrop (matches what hero displays)
        if let cached = BillboardImageCache.shared.get(itemId: cacheKey),
           let tmdbBackdrop = cached.0 {
            print("🎨 [Home] Using cached TMDB backdrop for UltraBlur: \(tmdbBackdrop.absoluteString)")
            return tmdbBackdrop.absoluteString
        }

        // Fall back to Plex art if no TMDB cached
        if let art = item.art {
            if art.hasPrefix("http") {
                return art
            }
            if let plexServer = FlixorCore.shared.plexServer {
                return plexServer.getImageUrl(path: art, width: 1920)
            }
        }

        // For episodes, try grandparent art (show backdrop)
        if item.type == "episode", let grandparentArt = item.grandparentArt {
            if grandparentArt.hasPrefix("http") {
                return grandparentArt
            }
            if let plexServer = FlixorCore.shared.plexServer {
                return plexServer.getImageUrl(path: grandparentArt, width: 1920)
            }
        }

        // Try thumb as fallback
        if let thumb = item.thumb {
            if thumb.hasPrefix("http") {
                return thumb
            }
            if let plexServer = FlixorCore.shared.plexServer {
                return plexServer.getImageUrl(path: thumb, width: 1920)
            }
        }

        return nil
    }

    // MARK: - Navigation

    func playItem(_ item: MediaItem) {
        // Stremio playback needs a resolved IMDb/TMDB id, which only the details
        // screen has. Send the user there; its play button starts Stremio playback.
        // Shows and seasons have nothing to play directly either; the hero can
        // now be fed from any row, including grouped Recently Added cards.
        if isStremioOnly || !item.id.hasPrefix("plex:") || item.type == "show" || item.type == "season" {
            pendingAction = .details(item)
            return
        }
        pendingAction = .play(.plex(item))
    }

    func showItemDetails(_ item: MediaItem) {
        guard item.id.hasPrefix("tmdb:"), (item.viewOffset ?? 0) > 0 else {
            pendingAction = .details(item)
            return
        }
        // Possibly a Trakt item: details' Play button resumes from the local store.
        Task { @MainActor in
            await TraktContinueWatchingService.shared.seedResumePoint(for: item)
            self.pendingAction = .details(item)
        }
    }

    /// Plays a Continue Watching item. Plex rows carry bare ratingKeys, which
    /// `playItem` would send to details, so they get the "plex:" prefix first.
    func playFromContinueWatching(_ item: MediaItem) {
        guard item.id.hasPrefix("tmdb:"), (item.viewOffset ?? 0) > 0 else {
            startContinueWatchingPlayback(item)
            return
        }
        // Possibly a Trakt item: make its position available to playback first.
        Task { @MainActor in
            await TraktContinueWatchingService.shared.seedResumePoint(for: item)
            self.startContinueWatchingPlayback(item)
        }
    }

    private func startContinueWatchingPlayback(_ item: MediaItem) {
        if isStremioOnly {
            playItem(item)
        } else {
            playItem(normalizeForHero([item]).first ?? item)
        }
    }

    /// Re-fetches Continue Watching (after a watch-state change).
    func refreshContinueWatching() async {
        // A watch-state change can alter Trakt progress and the next episode.
        await TraktContinueWatchingService.shared.invalidate()
        if isStremioOnly {
            await loadLocalContinueWatching()
            return
        }
        do {
            let data = try await fetchContinueWatching(bypassCache: true)
            publishContinueWatching(primary: data, showPrimaryFirst: false)
        } catch {
            print("⚠️ [Home] Continue Watching refresh failed: \(error)")
        }
    }

    func toggleMyList(_ item: MediaItem) {
        // TODO: Add/remove from watchlist
        print("Toggle My List: \(item.title)")
    }

    // MARK: - Cleanup

    deinit {
        billboardTimer?.invalidate()
        pollTimer?.invalidate()
    }
}

// MARK: - Navigation Actions

enum HomeAction {
    case play(PlayerDestination)
    case details(MediaItem)
}

extension HomeAction: Equatable {
    static func == (lhs: HomeAction, rhs: HomeAction) -> Bool {
        switch (lhs, rhs) {
        case (.play(let a), .play(let b)): return a == b
        case (.details(let a), .details(let b)): return a.id == b.id
        default: return false
        }
    }
}
