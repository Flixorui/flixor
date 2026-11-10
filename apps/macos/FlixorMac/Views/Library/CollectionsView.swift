//
//  CollectionsView.swift
//  FlixorMac
//
//  The Collections tab: the user's own collections, then Plex collections.
//

import SwiftUI

struct CollectionsView: View {
    let collections: [LibraryViewModel.CollectionEntry]
    let isLoading: Bool
    var plexError: String? = nil
    var onRetryPlex: (() -> Void)? = nil
    var onSelect: (LibraryViewModel.CollectionEntry) -> Void

    @EnvironmentObject private var router: NavigationRouter
    @EnvironmentObject private var mainViewState: MainViewState
    @Environment(\.flixorTheme) private var theme

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 20)]

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.sectionGap) {
                    UserCollectionsSection()

                    VStack(alignment: .leading, spacing: DS.Space.s16) {
                        Text("Plex Collections")
                            .flixorFont(.title2, weight: .semibold)
                            .foregroundStyle(theme.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        plexCollections
                    }
                }
                .background(TabScrollObserver(tab: .library))
                .padding(.horizontal, DS.Space.s64)
                .padding(.vertical, DS.Space.s32)
            }

        }
    }

    @ViewBuilder
    private var plexCollections: some View {
        if isLoading {
            LazyVGrid(columns: columns, spacing: DS.Space.s20) {
                ForEach(0..<6, id: \.self) { _ in
                    SkeletonView(height: 240, cornerRadius: DS.Radius.r18)
                        .frame(height: 240)
                }
            }
        } else if let plexError {
            VStack(alignment: .leading, spacing: DS.Space.s8) {
                Text(plexError)
                    .flixorFont(.callout)
                    .foregroundStyle(theme.textSecondary)
                if let onRetryPlex {
                    Button("Try Again", action: onRetryPlex)
                        .accessibilityLabel("Try loading Plex collections again")
                }
            }
        } else if collections.isEmpty {
            Text("Create collections in Plex to see them here.")
                .flixorFont(.callout)
                .foregroundStyle(theme.textSecondary)
        } else {
            LazyVGrid(columns: columns, spacing: DS.Space.s20) {
                ForEach(collections) { collection in
                    Button {
                        open(collection)
                    } label: {
                        collectionCard(for: collection)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(collection.title)
                }
            }
        }
    }

    private func open(_ collection: LibraryViewModel.CollectionEntry) {
        onSelect(collection)
        router.push(BrowseRoute(context: .plexCollection(ratingKey: collection.id, title: collection.title), title: collection.title),
                    on: mainViewState.selectedTab)
    }

    private func collectionCard(for collection: LibraryViewModel.CollectionEntry) -> some View {
        ZStack(alignment: .bottomLeading) {
            CachedAsyncImage(url: collection.artwork)
                .aspectRatio(16/9, contentMode: .fill)
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r18, style: .continuous))
                .overlay(
                    LinearGradient(
                        colors: [Color.black.opacity(0.75), Color.black.opacity(0)],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r18, style: .continuous))
                )

            VStack(alignment: .leading, spacing: DS.Space.s6) {
                Text(collection.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text("\(collection.count) items")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, DS.Space.s10)
                    .padding(.vertical, DS.Space.s6)
                    .background(Color.white.opacity(0.18), in: Capsule())
            }
            .padding(DS.Space.s18)
        }
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.r18, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 12, y: 8)
    }
}

#if DEBUG && canImport(PreviewsMacros)
#Preview {
    CollectionsView(
        collections: [
            .init(id: "1", title: "Christopher Nolan Collection", artwork: URL(string: "https://image.tmdb.org/t/p/w500/qmDpIHrmpJINaRKAfWQfftjCdyi.jpg"), count: 14),
            .init(id: "2", title: "Animated Favourites", artwork: URL(string: "https://image.tmdb.org/t/p/w500/2uNW4WbgBXL25BAbXGLnLqX71Sw.jpg"), count: 32)
        ],
        isLoading: false,
        onSelect: { _ in }
    )
    .environmentObject(NavigationRouter())
    .environmentObject(MainViewState())
    .background(Color.black)
}
#endif
