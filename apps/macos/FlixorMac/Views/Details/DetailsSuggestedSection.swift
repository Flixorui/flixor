//
//  DetailsSuggestedSection.swift
//  FlixorMac
//
//  Suggested tab: related and similar rows
//

import SwiftUI
import FlixorKit

// MARK: - Tab Content Helpers

struct SuggestedSections: View {
    @ObservedObject var vm: DetailsViewModel
    let layout: DetailsLayoutMetrics
    var onBrowse: ((BrowseContext) -> Void)?

    @ObservedObject private var profileSettings = ProfileSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: layout.width < 1100 ? 24 : 28) {
            if profileSettings.showRelatedContent && !vm.related.isEmpty {
                suggestedRow(
                    section: LibrarySection(
                        id: "rel",
                        title: "Related",
                        items: vm.related,
                        totalCount: vm.related.count,
                        libraryKey: nil,
                        browseContext: vm.relatedBrowseContext
                    )
                )
            }
            if profileSettings.showRelatedContent && !vm.similar.isEmpty {
                suggestedRow(
                    section: LibrarySection(
                        id: "sim",
                        title: "Similar",
                        items: vm.similar,
                        totalCount: vm.similar.count,
                        libraryKey: nil,
                        browseContext: vm.similarBrowseContext
                    )
                )
            }
        }
    }

    @ViewBuilder
    private func suggestedRow(section: LibrarySection) -> some View {
        if profileSettings.suggestedLayout == "poster" {
            PosterSectionRow(
                section: section,
                onTap: { media in
                    Task { await vm.load(for: media) }
                },
                onBrowse: { context in
                    onBrowse?(context)
                }
            )
            .padding(.trailing, DS.Space.s60)
        } else {
            LandscapeSectionView(
                section: section,
                onTap: { media in
                    Task { await vm.load(for: media) }
                },
                onBrowse: { context in
                    onBrowse?(context)
                }
            )
            .padding(.trailing, DS.Space.s60)
        }
    }
}
