import SwiftUI
import FlixorKit

struct TVHomeView: View {
    @StateObject private var vm = TVHomeViewModel()
    @Namespace private var contentFocusNS
    @EnvironmentObject private var session: SessionManager
    @FocusState private var focusedSection: String?
    var jumpToFirstRow: Bool = false

    @State private var focusedRowId: String?
    @State private var forceDefaultFocusRowId: String?

    var body: some View {
        ScrollViewReader { vProxy in
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 40) {

                // Billboard
                if let first = vm.billboardItems.first {
                    TVBillboardView(item: first, focusNS: contentFocusNS, defaultFocus: focusedSection == nil)
                        .padding(.top, UX.billboardTopPadding)
                        .id("billboard")
                } else if vm.isLoading {
                    placeholderBillboard
                        .padding(.top, UX.billboardTopPadding)
                        .id("billboard-placeholder")
                }

                // Row Order per spec
                // 1) My List (poster)
                if let myList = vm.additionalSections.first(where: { $0.id == "plex-watchlist" }), !myList.items.isEmpty {
                    TVCarouselRow(
                        title: "My List",
                        items: myList.items,
                        kind: .poster,
                        focusNS: contentFocusNS,
                        defaultFocus: forceDefaultFocusRowId == myList.id,
                        sectionId: myList.id
                    )
                    .padding(.top, focusedRowId == myList.id ? UX.rowSnapTopPadding : 0) // snap padding
                    .id("row-\(myList.id)")
                }

                // 2) Continue Watching — poster rail with inline expansion
                if !vm.continueWatching.isEmpty {
                    TVCarouselRow(
                        title: "Continue Watching",
                        items: vm.continueWatching,
                        kind: .poster,
                        focusNS: contentFocusNS,
                        defaultFocus: forceDefaultFocusRowId == "continue-watching",
                        sectionId: "continue-watching"
                    )
                    .padding(.top, focusedRowId == "continue-watching" ? UX.rowSnapTopPadding : 0) // snap padding
                    .id("row-continue-watching")
                }

                // 3) New on Flixor (Recently Added) — poster rail with inline expansion
                if !vm.recentlyAdded.isEmpty {
                    TVCarouselRow(
                        title: "New on Flixor",
                        items: vm.recentlyAdded,
                        kind: .poster,
                        focusNS: contentFocusNS,
                        defaultFocus: forceDefaultFocusRowId == "recently-added",
                        sectionId: "recently-added"
                    )
                    .padding(.top, focusedRowId == "recently-added" ? UX.rowSnapTopPadding : 0) // snap padding
                    .id("row-recently-added")
                }

                // 4) Popular on Plex (TMDB popular movies)
                if let popular = vm.additionalSections.first(where: { $0.id == "tmdb-popular-movies" }), !popular.items.isEmpty {
                    TVCarouselRow(
                        title: "Popular on Plex",
                        items: popular.items,
                        kind: .poster,
                        focusNS: contentFocusNS,
                        defaultFocus: forceDefaultFocusRowId == popular.id,
                        sectionId: popular.id
                    )
                    .padding(.top, focusedRowId == popular.id ? UX.rowSnapTopPadding : 0) // snap padding
                    .id("row-\(popular.id)")
                }

                // 5) Trending Now (TMDB trending TV)
                if let trending = vm.additionalSections.first(where: { $0.id == "tmdb-trending" }), !trending.items.isEmpty {
                    TVCarouselRow(
                        title: "Trending Now",
                        items: trending.items,
                        kind: .poster,
                        focusNS: contentFocusNS,
                        defaultFocus: forceDefaultFocusRowId == trending.id,
                        sectionId: trending.id
                    )
                    .padding(.top, focusedRowId == trending.id ? UX.rowSnapTopPadding : 0) // snap padding
                    .id("row-\(trending.id)")
                }

                // 6) On Deck — poster rail with inline expansion
                if !vm.onDeck.isEmpty {
                    TVCarouselRow(
                        title: "On Deck",
                        items: vm.onDeck,
                        kind: .poster,
                        focusNS: contentFocusNS,
                        defaultFocus: forceDefaultFocusRowId == "on-deck",
                        sectionId: "on-deck"
                    )
                    .padding(.top, focusedRowId == "on-deck" ? UX.rowSnapTopPadding : 0) // snap padding
                    .id("row-on-deck")
                }

                // Any remaining sections not already displayed
                ForEach(vm.additionalSections.filter { !["plex-watchlist","tmdb-popular-movies","tmdb-trending"].contains($0.id) }) { section in
                    TVCarouselRow(
                        title: section.title,
                        items: section.items,
                        kind: .landscape,
                        focusNS: contentFocusNS,
                        sectionId: section.id
                    )
                    .id("row-\(section.id)")
                }

                // Error message
                if let error = vm.error {
                    VStack(spacing: 12) {
                        Text("Unable to load content")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                        Text(error)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .padding(40)
                }

                // Loading skeletons
                if vm.isLoading {
                    loadingSkeletons
                }

                // Provide extra trailing space so the last row can snap under the tab bar
                Color.clear.frame(height: UX.tabHeight + UX.rowSnapInset + 150)
            }
            .padding(.bottom, 80)
        }
        // no permanent inset; content can scroll under the transparent tab bar
        .onPreferenceChange(RowFocusKey.self) { newId in
            guard let rid = newId, rid != focusedRowId else { return }
            focusedRowId = rid
            withAnimation(.easeInOut(duration: 0.24)) {
                vProxy.scrollTo("row-\(rid)", anchor: .top)
            }
        }
        // Bridge: if the nav bar sent a down command, move focus to the first row and snap
        .onChange(of: jumpToFirstRow) { _ in
            if let firstId = firstRowId() {
                withAnimation(.easeInOut(duration: 0.24)) { vProxy.scrollTo("row-\(firstId)", anchor: .top) }
                forceDefaultFocusRowId = firstId
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    forceDefaultFocusRowId = nil
                }
            }
        }
        }
        .background(Color.black)
        .focusScope(contentFocusNS)
        .task { await vm.load() }
        .onChange(of: session.isAuthenticated) { authed in
            if authed { Task { await vm.load() } }
        }
    }

    private var placeholderBillboard: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .frame(height: 820)
            .padding(.horizontal, 40)
    }
}

