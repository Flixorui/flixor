//
//  BrowseRoutes.swift
//  FlixorMac
//
//  Navigation routes shared by several features. Destination views are
//  registered in RootView's `navigationDestinations()`.
//

import SwiftUI

/// Full page for a row's "Browse" link (Home rows, addon catalogs, More Like This).
/// `context` is Equatable only, so the route is identified by a fresh id.
struct BrowseRoute: Hashable {
    let id = UUID()
    let context: BrowseContext
    /// The row's own title ("Trending Now"); the page falls back to the source's name.
    let title: String?

    static func == (lhs: BrowseRoute, rhs: BrowseRoute) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Full page for a cast or crew member (TMDB person).
struct PersonRoute: Hashable {
    let tmdbId: String
    let name: String
    let profilePath: String?
}

/// Browse titles from a production company or a TV network (TMDB).
struct EntityBrowseRoute: Hashable {
    enum Kind: String, Hashable {
        case company
        case network
    }

    let kind: Kind
    let id: Int
    let name: String
    let logoPath: String?
}

extension NavigationRouter {
    /// Pushes any Hashable route onto the navigation stack of `tab`.
    func push<Route: Hashable>(_ route: Route, on tab: NavItem) {
        switch tab {
        case .home: homePath.append(route)
        case .search: searchPath.append(route)
        case .library: libraryPath.append(route)
        case .myList: myListPath.append(route)
        case .newPopular: newPopularPath.append(route)
        case .downloads: downloadsPath.append(route)
        }
    }
}
