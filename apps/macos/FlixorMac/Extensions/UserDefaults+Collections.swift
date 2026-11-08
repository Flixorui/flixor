//
//  UserDefaults+Collections.swift
//  FlixorMac
//
//  Profile-scoped storage for user-built collections. Read and write through
//  `UserCollectionsStore.shared` in UI code so views update.
//

import Foundation

extension UserDefaults {
    private static let userCollectionsKey = "userCollections"

    /// Decodes one collection at a time, so one unreadable entry (from a newer
    /// build, say) doesn't take the rest with it.
    private struct LossyCollection: Decodable {
        let value: UserCollection?

        init(from decoder: Decoder) throws {
            value = try? UserCollection(from: decoder)
        }
    }

    var userCollections: [UserCollection] {
        get {
            guard let data = data(forKey: profileKey(Self.userCollectionsKey)) else { return [] }
            let entries = (try? JSONDecoder().decode([LossyCollection].self, from: data)) ?? []
            return entries.compactMap(\.value)
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            set(data, forKey: profileKey(Self.userCollectionsKey))
        }
    }
}
