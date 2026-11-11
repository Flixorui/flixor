//
//  HomeViewModel.swift
//  FlixorMac
//
//  View model for home screen using FlixorCore
//

import AppKit
import Combine
import Foundation
import SwiftUI
import FlixorKit

// Use types from FlixorKit directly

// MARK: - Hero State

/// The hero's rotating state, kept out of HomeViewModel so a page turn only
/// re-renders the hero views and the page background, not the whole page.
@MainActor
final class HomeHeroState: ObservableObject {
    @Published var currentIndex = 0
    @Published var colors: PlexUltraBlurColors?
}

// MARK: - Extra Row Groups

/// One TMDB list row (Stremio-only discovery).
private struct TMDBListSpec {
    let id: String
    let title: String
    let media: TMDBMediaType
    let kind: TMDBBrowseKind
    var genreId: String? = nil
}

/// A source of discovery / catalog rows, loaded alongside the others.
private enum ExtraRowSource {
    case tmdbTrending
    case watchlist
    case streaming
    case stremioCatalogs
    case plexGenres
    case trakt
    case tmdbList(TMDBListSpec)
}

private struct ExtraRowGroup {
    let key: String
    let source: ExtraRowSource
}

/// The Trakt rows, in display order.
private enum TraktRow: CaseIterable {
    case trendingMovies, trendingShows, watchlist, history, recommended, popularShows
}

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
    private let pollInterval: TimeInterval = 180 // Poll every 3 minutes while Home is visible
    private var lastContinueWatchingRefresh: Date?
    private var isPolling = false

    // MARK: - Visibility
    // Hidden tabs stay alive, so Home tracks whether it is actually on screen
    // and pauses polling and hero rotation otherwise.
    private var isAppActive = true
    private var isHomeTabSelected = true
    private var isHomeOnScreen = true
    private var wasHomeVisible = true
    private var hasStartedLoad = false
    /// A player closed since the last Continue Watching refresh, so Trakt progress may have moved.
    private var traktRefreshPending = false
    /// Local watch history changed while a player was open.
    private var localHistoryStale = false

    private var isHomeVisible: Bool {
        isAppActive && isHomeTabSelected && isHomeOnScreen
    }

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

    /// Observed only by the hero views and the page background.
    let hero = HomeHeroState()

    var currentBillboardIndex: Int {
        get { hero.currentIndex }
        set { hero.currentIndex = newValue }
    }
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
    var heroColors: PlexUltraBlurColors? {
        get { hero.colors }
        set { hero.colors = newValue }
    }
    private var ultraBlurCache: [String: PlexUltraBlurColors] = [:]
    private var lastHeroColorKey: String?

    private var billboardTimer: Timer?
    private var loadTask: Task<Void, Never>?

    /// Bumped per extra-rows load so an older load can't publish over a newer one.
    private var extraLoadGeneration = 0
    /// Rows of each extra row group from the last load, shown while a reload of that group runs.
    private var extraGroupSlots: [String: [HomeRowSlot]] = [:]
    /// The initial load's extras group is still waiting for an extras load to finish.
    private var extrasGroupOpen = false

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
        hasStartedLoad = true
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
            startPolling()
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
        // Finished (hero seed + finishGroup) by whichever extras load is current
        // when it ends, so a retry or reload started meanwhile doesn't end it early.
        extrasGroupOpen = true
        Task { @MainActor in
            await self.loadAdditionalRows()
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

        // Local history seeds the hero first; the extras load falls back to
        // discovery rows and finishes the group (see loadAdditionalRows).
        extrasGroupOpen = true
        Task { @MainActor in
            await self.loadAdditionalRows()
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
            if await self.loadAdditionalRows() {
                self.seedBillboardFromExtraSections()
            }
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
                if await self.loadAdditionalRows() {
                    self.seedBillboardFromExtraSections()
                }
            case .stremioCatalog where self.extraSectionsState.isLoading:
                // The running load would publish over a single-row fix; reload
                // all extras as the current load instead.
                await self.loadAdditionalRows()
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
                    self.extraGroupSlots["stremio-catalogs"] = slots.filter { $0.id.hasPrefix("stremio-catalog-") }
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

    /// Reloads the discovery / Trakt / addon / streaming rows (e.g. after a
    /// Streaming Availability setting changed).
    func reloadExtraRows() async {
        if await loadAdditionalRows() {
            seedBillboardFromExtraSections()
        }
    }

    /// Loads every extra row group at once. Rows show in their final order as
    /// each group comes back; groups still loading keep their rows from the
    /// previous load, if any.
    /// - Returns: false when a newer load superseded this one before it finished.
    @discardableResult
    private func loadAdditionalRows() async -> Bool {
        extraLoadGeneration += 1
        let generation = extraLoadGeneration
        let groups = isStremioOnly ? stremioExtraRowGroups() : plexExtraRowGroups()
        var loaded: [String: [HomeRowSlot]] = [:]

        func ordered() -> [HomeRowSlot] {
            groups.flatMap { loaded[$0.key] ?? extraGroupSlots[$0.key] ?? [] }
        }

        await withTaskGroup(of: (String, [HomeRowSlot]).self) { taskGroup in
            for group in groups {
                let key = group.key
                let source = group.source
                taskGroup.addTask { (key, await self.loadExtraRowGroup(source)) }
            }
            for await (key, slots) in taskGroup {
                loaded[key] = slots
                guard generation == self.extraLoadGeneration, loaded.count < groups.count else { continue }
                self.publishPendingExtraSlots(ordered())
            }
        }

        guard generation == extraLoadGeneration else { return false }
        extraGroupSlots = loaded
        let slots = ordered()
        print("✅ [Home] Extra sections prepared: \(slots.map { $0.title }.joined(separator: ", "))")
        setExtraSlots(slots)
        if extrasGroupOpen {
            extrasGroupOpen = false
            // Last resort for the hero when the other rows came back empty, so it
            // resolves instead of shimmering forever.
            seedBillboardFromExtraSections()
            finishGroup()
        }
        return true
    }

    /// Plex mode groups, in display order. The Rows Settings toggles apply here too.
    private func plexExtraRowGroups() -> [ExtraRowGroup] {
        let settings = UserDefaults.standard
        var groups: [ExtraRowGroup] = []
        // Popular on Plex / Trending Now (Continue Watching is rendered separately)
        if settings.showPlexPopular || settings.showTrendingRows {
            groups.append(ExtraRowGroup(key: "tmdb-trending", source: .tmdbTrending))
        }
        if settings.showWatchlist {
            groups.append(ExtraRowGroup(key: "watchlist", source: .watchlist))
        }
        // Streaming service Top 10 rows
        groups.append(ExtraRowGroup(key: "streaming", source: .streaming))
        // Addon catalog rows, in addon priority order, as in Stremio-only mode.
        if settings.showStremioCatalogRows {
            groups.append(ExtraRowGroup(key: "stremio-catalogs", source: .stremioCatalogs))
        }
        groups.append(ExtraRowGroup(key: "plex-genres", source: .plexGenres))
        if settings.showTraktRows {
            groups.append(ExtraRowGroup(key: "trakt", source: .trakt))
        }
        return groups
    }

    /// Stremio-only groups, in display order.
    private func stremioExtraRowGroups() -> [ExtraRowGroup] {
        let settings = UserDefaults.standard
        var groups: [ExtraRowGroup] = []
        func list(_ spec: TMDBListSpec) {
            groups.append(ExtraRowGroup(key: spec.id, source: .tmdbList(spec)))
        }

        // Addon catalogs first when present - they're the user's own configured
        // sources, so they outrank generic TMDB discovery.
        if settings.showStremioCatalogRows {
            groups.append(ExtraRowGroup(key: "stremio-catalogs", source: .stremioCatalogs))
        }
        // Trending is the headline row and also seeds the hero, so it goes first.
        if settings.showTrendingRows {
            list(TMDBListSpec(id: "tmdb-trending-movies", title: String(localized: "Trending Movies"), media: .movie, kind: .trending))
            list(TMDBListSpec(id: "tmdb-trending-tv", title: String(localized: "Trending TV Shows"), media: .tv, kind: .trending))
        }
        // Streaming service Top 10 rows (cache first)
        groups.append(ExtraRowGroup(key: "streaming", source: .streaming))
        // Watchlist: the Plex.tv half is skipped automatically when plexTv is nil,
        // so this is the Trakt watchlist (plus local entries once Phase 3 lands).
        if settings.showWatchlist {
            groups.append(ExtraRowGroup(key: "watchlist", source: .watchlist))
        }
        if settings.showPlexPopular {
            list(TMDBListSpec(id: "tmdb-popular-movies", title: String(localized: "Popular Movies"), media: .movie, kind: .popular))
            list(TMDBListSpec(id: "tmdb-popular-tv", title: String(localized: "Popular TV Shows"), media: .tv, kind: .popular))
        }
        for row in Self.stremioGenreRows {
            list(TMDBListSpec(
                id: "tmdb-genre-\(row.media.rawValue)-\(row.genreId)",
                title: row.title,
                media: row.media,
                kind: .genre,
                genreId: row.genreId
            ))
        }
        list(TMDBListSpec(id: "tmdb-top-rated-movies", title: String(localized: "Top Rated Movies"), media: .movie, kind: .topRated))
        list(TMDBListSpec(id: "tmdb-upcoming", title: String(localized: "Coming Soon"), media: .movie, kind: .upcoming))
        // Trakt rows require a linked account; they no-op otherwise.
        if settings.showTraktRows {
            groups.append(ExtraRowGroup(key: "trakt", source: .trakt))
        }
        return groups
    }

    private func loadExtraRowGroup(_ source: ExtraRowSource) async -> [HomeRowSlot] {
        switch source {
        case .tmdbTrending:
            return await loadTMDBTrendingSlots()
        case .watchlist:
            guard let section = await fetchPlexTvWatchlistSection() else { return [] }
            return [.section(section)]
        case .streaming:
            // Top 10 and "New on" rows (cache first; only due lists cost an API call).
            return await StreamingAvailabilityStore.shared.sections().map { HomeRowSlot.section($0) }
        case .stremioCatalogs:
            return await fetchStremioCatalogSections()
        case .plexGenres:
            do {
                return try await fetchGenreSections().map { HomeRowSlot.section($0) }
            } catch {
                print("⚠️ [Home] Genre sections failed: \(error)")
                return []
            }
        case .trakt:
            return await fetchTraktSections()
        case .tmdbList(let spec):
            guard let slot = await fetchTMDBListSection(
                id: spec.id, title: spec.title, media: spec.media, kind: spec.kind, genreId: spec.genreId
            ) else { return [] }
            return [slot]
        }
    }

    /// TMDB: Popular on Plex / Trending Now
    private func loadTMDBTrendingSlots() async -> [HomeRowSlot] {
        let settings = UserDefaults.standard
        do {
            let (popular, trending) = try await fetchTMDBTrendingTVSections()
            var slots: [HomeRowSlot] = []
            if settings.showPlexPopular, let p = popular.first { slots.append(.section(p)) }
            if settings.showTrendingRows, let t = trending.first { slots.append(.section(t)) }
            return slots
        } catch {
            print("⚠️ [Home] TMDB trending failed: \(error)")
            return [.failure(HomeRowFailure(
                id: settings.showPlexPopular ? "tmdb-popular" : "tmdb-trending",
                title: settings.showPlexPopular ? String(localized: "Popular on Plex") : String(localized: "Trending Now"),
                source: "TMDB",
                message: error.localizedDescription,
                retry: .extras
            ))]
        }
    }

    /// Shows the rows loaded so far. Rows Settings and the load state are
    /// updated once, when the whole load finishes.
    private func publishPendingExtraSlots(_ slots: [HomeRowSlot]) {
        extraSlots = slots
        resolvePreferredHero()
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

            let sections: [LibrarySection] = await boundedMap(Array(limitedCollections.prefix(5))) { collection -> LibrarySection? in
                // A failed collection is left out; the others still show.
                guard let items = try? await plexServer.getCollectionItems(ratingKey: collection.ratingKey, size: 15),
                      !items.isEmpty else { return nil }
                return LibrarySection(
                    id: "collection-\(collection.ratingKey)",
                    title: collection.title ?? String(localized: "Untitled Collection"),
                    items: items.map { self.toMediaItem($0) },
                    totalCount: collection.childCount ?? items.count,
                    libraryKey: nil,
                    browseContext: .plexCollection(ratingKey: collection.ratingKey, title: collection.title ?? String(localized: "Collection")),
                    isCollection: true
                )
            }.compactMap { $0 }

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

    /// Runs `transform` over `items`, at most `limit` at a time, and returns the
    /// results in input order.
    private func boundedMap<T, R: Sendable>(
        _ items: [T],
        limit: Int = 6,
        _ transform: @escaping @MainActor (T) async -> R
    ) async -> [R] {
        guard !items.isEmpty else { return [] }
        var results = [R?](repeating: nil, count: items.count)
        await withTaskGroup(of: (Int, R).self) { group in
            var next = 0
            while next < min(limit, items.count) {
                let index = next
                let item = items[index]
                group.addTask { (index, await transform(item)) }
                next += 1
            }
            while let (index, value) = await group.next() {
                results[index] = value
                if next < items.count {
                    let nextIndex = next
                    let item = items[nextIndex]
                    group.addTask { (nextIndex, await transform(item)) }
                    next += 1
                }
            }
        }
        return results.compactMap { $0 }
    }

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
                    addonName: entry.addonName,
                    supportsPaging: entry.catalog.extra?.contains { $0.name == "skip" } ?? false
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
            browseContext: .stremioCatalog(StremioCatalogBrowse(
                installationId: ref.installationId,
                type: ref.type,
                catalogId: ref.catalogId,
                title: ref.displayName,
                addonName: ref.addonName,
                supportsPaging: ref.supportsPaging
            ))
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
            art: FlixorCore.shared.tmdb.getBackdropUrl(path: r.backdropPath, size: "w780"),
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
            let art = FlixorCore.shared.tmdb.getBackdropUrl(path: r.backdropPath, size: "w780")
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
                let meta = try await plexTv.getWatchlist(includeGuids: true)

                let resolved: [MediaItem?] = await boundedMap(Array(meta.prefix(20))) { m -> MediaItem? in
                    let mediaType = (m.type ?? "show") == "movie" ? "movie" : "show"

                    // Try to extract TMDB ID from Plex GUIDs array
                    let itemId: String
                    let tmdbIdFound = m.guids.lazy.compactMap { self.extractTMDBId(from: $0) }.first

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
                            return nil
                        }
                    } else if let ratingKey = m.ratingKey {
                        itemId = "plex:\(ratingKey)"
                        print("⚠️ [Home Watchlist] Plex item \(m.title ?? "Unknown") using Plex rating key (no key)")
                    } else {
                        return nil
                    }

                    return MediaItem(
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
                }
                for item in resolved.compactMap({ $0 }) {
                    allItems[item.id] = item
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

                // Don't overwrite Plex items (they may have more metadata)
                var pending = Set<String>()
                let missing = watchlist.prefix(20).filter { wlItem in
                    let itemId: String
                    if let movie = wlItem.movie, let tmdbId = movie.ids.tmdb {
                        itemId = "tmdb:movie:\(tmdbId)"
                    } else if let show = wlItem.show, let tmdbId = show.ids.tmdb {
                        itemId = "tmdb:tv:\(tmdbId)"
                    } else {
                        return false
                    }
                    guard allItems[itemId] == nil, !pending.contains(itemId) else { return false }
                    pending.insert(itemId)
                    return true
                }

                let traktItems: [MediaItem?] = await boundedMap(Array(missing)) { wlItem -> MediaItem? in
                    if let movie = wlItem.movie {
                        return await self.mapTraktMovieToMediaItem(movie)
                    } else if let show = wlItem.show {
                        return await self.mapTraktShowToMediaItem(show)
                    }
                    return nil
                }
                for item in traktItems.compactMap({ $0 }) {
                    allItems[item.id] = item
                    print("✅ [Home Watchlist] Trakt item \(item.title) added: \(item.id)")
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

    /// Poster (w500) and row backdrop (w780) from one TMDB details request.
    private func fetchTMDBArtwork(mediaType: String, id: Int) async -> (poster: String?, backdrop: String?) {
        let tmdb = FlixorCore.shared.tmdb
        do {
            if mediaType == "movie" {
                let detail = try await tmdb.getMovieDetails(id: id)
                return (tmdb.getPosterUrl(path: detail.posterPath, size: "w500"),
                        tmdb.getBackdropUrl(path: detail.backdropPath, size: "w780"))
            } else {
                let detail = try await tmdb.getTVDetails(id: id)
                return (tmdb.getPosterUrl(path: detail.posterPath, size: "w500"),
                        tmdb.getBackdropUrl(path: detail.backdropPath, size: "w780"))
            }
        } catch {
            return (nil, nil)
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

        var rows: [(label: String, genre: String, libKey: String)] = []
        for spec in genreRows {
            let lib = (spec.type == "movie") ? movieLib : showLib
            guard let libKey = lib?.key else { continue }
            rows.append((label: spec.label, genre: spec.genre, libKey: libKey))
        }
        let out: [LibrarySection?] = await boundedMap(rows) { spec -> LibrarySection? in
            let libKey = spec.libKey
            do {
                // Fetch items with genre filter
                let plexItems = try await plexServer.getLibraryItems(key: libKey, limit: 20, genre: spec.genre)
                let items = plexItems.map { self.toMediaItem($0) }
                guard !items.isEmpty else { return nil }
                return LibrarySection(
                    id: "genre-\(spec.genre.lowercased())",
                    title: spec.label,
                    items: Array(items.prefix(12)),
                    totalCount: items.count,
                    libraryKey: libKey,
                    browseContext: .plexDirectory(path: "/library/sections/\(libKey)/all?genre=\(spec.genre)", title: spec.label)
                )
            } catch {
                print("⚠️ [Home] Genre fetch failed for \(spec.label): \(error)")
                return nil
            }
        }
        return out.compactMap { $0 }
    }

    // MARK: - Trakt Sections

    /// Trakt rows in display order, fetched at the same time; a row that fails
    /// becomes a failure slot under its own id and title.
    private func fetchTraktSections() async -> [HomeRowSlot] {
        let rows = FlixorCore.shared.trakt.isAuthenticated
            ? TraktRow.allCases
            : TraktRow.allCases.filter { $0 == .trendingMovies || $0 == .trendingShows || $0 == .popularShows }
        let slots: [HomeRowSlot?] = await boundedMap(rows) { row -> HomeRowSlot? in
            await self.loadTraktRow(row)
        }
        return slots.compactMap { $0 }
    }

    private func loadTraktRow(_ row: TraktRow) async -> HomeRowSlot? {
        let trakt = FlixorCore.shared.trakt
        let id: String
        let title: String
        let browseContext: BrowseContext
        switch row {
        case .trendingMovies:
            id = "trakt-trending-movies"
            title = String(localized: "Trending Movies on Trakt")
            browseContext = .trakt(kind: .trendingMovies)
        case .trendingShows:
            id = "trakt-trending-shows"
            title = String(localized: "Trending TV Shows on Trakt")
            browseContext = .trakt(kind: .trendingShows)
        case .watchlist:
            id = "trakt-watchlist"
            title = String(localized: "Your Trakt Watchlist")
            browseContext = .trakt(kind: .watchlist)
        case .history:
            id = "trakt-history"
            title = String(localized: "Recently Watched")
            browseContext = .trakt(kind: .history)
        case .recommended:
            id = "trakt-recs"
            title = String(localized: "Recommended for You")
            browseContext = .trakt(kind: .recommendations)
        case .popularShows:
            id = "trakt-popular-shows"
            title = String(localized: "Popular TV Shows on Trakt")
            browseContext = .trakt(kind: .popularShows)
        }

        do {
            let items: [MediaItem]
            switch row {
            case .trendingMovies:
                let trendingMovies = try await trakt.getTrendingMovies(limit: 12)
                items = await mapTraktMoviesToMediaItems(trendingMovies.map { $0.movie })
            case .trendingShows:
                let trendingShows = try await trakt.getTrendingShows(limit: 12)
                items = await mapTraktShowsToMediaItems(trendingShows.map { $0.show })
            case .watchlist:
                let watchlist = try await trakt.getWatchlist()
                let mapped: [MediaItem?] = await boundedMap(Array(watchlist.prefix(12))) { wlItem -> MediaItem? in
                    if let movie = wlItem.movie { return await self.mapTraktMovieToMediaItem(movie) }
                    if let show = wlItem.show { return await self.mapTraktShowToMediaItem(show) }
                    return nil
                }
                items = mapped.compactMap { $0 }
            case .history:
                // Movies and shows fetched separately like mobile
                async let moviesTask = trakt.getHistory(type: "movies", page: 1, limit: 20)
                async let showsTask = trakt.getHistory(type: "shows", page: 1, limit: 20)
                let (moviesHistory, showsHistory) = try await (moviesTask, showsTask)

                // Combine and deduplicate by TMDB ID, movies first
                var seenIds = Set<String>()
                var movies: [FlixorKit.TraktMovie] = []
                var shows: [FlixorKit.TraktShow] = []
                for histItem in moviesHistory {
                    if let movie = histItem.movie, let tmdbId = movie.ids.tmdb,
                       seenIds.insert("tmdb:movie:\(tmdbId)").inserted {
                        movies.append(movie)
                    }
                }
                for histItem in showsHistory {
                    if let show = histItem.show, let tmdbId = show.ids.tmdb,
                       seenIds.insert("tmdb:tv:\(tmdbId)").inserted {
                        shows.append(show)
                    }
                }
                // Only the first 12 are shown, so only those are looked up.
                let movieCount = min(movies.count, 12)
                let showCount = min(shows.count, 12 - movieCount)
                let movieItems = await mapTraktMoviesToMediaItems(Array(movies.prefix(movieCount)))
                let showItems = await mapTraktShowsToMediaItems(Array(shows.prefix(showCount)))
                items = Array((movieItems + showItems).prefix(12))
            case .recommended:
                let recommended = try await trakt.getRecommendedMovies(limit: 12)
                items = await mapTraktMoviesToMediaItems(recommended)
            case .popularShows:
                let popularShows = try await trakt.getPopularShows(limit: 12)
                items = await mapTraktShowsToMediaItems(popularShows)
            }
            guard !items.isEmpty else { return nil }
            return .section(LibrarySection(
                id: id,
                title: title,
                items: items,
                totalCount: items.count,
                libraryKey: nil,
                browseContext: browseContext
            ))
        } catch {
            print("⚠️ [Home] Trakt row '\(title)' failed: \(error)")
            return .failure(HomeRowFailure(id: id, title: title, source: "Trakt", message: error.localizedDescription, retry: .extras))
        }
    }

    // Helpers: Trakt mappers (results keep the input order)
    private func mapTraktMoviesToMediaItems(_ movies: [FlixorKit.TraktMovie]) async -> [MediaItem] {
        let mapped: [MediaItem?] = await boundedMap(movies) { movie -> MediaItem? in
            await self.mapTraktMovieToMediaItem(movie)
        }
        return mapped.compactMap { $0 }
    }

    private func mapTraktMovieToMediaItem(_ movie: FlixorKit.TraktMovie) async -> MediaItem? {
        guard let tmdb = movie.ids.tmdb else { return nil }
        let (poster, backdrop) = await fetchTMDBArtwork(mediaType: "movie", id: tmdb)
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
        let mapped: [MediaItem?] = await boundedMap(shows) { show -> MediaItem? in
            await self.mapTraktShowToMediaItem(show)
        }
        return mapped.compactMap { $0 }
    }

    private func mapTraktShowToMediaItem(_ show: FlixorKit.TraktShow) async -> MediaItem? {
        guard let tmdb = show.ids.tmdb else { return nil }
        let (poster, backdrop) = await fetchTMDBArtwork(mediaType: "tv", id: tmdb)
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
            return FlixorCore.shared.tmdb.getBackdropUrl(path: path, size: "w780")
        }

        // Priority 2: Any language with title (iso_639_1 is not null)
        if let withLang = pick(backs.filter { $0.iso6391 != nil }), let path = withLang.filePath {
            return FlixorCore.shared.tmdb.getBackdropUrl(path: path, size: "w780")
        }

        // Priority 3: Fallback to any backdrop (including textless)
        guard let any = pick(backs), let path = any.filePath else { return nil }
        return FlixorCore.shared.tmdb.getBackdropUrl(path: path, size: "w780")
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

        let sections: [LibrarySection?] = await boundedMap(filteredLibraries) { library -> LibrarySection? in
            do {
                // Fetch recently added for this specific library
                let allItems = try await plexServer.getRecentlyAdded(libraryKey: library.key, bypassCache: bypassCache)
                // Fetch more items if grouping is enabled to account for consolidation
                let fetchLimit = shouldGroupEpisodes ? 30 : 20
                let rawItems = Array(allItems.prefix(fetchLimit))
                guard !rawItems.isEmpty else { return nil }

                let finalItems: [MediaItem]
                if shouldGroupEpisodes {
                    // Group TV episodes by series, keep movies/shows as-is
                    let processedItems = self.groupEpisodesBySeries(rawItems.map { self.toMediaItem($0) })
                    finalItems = Array(processedItems.prefix(20))
                    print("✅ [Home] Recently Added in \(library.title): \(rawItems.count) raw → \(finalItems.count) grouped items")
                } else {
                    // Show individual items without grouping
                    finalItems = Array(rawItems.prefix(20).map { self.toMediaItem($0) })
                    print("✅ [Home] Recently Added in \(library.title): \(finalItems.count) items (ungrouped)")
                }

                return LibrarySection(
                    id: "recently-added-\(library.key)",
                    title: String(localized: "Recently Added in \(library.title)"),
                    items: finalItems,
                    totalCount: finalItems.count,
                    libraryKey: library.key,
                    browseContext: .plexDirectory(
                        path: "/library/sections/\(library.key)/recentlyAdded",
                        title: String(localized: "Recently Added in \(library.title)")
                    )
                )
            } catch {
                print("⚠️ [Home] Failed to load recently added for \(library.title): \(error)")
                // Continue with other libraries
                return nil
            }
        }

        return sections.compactMap { $0 }
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

    /// Start polling for Continue Watching and Recently Added rows. Runs only
    /// while Home is visible; `visibilityChanged()` starts and stops it.
    func startPolling() {
        guard !isPolling, isHomeVisible, hasStartedLoad else { return }
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
        guard isPolling || pollTimer != nil else { return }
        pollTimer?.invalidate()
        pollTimer = nil
        isPolling = false
        print("⏹️ [Home] Polling stopped")
    }

    /// Poll only dynamic rows (Continue Watching, Recently Added per library)
    /// This is a light refresh - doesn't reload the entire home screen
    private func pollDynamicRows() async {
        // Progress is saved while playing; the row refreshes when the player closes.
        guard isHomeVisible, !PlaybackCommandState.shared.isPlayerActive else { return }
        print("🔄 [Home] Polling dynamic rows (bypassing cache)...")
        lastContinueWatchingRefresh = Date()

        // Poll Continue Watching (bypass cache to get fresh data). Trakt entries
        // come from their cache unless it has expired.
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

        guard !isStremioOnly else { return }

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

    // MARK: - Visibility

    /// The app became active / inactive (or its windows hidden / shown).
    func setAppActive(_ active: Bool) {
        isAppActive = active
        visibilityChanged()
    }

    /// Home became / stopped being the selected tab.
    func setHomeTabSelected(_ selected: Bool) {
        isHomeTabSelected = selected
        visibilityChanged()
    }

    /// Home's root view appeared / disappeared (a page pushed onto Home's stack).
    func setHomeOnScreen(_ onScreen: Bool) {
        isHomeOnScreen = onScreen
        visibilityChanged()
        // Back from a pushed player that still counts as open: the stale check
        // above skipped, so run it once the player has closed.
        guard onScreen, hasStartedLoad, PlaybackCommandState.shared.isPlayerActive else { return }
        Task { @MainActor [weak self] in
            for await isActive in PlaybackCommandState.shared.$isPlayerActive.values where !isActive {
                self?.playerActivityChanged(isActive: false)
                break
            }
        }
    }

    private func visibilityChanged() {
        let visible = isHomeVisible
        guard visible != wasHomeVisible else { return }
        wasHomeVisible = visible
        if visible {
            resumeBillboardRotation()
            guard hasStartedLoad else { return }
            startPolling()
            Task { await self.refreshContinueWatchingIfStale() }
        } else {
            stopBillboardRotation()
            stopPolling()
        }
    }

    /// A player opened or closed anywhere in the app.
    func playerActivityChanged(isActive: Bool) {
        guard !isActive, hasStartedLoad else { return }
        // Trakt progress may have moved while watching.
        traktRefreshPending = true
        if localHistoryStale {
            localHistoryStale = false
            Task { await self.loadLocalContinueWatching() }
        }
        if isHomeVisible {
            Task { await self.refreshContinueWatchingIfStale() }
        }
    }

    /// Stream playback wrote progress to the local watch history.
    func localWatchHistoryChanged() {
        guard isStremioOnly else { return }
        // Don't reload underneath the player; pick it up when it closes.
        if PlaybackCommandState.shared.isPlayerActive {
            localHistoryStale = true
            return
        }
        Task { await self.loadLocalContinueWatching() }
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
        let sections: [LibrarySection?] = await boundedMap(filteredLibraries) { library -> LibrarySection? in
            do {
                print("📦 [Home] Fetching items for library: \(library.title)")
                let items = try await plexServer.getLibraryItems(key: library.key, limit: 20)
                guard !items.isEmpty else { return nil }
                print("✅ [Home] Received \(items.count) items for \(library.title)")
                return LibrarySection(
                    id: library.key,
                    title: library.title,
                    items: items.map { self.toMediaItem($0) },
                    totalCount: items.count,
                    libraryKey: library.key,
                    browseContext: .plexLibrary(key: library.key, title: library.title)
                )
            } catch {
                print("⚠️ [Home] Failed to load library \(library.title): \(error)")
                // Continue with other libraries
                return nil
            }
        }

        return sections.compactMap { $0 }
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

        resumeBillboardRotation()
    }

    func stopBillboardRotation() {
        billboardTimer?.invalidate()
        billboardTimer = nil
    }

    /// (Re)starts the 8 s rotation, when auto-rotate is on and Home is visible.
    func resumeBillboardRotation() {
        billboardTimer?.invalidate()
        billboardTimer = nil
        guard heroAutoRotate, !billboardItems.isEmpty, isHomeVisible else { return }

        billboardTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.advanceBillboard()
            }
        }
    }

    private func advanceBillboard() {
        guard !billboardItems.isEmpty else { return }
        let newIndex = (hero.currentIndex + 1) % billboardItems.count
        withAnimation {
            hero.currentIndex = newIndex
        }
        Task { await fetchHeroColors(for: newIndex) }
    }

    // MARK: - UltraBlur Colors

    /// Fetch UltraBlur colors for the current hero/billboard item
    func fetchHeroColors(for index: Int) async {
        guard index >= 0 && index < billboardItems.count else { return }
        // Only the billboard layout tints the page; the carousel fades into a flat color.
        guard heroColorsAreShown else { return }
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

    /// Whether the page background shows the hero colors (see HomeView.homeBackground).
    private var heroColorsAreShown: Bool {
        UserDefaults.standard.heroLayout != "carousel"
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
    /// Refreshes after returning to the app or to Home, at most every 20 seconds.
    /// Trakt entries are re-fetched only after a player closed or once their cache expires.
    func refreshContinueWatchingIfStale() async {
        guard !PlaybackCommandState.shared.isPlayerActive else { return }
        if let last = lastContinueWatchingRefresh, Date().timeIntervalSince(last) < 20 { return }
        lastContinueWatchingRefresh = Date()
        let refreshTrakt = traktRefreshPending
        traktRefreshPending = false
        await reloadContinueWatching(refreshTrakt: refreshTrakt)
    }

    func refreshContinueWatching() async {
        // A watch-state change can alter Trakt progress and the next episode.
        await reloadContinueWatching(refreshTrakt: true)
    }

    private func reloadContinueWatching(refreshTrakt: Bool) async {
        if refreshTrakt {
            await TraktContinueWatchingService.shared.invalidate()
        }
        localHistoryStale = false
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
