//
//  TraktListsViewModel.swift
//  FlixorMac
//
//  The user's Trakt personal lists on the My List screen: which list is selected,
//  its items (filtered and sorted like My List), and creating, editing, deleting
//  and removing from lists.
//
//  Trakt allows about one write per second, so writes are batched and update local
//  state rather than re-fetching, and change notifications are coalesced.
//

import Foundation
import SwiftUI
import Combine
import FlixorKit

@MainActor
final class TraktListsViewModel: ObservableObject {
    typealias FilterType = MyListViewModel.FilterType
    typealias SortOption = MyListViewModel.SortOption

    private struct LoadedList {
        var items: [TraktListGridItem]
        var hiddenPeopleCount: Int
        /// Every entry on the list, including people the grid can't show.
        var entryCount: Int
        var loadedAt: Date
    }

    @Published private(set) var isConnected = false
    @Published private(set) var lists: [TraktUserList] = []
    @Published private(set) var isLoadingLists = false
    @Published private(set) var listsError: String?
    /// Nil means the merged My List view.
    @Published private(set) var selectedListId: Int?

    @Published private(set) var items: [TraktListGridItem] = []
    @Published private(set) var visibleItems: [TraktListGridItem] = []
    @Published private(set) var hiddenPeopleCount = 0
    @Published private(set) var isLoadingItems = false
    @Published private(set) var itemsError: String?
    /// A write to Trakt is in flight.
    @Published private(set) var isMutating = false

    @Published var filter: FilterType = .all {
        didSet { applyFilters() }
    }
    @Published var sort: SortOption = .dateAdded {
        didSet { applyFilters() }
    }
    @Published var searchQuery = "" {
        didSet { applyFilters() }
    }
    @Published var bulkMode = false
    @Published var selectedIDs: Set<Int> = []

    private let service = TraktListsService.shared
    private let api = APIClient.shared

    private var loaded: [Int: LoadedList] = [:]
    private var posterURLs: [String: URL] = [:]

    private var listsTask: Task<Void, Never>?
    private var listsGeneration = 0
    private var isListsRequestInFlight = false
    private var itemsTask: Task<Void, Never>?
    private var itemsGeneration = 0
    private var posterTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var rateLimitRetryTask: Task<Void, Never>?
    private var rateLimitRetries = 0

    /// Changes our own writes announce are already applied locally.
    private var ownWriteDepth = 0
    private var changedListIds: Set<Int> = []
    private var connectionKey: Int?
    private var changeObserver: AnyCancellable?

    /// A cached list is shown at once and re-fetched when older than this.
    private let freshnessInterval: TimeInterval = 60
    private let refreshDebounceNanos: UInt64 = 600_000_000
    private let rateLimitRetryNanos: UInt64 = 15_000_000_000
    private let maxRateLimitRetries = 2
    private let posterBatchSize = 12

    init() {
        changeObserver = NotificationCenter.default
            .publisher(for: .traktListsDidChange)
            .sink { [weak self] notification in
                let listId = notification.userInfo?["listId"] as? Int
                MainActor.assumeIsolated {
                    self?.handleListsChanged(listId: listId)
                }
            }
    }

    // MARK: - Derived

    var selectedList: TraktUserList? {
        guard let selectedListId else { return nil }
        return lists.first { $0.id == selectedListId }
    }

    /// Live count once a list has been loaded, Trakt's own count until then.
    func count(for list: TraktUserList) -> Int {
        loaded[list.id]?.entryCount ?? list.itemCount
    }

