//
//  UserDefaults+Search.swift
//  FlixorMac
//
//  Profile-scoped persistence for the Search screen: recent searches, the
//  Explore/Discover choice and the Discover filters.
//

import Foundation

extension UserDefaults {
    private enum SearchScreenKeys {
        static let recentSearches = "searchRecentQueries"
        static let idleTab = "searchIdleTab"
        static let discoverFilters = "searchDiscoverFilters"
    }

    /// Maximum number of recent searches kept per profile.
    static let recentSearchesLimit = 15

    /// Recent search queries for the active profile, most recent first.
    var recentSearches: [String] {
        get { stringArray(forKey: profileKey(SearchScreenKeys.recentSearches)) ?? [] }
        set {
            set(Array(newValue.prefix(Self.recentSearchesLimit)),
                forKey: profileKey(SearchScreenKeys.recentSearches))
        }
    }

    /// Which empty-query view the Search screen shows ("explore" or "discover").
    var searchIdleTab: String? {
        get { string(forKey: profileKey(SearchScreenKeys.idleTab)) }
        set { set(newValue, forKey: profileKey(SearchScreenKeys.idleTab)) }
    }

    /// Token that changes when the active profile changes. Used by the Search
    /// screen (which survives profile switches) to reload profile-scoped state.
    var searchProfileScopeToken: String {
        profileKey(SearchScreenKeys.recentSearches)
    }
}
