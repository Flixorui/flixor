//
//  UserCollection.swift
//  FlixorMac
//
//  A collection the user builds from one or more sources (addon catalog, TMDB
//  discover query, TMDB movie collection, a person's credits, public Trakt
//  list). Stored per profile as JSON; see UserCollectionsStore.
//

import Foundation
import FlixorKit

struct UserCollectionCover: Codable, Hashable {
    enum Style: String, Codable, CaseIterable, Identifiable {
        case poster
        case backdrop

        var id: String { rawValue }
        var title: String { self == .poster ? "Poster" : "Backdrop" }
    }

    var url: String
    var style: Style
}

struct UserCollection: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var cover: UserCollectionCover?
    var sources: [UserCollectionSource]
    var showOnHome: Bool
    var createdAt: Date = Date()

    /// Stable id of this collection's row in the home row system.
    var homeRowId: String { "user-collection-\(id)" }

    /// What the collection's content depends on: changes only when the sources do.
    var contentKey: [UserCollectionSource.Kind] { sources.map(\.kind) }

    var sourceSummary: String {
        sources.count == 1 ? "1 source" : "\(sources.count) sources"
    }

    static func new() -> UserCollection {
        UserCollection(name: "", cover: nil, sources: [], showOnHome: false)
    }
}

struct UserCollectionSource: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var kind: Kind

    enum Kind: Codable, Hashable {
        case addonCatalog(AddonCatalog)
        case tmdbDiscover(Discover)
        case tmdbCollection(MovieCollection)
        case person(Person)
        case traktList(TraktList)
    }

    struct AddonCatalog: Codable, Hashable {
        var installationId: String
        var addonId: String
        var addonName: String
        var type: String
        var catalogId: String
        var displayName: String
    }

    struct Discover: Codable, Hashable {
        var mediaType: TMDBDiscoverMediaType = .movie
        var genreIds: [Int] = []
        var genreNames: [String] = []
        var companyId: Int?
        var companyName: String?
        var networkId: Int?
        var networkName: String?
        var yearFrom: Int?
        var yearTo: Int?
        var sort: TMDBDiscoverSort = .popularity
    }

    struct MovieCollection: Codable, Hashable {
        var id: Int
        var name: String
        var posterPath: String?
    }

    struct Person: Codable, Hashable {
        enum Credits: String, Codable, CaseIterable, Identifiable {
            case knownFor, acting, directing, allCrew

            var id: String { rawValue }

            var title: String {
                switch self {
                case .knownFor: return "Known for"
                case .acting: return "Acting"
                case .directing: return "Directing"
                case .allCrew: return "All crew work"
                }
            }
        }

        enum Order: String, Codable, CaseIterable, Identifiable {
            case popularity, newest, oldest

            var id: String { rawValue }

            var title: String {
                switch self {
                case .popularity: return "Most popular"
                case .newest: return "Newest first"
                case .oldest: return "Oldest first"
                }
            }

            var creditOrder: TMDBPersonCreditOrder {
                switch self {
                case .popularity: return .popularity
                case .newest: return .newest
                case .oldest: return .oldest
                }
            }
        }

        var id: Int
        var name: String
        var profilePath: String?
        var credits: Credits = .knownFor
        var order: Order = .popularity
    }

    struct TraktList: Codable, Hashable {
        var id: Int
        var name: String
        var owner: String?
    }

    /// The kinds of source offered by the editor.
    enum Template: String, CaseIterable, Identifiable {
        case addonCatalog, tmdbDiscover, tmdbCollection, person, traktList

        var id: String { rawValue }

        var title: String {
            switch self {
            case .addonCatalog: return "Addon catalog"
            case .tmdbDiscover: return "TMDB discover"
            case .tmdbCollection: return "TMDB movie collection"
            case .person: return "Person's credits"
            case .traktList: return "Public Trakt list"
            }
        }

        var iconName: String {
            switch self {
            case .addonCatalog: return "puzzlepiece.extension.fill"
            case .tmdbDiscover: return "slider.horizontal.3"
            case .tmdbCollection: return "film.stack.fill"
            case .person: return "person.crop.rectangle.fill"
            case .traktList: return "list.star"
            }
        }
    }

    var template: Template {
        switch kind {
        case .addonCatalog: return .addonCatalog
        case .tmdbDiscover: return .tmdbDiscover
        case .tmdbCollection: return .tmdbCollection
        case .person: return .person
        case .traktList: return .traktList
        }
    }

    var title: String {
        switch kind {
        case .addonCatalog(let catalog): return catalog.displayName
        case .tmdbDiscover(let discover): return discover.summaryTitle
        case .tmdbCollection(let collection): return collection.name
        case .person(let person): return person.name
        case .traktList(let list): return list.name
        }
    }

    var subtitle: String {
        switch kind {
        case .addonCatalog(let catalog): return catalog.addonName
        case .tmdbDiscover(let discover): return discover.summaryDetail
        case .tmdbCollection: return "TMDB movie collection"
        case .person(let person): return "\(person.credits.title), \(person.order.title.lowercased())"
        case .traktList(let list): return list.owner.map { "Trakt list by \($0)" } ?? "Trakt list"
        }
    }
}

extension UserCollectionSource.Discover {
    var summaryTitle: String {
        let media = mediaType == .movie ? "Movies" : "TV shows"
        return genreNames.isEmpty ? media : "\(genreNames.joined(separator: ", ")) \(media.lowercased())"
    }

    var summaryDetail: String {
        var parts: [String] = []
        if let companyName { parts.append(companyName) }
        if let networkName { parts.append(networkName) }
        switch (yearFrom, yearTo) {
        case let (from?, to?): parts.append(from == to ? "\(from)" : "\(from) to \(to)")
        case let (from?, nil): parts.append("From \(from)")
        case let (nil, to?): parts.append("Up to \(to)")
        case (nil, nil): break
        }
        parts.append(sort.collectionTitle)
        return parts.joined(separator: " · ")
    }

    var query: TMDBDiscoverQuery {
        var query = TMDBDiscoverQuery(mediaType: mediaType, sort: sort)
        query.genreIds = genreIds
        query.yearFrom = yearFrom
        query.yearTo = yearTo
        if let companyId { query.companyIds = [companyId] }
        if mediaType == .tv, let networkId { query.networkIds = [networkId] }
        return query
    }
}

extension TMDBDiscoverSort {
    var collectionTitle: String {
        switch self {
        case .popularity: return "Most popular"
        case .rating: return "Highest rated"
        case .newest: return "Newest first"
        case .oldest: return "Oldest first"
        case .voteCount: return "Most votes"
        case .revenue: return "Highest revenue"
        }
    }
}

/// Opens a user collection's detail page.
struct UserCollectionRoute: Hashable {
    let collectionId: String
}
