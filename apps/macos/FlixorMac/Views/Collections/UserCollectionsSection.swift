//
//  UserCollectionsSection.swift
//  FlixorMac
//
//  The user's collections as a grid of cards, with create, edit and delete.
//  Shown in the Collections tab next to Plex collections, and as the whole
//  Library page in Stremio-only mode.
//

import SwiftUI

struct UserCollectionsSection: View {
    /// Fills the page with a call to action when there are no collections.
    var isStandalone = false

    @ObservedObject private var store = UserCollectionsStore.shared
    @EnvironmentObject private var router: NavigationRouter
    @EnvironmentObject private var mainViewState: MainViewState
    @Environment(\.flixorTheme) private var theme

    @State private var editorRequest: UserCollectionEditorRequest?
    @State private var pendingDelete: UserCollection?

    private let columns = [GridItem(.adaptive(minimum: 260), spacing: DS.Space.s20)]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            header
            if store.collections.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: DS.Space.s20) {
                    ForEach(store.collections) { collection in
                        card(for: collection)
                    }
                }
            }
        }
        .sheet(item: $editorRequest) { request in
            UserCollectionEditorView(collection: request.collection)
        }
        .confirmationDialog(
            "Delete \(pendingDelete?.name ?? "collection")?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Collection", role: .destructive) {
                if let pendingDelete { store.delete(id: pendingDelete.id) }
                pendingDelete = nil
            }
        } message: {
            Text("This removes the collection and its home row. Titles and sources aren't affected.")
        }
    }

    private var header: some View {
        HStack {
            Text("My Collections")
                .flixorFont(.title2, weight: .semibold)
                .foregroundStyle(theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                editorRequest = UserCollectionEditorRequest(collection: nil)
            } label: {
                Label("New Collection", systemImage: "plus")
            }
            .accessibilityLabel("New collection")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if isStandalone {
            BrowseMessageView(
                systemImage: "rectangle.stack.badge.plus",
                title: "No collections yet",
                message: "Build your own from addon catalogs, TMDB, people and Trakt lists.",
                retryTitle: "Create a Collection",
                onRetry: { editorRequest = UserCollectionEditorRequest(collection: nil) }
            )
        } else {
            Text("Build your own from addon catalogs, TMDB, people and Trakt lists.")
                .flixorFont(.callout)
                .foregroundStyle(theme.textSecondary)
        }
    }

    private func card(for collection: UserCollection) -> some View {
        Button {
            router.push(UserCollectionRoute(collectionId: collection.id), on: mainViewState.selectedTab)
        } label: {
            UserCollectionCard(collection: collection)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(collection.name), \(collection.sourceSummary)")
        .contextMenu {
            Button("Edit") { editorRequest = UserCollectionEditorRequest(collection: collection) }
            Button(collection.showOnHome ? "Remove from Home" : "Show on Home") {
                store.setShowOnHome(!collection.showOnHome, id: collection.id)
            }
            Divider()
            Button("Delete", role: .destructive) { pendingDelete = collection }
        }
    }
}

/// Cover art, or (without spending a request) art from the last time the
/// collection was loaded, or a plain placeholder.
struct UserCollectionCard: View {
    let collection: UserCollection

    @State private var cachedArt: URL?
    @Environment(\.flixorTheme) private var theme

    private var artURL: URL? {
        collection.cover.flatMap { URL(string: $0.url) } ?? cachedArt
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(theme.surfaceElevated)
            if let artURL {
                CachedAsyncImage(url: artURL)
            } else {
                Image(systemName: "rectangle.stack.fill")
                    .font(.flixorIcon(DS.Icon.huge, weight: .light))
                    .foregroundStyle(theme.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            LinearGradient(
                colors: [theme.scrim(DS.Opacity.scrimHeavy), Color.clear],
                startPoint: .bottom,
                endPoint: .center
            )
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                Text(collection.name)
                    .flixorFont(.headline)
                    .foregroundStyle(Color.white)
                    .lineLimit(2)
                Text(collection.sourceSummary)
                    .flixorFont(.caption, weight: .medium)
                    .foregroundStyle(Color.white.opacity(DS.Opacity.strong))
            }
            .padding(DS.Space.cardPadding)
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .stroke(theme.separator, lineWidth: DS.Border.thin)
        )
        .contentShape(Rectangle())
        .task(id: collection.contentKey) {
            guard collection.cover == nil else { return }
            let items = await UserCollectionPreviewCache.shared.cached(for: collection)?.items ?? []
            let art = items.lazy.compactMap { $0.art ?? $0.thumb }.first
            cachedArt = art.flatMap(URL.init(string:))
        }
    }
}

/// The Library page in Stremio-only mode, where there are no Plex libraries.
struct UserCollectionsPage: View {
    @Environment(\.windowMetrics) private var metrics

    var body: some View {
        ScrollView {
            UserCollectionsSection(isStandalone: true)
                .padding(.horizontal, metrics.pageGutter)
                .padding(.vertical, DS.Space.s32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HomeBackground())
        .navigationTitle("")
    }
}
