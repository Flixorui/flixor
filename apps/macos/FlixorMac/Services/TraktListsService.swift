//
//  TraktListsService.swift
//  FlixorMac
//
//  The signed-in user's Trakt personal lists: read, create, delete, and add or
//  remove app items. All calls need Trakt to be connected. Trakt allows roughly
//  one write per second; `TraktService` retries once on 429.
//

import Foundation
import FlixorKit

extension Notification.Name {
    /// Posted after a list is created or deleted, or its items change.
    /// userInfo: ["listId": Int].
    static let traktListsDidChange = Notification.Name("traktListsDidChange")
}

@MainActor
final class TraktListsService {
    static let shared = TraktListsService()

    enum ListsError: LocalizedError {
        case notConnected
        case unresolved
        case notFound

        var errorDescription: String? {
            switch self {
            case .notConnected: return "Connect Trakt in Settings to use lists"
            case .unresolved: return "Couldn't find a Trakt id for this item"
            case .notFound: return "This item wasn't found on Trakt"
            }
        }
    }

    private init() {}

    var isAvailable: Bool { FlixorCore.shared.isTraktAuthenticated }

    private var trakt: TraktService { FlixorCore.shared.trakt }

    /// The user's lists.
    func myLists() async throws -> [TraktUserList] {
        guard isAvailable else { throw ListsError.notConnected }
        return try await trakt.getMyLists()
    }

    /// Items on a list. `type`: "movies", "shows", "seasons", "episodes" or nil for all.
    func items(listId: Int, type: String? = nil) async throws -> [TraktListEntry] {
        guard isAvailable else { throw ListsError.notConnected }
        return try await trakt.getListItems(listId: listId, type: type)
    }

    /// Creates a list and returns it.
    func createList(name: String, description: String? = nil, privacy: TraktListPrivacy = .private) async throws -> TraktUserList {
        guard isAvailable else { throw ListsError.notConnected }
        let list = try await trakt.createList(name: name, description: description, privacy: privacy)
        post(listId: list.id)
        return list
    }

    func deleteList(listId: Int) async throws {
        guard isAvailable else { throw ListsError.notConnected }
        try await trakt.deleteList(listId: listId)
        post(listId: listId)
    }

    /// Adds a movie, show, season or episode to a list.
    @discardableResult
    func add(_ item: MediaItem, toList listId: Int) async throws -> TraktSyncResult {
        guard let target = WatchStateTarget(item: item) else { throw ListsError.unresolved }
        return try await add(target, toList: listId)
    }

    @discardableResult
    func add(_ target: WatchStateTarget, toList listId: Int) async throws -> TraktSyncResult {
        let items = try await syncItems(for: target)
        let result = try await trakt.addToList(listId: listId, items: items)
        if result.addedCount == 0, result.existingCount == 0, result.notFoundCount > 0 {
            throw ListsError.notFound
        }
        post(listId: listId)
        return result
    }

    @discardableResult
    func remove(_ item: MediaItem, fromList listId: Int) async throws -> TraktSyncResult {
        guard let target = WatchStateTarget(item: item) else { throw ListsError.unresolved }
        return try await remove(target, fromList: listId)
    }

    @discardableResult
    func remove(_ target: WatchStateTarget, fromList listId: Int) async throws -> TraktSyncResult {
        let items = try await syncItems(for: target)
        let result = try await trakt.removeFromList(listId: listId, items: items)
        post(listId: listId)
        return result
    }

    // MARK: - Private

    private func syncItems(for target: WatchStateTarget) async throws -> TraktSyncItems {
        guard isAvailable else { throw ListsError.notConnected }
        let watchState = WatchStateService.shared
        let resolved = await watchState.resolve(target, needTitleIds: true)
        guard let items = watchState.traktItems(for: resolved) else { throw ListsError.unresolved }
        return items
    }

    private func post(listId: Int) {
        NotificationCenter.default.post(name: .traktListsDidChange, object: nil, userInfo: ["listId": listId])
    }
}