    /// "12 titles · Private · Description" for the page header.
    var selectedListSummary: String? {
        guard let list = selectedList else { return nil }
        let titleCount = items.isEmpty && loaded[list.id] == nil ? list.itemCount : items.count
        var parts = [String(localized: "\(titleCount) titles")]
        if hiddenPeopleCount > 0 {
            parts.append(String(localized: "\(hiddenPeopleCount) people not shown"))
        }
        if let privacy = list.privacy.flatMap(TraktListPrivacy.init(rawValue:)) {
            parts.append(privacy.displayName)
        }
        if let description = list.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
            parts.append(description)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Connection

    /// Re-reads the Trakt connection. Cheap: only acts when it changed. There is no
    /// sign-in notification, so the view calls this on appear, on tab change and
    /// when the window becomes key (Settings is a sheet over this screen).
    func refreshConnection() {
        let connected = service.isAvailable
        let key = connected ? FlixorCore.shared.trakt.getTokens()?.accessToken.hashValue : nil
        guard connected != isConnected || key != connectionKey else { return }

        let wasConnected = isConnected
        isConnected = connected
        connectionKey = key

        guard connected else {
            resetForDisconnect()
            return
        }

        // A new token can mean a different account, so nothing cached can be trusted.
        loaded.removeAll()
        loadLists(quiet: wasConnected)
        if let selectedListId {
            loadItems(listId: selectedListId, quiet: true)
        }
    }

    private func resetForDisconnect() {
        invalidateListsLoad()
        refreshTask?.cancel()
        rateLimitRetryTask?.cancel()
        rateLimitRetryTask = nil
        listsError = nil
        lists = []
        loaded.removeAll()
        select(nil)
    }

    // MARK: - Selection

    func select(_ listId: Int?) {
        guard listId != selectedListId else { return }
        selectedListId = listId
        bulkMode = false
        selectedIDs = []
        searchQuery = ""
        itemsError = nil
        cancelItemsLoad()
        posterTask?.cancel()

        guard let listId else {
            items = []
            hiddenPeopleCount = 0
            applyFilters()
            return
        }

        if let cached = loaded[listId] {
            items = cached.items
            hiddenPeopleCount = cached.hiddenPeopleCount
            applyFilters()
            loadPosters(listId: listId)
            if Date().timeIntervalSince(cached.loadedAt) > freshnessInterval {
                loadItems(listId: listId, quiet: true)
            }
        } else {
            items = []
            hiddenPeopleCount = 0
            applyFilters()
            loadItems(listId: listId, quiet: false)
        }
    }

    func toggleSelection(for item: TraktListGridItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    func clearSelection() {
        selectedIDs.removeAll()
    }

    // MARK: - Loading

    func loadLists(quiet: Bool = false) {
        guard isConnected else { return }
        invalidateListsLoad()
        isListsRequestInFlight = true
        let generation = listsGeneration
        if !quiet {
            isLoadingLists = true
            listsError = nil
        }

        listsTask = Task { [weak self] in
            guard let service = self?.service else { return }
            do {
                let lists = try await service.myLists()
                guard let self, generation == self.listsGeneration else { return }
                self.isListsRequestInFlight = false
                self.isLoadingLists = false
                self.applyLists(lists)
            } catch {
                guard let self, generation == self.listsGeneration, !Self.isCancellation(error) else { return }
                self.isListsRequestInFlight = false
                self.isLoadingLists = false
                // A failed background refresh keeps the lists already on screen.
                if self.lists.isEmpty {
                    self.listsError = Self.describe(error)
                }
                self.handleLoadFailure(error)
            }
        }
    }

    private func invalidateListsLoad() {
        listsTask?.cancel()
        listsGeneration += 1
        isListsRequestInFlight = false
        isLoadingLists = false
    }

    /// Retries whatever failed. Also the target of the automatic rate-limit retry.
    func retry() {
        if listsError != nil {
            loadLists()
        }
        if let selectedListId, itemsError != nil {
            loadItems(listId: selectedListId, quiet: !items.isEmpty)
        }
    }

    private func applyLists(_ fetched: [TraktUserList]) {
        listsError = nil
        rateLimitRetries = 0
        lists = sorted(fetched)

        let ids = Set(fetched.map(\.id))
        loaded = loaded.filter { ids.contains($0.key) }
        if let selectedListId, !ids.contains(selectedListId) {
            select(nil)
        }
    }

    private func sorted(_ lists: [TraktUserList]) -> [TraktUserList] {
        lists.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func cancelItemsLoad() {
        itemsTask?.cancel()
        itemsGeneration += 1
        isLoadingItems = false
    }

    private func loadItems(listId: Int, quiet: Bool) {
        cancelItemsLoad()
        let generation = itemsGeneration
        if !quiet {
            isLoadingItems = true
        }
        itemsError = nil

        itemsTask = Task { [weak self] in
            guard let service = self?.service else { return }
            do {
                let entries = try await service.items(listId: listId)
                guard let self, generation == self.itemsGeneration else { return }
                self.applyEntries(entries, listId: listId)
            } catch {
                guard let self, generation == self.itemsGeneration, !Self.isCancellation(error) else { return }
                self.isLoadingItems = false
                if Self.status(of: error) == 404 {
                    self.handleListGone(listId: listId)
                    return
                }
                self.itemsError = Self.describe(error)
                self.handleLoadFailure(error)
            }
        }
    }

    private func applyEntries(_ entries: [TraktListEntry], listId: Int) {
        var mapped = entries.compactMap(TraktListGridItem.init(entry:))
        for index in mapped.indices {
            if let key = mapped[index].posterKey, let url = posterURLs[key] {
                mapped[index].imageURL = url
            }
        }
        let people = entries.filter { $0.type == "person" }.count
        loaded[listId] = LoadedList(
            items: mapped,
            hiddenPeopleCount: people,
            entryCount: entries.count,
            loadedAt: Date()
        )

        isLoadingItems = false
        itemsError = nil
        rateLimitRetries = 0
        guard listId == selectedListId else { return }

        items = mapped
        hiddenPeopleCount = people
        selectedIDs.formIntersection(mapped.map(\.id))
        applyFilters()
        loadPosters(listId: listId)
    }

    private func handleListGone(listId: Int) {
        loaded[listId] = nil
        lists.removeAll { $0.id == listId }
        if selectedListId == listId {
            select(nil)
            ToastManager.shared.show(String(localized: "That list no longer exists on Trakt"), type: .info)
        }
    }

    private func handleLoadFailure(_ error: Error) {
        if Self.isSignedOut(error) {
            refreshConnection()
        } else if Self.status(of: error) == 429 {
            scheduleRateLimitRetry()
        }
    }

    /// TraktService has already retried once; give Trakt longer before trying again.
    private func scheduleRateLimitRetry() {
        guard rateLimitRetryTask == nil, rateLimitRetries < maxRateLimitRetries else { return }
        rateLimitRetries += 1
        let delay = rateLimitRetryNanos
        rateLimitRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, let self else { return }
            self.rateLimitRetryTask = nil
            self.retry()
        }
    }

    // MARK: - Change notifications

    private func handleListsChanged(listId: Int?) {
        guard ownWriteDepth == 0 else { return }
        if let id = listId ?? selectedListId {
            changedListIds.insert(id)
            loaded[id] = nil
        }

        // Adding several titles posts once per title; refresh once they settle.
        refreshTask?.cancel()
        let delay = refreshDebounceNanos
        refreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, let self else { return }
            let changed = self.changedListIds
            self.changedListIds = []
            self.loadLists(quiet: true)
            if let selected = self.selectedListId, changed.contains(selected) {
                self.loadItems(listId: selected, quiet: true)
            }
        }
    }

    // MARK: - Posters

    private func loadPosters(listId: Int) {
        posterTask?.cancel()
        guard let source = loaded[listId]?.items else { return }

        var seen = Set<String>()
        var pending: [(key: String, isMovie: Bool, tmdbId: Int)] = []
        for item in source {
            guard let key = item.posterKey, let tmdbId = item.tmdbId,
                  posterURLs[key] == nil, seen.insert(key).inserted else { continue }
            pending.append((key, item.mediaType == .movie, tmdbId))
        }
        guard !pending.isEmpty else { return }

        let batchSize = posterBatchSize
        posterTask = Task { [weak self] in
            for start in stride(from: 0, to: pending.count, by: batchSize) {
                let batch = pending[start..<min(start + batchSize, pending.count)]
                let results = await withTaskGroup(of: (String, URL?).self) { group -> [(String, URL?)] in
                    for entry in batch {
                        group.addTask { [weak self] in
                            (entry.key, await self?.fetchPoster(isMovie: entry.isMovie, tmdbId: entry.tmdbId))
                        }
                    }
                    var collected: [(String, URL?)] = []
                    for await result in group {
                        collected.append(result)
                    }
                    return collected
                }
                guard !Task.isCancelled, let self else { return }
                self.applyPosters(results, listId: listId)
            }
        }
    }

    private func fetchPoster(isMovie: Bool, tmdbId: Int) async -> URL? {
        struct Details: Codable { let poster_path: String? }
        do {
            let details: Details = try await api.get("/api/tmdb/\(isMovie ? "movie" : "tv")/\(tmdbId)")
            guard let path = details.poster_path else { return nil }
            return ImageService.shared.proxyImageURL(url: "https://image.tmdb.org/t/p/w342\(path)")
        } catch {
            return nil
        }
    }

    private func applyPosters(_ results: [(String, URL?)], listId: Int) {
        var found: [String: URL] = [:]
        for case let (key, url?) in results {
            found[key] = url
        }
        guard !found.isEmpty else { return }
        posterURLs.merge(found) { _, new in new }

        func fill(_ target: inout [TraktListGridItem]) {
            for index in target.indices {
                if let key = target[index].posterKey, let url = found[key] {
                    target[index].imageURL = url
                }
            }
        }

        if var cached = loaded[listId] {
            fill(&cached.items)
            loaded[listId] = cached
        }
        if listId == selectedListId {
            fill(&items)
            applyFilters()
        }
    }

    // MARK: - Removing items

    func remove(_ item: TraktListGridItem) async {
        _ = await remove(items: [item])
    }

    func removeSelected() async {
        let targets = items.filter { selectedIDs.contains($0.id) }
        if await remove(items: targets) {
            selectedIDs.removeAll()
            bulkMode = false
        }
    }

    private func remove(items targets: [TraktListGridItem]) async -> Bool {
        guard let list = selectedList, !targets.isEmpty, !isMutating else { return false }

        var payload = TraktSyncItems()
        var removable: [TraktListGridItem] = []
        for item in targets {
            guard let sync = item.syncItems else { continue }
            payload.movies += sync.movies
            payload.shows += sync.shows
            removable.append(item)
        }
        guard !payload.isEmpty else {
            ToastManager.shared.show(String(localized: "Couldn't find a Trakt id for this item"), type: .error)
            return false
        }

        // A load already in flight would bring the removed entries back.
        cancelItemsLoad()
        do {
            let result = try await performWrite {
                try await service.remove(payload, fromList: list.id)
            }
            // "Not found" means already gone, which is what was asked for.
            let accountedFor = result.deletedCount + result.notFoundCount
            guard accountedFor > 0 else {
                ToastManager.shared.show(String(localized: "Trakt didn't remove anything from \(list.name)"), type: .error)
                return false
            }
            applyRemoval(of: Set(removable.map(\.id)), listId: list.id)
            if accountedFor < removable.count {
                // Trakt doesn't say which ones failed; show what is really there.
                if selectedListId == list.id {
                    loadItems(listId: list.id, quiet: true)
                }
                ToastManager.shared.show(String(localized: "Some titles couldn't be removed from \(list.name)"), type: .info)
            } else if removable.count == 1, let item = removable.first {
                ToastManager.shared.show(String(localized: "Removed \(item.title) from \(list.name)"), type: .success)
            } else {
                ToastManager.shared.show(String(localized: "Removed \(removable.count) titles from \(list.name)"), type: .success)
            }
            return true
        } catch {
            ToastManager.shared.show(String(localized: "Couldn't remove from \(list.name): \(Self.describe(error))"), type: .error)
            handleWriteFailure(error)
            return false
        }
    }

    private func applyRemoval(of ids: Set<Int>, listId: Int) {
        // Anything fetched while the write was in flight may predate it.
        cancelItemsLoad()
        if var cached = loaded[listId] {
            let before = cached.items.count
            cached.items.removeAll { ids.contains($0.id) }
            cached.entryCount -= before - cached.items.count
            loaded[listId] = cached
        }
        if listId == selectedListId {
            items.removeAll { ids.contains($0.id) }
            selectedIDs.subtract(ids)
            applyFilters()
        }
    }

    // MARK: - Creating, editing, deleting lists

    /// Creates a list and selects it. Returns an error message, or nil on success.
    func createList(name: String, description: String, privacy: TraktListPrivacy) async -> String? {
        guard !isMutating else { return String(localized: "Another change is still saving.") }
        do {
            let created = try await performWrite {
                try await service.createList(
                    name: name,
                    description: description.isEmpty ? nil : description,
                    privacy: privacy
                )
            }
            lists = sorted(lists + [created])
            select(created.id)
            ToastManager.shared.show(String(localized: "Created \(created.name)"), type: .success)
            return nil
        } catch {
            handleWriteFailure(error)
            return Self.describe(error)
        }
    }

    /// Saves a list's details. Returns an error message, or nil on success.
    func updateList(_ list: TraktUserList, name: String, description: String, privacy: TraktListPrivacy) async -> String? {
        guard !isMutating else { return String(localized: "Another change is still saving.") }
        do {
            let updated = try await performWrite {
                try await service.updateList(listId: list.id, name: name, description: description, privacy: privacy)
            }
            lists = sorted(lists.map { $0.id == updated.id ? updated : $0 })
            ToastManager.shared.show(String(localized: "Saved \(updated.name)"), type: .success)
            return nil
        } catch {
            handleWriteFailure(error)
            return Self.describe(error)
        }
    }

    func deleteList(_ list: TraktUserList) async {
        guard !isMutating else { return }
        do {
            try await performWrite {
                try await service.deleteList(listId: list.id)
            }
            removeDeletedList(list)
            ToastManager.shared.show(String(localized: "Deleted \(list.name)"), type: .success)
        } catch {
            if Self.status(of: error) == 404 {
                removeDeletedList(list)
                ToastManager.shared.show(String(localized: "Deleted \(list.name)"), type: .success)
                return
            }
            ToastManager.shared.show(String(localized: "Couldn't delete \(list.name): \(Self.describe(error))"), type: .error)
            handleWriteFailure(error)
        }
    }

    private func removeDeletedList(_ list: TraktUserList) {
        if selectedListId == list.id {
            select(nil)
        }
        lists.removeAll { $0.id == list.id }
        loaded[list.id] = nil
    }

    private func performWrite<T>(_ operation: () async throws -> T) async throws -> T {
        // A list fetch sent before this write would undo it when it lands.
        let interruptedListsLoad = isListsRequestInFlight
        invalidateListsLoad()
        isMutating = true
        ownWriteDepth += 1
        defer {
            isMutating = false
            ownWriteDepth -= 1
            if interruptedListsLoad {
                loadLists(quiet: !lists.isEmpty)
            }
        }
        return try await operation()
    }

    private func handleWriteFailure(_ error: Error) {
        if Self.isSignedOut(error) {
            refreshConnection()
        }
    }

    // MARK: - Filtering

    private func applyFilters() {
        var working = items

        switch filter {
        case .all:
            break
        case .movies:
            working = working.filter { $0.mediaType == .movie }
        case .shows:
            working = working.filter { $0.mediaType == .show }
        }

        let term = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !term.isEmpty {
            working = working.filter { $0.matches(term) }
        }

        switch sort {
        case .dateAdded:
            working.sort { ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast) }
        case .title:
            working.sort { $0.parentTitle.localizedCaseInsensitiveCompare($1.parentTitle) == .orderedAscending }
        case .year:
            working.sort { ($0.year ?? 0) > ($1.year ?? 0) }
        case .rating:
            working.sort { ($0.rating ?? -1) > ($1.rating ?? -1) }
        }

        visibleItems = working
        // Bulk actions must only reach titles the user can see.
        let visibleIDs = Set(working.map(\.id))
        if !selectedIDs.isSubset(of: visibleIDs) { selectedIDs.formIntersection(visibleIDs) }
    }

