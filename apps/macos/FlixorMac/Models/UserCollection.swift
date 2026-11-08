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
        var title: String { self == .poster ? String(localized: "Poster") : String(localized: "Backdrop") }
    }

    var url: String
    var style: Style

    private enum CodingKeys: String, CodingKey {
        case url, style
    }
}

// Decoding is tolerant below: a missing or unknown optional field falls back to its
// default, so entries written by another build aren't dropped and then erased by the
// next save. Only what identifies an entry stays required. Each `init(from:)` is in
// an extension to keep the memberwise initializer.

extension UserCollectionCover {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(String.self, forKey: .url)
        style = (try? container.decodeIfPresent(Style.self, forKey: .style)) ?? .poster
    }
}

struct UserCollection: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var cover: UserCollectionCover?
    var sources: [UserCollectionSource]
    var showOnHome: Bool
    var createdAt: Date = Date()

    private enum CodingKeys: String, CodingKey {
        case id, name, cover, sources, showOnHome, createdAt
    }

    /// Stable id of this collection's row in the home row system.
    var homeRowId: String { "user-collection-\(id)" }

    /// What the collection's content depends on: changes only when the sources do.
    var contentKey: [UserCollectionSource.Kind] { sources.map(\.kind) }

    var sourceSummary: String {
        String(localized: "\(sources.count) sources")
    }

    static func new() -> UserCollection {
        UserCollection(name: "", cover: nil, sources: [], showOnHome: false)
    }
}

extension UserCollection {
    /// Keeps the sources it can read when another one can't be decoded.
    private struct LossySource: Decodable {
        let value: UserCollectionSource?

        init(from decoder: Decoder) throws {
            value = try? UserCollectionSource(from: decoder)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        cover = try? container.decodeIfPresent(UserCollectionCover.self, forKey: .cover)
        let entries = (try? container.decodeIfPresent([LossySource].self, forKey: .sources)) ?? []
        sources = entries.compactMap(\.value)
        showOnHome = (try? container.decodeIfPresent(Bool.self, forKey: .showOnHome)) ?? false
        createdAt = (try? container.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date()
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

        private enum CodingKeys: String, CodingKey {
            case installationId, addonId, addonName, type, catalogId, displayName
        }
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

        private enum CodingKeys: String, CodingKey {
            case mediaType, genreIds, genreNames, companyId, companyName, networkId, networkName, yearFrom, yearTo, sort
        }
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
                case .knownFor: return String(localized: "Known for")
                case .acting: return String(localized: "Acting")
                case .directing: return String(localized: "Directing")
                case .allCrew: return String(localized: "All crew work")
                }
            }
        }

        enum Order: String, Codable, CaseIterable, Identifiable {
            case popularity, newest, oldest

            var id: String { rawValue }

            var title: String {
                switch self {
                case .popularity: return String(localized: "Most popular")
                case .newest: return String(localized: "Newest first")
                case .oldest: return String(localized: "Oldest first")
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

        private enum CodingKeys: String, CodingKey {
            case id, name, profilePath, credits, order
        }
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
            case .addonCatalog: return String(localized: "Addon catalog")
            case .tmdbDiscover: return String(localized: "TMDB discover")
            case .tmdbCollection: return String(localized: "TMDB movie collection")
            case .person: return String(localized: "Person's credits")
            case .traktList: return String(localized: "Public Trakt list")
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
        case .tmdbCollection: return String(localized: "TMDB movie collection")
        case .person(let person): return "\(person.credits.title), \(person.order.title.lowercased())"
        case .traktList(let list): return list.owner.map { String(localized: "Trakt list by \($0)") } ?? String(localized: "Trakt list")
        }
    }
}

extension UserCollectionSource.AddonCatalog {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        installationId = try container.decode(String.self, forKey: .installationId)
        addonId = try container.decode(String.self, forKey: .addonId)
        type = try container.decode(String.self, forKey: .type)
        catalogId = try container.decode(String.self, forKey: .catalogId)
        addonName = (try? container.decodeIfPresent(String.self, forKey: .addonName)) ?? ""
        displayName = (try? container.decodeIfPresent(String.self, forKey: .displayName)) ?? catalogId
    }
}

extension UserCollectionSource.Discover {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mediaType = (try? container.decodeIfPresent(TMDBDiscoverMediaType.self, forKey: .mediaType)) ?? .movie
        genreIds = (try? container.decodeIfPresent([Int].self, forKey: .genreIds)) ?? []
        genreNames = (try? container.decodeIfPresent([String].self, forKey: .genreNames)) ?? []
        companyId = try? container.decodeIfPresent(Int.self, forKey: .companyId)
        companyName = try? container.decodeIfPresent(String.self, forKey: .companyName)
        networkId = try? container.decodeIfPresent(Int.self, forKey: .networkId)
        networkName = try? container.decodeIfPresent(String.self, forKey: .networkName)
        yearFrom = try? container.decodeIfPresent(Int.self, forKey: .yearFrom)
        yearTo = try? container.decodeIfPresent(Int.self, forKey: .yearTo)
        sort = (try? container.decodeIfPresent(TMDBDiscoverSort.self, forKey: .sort)) ?? .popularity
    }
}

extension UserCollectionSource.Person {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        profilePath = try? container.decodeIfPresent(String.self, forKey: .profilePath)
        credits = (try? container.decodeIfPresent(Credits.self, forKey: .credits)) ?? .knownFor
        order = (try? container.decodeIfPresent(Order.self, forKey: .order)) ?? .popularity
    }
}

extension UserCollectionSource.Discover {
    var summaryTitle: String {
        let media = mediaType == .movie ? String(localized: "Movies") : String(localized: "TV shows")
        return genreNames.isEmpty ? media : "\(genreNames.joined(separator: ", ")) \(media.lowercased())"
    }

    var summaryDetail: String {
        var parts: [String] = []
        if let companyName { parts.append(companyName) }
        if let networkName { parts.append(networkName) }
        switch (yearFrom, yearTo) {
        case let (from?, to?): parts.append(from == to ? "\(from)" : String(localized: "\(String(from)) to \(String(to))"))
        case let (from?, nil): parts.append(String(localized: "From \(String(from))"))
        case let (nil, to?): parts.append(String(localized: "Up to \(String(to))"))
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
        case .popularity: return String(localized: "Most popular")
        case .rating: return String(localized: "Highest rated")
        case .newest: return String(localized: "Newest first")
        case .oldest: return String(localized: "Oldest first")
        case .voteCount: return String(localized: "Most votes")
        case .revenue: return String(localized: "Highest revenue")
        }
    }
}

/// Opens a user collection's detail page.
struct UserCollectionRoute: Hashable {
    let collectionId: String
}
