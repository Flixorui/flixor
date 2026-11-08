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
        VStack(alignment: .leading, spacing: DS.Space.s48) {
            if profileSettings.showRelatedContent && !vm.related.isEmpty {
                suggestedRow(
                    section: LibrarySection(
                        id: "rel",
                        title: String(localized: "Related"),
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
                        title: String(localized: "Similar"),
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
            .modifier(DetailsSuggestedRowLayout())
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
            .modifier(DetailsSuggestedRowLayout())
        }
    }
}

/// The shared rows carry the page inset themselves, so they replace the section's
/// and scroll out to the window's edges.
private struct DetailsSuggestedRowLayout: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, -DetailsSectionStyle.inset)
            .environment(\.rowTitleFont, DetailsSectionStyle.headingFont)
    }
}
