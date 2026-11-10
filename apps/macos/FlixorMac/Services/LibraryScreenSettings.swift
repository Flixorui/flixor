//
//  LibraryScreenSettings.swift
//  FlixorMac
//
//  Settings > Library Screen: grid appearance, header options, tab order and
//  what the Library remembers between visits. Stored per profile (keys go
//  through `profileKey`, like the Home and Details settings).
//

import Foundation
import Combine
import SwiftUI

enum LibraryPosterSize: String, CaseIterable, Identifiable {
    case followHome, small, medium, large, xlarge
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .followHome: return String(localized: "Same as Home")
        case .small: return CardPosterSize.small.displayName
        case .medium: return CardPosterSize.medium.displayName
        case .large: return CardPosterSize.large.displayName
        case .xlarge: return CardPosterSize.xlarge.displayName
        }
    }

    /// The card size to use, resolving "Same as Home" to the Home setting.
    func resolved(homeSize: String) -> CardPosterSize {
        switch self {
        case .followHome: return CardPosterSize(stored: homeSize)
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xlarge: return .xlarge
        }
    }
}

enum LibraryGridDensity: String, CaseIterable, Identifiable {
    case compact, comfortable
    var id: String { rawValue }
    var displayName: String { self == .compact ? String(localized: "Compact") : String(localized: "Comfortable") }
    /// Gap between posters.
    var spacing: CGFloat { self == .compact ? DS.Space.s10 : DS.Space.s18 }
}

enum LibraryTitleDisplay: String, CaseIterable, Identifiable {
    case titleAndYear, titleOnly, none
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .titleAndYear: return String(localized: "Title and year")
        case .titleOnly: return String(localized: "Title only")
        case .none: return String(localized: "None")
        }
    }
}

@MainActor
final class LibraryScreenSettings: ObservableObject {
    static let shared = LibraryScreenSettings()

    /// Stored value of `defaultTab` meaning "the tab used last".
    static let lastUsedTab = "last"
    /// Stored tab value for the Collections tab; Plex sections use "section:<id>".
    static let collectionsTab = "collections"
    static func sectionTab(_ id: String) -> String { "section:\(id)" }

    private enum Keys {
        static let posterSize = "library.posterSize"
        static let density = "library.density"
        static let titleDisplay = "library.titleDisplay"
        static let showGenreChips = "library.showGenreChips"
        static let tabOrder = "library.tabOrder"
        static let showCollectionsTab = "library.showCollectionsTab"
        static let defaultTab = "library.defaultTab"
        static let rememberViewMode = "library.rememberViewMode"
        static let rememberSort = "library.rememberSort"
        static let rememberFilters = "library.rememberFilters"
        // Memory, written as the Library is used
        static let lastViewMode = "library.lastViewMode"
        static let lastTab = "library.lastTab"
        static let sortBySection = "library.sortBySection"
        static let filtersBySection = "library.filtersBySection"
    }

    private let defaults = UserDefaults.standard
    private var isLoading = false
    private var profileObserver: AnyCancellable?

    @Published var posterSize: LibraryPosterSize = .followHome { didSet { save(posterSize.rawValue, Keys.posterSize) } }
    @Published var density: LibraryGridDensity = .comfortable { didSet { save(density.rawValue, Keys.density) } }
    @Published var titleDisplay: LibraryTitleDisplay = .titleAndYear { didSet { save(titleDisplay.rawValue, Keys.titleDisplay) } }
    @Published var showGenreChips = true { didSet { save(showGenreChips, Keys.showGenreChips) } }
    /// Plex section ids in tab order; sections not listed keep Plex's order after these.
    @Published var tabOrder: [String] = [] { didSet { save(tabOrder, Keys.tabOrder) } }
    @Published var showCollectionsTab = true { didSet { save(showCollectionsTab, Keys.showCollectionsTab) } }
    @Published var defaultTab: String = LibraryScreenSettings.lastUsedTab { didSet { save(defaultTab, Keys.defaultTab) } }
    @Published var rememberViewMode = true { didSet { save(rememberViewMode, Keys.rememberViewMode) } }
    @Published var rememberSort = true { didSet { save(rememberSort, Keys.rememberSort) } }
    @Published var rememberFilters = false { didSet { save(rememberFilters, Keys.rememberFilters) } }

