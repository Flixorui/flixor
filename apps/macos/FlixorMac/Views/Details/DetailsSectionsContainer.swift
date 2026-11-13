//
//  DetailsSectionsContainer.swift
//  FlixorMac
//
//  Everything below the details hero: the sections the user enabled, in the
//  order they chose (DetailsSectionsStore), shown as tabs or as one page.
//  Owns the per-page state of sections that load their own data.
//

import SwiftUI
import FlixorKit

struct DetailsSectionsContainer: View {
    @ObservedObject var vm: DetailsViewModel
    let layout: DetailsLayoutMetrics
    @Binding var activeTab: String
    let onPlayEpisode: (DetailsViewModel.Episode) -> Void
    let onStremioEpisode: (DetailsViewModel.Episode) -> Void
    let onPersonTap: (CastCrewCard.Person) -> Void
    let onBrowse: (BrowseContext) -> Void
    let commentsModel: DetailsCommentsModel

    @EnvironmentObject private var router: NavigationRouter
    @EnvironmentObject private var mainView: MainViewState
    @ObservedObject private var store = DetailsSectionsStore.shared
    @ObservedObject private var profileSettings = ProfileSettings.shared
    @ObservedObject private var myblurayStore = MyBluraySettingsStore.shared

    @StateObject private var collectionModel = DetailsCollectionModel()
    @StateObject private var physicalModel = DetailsPhysicalModel()
    @StateObject private var episodeState = DetailsEpisodeStateModel()
    @State private var selectedTrailer: Trailer?

    private var isTabbed: Bool { profileSettings.detailsScreenLayout == "tabbed" }

