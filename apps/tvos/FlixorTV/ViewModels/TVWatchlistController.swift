import Foundation
import SwiftUI

extension Notification.Name {
    static let tvWatchlistDidChange = Notification.Name("tvWatchlistDidChange")
}

@MainActor
final class TVWatchlistController: ObservableObject {
    static let shared = TVWatchlistController()

    @Published private(set) var ids: Set<String> = []

    func synchronize(with ids: [String]) {
        self.ids = Set(ids.map(normalize))
    }

    func contains(_ id: String) -> Bool {
        ids.contains(normalize(id))
    }

    func registerAdd(id: String) {
        ids.insert(normalize(id))
        NotificationCenter.default.post(name: .tvWatchlistDidChange, object: nil)
    }

    func registerRemove(id: String) {
        ids.remove(normalize(id))
        NotificationCenter.default.post(name: .tvWatchlistDidChange, object: nil)
    }

    private func normalize(_ id: String) -> String {
        id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
