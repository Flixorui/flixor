//
//  TraktService+ListEditing.swift
//  FlixorKit
//
//  Editing an existing personal list (name, description, privacy).
//

import Foundation

extension TraktService {
    /// Updates a personal list and returns it. Only the fields passed are sent,
    /// so anything left nil keeps its current value. An empty `description`
    /// clears it. Requires auth.
    @discardableResult
    public func updateList(
        listId: Int,
        name: String? = nil,
        description: String? = nil,
        privacy: TraktListPrivacy? = nil
    ) async throws -> TraktUserList {
        struct Body: Encodable {
            let name: String?
            let description: String?
            let privacy: String?
        }
        let (data, _) = try await send(
            method: "PUT",
            path: "/users/me/lists/\(listId)",
            body: Body(name: name, description: description, privacy: privacy?.rawValue),
            auth: true
        )
        return try JSONDecoder().decode(TraktUserList.self, from: data)
    }
}