    private init() {
        reload()
        // Profile switches republish ProfileSettings; follow them (as DetailsSectionsStore does).
        profileObserver = ProfileSettings.shared.objectWillChange
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in Task { @MainActor [weak self] in self?.reload() } }
    }

    func reload() {
        isLoading = true
        defer { isLoading = false }
        posterSize = LibraryPosterSize(rawValue: string(Keys.posterSize) ?? "") ?? .followHome
        density = LibraryGridDensity(rawValue: string(Keys.density) ?? "") ?? .comfortable
        titleDisplay = LibraryTitleDisplay(rawValue: string(Keys.titleDisplay) ?? "") ?? .titleAndYear
        showGenreChips = bool(Keys.showGenreChips, default: true)
        tabOrder = defaults.stringArray(forKey: defaults.profileKey(Keys.tabOrder)) ?? []
        showCollectionsTab = bool(Keys.showCollectionsTab, default: true)
        defaultTab = string(Keys.defaultTab) ?? Self.lastUsedTab
        rememberViewMode = bool(Keys.rememberViewMode, default: true)
        rememberSort = bool(Keys.rememberSort, default: true)
        rememberFilters = bool(Keys.rememberFilters, default: false)
    }

    func resetToDefaults() {
        for key in [Keys.posterSize, Keys.density, Keys.titleDisplay, Keys.showGenreChips, Keys.tabOrder,
                    Keys.showCollectionsTab, Keys.defaultTab, Keys.rememberViewMode, Keys.rememberSort, Keys.rememberFilters] {
            defaults.removeObject(forKey: defaults.profileKey(key))
        }
        reload()
    }

    // MARK: Tab order

    /// `sections` sorted by the saved tab order.
    func ordered<T>(_ sections: [T], id: (T) -> String) -> [T] {
        let rank = Dictionary(tabOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return sections.enumerated().sorted { a, b in
            let ra = rank[id(a.element)] ?? (tabOrder.count + a.offset)
            let rb = rank[id(b.element)] ?? (tabOrder.count + b.offset)
            return ra < rb
        }.map(\.element)
    }

    /// Moves `id` to the position of `target` among `currentIds` (the visible order).
    func moveTab(_ id: String, to target: String, currentIds: [String]) {
        var ids = currentIds
        guard id != target, let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: target) else { return }
        ids.remove(at: from)
        ids.insert(id, at: to)
        tabOrder = ids
    }

    // MARK: Memory

    var lastViewMode: String? {
        get { string(Keys.lastViewMode) }
        set { defaults.set(newValue, forKey: defaults.profileKey(Keys.lastViewMode)) }
    }

    var lastTab: String? {
        get { string(Keys.lastTab) }
        set { defaults.set(newValue, forKey: defaults.profileKey(Keys.lastTab)) }
    }

    func rememberedSort(section: String) -> String? {
        (defaults.dictionary(forKey: defaults.profileKey(Keys.sortBySection)) as? [String: String])?[section]
    }

    func setRememberedSort(_ sort: String, section: String) {
        var all = (defaults.dictionary(forKey: defaults.profileKey(Keys.sortBySection)) as? [String: String]) ?? [:]
        all[section] = sort
        defaults.set(all, forKey: defaults.profileKey(Keys.sortBySection))
    }

    /// Saved filters for a section: keys "genre", "year", "decade".
    func rememberedFilters(section: String) -> [String: String] {
        ((defaults.dictionary(forKey: defaults.profileKey(Keys.filtersBySection)) as? [String: [String: String]]) ?? [:])[section] ?? [:]
    }

    func setRememberedFilters(_ filters: [String: String], section: String) {
        var all = (defaults.dictionary(forKey: defaults.profileKey(Keys.filtersBySection)) as? [String: [String: String]]) ?? [:]
        all[section] = filters.isEmpty ? nil : filters
        defaults.set(all, forKey: defaults.profileKey(Keys.filtersBySection))
    }

    // MARK: Storage helpers

    private func save(_ value: Any, _ key: String) {
        guard !isLoading else { return }
        defaults.set(value, forKey: defaults.profileKey(key))
    }

    private func string(_ key: String) -> String? { defaults.string(forKey: defaults.profileKey(key)) }

    private func bool(_ key: String, default value: Bool) -> Bool {
        defaults.object(forKey: defaults.profileKey(key)) as? Bool ?? value
    }
}