    var body: some View {
        VStack(spacing: 0) {
            if isTabbed {
                DetailsTabsBar(tabs: tabs, activeTab: effectiveTabBinding)
            }

            Group {
                if isTabbed {
                    VStack(spacing: DS.Space.sectionGap) {
                        if let key = sectionKey(forTab: effectiveTab) {
                            section(key)
                        }
                    }
                } else {
                    VStack(spacing: DS.Space.s48) {
                        ForEach(availableSections) { key in
                            section(key)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, layout.contentPadding)
            .padding(.top, DS.Space.s20)
            .padding(.bottom, DS.Space.sectionGap)
        }
        .sheet(item: $selectedTrailer) { trailer in
            TrailerModal(trailer: trailer, onClose: { selectedTrailer = nil })
        }
        .task(id: collectionMovieId) {
            await collectionModel.load(movieId: collectionMovieId)
        }
        .task(id: physicalTaskKey) {
            await physicalModel.load(imdbId: physicalImdbId, settings: myblurayStore)
        }

    }

    /// IMDb id of the movie being viewed (nil for shows and episodes): drives Physical Releases.
    private var physicalImdbId: String? {
        guard vm.mediaKind == "movie", !vm.isEpisode, myblurayStore.isOn(.physicalReleases) else { return nil }
        return vm.imdbId
    }

    /// Reloads Physical Releases when the title or its settings change.
    private var physicalTaskKey: String {
        [physicalImdbId ?? "-", myblurayStore.discCountry,
         "\(myblurayStore.isOn(.uhdFormat))\(myblurayStore.isOn(.blurayFormat))\(myblurayStore.isOn(.boxSets))\(myblurayStore.isOn(.quickAdd))"]
            .joined(separator: "|")
    }

    /// The Parents Guide section is visible and has its Age Rating card.
    private var guidanceShowsRating: Bool {
        store.isEnabled(.guidance) && guidanceContent.certificate != nil
    }

    /// Age rating, Common Sense and IMDb parents guide, as far as Settings allows.
    private var guidanceContent: DetailsGuidanceContent {
        DetailsGuidanceContent(title: vm.myblurayTitle, guide: vm.parentsGuide, settings: myblurayStore)
    }

    /// TMDB id of the movie being viewed (nil for shows), drives the collection row.
    private var collectionMovieId: Int? {
        guard vm.mediaKind == "movie", !vm.isEpisode else { return nil }
        return vm.tmdbId.flatMap { Int($0) }
    }

    // MARK: - Sections

    /// Enabled sections that apply to (and have content for) the current item, in order.
    private var availableSections: [DetailsSectionKey] {
        store.orderedEnabledKeys.filter(isAvailable)
    }

    private func isAvailable(_ key: DetailsSectionKey) -> Bool {
        switch key {
        case .episodes:
            return (vm.mediaKind == "tv" || vm.isSeason) && !vm.isEpisode
        case .suggested:
            return !vm.isSeason && !vm.isEpisode && profileSettings.showRelatedContent
        case .collection:
            return collectionMovieId != nil && collectionModel.collection != nil
        case .cast:
            return profileSettings.showCastCrew && (!vm.cast.isEmpty || !vm.crew.isEmpty || !vm.guestStars.isEmpty)
        case .trailers:
            return !vm.trailers.isEmpty
        case .physical:
            return physicalImdbId != nil && physicalModel.phase == .loaded
        case .guidance:
            return !guidanceContent.isEmpty
        case .comments:
            return vm.titleWatchTarget != nil
        case .about:
            return true
        }
    }

    @ViewBuilder
    private func section(_ key: DetailsSectionKey) -> some View {
        switch key {
        case .episodes:
            EpisodesTabContent(
                vm: vm,
                layout: layout,
                episodeState: episodeState,
                onPlayEpisode: onPlayEpisode,
                onStremioEpisode: onStremioEpisode
            )
        case .suggested:
            SuggestedSections(vm: vm, layout: layout, onBrowse: onBrowse)
        case .collection:
            if let collection = collectionModel.collection {
                DetailsCollectionSection(
                    collection: collection,
                    currentMovieId: collectionMovieId,
                    onSelect: { media in Task { await vm.load(for: media) } }
                )
            }
        case .cast:
            DetailsCastSection(
                people: DetailsCastSection.people(for: vm),
                showsGuestStars: vm.isEpisode && !vm.guestStars.isEmpty,
                onPersonTap: onPersonTap
            )
            .equatable()
        case .trailers:
            DetailsTrailersSection(trailers: vm.trailers, onPlay: { selectedTrailer = $0 })
        case .physical:
            DetailsPhysicalSection(model: physicalModel, onSelect: { edition in
                router.push(EditionRoute(summary: edition), on: mainView.selectedTab)
            })
        case .guidance:
            DetailsGuidanceSection(content: guidanceContent)
        case .comments:
            // The settled target: titleWatchTarget fills in over several load
            // steps and would restart the Trakt request each time.
            DetailsCommentsSection(model: commentsModel, target: vm.commentsTarget)
        case .about:
            // Parents Guide's Age Rating card replaces About's rating box when
            // both would show.
            DetailsTabContent(vm: vm, layout: layout, onEntityTap: openEntity,
                              hidesContentRating: guidanceShowsRating)
        }
    }

    // MARK: - Tabs

    private var tabs: [DetailsTab] {
        availableSections.map { DetailsTab(id: $0.tabId, label: $0.tabLabel, count: nil) }
    }

    /// The selected tab, or the first visible one when the selection isn't
    /// shown for this item (hidden in settings, or not applicable).
    private var effectiveTab: String {
        let ids = tabs.map(\.id)
        if ids.contains(activeTab) { return activeTab }
        return ids.first ?? activeTab
    }

    private var effectiveTabBinding: Binding<String> {
        Binding(get: { effectiveTab }, set: { activeTab = $0 })
    }

    private func sectionKey(forTab tab: String) -> DetailsSectionKey? {
        availableSections.first(where: { $0.tabId == tab })
    }

    // MARK: - Navigation

    private func openEntity(_ route: EntityBrowseRoute) {
        router.push(route, on: mainView.selectedTab)
    }
}

// MARK: - Trailers Section

struct DetailsTrailersSection: View {
    let trailers: [Trailer]
    let onPlay: (Trailer) -> Void

    @Environment(\.flixorTheme) private var theme

    private let cardWidth: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: DetailsSectionStyle.headingGap) {
            DetailsSectionHeading("Trailers & Videos")

            DetailsHorizontalRow {
                LazyHStack(alignment: .top, spacing: DS.Space.s16) {
                    ForEach(trailers) { trailer in
                        TrailerCard(trailer: trailer, width: cardWidth, onPlay: { onPlay(trailer) })
                            .accessibilityLabel(Text("Play \(trailer.name)"))
                    }
                }
            }
        }
    }
}
