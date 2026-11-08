//
//  DetailsView+Layout.swift
//  FlixorMac
//
//  Page composition: the hero stays first, then the user-ordered sections
//  (tabbed or single page), see DetailsSectionsContainer.
//

import SwiftUI
import FlixorKit

extension DetailsView {
    // MARK: - Page Layout

    func pageContent(layout: DetailsLayoutMetrics) -> some View {
        VStack(spacing: 0) {
            DetailsHeroSection(
                vm: vm,
                item: item,
                trailers: vm.trailers,
                onPlay: playContent,
                onStremio: openHeroStremioSources,
                showsStremioButton: canShowStremioAction,
                onViewShow: viewParentShow,
                layout: layout,
                onChooseStremioSource: chooseHeroStremioSource
            )

            DetailsSectionsContainer(
                vm: vm,
                layout: layout,
                activeTab: $activeTab,
                onPlayEpisode: playEpisode,
                onStremioEpisode: openEpisodeStremioSources,
                onPersonTap: { person in presentPerson(person) },
                onBrowse: { context in presentBrowse(context) }
            )
        }
    }
}
