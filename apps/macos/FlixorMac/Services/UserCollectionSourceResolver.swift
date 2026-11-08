//
//  UserCollectionSourceResolver.swift
//  FlixorMac
//
//  Fetches one page of one collection source as MediaItems, and de-duplicates
//  titles across sources. Every request here is made because a collection is on
//  screen or the user asked for a preview; nothing runs in the background.
//

import Foundation
import FlixorKit

struct UserCollectionSourcePage {
    let items: [MediaItem]
    /// Pass back as `cursor` for the next page; nil when there is no more.
    let nextCursor: Int?
}

enum UserCollectionSourceError: LocalizedError {
    case addonUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .addonUnavailable(let name):
            return "\(name) isn't installed any more, or no longer offers this catalog."
        }
    }
}

enum UserCollectionSourceResolver {
    /// Items per addon catalog page; each may cost a TMDB id lookup.
    static let addonPageSize = 50
    static let traktPageSize = 50

    /// `limit` caps items for short lists (home rows, previews); nil = a full page.
    static func fetchPage(
        _ source: UserCollectionSource,
        cursor: Int? = nil,
        limit: Int? = nil
    ) async throws -> UserCollectionSourcePage {
        let tmdb = await FlixorCore.shared.tmdb
        switch source.kind {
        case .addonCatalog(let catalog):
            return try await fetchAddon(catalog, skip: cursor ?? 0, limit: limit ?? addonPageSize)

        case .tmdbDiscover(let discover):
            var query = discover.query
            let page = cursor ?? 1
            query.page = page
            let response = try await tmdb.discover(query)
            let items = capped(response.results, limit).map { MediaItem.fromTMDB($0, mediaType: discover.mediaType) }
            return UserCollectionSourcePage(items: items, nextCursor: page < (response.totalPages ?? page) ? page + 1 : nil)

        case .tmdbCollection(let collection):
            let details = try await tmdb.getCollection(id: collection.id)
            let items = capped(details.parts, limit).map { MediaItem.fromTMDB($0, mediaType: .movie) }
            return UserCollectionSourcePage(items: items, nextCursor: nil)

        case .person(let person):
            let profile = try await tmdb.getPersonProfile(id: person.id)
            let credits = Self.credits(of: profile, for: person).filter { $0.posterPath != nil }
            return UserCollectionSourcePage(items: capped(credits, limit).map { MediaItem.fromTMDB($0) }, nextCursor: nil)

        case .traktList(let list):
            let page = cursor ?? 1
            let trakt = await FlixorCore.shared.trakt
            let response = try await trakt.getPublicListItems(
                listId: list.id,
                page: page,
                limit: min(limit ?? traktPageSize, traktPageSize)
            )
            let items = response.items.compactMap(mediaItem(from:))
            return UserCollectionSourcePage(items: items, nextCursor: response.hasMore ? page + 1 : nil)
        }
    }

    /// User-facing text for a failed source.
    static func message(for error: Error) -> String {
        if let traktError = error as? TraktError, case .httpError(let status) = traktError {
            switch status {
            case 404: return "This Trakt list is private or no longer exists."
            case 429: return "Trakt's rate limit was reached. Try again in a moment."
            default: return "Trakt returned an error (\(status))."
            }
        }
        return TMDBErrorMessage.message(for: error, fallback: "This source couldn't be loaded.")
    }

    // MARK: - Sources

    private static func fetchAddon(
        _ source: UserCollectionSource.AddonCatalog,
        skip: Int,
        limit: Int
    ) async throws -> UserCollectionSourcePage {
        // Match by installation first, then by addon id so a reinstall keeps working.
        let catalogs = await StremioService.shared.getBrowsableCatalogs()
        let matches = catalogs.filter { $0.catalog.type == source.type && $0.catalog.catalogId == source.catalogId }
        guard let entry = matches.first(where: { $0.installationId == source.installationId })
            ?? matches.first(where: { $0.addonId == source.addonId }) else {
            throw UserCollectionSourceError.addonUnavailable(source.addonName)
        }

        let previews = try await StremioService.shared.fetchCatalog(
            installationId: entry.installationId,
            type: source.type,
            catalogId: source.catalogId,
            extras: skip > 0 ? ["skip": String(skip)] : [:],
            limit: limit
        )
        let items = await StremioCatalogMapper.shared.mediaItems(from: previews)
        let supportsPaging = entry.catalog.extra?.contains { $0.name == "skip" } ?? false
        return UserCollectionSourcePage(
            items: items,
            nextCursor: supportsPaging && !previews.isEmpty ? skip + previews.count : nil
        )
    }

    private static func credits(
        of profile: TMDBPersonProfile,
        for person: UserCollectionSource.Person
    ) -> [TMDBPersonCredit] {
        let order = person.order.creditOrder
        switch person.credits {
        case .knownFor:
            return profile.knownForCredits(sortedBy: order)
        case .acting:
            return profile.castCredits(sortedBy: order)
        case .allCrew:
            return profile.crewCredits(sortedBy: order)
        case .directing:
            // After de-duplication `job` can hold several jobs joined with ", ".
            return profile.crewCredits(sortedBy: order).filter { credit in
                (credit.job ?? "").components(separatedBy: ", ").contains("Director")
            }
        }
    }

