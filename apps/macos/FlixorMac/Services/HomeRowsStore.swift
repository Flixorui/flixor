//
//  HomeRowsStore.swift
//  FlixorMac
//
//  Observable owner of the per-profile home screen customisation: row order,
//  custom titles, hidden rows, the list of known rows, hero source and
//  Continue Watching options. HomeViewModel registers the rows it builds;
//  Rows Settings lists, reorders, renames and hides them.
//

import Combine
import SwiftUI

@MainActor
final class HomeRowsStore: ObservableObject {
    static let shared = HomeRowsStore()

    private let defaults = UserDefaults.standard
    private var profileObserver: AnyCancellable?

    /// User row order (row ids). Empty = default order.
    @Published private(set) var order: [String]
    /// Custom titles by row id.
    @Published private(set) var titles: [String: String]
    /// Individually hidden row ids.
    @Published private(set) var hidden: Set<String>
    /// Known rows in default order.
    @Published private(set) var catalog: [HomeRowDescriptor]

    @Published var heroSource: HomeHeroSource {
        didSet {
            guard heroSource != oldValue else { return }
            defaults.homeHeroSource = heroSource
        }
    }

    @Published var continueWatchingSort: ContinueWatchingSort {
        didSet {
            guard continueWatchingSort != oldValue else { return }
            defaults.continueWatchingSort = continueWatchingSort
        }
    }

    @Published var continueWatchingBlurNextUp: Bool {
        didSet {
            guard continueWatchingBlurNextUp != oldValue else { return }
            defaults.continueWatchingBlurNextUp = continueWatchingBlurNextUp
        }
    }

