//
//  HeroSourceSettingsRow.swift
//  FlixorMac
//
//  Chooses what feeds the home hero. Falls back to the default when the
//  chosen source has nothing to show.
//

import SwiftUI

struct HeroSourceSettingsRow: View {
    @ObservedObject private var store = HomeRowsStore.shared

    /// Rows selectable as a source; Continue Watching and the watchlist have
    /// their own entries. User collections load lazily, so they can't feed the hero.
    private var rowOptions: [HomeRowDescriptor] {
        store.orderedCatalog.filter {
            $0.id != homeContinueWatchingRowId && $0.id != homeWatchlistRowId && $0.kind != .userCollection
        }
    }

    /// A previously chosen row that is not currently known (keeps the Picker valid).
    private var missingSelection: String? {
        guard case .row(let id) = store.heroSource,
              id != homeContinueWatchingRowId,
              id != homeWatchlistRowId,
              !rowOptions.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    var body: some View {
        SettingsRow(
            icon: "photo.on.rectangle",
            iconColor: .teal,
            title: "Hero Source",
            subtitle: "Falls back to the default when the source is empty",
            showDivider: false
        ) {
            Picker("", selection: $store.heroSource) {
                Text("Default").tag(HomeHeroSource.automatic)
                Text("Continue Watching").tag(HomeHeroSource.continueWatching)
                Text("My List").tag(HomeHeroSource.myList)

                if !rowOptions.isEmpty || missingSelection != nil {
                    Divider()
                }
                ForEach(rowOptions) { row in
                    Text(store.title(for: row.id, default: row.defaultTitle))
                        .tag(HomeHeroSource.row(row.id))
                }
                if let missingSelection {
                    Text("Unavailable row").tag(HomeHeroSource.row(missingSelection))
                }
            }
            .labelsHidden()
            .frame(width: 200)
            .accessibilityLabel(Text("Hero source"))
        }
    }
}
