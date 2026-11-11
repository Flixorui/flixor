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
        // One "More Like This" row: Related first, then Similar titles not
        // already in it (TMDB's Similar list is the weaker of the two).
        let items = vm.moreLikeThis
        if profileSettings.showRelatedContent && !items.isEmpty {
            suggestedRow(
                section: LibrarySection(
                    id: "more-like-this",
                    title: String(localized: "More Like This"),
                    items: items,
                    totalCount: items.count,
                    libraryKey: nil,
                    browseContext: vm.related.isEmpty ? vm.similarBrowseContext : vm.relatedBrowseContext
                )
            )
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
