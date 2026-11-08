//
//  TraktListsService+Editing.swift
//  FlixorMac
//
//  List edits used by the My List screen: updating a list's details, and removing
//  many entries in one request (Trakt allows roughly one write per second, so
//  bulk removal must not loop).
//

import Foundation
import FlixorKit

extension TraktListsService {
    /// Updates a list's name, description and privacy, and returns it.
    func updateList(
        listId: Int,
        name: String,
        description: String,
        privacy: TraktListPrivacy
    ) async throws -> TraktUserList {
        guard isAvailable else { throw ListsError.notConnected }
        let list = try await FlixorCore.shared.trakt.updateList(
            listId: listId,
            name: name,
            description: description,
            privacy: privacy
        )
        postChange(listId: listId)
        return list
    }

    /// Removes everything in `items` from a list with a single request.
    @discardableResult
    func remove(_ items: TraktSyncItems, fromList listId: Int) async throws -> TraktSyncResult {
        guard isAvailable else { throw ListsError.notConnected }
        let result = try await FlixorCore.shared.trakt.removeFromList(listId: listId, items: items)
        postChange(listId: listId)
        return result
    }

    private func postChange(listId: Int) {
        NotificationCenter.default.post(name: .traktListsDidChange, object: nil, userInfo: ["listId": listId])
    }
}