    private static func mediaItem(from entry: TraktPublicListEntry) -> MediaItem? {
        guard let media = entry.movie ?? entry.show, let title = media.title, !title.isEmpty else { return nil }
        let isShow = entry.show != nil
        if let tmdbId = media.ids?.tmdb {
            return MediaItem.fromTMDB(
                id: tmdbId,
                isTV: isShow,
                title: title,
                posterPath: media.posterURL,
                backdropPath: media.fanartURL,
                date: media.released ?? media.firstAired ?? media.year.map(String.init),
                voteAverage: media.rating,
                overview: media.overview
            )
        }
        guard let imdb = media.ids?.imdb else { return nil }
        let item = MediaItem.fromTMDB(
            id: 0,
            isTV: isShow,
            title: title,
            posterPath: media.posterURL,
            backdropPath: media.fanartURL,
            date: media.released ?? media.firstAired ?? media.year.map(String.init),
            voteAverage: media.rating,
            overview: media.overview
        )
        return MediaItem(
            id: "stremio:\(isShow ? "series" : "movie"):\(imdb)",
            title: item.title, type: item.type, thumb: item.thumb, art: item.art, year: item.year,
            rating: item.rating, duration: nil, viewOffset: nil, summary: item.summary,
            grandparentTitle: nil, grandparentThumb: nil, grandparentArt: nil, grandparentRatingKey: nil,
            parentIndex: nil, index: nil, parentRatingKey: nil, parentTitle: nil, leafCount: nil, viewedLeafCount: nil
        )
    }

    private static func capped<T>(_ items: [T], _ limit: Int?) -> [T] {
        guard let limit else { return items }
        return Array(items.prefix(limit))
    }
}

// MARK: - De-duplication

/// Keeps one copy of each title across sources. Items match by id; addon items
/// that TMDB couldn't map also match by title and year.
struct UserCollectionDeduper {
    private var seenIds = Set<String>()
    private var seenTitles: [String: Bool] = [:]

    /// True the first time a title is seen.
    mutating func insert(_ item: MediaItem) -> Bool {
        guard seenIds.insert(item.id).inserted else { return false }
        let isTMDB = item.id.hasPrefix("tmdb:")
        if let year = item.year {
            let key = "\(item.type)|\(year)|\(item.title.lowercased())"
            if let seenTMDB = seenTitles[key] {
                // Two TMDB ids are two real titles, even with the same name and year.
                if !(isTMDB && seenTMDB) { return false }
            } else {
                seenTitles[key] = isTMDB
            }
        }
        return true
    }
}

// MARK: - First-page cache

/// The first items of a collection, for home rows and the cover picker.
struct UserCollectionPreview {
    struct Failure: Identifiable, Equatable {
        let id: String
        let sourceTitle: String
        let message: String
    }

    let items: [MediaItem]
    let failures: [Failure]
}

/// Cached first page of each collection. Costs nothing until asked; concurrent
/// callers share one load, and it outlives the row that started it.
actor UserCollectionPreviewCache {
    static let shared = UserCollectionPreviewCache()

    private struct Entry {
        let preview: UserCollectionPreview
        let expires: Date
    }

    private static let ttl: TimeInterval = 30 * 60
    /// Failures are retried sooner than good results expire.
    private static let failureTTL: TimeInterval = 2 * 60

    private var entries: [[UserCollectionSource.Kind]: Entry] = [:]
    private var loading: [[UserCollectionSource.Kind]: Task<UserCollectionPreview, Never>] = [:]

    /// A cached preview, if any. Never touches the network.
    func cached(for collection: UserCollection) -> UserCollectionPreview? {
        entries[collection.contentKey]?.preview
    }

    func preview(for collection: UserCollection, forceRefresh: Bool = false) async -> UserCollectionPreview {
        let key = collection.contentKey
        if !forceRefresh, let entry = entries[key], entry.expires > Date() {
            return entry.preview
        }
        if let running = loading[key] {
            return await running.value
        }
        let sources = collection.sources
        let task = Task { await Self.load(sources) }
        loading[key] = task
        let preview = await task.value
        loading[key] = nil
        let ttl = preview.failures.isEmpty ? Self.ttl : Self.failureTTL
        entries[key] = Entry(preview: preview, expires: Date().addingTimeInterval(ttl))
        return preview
    }

    /// One short page per source, interleaved so every source is represented.
    private static func load(_ sources: [UserCollectionSource]) async -> UserCollectionPreview {
        let perSource = sources.count == 1 ? 20 : max(10, 30 / sources.count)
        var pages: [Int: Result<[MediaItem], Error>] = [:]
        await withTaskGroup(of: (Int, Result<[MediaItem], Error>).self) { group in
            for (index, source) in sources.enumerated() {
                group.addTask {
                    do {
                        let page = try await UserCollectionSourceResolver.fetchPage(source, limit: perSource)
                        return (index, .success(page.items))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            for await (index, result) in group {
                pages[index] = result
            }
        }

        var failures: [UserCollectionPreview.Failure] = []
        var lists: [[MediaItem]] = []
        for (index, source) in sources.enumerated() {
            switch pages[index] {
            case .success(let items):
                lists.append(items)
            case .failure(let error):
                failures.append(.init(
                    id: source.id,
                    sourceTitle: source.title,
                    message: UserCollectionSourceResolver.message(for: error)
                ))
            case nil:
                break
            }
        }

        var deduper = UserCollectionDeduper()
        var merged: [MediaItem] = []
        let longest = lists.map(\.count).max() ?? 0
        for position in 0..<longest {
            for list in lists where position < list.count && deduper.insert(list[position]) {
                merged.append(list[position])
            }
        }
        return UserCollectionPreview(items: Array(merged.prefix(40)), failures: failures)
    }
}
