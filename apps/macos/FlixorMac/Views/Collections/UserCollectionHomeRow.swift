//
//  UserCollectionHomeRow.swift
//  FlixorMac
//
//  A collection as a home row. HomeView's lazy stack only builds this near the
//  viewport, so a row off screen costs no requests; results are cached.
//

import SwiftUI

struct UserCollectionHomeRow: View {
    let collectionId: String
    let title: String
    let onTap: (MediaItem) -> Void

    private enum LoadState {
        case loading
        case loaded([MediaItem])
        case empty
        case failed(String)
    }

    @State private var state: LoadState = .loading
    @State private var loadedKey: [UserCollectionSource.Kind]?

    @ObservedObject private var store = UserCollectionsStore.shared
    @ObservedObject private var profileSettings = ProfileSettings.shared
    @ObservedObject private var cardStyle = CardStyleStore.shared
    @EnvironmentObject private var router: NavigationRouter
    @EnvironmentObject private var mainViewState: MainViewState
    @Environment(\.windowMetrics) private var metrics
    @Environment(\.flixorTheme) private var theme

    private var isPosterLayout: Bool { profileSettings.rowLayout == "poster" }

    var body: some View {
        if let collection = store.collection(id: collectionId) {
            content(collection)
                .task(id: collection.contentKey) { await load(collection) }
        }
    }

    @ViewBuilder
    private func content(_ collection: UserCollection) -> some View {
        switch state {
        case .loading:
            SkeletonCarouselRow(
                itemWidth: isPosterLayout ? metrics.posterWidth(designWidth: 160, storedSize: profileSettings.posterSize) : 420,
                itemCount: isPosterLayout ? 6 : 4,
                cardType: isPosterLayout ? .poster : .landscape
            )
        case .loaded(let items):
            row(items)
        case .empty:
            messageRow("Nothing in this collection right now.", retry: nil)
        case .failed(let message):
            messageRow(message) {
                Task { await load(collection, forceRefresh: true) }
            }
        }
    }

    @ViewBuilder
    private func row(_ items: [MediaItem]) -> some View {
        let openAll = { router.push(UserCollectionRoute(collectionId: collectionId), on: mainViewState.selectedTab) }
        if isPosterLayout {
            let width = metrics.posterWidth(base: CardPosterSize(stored: profileSettings.posterSize).baseWidth)
            let height = width * DS.Layout.posterAspect + (cardStyle.titleMode == .always ? CardMetrics.posterCaptionHeight : 0)
            CarouselRow(title: title, items: items, itemWidth: width, spacing: 14, rowHeight: height, browseAction: openAll) { item in
                PosterSectionCard(item: item, width: width, onTap: { onTap(item) })
            }
        } else {
            CarouselRow(title: title, items: items, itemWidth: 420, spacing: 16, rowHeight: (420 * 0.5) + 56, browseAction: openAll) { item in
                LandscapeCard(item: item, width: 420) { onTap(item) }
            }
        }
    }

    private func messageRow(_ message: String, retry: (() -> Void)?) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            Text(title)
                .flixorFont(.title3, weight: .semibold)
                .foregroundStyle(theme.textPrimary)
            HStack(spacing: DS.Space.s12) {
                Text(message)
                    .flixorFont(.callout)
                    .foregroundStyle(theme.textSecondary)
                if let retry {
                    Button("Retry", action: retry)
                        .accessibilityLabel("Retry loading \(title)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Space.s20)
    }

    private func load(_ collection: UserCollection, forceRefresh: Bool = false) async {
        if loadedKey != collection.contentKey {
            state = .loading
        }
        let preview = await UserCollectionPreviewCache.shared.preview(for: collection, forceRefresh: forceRefresh)
        loadedKey = collection.contentKey
        if !preview.items.isEmpty {
            state = .loaded(preview.items)
        } else if let failure = preview.failures.first {
            state = .failed(failure.message)
        } else {
            state = .empty
        }
    }
}
