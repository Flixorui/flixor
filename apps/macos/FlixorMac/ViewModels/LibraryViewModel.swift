//
//  LibraryViewModel.swift
//  FlixorMac
//
//  View model powering the Library / Browse experience.
//

import Foundation
import SwiftUI

@MainActor
final class LibraryViewModel: ObservableObject {
    // MARK: - Types

    enum LibraryFilter: String, CaseIterable, Identifiable {
        case all
        case movies
        case shows

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return String(localized: "All")
            case .movies: return String(localized: "Movies")
            case .shows: return String(localized: "TV Shows")
            }
        }
    }

    enum SortOption: String, CaseIterable, Identifiable {
        case dateAddedDesc
        case dateAddedAsc
        case titleAsc
        case titleDesc
        case yearDesc
        case yearAsc
        case ratingDesc
        case ratingAsc

        var id: String { rawValue }

        var label: String {
            switch self {
            case .dateAddedDesc: return String(localized: "Date Added • Newest")
            case .dateAddedAsc: return String(localized: "Date Added • Oldest")
            case .titleAsc: return String(localized: "Title • A-Z")
            case .titleDesc: return String(localized: "Title • Z-A")
            case .yearDesc: return String(localized: "Release Year • Newest")
            case .yearAsc: return String(localized: "Release Year • Oldest")
            case .ratingDesc: return String(localized: "Rating • High to Low")
            case .ratingAsc: return String(localized: "Rating • Low to High")
            }
        }

        var apiParameter: String {
            switch self {
            case .dateAddedDesc: return "addedAt:desc"
            case .dateAddedAsc: return "addedAt"
            case .titleAsc: return "titleSort"
            case .titleDesc: return "titleSort:desc"
            case .yearDesc: return "year:desc"
            case .yearAsc: return "year"
            case .ratingDesc: return "rating:desc"
            case .ratingAsc: return "rating"
            }
        }
    }

    enum ViewMode: String, CaseIterable, Identifiable {
        case grid
        case list

        var id: String { rawValue }
    }

    enum ContentTab: Int, CaseIterable, Identifiable {
        case library
        case collections

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .library: return String(localized: "Library")
            case .collections: return String(localized: "Collections")
            }
        }
    }

    struct LibrarySectionSummary: Identifiable, Equatable {
        enum Kind: String {
            case movie
            case show
            case other
        }

        let id: String
        let title: String
        let kind: Kind
    }

    struct LibraryEntry: Identifiable {
        let id: String
        let media: MediaItem
        let addedAt: Date?
        let rating: Double?
        let year: Int?
    }

    struct CollectionEntry: Identifiable {
        let id: String
        let title: String
        let artwork: URL?
        let count: Int
    }

    struct FilterOption: Identifiable, Equatable {
        let id: String
        let label: String
        let value: String
    }

    // MARK: - Published State

    @Published private(set) var sections: [LibrarySectionSummary] = []
    @Published var activeSection: LibrarySectionSummary? {
        didSet {
            guard activeSection?.id != oldValue?.id else { return }
            if let id = activeSection?.id {
                if contentTab == .library { settings.lastTab = LibraryScreenSettings.sectionTab(id) }
                restoreSort(for: id)
            }
            startReload()
        }
    }

    @Published var filter: LibraryFilter = .all {
        didSet {
            guard oldValue != filter else { return }
            Task { await selectSectionForFilter() }
        }
    }

    @Published var sort: SortOption = .dateAddedDesc {
        didSet {
            guard oldValue != sort else { return }
            applyFilters()
            if !isRestoringSort, settings.rememberSort, let id = activeSection?.id {
                settings.setRememberedSort(sort.rawValue, section: id)
            }
            // The server pages in sort order, so with pages still to come start again
            // from the first one. What is loaded stays on screen until it arrives.
            if !isRestoringSort, let id = activeSection?.id, hasMore || isLoading {
                startReload(refreshFacets: facetsSectionId != id, keepItems: true)
            }
        }
    }

    @Published var viewMode: ViewMode = .grid {
        didSet { if settings.rememberViewMode { settings.lastViewMode = viewMode.rawValue } }
    }
    @Published var contentTab: ContentTab = .library {
        didSet {
            if contentTab == .collections {
                settings.lastTab = LibraryScreenSettings.collectionsTab
            } else if let id = activeSection?.id {
                settings.lastTab = LibraryScreenSettings.sectionTab(id)
            }
            guard contentTab == .collections else { return }
            Task { await loadCollectionsIfNeeded() }
        }
    }

    @Published var searchQuery: String = "" {
        didSet {
            guard oldValue != searchQuery else { return }
            scheduleSearchFilter()
        }
    }

    @Published private(set) var items: [LibraryEntry] = []
    @Published private(set) var visibleItems: [LibraryEntry] = []
    @Published private(set) var collections: [CollectionEntry] = []

    @Published private(set) var genres: [FilterOption] = []
    @Published private(set) var years: [FilterOption] = []
    @Published private(set) var selectedGenre: FilterOption?
    @Published private(set) var selectedYear: FilterOption?
    /// A whole decade (e.g. 2010 for the 2010s), sent as Plex's `decade` filter.
    @Published private(set) var selectedDecade: Int?

    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var isLoadingCollections: Bool = false
    @Published var hasMore: Bool = false
    @Published var errorMessage: String?

    // MARK: - Private

    private let api = APIClient.shared
    private let settings = LibraryScreenSettings.shared
    private var isRestoringSort = false
    private let pageSize = 50
    private var offsets: [String: Int] = [:]
    private var totals: [String: Int] = [:]
    private var sectionsLoaded = false
    private var collectionsCache: [String: [CollectionEntry]] = [:]

    /// Lowercased title and summary for each entry in `items`, same order.
    private struct SearchKey {
        let title: String
        let summary: String?
    }
    private var itemSearchKeys: [SearchKey] = []
    /// The sort `items` arrived in from the server; nil until the first page.
    private var itemsSort: SortOption?
    /// Section whose genre and year lists are loaded.
    private var facetsSectionId: String?
    private var loadTask: Task<Void, Never>?
    /// Bumped by each reload; responses for an older one are dropped.
    private var loadGeneration = 0
    private var searchTask: Task<Void, Never>?

    // MARK: - Public API

    func loadIfNeeded() async {
        guard !sectionsLoaded else { return }
        if settings.rememberViewMode, let mode = ViewMode(rawValue: settings.lastViewMode ?? "") {
            viewMode = mode
        }
        do {
            try await fetchSections()
            sectionsLoaded = true
            if activeSection == nil {
                await selectSectionForFilter()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectSection(_ section: LibrarySectionSummary) {
        activeSection = section
    }

    /// Total titles in the active section for the current filters, once the
    /// server has reported it.
    var activeTotal: Int? {
        activeSection.flatMap { totals[$0.id] }
    }

    func updateGenre(_ option: FilterOption?) {
        guard selectedGenre?.id != option?.id else { return }
        selectedGenre = option
        saveFilters()
        startReload(refreshFacets: false)
    }

    func updateYear(_ option: FilterOption?) {
        guard selectedYear?.id != option?.id || selectedDecade != nil else { return }
        selectedYear = option
        selectedDecade = nil
        saveFilters()
        startReload(refreshFacets: false)
    }

    // MARK: Remembered sort and filters (Settings > Library Screen)

    private func restoreSort(for sectionId: String) {
        guard settings.rememberSort,
              let raw = settings.rememberedSort(section: sectionId),
              let saved = SortOption(rawValue: raw), saved != sort else { return }
        isRestoringSort = true
        sort = saved
        isRestoringSort = false
    }

    private func restoreFilters(for sectionId: String) {
        guard settings.rememberFilters else { return }
        let saved = settings.rememberedFilters(section: sectionId)
        selectedGenre = saved["genre"].flatMap { id in genres.first { $0.id == id } }
        if let year = saved["year"] {
            selectedYear = years.first { $0.id == year }
        } else if let decade = saved["decade"].flatMap(Int.init) {
            selectedDecade = decade
        }
    }

    private func saveFilters() {
        guard settings.rememberFilters, let id = activeSection?.id else { return }
        var filters: [String: String] = [:]
        filters["genre"] = selectedGenre?.id
        filters["year"] = selectedYear?.id
        if let decade = selectedDecade { filters["decade"] = String(decade) }
        settings.setRememberedFilters(filters, section: id)
    }

    /// Filters to a whole decade; replaces any single-year filter.
    func updateDecade(_ decade: Int?) {
        guard selectedDecade != decade || selectedYear != nil else { return }
        selectedDecade = decade
        selectedYear = nil
        saveFilters()
        startReload(refreshFacets: false)
    }

    /// Decades that have at least one title, newest first.
    var decades: [Int] {
        Set(years.compactMap { Int($0.value) }.map { $0 / 10 * 10 }).sorted(by: >)
    }

    /// The library's years within a decade, newest first.
    func years(inDecade decade: Int) -> [FilterOption] {
        years.filter { Int($0.value).map { $0 / 10 * 10 == decade } ?? false }
    }

    var hasActiveFilters: Bool {
        selectedGenre != nil || selectedYear != nil || selectedDecade != nil
    }

    func clearFilters() {
        updateGenre(nil)
        updateYear(nil)
        updateDecade(nil)
    }

    func loadMoreIfNeeded(currentItem item: LibraryEntry) {
        guard contentTab == .library,
              hasMore,
              !isLoading,
              !isLoadingMore,
              let index = visibleItems.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        let thresholdIndex = visibleItems.index(visibleItems.endIndex, offsetBy: -5, limitedBy: visibleItems.startIndex) ?? visibleItems.startIndex
        if index >= thresholdIndex {
            Task { await fetchItems(reset: false) }
        }
    }

    func retry() async {
        errorMessage = nil
        sectionsLoaded = false
        let hadSection = activeSection != nil
        await loadIfNeeded()
        // loadIfNeeded only loads items when it picks a section, so reload the one
        // already showing. Keeps the current filters and sort.
        if hadSection, errorMessage == nil, activeSection != nil {
            startReload(refreshFacets: false)
        }
    }

    // MARK: - Data Loading

    private func fetchSections() async throws {
        struct LibraryResponse: Codable {
            let key: String
            let title: String
            let type: String
        }

        let libs: [LibraryResponse] = try await api.get("/api/plex/libraries")
        let mapped = libs.map { lib -> LibrarySectionSummary in
            let kind: LibrarySectionSummary.Kind
            switch lib.type {
            case "movie": kind = .movie
            case "show": kind = .show
            default: kind = .other
            }
            return LibrarySectionSummary(id: lib.key, title: lib.title, kind: kind)
        }
        sections = mapped.filter { $0.kind != .other }
        if sections.isEmpty {
            errorMessage = String(localized: "No Plex libraries available. Connect a Plex server in Settings.")
        }
    }

    private func selectSectionForFilter() async {
        guard !sections.isEmpty else { return }
        switch filter {
        case .all:
            if activeSection == nil {
                // Settings > Library Screen > Default Tab (or the tab used last).
                let ordered = settings.ordered(sections) { $0.id }
                let tab = settings.defaultTab == LibraryScreenSettings.lastUsedTab
                    ? (settings.lastTab ?? "") : settings.defaultTab
                if tab == LibraryScreenSettings.collectionsTab, settings.showCollectionsTab {
                    activeSection = ordered.first
                    contentTab = .collections
                } else if let match = ordered.first(where: { LibraryScreenSettings.sectionTab($0.id) == tab }) {
                    activeSection = match
                } else {
                    activeSection = ordered.first
                }
            }
        case .movies:
            if let movie = sections.first(where: { $0.kind == .movie }) {
                activeSection = movie
            }
        case .shows:
            if let show = sections.first(where: { $0.kind == .show }) {
                activeSection = show
            }
        }
    }

    /// Cancels any load in progress and starts a new one for the active section.
    private func startReload(refreshFacets: Bool = true, keepItems: Bool = false) {
        loadTask?.cancel()
        loadGeneration &+= 1
        let generation = loadGeneration
        loadTask = Task { [weak self] in
            await self?.reloadCurrentSection(refreshFacets: refreshFacets, keepItems: keepItems, generation: generation)
        }
    }

    /// - Parameter refreshFacets: Reload the genre/year lists (a new section).
    ///   Filter changes pass false: reloading the lists resets the selected
    ///   genre and year, which used to undo the filter before the fetch.
    /// - Parameter keepItems: Leave the current items on screen until the first page arrives.
    private func reloadCurrentSection(refreshFacets: Bool, keepItems: Bool, generation: Int) async {
        guard let section = activeSection, generation == loadGeneration else { return }
        isLoading = true
        if !keepItems {
            items = []
            itemSearchKeys = []
            visibleItems = []
        }
        offsets[section.id] = 0
        totals[section.id] = nil
        clearCollectionCacheIfNeeded(for: section)

        let needsFacets = refreshFacets || facetsSectionId != section.id
        if refreshFacets {
            selectedGenre = nil
            selectedYear = nil
            selectedDecade = nil
        }
        let restoresFilters = refreshFacets
            && settings.rememberFilters
            && !settings.rememberedFilters(section: section.id).isEmpty

        if needsFacets && restoresFilters {
            // Saved filters need the genre/year lists before the first page.
            await fetchFacets(for: section, generation: generation)
            guard generation == loadGeneration else { return }
            restoreFilters(for: section.id)
            await fetchItems(reset: true)
        } else if needsFacets {
            async let facets: Void = fetchFacets(for: section, generation: generation)
            await fetchItems(reset: true)
            await facets
        } else {
            await fetchItems(reset: true)
        }

        guard generation == loadGeneration else { return }
        if contentTab == .collections {
            await loadCollectionsIfNeeded()
        }
    }

    private func fetchFacets(for section: LibrarySectionSummary, generation: Int) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchGenres(for: section, generation: generation) }
            group.addTask { await self.fetchYears(for: section, generation: generation) }
        }
        if generation == loadGeneration, !Task.isCancelled {
            facetsSectionId = section.id
        }
    }

    private func fetchGenres(for section: LibrarySectionSummary, generation: Int) async {
        struct DirectoryEntry: Codable {
            let key: String?
            let title: String?
        }
        struct DirectoryContainer: Codable {
            let Directory: [DirectoryEntry]?
        }
        struct DirectoryResponse: Codable {
            let MediaContainer: DirectoryContainer?
            let Directory: [DirectoryEntry]?
        }

        do {
            let response: DirectoryResponse = try await api.get("/api/plex/library/\(section.id)/genre")
            guard generation == loadGeneration else { return }
            let dirs = response.MediaContainer?.Directory ?? response.Directory ?? []
            genres = dirs.compactMap {
                guard let key = $0.key, let title = $0.title else { return nil }
                return FilterOption(id: key, label: title, value: key)
            }.sorted { $0.label < $1.label }
        } catch {
            guard generation == loadGeneration else { return }
            genres = []
        }
    }

    private func fetchYears(for section: LibrarySectionSummary, generation: Int) async {
        struct DirectoryEntry: Codable {
            let key: String?
            let title: String?
        }
        struct DirectoryContainer: Codable {
            let Directory: [DirectoryEntry]?
        }
        struct DirectoryResponse: Codable {
            let MediaContainer: DirectoryContainer?
            let Directory: [DirectoryEntry]?
        }

        do {
            let response: DirectoryResponse = try await api.get("/api/plex/library/\(section.id)/year")
            guard generation == loadGeneration else { return }
            let dirs = response.MediaContainer?.Directory ?? response.Directory ?? []
            years = dirs.compactMap {
                guard let key = $0.key, let title = $0.title else { return nil }
                return FilterOption(id: key, label: title, value: key)
            }
            .sorted { ($0.value) > ($1.value) }
        } catch {
            guard generation == loadGeneration else { return }
            years = []
        }
    }

    func fetchItems(reset: Bool) async {
        guard let section = activeSection else { return }
        let generation = loadGeneration
        let requestedSort = sort

        if reset {
            isLoading = true
        } else {
            guard hasMore, !isLoadingMore else { return }
            isLoadingMore = true
        }

        struct Response: Codable {
            let size: Int?
            let totalSize: Int?
            let offset: Int?
            let Metadata: [MediaItemFull]?
        }

        let offset = reset ? 0 : (offsets[section.id] ?? 0)

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "offset", value: "\(offset)"),
            URLQueryItem(name: "limit", value: "\(pageSize)"),
            URLQueryItem(name: "sort", value: requestedSort.apiParameter)
        ]
        if let genre = selectedGenre?.value {
            queryItems.append(URLQueryItem(name: "genre", value: genre))
        }
        if let year = selectedYear?.value {
            queryItems.append(URLQueryItem(name: "year", value: year))
        } else if let decade = selectedDecade {
            queryItems.append(URLQueryItem(name: "decade", value: String(decade)))
        }

        do {
            let response: Response = try await api.get("/api/plex/library/\(section.id)/all", queryItems: queryItems)
            // A newer reload replaced this request: keep its results off the grid.
            guard generation == loadGeneration, activeSection?.id == section.id else {
                if !reset { isLoadingMore = false }
                return
            }
            let metadata = response.Metadata ?? []
            let mapped = metadata.map { mapMedia($0) }
            let keys = mapped.map(Self.searchKey(for:))

            if reset {
                items = mapped
                itemSearchKeys = keys
                itemsSort = requestedSort
                offsets[section.id] = mapped.count
            } else {
                items.append(contentsOf: mapped)
                itemSearchKeys.append(contentsOf: keys)
                offsets[section.id] = (offsets[section.id] ?? 0) + mapped.count
            }

            let total = response.totalSize ?? response.size ?? ((offsets[section.id] ?? 0) + max(0, mapped.count))
            totals[section.id] = total
            hasMore = (offsets[section.id] ?? 0) < total
            if !reset, itemsSort == sort {
                // Already in order: add the new page's matches at the end.
                visibleItems.append(contentsOf: filtered(mapped, keys: keys))
            } else {
                applyFilters()
            }
        } catch {
            guard generation == loadGeneration, !Task.isCancelled else {
                if !reset { isLoadingMore = false }
                return
            }
            if reset {
                // A failed first page leaves nothing to page from: drop any items
                // kept on screen so a later load-more can't append a duplicate page.
                items = []
                itemSearchKeys = []
                visibleItems = []
                hasMore = false
            }
            errorMessage = error.localizedDescription
        }

        isLoading = false
        isLoadingMore = false
    }

    private func mapMedia(_ metadata: MediaItemFull) -> LibraryEntry {
        var media = metadata.toMediaItem()

        // Ensure unique id includes library ratingKey prefix
        if !media.id.hasPrefix("plex:") {
            media = MediaItem(
                id: "plex:\(media.id)",
                title: media.title,
                type: media.type,
                thumb: media.thumb,
                art: media.art,
                year: media.year,
                rating: media.rating,
                duration: media.duration,
                viewOffset: media.viewOffset,
                summary: media.summary,
                grandparentTitle: media.grandparentTitle,
                grandparentThumb: media.grandparentThumb,
                grandparentArt: media.grandparentArt,
                grandparentRatingKey: media.grandparentRatingKey,
                parentIndex: media.parentIndex,
                index: media.index,
                parentRatingKey: media.parentRatingKey,
                parentTitle: media.parentTitle,
                leafCount: media.leafCount,
                viewedLeafCount: media.viewedLeafCount,
                editionTitle: media.editionTitle
            )
        }

        let addedAtDate: Date?
        if let addedAt = metadata.addedAt {
            addedAtDate = Date(timeIntervalSince1970: TimeInterval(addedAt))
        } else {
            addedAtDate = nil
        }

        return LibraryEntry(
            id: media.id,
            media: media,
            addedAt: addedAtDate,
            rating: metadata.rating,
            year: metadata.year
        )
    }

    private static func searchKey(for entry: LibraryEntry) -> SearchKey {
        SearchKey(title: entry.media.title.lowercased(), summary: entry.media.summary?.lowercased())
    }

    /// Applies the search text after a short pause in typing; clearing it applies at once.
    private func scheduleSearchFilter() {
        searchTask?.cancel()
        if searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            applyFilters()
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            self?.applyFilters()
        }
    }

    private func filtered(_ entries: [LibraryEntry], keys: [SearchKey]) -> [LibraryEntry] {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return entries }
        let term = searchQuery.lowercased()
        var output: [LibraryEntry] = []
        for (entry, key) in zip(entries, keys)
        where key.title.contains(term) || key.summary?.contains(term) == true {
            output.append(entry)
        }
        return output
    }

    private func applyFilters() {
        var output = filtered(items, keys: itemSearchKeys)

        // Items keep the server's order for the sort they were fetched with; a sort
        // chosen since then is applied locally.
        if itemsSort != sort {
            output.sort { lhs, rhs in
                switch sort {
                case .dateAddedDesc:
                    return (lhs.addedAt ?? .distantPast) > (rhs.addedAt ?? .distantPast)
                case .dateAddedAsc:
                    return (lhs.addedAt ?? .distantPast) < (rhs.addedAt ?? .distantPast)
                case .titleAsc:
                    return lhs.media.title.localizedCaseInsensitiveCompare(rhs.media.title) == .orderedAscending
                case .titleDesc:
                    return lhs.media.title.localizedCaseInsensitiveCompare(rhs.media.title) == .orderedDescending
                case .yearDesc:
                    return (lhs.year ?? 0) > (rhs.year ?? 0)
                case .yearAsc:
                    return (lhs.year ?? 0) < (rhs.year ?? 0)
                case .ratingDesc:
                    return (lhs.rating ?? -Double.infinity) > (rhs.rating ?? -Double.infinity)
                case .ratingAsc:
                    return (lhs.rating ?? Double.infinity) < (rhs.rating ?? Double.infinity)
                }
            }
        }

        visibleItems = output
    }

    // MARK: - Collections

    private func loadCollectionsIfNeeded() async {
        guard let section = activeSection else { return }
        if let cached = collectionsCache[section.id] {
            collections = cached
            return
        }
        await fetchCollections(for: section)
    }

    private func fetchCollections(for section: LibrarySectionSummary) async {
        struct Response: Codable {
            struct Container: Codable { let Metadata: [Metadata]? }
            struct Metadata: Codable {
                let ratingKey: String?
                let title: String?
                let thumb: String?
                let composite: String?
                let childCount: Int?
            }
            let MediaContainer: Container?
            let Metadata: [Metadata]?
        }

        isLoadingCollections = true
        defer { isLoadingCollections = false }

        do {
            let response: Response = try await api.get("/api/plex/library/\(section.id)/collections")
            let metadata = response.MediaContainer?.Metadata ?? response.Metadata ?? []
            let mapped: [CollectionEntry] = metadata.compactMap { entry in
                guard let id = entry.ratingKey, let title = entry.title else { return nil }
                let artPath = entry.composite ?? entry.thumb
                let url = ImageService.shared.plexImageURL(path: artPath, width: 600, height: 360)
                return CollectionEntry(
                    id: id,
                    title: title,
                    artwork: url,
                    count: entry.childCount ?? 0
                )
            }
            collectionsCache[section.id] = mapped
            collections = mapped
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearCollectionCacheIfNeeded(for section: LibrarySectionSummary) {
        guard contentTab == .collections else { return }
        collections = collectionsCache[section.id] ?? []
    }
}