    // MARK: - Errors

    private static func status(of error: Error) -> Int? {
        if case TraktError.httpError(let status) = error { return status }
        return nil
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        return (error as? URLError)?.code == .cancelled
    }

    private static func isSignedOut(_ error: Error) -> Bool {
        if case TraktListsService.ListsError.notConnected = error { return true }
        if case TraktError.authenticationRequired = error { return true }
        return false
    }

    private static func describe(_ error: Error) -> String {
        if let error = error as? TraktError {
            switch error {
            case .authenticationRequired, .noRefreshToken:
                return String(localized: "Your Trakt session has expired. Reconnect Trakt in Settings.")
            case .httpError(let status):
                switch status {
                case 429:
                    return String(localized: "Trakt is limiting requests right now. Try again in a moment.")
                case 404:
                    return String(localized: "This list no longer exists on Trakt.")
                case 409:
                    return String(localized: "You already have a list with that name.")
                case 420:
                    return String(localized: "You've reached the number of lists your Trakt account allows.")
                case 423:
                    return String(localized: "Your Trakt account is locked.")
                case 500...599:
                    return String(localized: "Trakt is having problems right now. Try again later.")
                default:
                    return String(localized: "Trakt returned an error (\(status)).")
                }
            default:
                return String(localized: "Trakt sent an unexpected response.")
            }
        }
        if error is URLError {
            return String(localized: "Couldn't reach Trakt. Check your connection.")
        }
        if error is DecodingError {
            return String(localized: "Trakt sent data this app couldn't read.")
        }
        return error.localizedDescription
    }
}

extension TraktListPrivacy {
    var displayName: String {
        switch self {
        case .private: return String(localized: "Private")
        case .link: return String(localized: "Anyone with the link")
        case .friends: return String(localized: "Friends")
        case .public: return String(localized: "Public")
        }
    }
}
