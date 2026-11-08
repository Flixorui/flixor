//
//  UserDefaults+HomeRows.swift
//  FlixorMac
//
//  Profile-scoped home screen customisation: row order, custom row titles,
//  hidden rows, the list of known rows, hero source and Continue Watching
//  options. Read and write through `HomeRowsStore.shared` in UI code so views
//  update.
//

import Foundation

extension UserDefaults {
    private enum HomeRowKeys {
        static let order = "homeRowOrder"
        static let titles = "homeRowTitles"
        static let hidden = "homeRowHidden"
        static let catalog = "homeRowCatalog"
        static let heroSource = "homeHeroSource"
        static let continueWatchingSort = "continueWatchingSort"
        static let continueWatchingBlurNextUp = "continueWatchingBlurNextUp"
    }

    /// User row order (row ids). Empty = default order.
    var homeRowOrder: [String] {
        get { stringArray(forKey: profileKey(HomeRowKeys.order)) ?? [] }
        set { set(newValue, forKey: profileKey(HomeRowKeys.order)) }
    }

    /// Custom row titles by row id.
    var homeRowTitles: [String: String] {
        get { dictionary(forKey: profileKey(HomeRowKeys.titles)) as? [String: String] ?? [:] }
        set { set(newValue, forKey: profileKey(HomeRowKeys.titles)) }
    }

    /// Individually hidden row ids.
    var homeRowHidden: [String] {
        get { stringArray(forKey: profileKey(HomeRowKeys.hidden)) ?? [] }
        set { set(newValue, forKey: profileKey(HomeRowKeys.hidden)) }
    }

    /// Rows the home screen produced last time, in default order.
    var homeRowCatalog: [HomeRowDescriptor] {
        get {
            guard let data = data(forKey: profileKey(HomeRowKeys.catalog)) else { return [] }
            return (try? JSONDecoder().decode([HomeRowDescriptor].self, from: data)) ?? []
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            set(data, forKey: profileKey(HomeRowKeys.catalog))
        }
    }

    /// Hero source ("default", "continueWatching", "myList", "row:<id>").
    var homeHeroSource: HomeHeroSource {
        get { HomeHeroSource(storageValue: string(forKey: profileKey(HomeRowKeys.heroSource))) }
        set { set(newValue.storageValue, forKey: profileKey(HomeRowKeys.heroSource)) }
    }

    /// Continue Watching order. Default: recently watched.
    var continueWatchingSort: ContinueWatchingSort {
        get {
            string(forKey: profileKey(HomeRowKeys.continueWatchingSort)).flatMap(ContinueWatchingSort.init(rawValue:)) ?? .recent
        }
        set { set(newValue.rawValue, forKey: profileKey(HomeRowKeys.continueWatchingSort)) }
    }

    /// Blur stills of up-next episodes in Continue Watching. Default off.
    var continueWatchingBlurNextUp: Bool {
        get { object(forKey: profileKey(HomeRowKeys.continueWatchingBlurNextUp)) as? Bool ?? false }
        set { set(newValue, forKey: profileKey(HomeRowKeys.continueWatchingBlurNextUp)) }
    }
}
