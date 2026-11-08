//
//  UserCollectionsStore.swift
//  FlixorMac
//
//  Observable owner of the current profile's user-built collections. Keeps the
//  home row system (HomeRowsStore) told about collections shown on home.
//

import Combine
import SwiftUI

@MainActor
final class UserCollectionsStore: ObservableObject {
    static let shared = UserCollectionsStore()

    @Published private(set) var collections: [UserCollection]

    private let defaults = UserDefaults.standard
    private var profileObserver: AnyCancellable?

    private init() {
        collections = defaults.userCollections

        // Same signal HomeRowsStore uses to follow profile switches.
        profileObserver = ProfileSettings.shared.objectWillChange
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.reload()
                }
            }

        // First access can happen while a view body runs; registering publishes.
        Task { @MainActor [weak self] in
            self?.syncHomeRows()
        }
    }

    func reload() {
        // HomeRowsStore must hold the new profile's rows before we merge ours in,
        // or register() would write the old profile's rows into the new one.
        HomeRowsStore.shared.reload()
        let fresh = defaults.userCollections
        if fresh != collections { collections = fresh }
        syncHomeRows()
    }

    func collection(id: String) -> UserCollection? {
        collections.first { $0.id == id }
    }

    /// Collections that get a home row.
    var homeCollections: [UserCollection] {
        collections.filter { $0.showOnHome && !$0.sources.isEmpty }
    }

    /// Adds a new collection or replaces the one with the same id.
    func save(_ collection: UserCollection) {
        var next = collections
        if let index = next.firstIndex(where: { $0.id == collection.id }) {
            next[index] = collection
        } else {
            next.append(collection)
        }
        apply(next)
    }

    func delete(id: String) {
        guard let collection = collection(id: id) else { return }
        apply(collections.filter { $0.id != id })
        // Forget row customisation, so it can't resurface.
        let rows = HomeRowsStore.shared
        rows.rename(collection.homeRowId, to: nil, defaultTitle: collection.name)
        rows.setHidden(collection.homeRowId, false)
    }

    func setShowOnHome(_ show: Bool, id: String) {
        guard var collection = collection(id: id), collection.showOnHome != show else { return }
        collection.showOnHome = show
        save(collection)
    }

    private func apply(_ next: [UserCollection]) {
        guard next != collections else { return }
        collections = next
        defaults.userCollections = next
        syncHomeRows()
    }

    private func syncHomeRows() {
        let descriptors = homeCollections.map {
            HomeRowDescriptor(
                id: $0.homeRowId,
                defaultTitle: $0.name,
                kind: .userCollection,
                group: .userCollections,
                detail: "Your collection · \($0.sourceSummary)"
            )
        }
        HomeRowsStore.shared.register(descriptors, group: .userCollections)
    }
}