private extension TVHomeView {
    func firstRowId() -> String? {
        if let myList = vm.additionalSections.first(where: { $0.id == "plex-watchlist" }), !myList.items.isEmpty { return myList.id }
        if !vm.continueWatching.isEmpty { return "continue-watching" }
        if !vm.recentlyAdded.isEmpty { return "recently-added" }
        if let popular = vm.additionalSections.first(where: { $0.id == "tmdb-popular-movies" }), !popular.items.isEmpty { return popular.id }
        if let trending = vm.additionalSections.first(where: { $0.id == "tmdb-trending" }), !trending.items.isEmpty { return trending.id }
        if !vm.onDeck.isEmpty { return "on-deck" }
        return vm.additionalSections.first?.id
    }
}

// MARK: - Loading skeletons for perceived performance
extension TVHomeView {
    @ViewBuilder
    var loadingSkeletons: some View {
        VStack(spacing: 32) {
            skeletonRow(title: "My List", poster: true)
            skeletonRow(title: "Continue Watching", poster: false)
            skeletonRow(title: "New on Flixor", poster: true)
        }
    }

    private func skeletonRow(title: String, poster: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, UX.gridH)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: UX.itemSpacing) {
                    ForEach(0..<8, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: poster ? UX.posterRadius : UX.landscapeRadius, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .frame(width: poster ? UX.posterWidth : UX.landscapeWidth,
                                   height: poster ? UX.posterHeight : UX.landscapeHeight)
                    }
                }
                .padding(.horizontal, UX.gridH)
                .frame(height: poster ? UX.posterHeight : UX.landscapeHeight)
            }
        }
    }
}