    private init() {
        order = defaults.homeRowOrder
        titles = defaults.homeRowTitles
        hidden = Set(defaults.homeRowHidden)
        catalog = defaults.homeRowCatalog
        heroSource = defaults.homeHeroSource
        continueWatchingSort = defaults.continueWatchingSort
        continueWatchingBlurNextUp = defaults.continueWatchingBlurNextUp

        // Profile switches call ProfileSettings.reloadFromStorage(), which
        // republishes every setting; re-read ours when that happens.
        profileObserver = ProfileSettings.shared.objectWillChange
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.reload()
                }
            }
    }

    /// Re-reads everything for the current profile. Only publishes values that changed.
    func reload() {
        let newOrder = defaults.homeRowOrder
        if newOrder != order { order = newOrder }
        let newTitles = defaults.homeRowTitles
        if newTitles != titles { titles = newTitles }
        let newHidden = Set(defaults.homeRowHidden)
        if newHidden != hidden { hidden = newHidden }
        let newCatalog = defaults.homeRowCatalog
        if newCatalog != catalog { catalog = newCatalog }
        let newHero = defaults.homeHeroSource
        if newHero != heroSource { heroSource = newHero }
        let newSort = defaults.continueWatchingSort
        if newSort != continueWatchingSort { continueWatchingSort = newSort }
        let newBlur = defaults.continueWatchingBlurNextUp
        if newBlur != continueWatchingBlurNextUp { continueWatchingBlurNextUp = newBlur }
    }

    // MARK: - Known rows

    private static let groupOrder: [HomeRowGroup] = [.continueWatching, .recentlyAdded, .collections, .userCollections, .extras]

    /// Replaces the known rows of one group (called by HomeViewModel after the
    /// group loads). Groups keep their default position relative to each other.
    func register(_ descriptors: [HomeRowDescriptor], group: HomeRowGroup) {
        var seen = Set<String>()
        let unique = descriptors.filter { $0.group == group && seen.insert($0.id).inserted }
        var byGroup = Dictionary(grouping: catalog, by: \.group)
        byGroup[group] = unique
        let merged = Self.groupOrder.flatMap { byGroup[$0] ?? [] }
        guard merged != catalog else { return }
        catalog = merged
        defaults.homeRowCatalog = merged
    }

    /// Known rows in the user's order.
    var orderedCatalog: [HomeRowDescriptor] {
        Self.ordered(catalog, id: \.id, userOrder: order)
    }

    var hasCustomOrder: Bool { !order.isEmpty }

    // MARK: - Titles

    /// The title to show for a row: the custom title if set, else `defaultTitle`.
    func title(for id: String, default defaultTitle: String) -> String {
        if let custom = titles[id], !custom.isEmpty { return custom }
        return defaultTitle
    }

    func customTitle(for id: String) -> String? { titles[id] }

    /// Sets a custom title; nil, blank or the default title removes it.
    func rename(_ id: String, to newTitle: String?, defaultTitle: String) {
        let trimmed = newTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var next = titles
        if trimmed.isEmpty || trimmed == defaultTitle {
            next.removeValue(forKey: id)
        } else {
            next[id] = trimmed
        }
        guard next != titles else { return }
        titles = next
        defaults.homeRowTitles = next
    }

    // MARK: - Visibility

    func isHidden(_ id: String) -> Bool { hidden.contains(id) }

    func setHidden(_ id: String, _ isHidden: Bool) {
        var next = hidden
        if isHidden { next.insert(id) } else { next.remove(id) }
        guard next != hidden else { return }
        hidden = next
        defaults.homeRowHidden = Array(next).sorted()
    }

    func showAllRows() {
        guard !hidden.isEmpty else { return }
        hidden = []
        defaults.homeRowHidden = []
    }

    // MARK: - Order

    /// Moves rows within `orderedCatalog` (List `.onMove` semantics).
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var ids = orderedCatalog.map(\.id)
        let moving = source.sorted().map { ids[$0] }
        let insertAt = destination - source.filter { $0 < destination }.count
        for index in source.sorted(by: >) { ids.remove(at: index) }
        ids.insert(contentsOf: moving, at: max(0, min(insertAt, ids.count)))
        setOrder(keepingUnlistedRows(ids))
    }

    /// Moves one row up (-1) or down (+1).
    func move(_ id: String, by delta: Int) {
        var ids = orderedCatalog.map(\.id)
        guard let index = ids.firstIndex(of: id) else { return }
        let target = index + delta
        guard ids.indices.contains(target) else { return }
        ids.swapAt(index, target)
        setOrder(keepingUnlistedRows(ids))
    }

    func resetOrder() {
        setOrder([])
    }

    /// Keeps the saved position of rows not listed right now (e.g. Plex rows
    /// while in Stremio-only mode) so a reorder doesn't forget them.
    private func keepingUnlistedRows(_ ids: [String]) -> [String] {
        let listed = Set(ids)
        return ids + order.filter { !listed.contains($0) }
    }

    private func setOrder(_ ids: [String]) {
        guard ids != order else { return }
        order = ids
        defaults.homeRowOrder = ids
    }

    // MARK: - Ordering helper

    /// Applies a user order to items in default order. Items in `userOrder`
    /// follow it; items it doesn't know (new rows, placeholders) stay right
    /// after the nearest preceding known item of the default order.
    static func ordered<T>(_ items: [T], id: (T) -> String, userOrder: [String]) -> [T] {
        guard !userOrder.isEmpty else { return items }
        var rank: [String: Int] = [:]
        for (index, rowId) in userOrder.enumerated() where rank[rowId] == nil {
            rank[rowId] = index
        }
        var lastKey = -1.0
        var keyed: [(key: Double, index: Int, item: T)] = []
        keyed.reserveCapacity(items.count)
        for (index, item) in items.enumerated() {
            if let known = rank[id(item)] {
                lastKey = Double(known)
                keyed.append((lastKey, index, item))
            } else {
                keyed.append((lastKey + 0.5, index, item))
            }
        }
        return keyed
            .sorted { $0.key != $1.key ? $0.key < $1.key : $0.index < $1.index }
            .map(\.item)
    }
}
