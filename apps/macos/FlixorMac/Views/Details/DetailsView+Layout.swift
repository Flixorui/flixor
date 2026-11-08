//
//  DetailsView+Layout.swift
//  FlixorMac
//
//  Page composition: hero, tabs bar, and which sections appear (tabbed vs unified)
//

import SwiftUI
import FlixorKit

extension DetailsView {
    // MARK: - Page Layout

    func pageContent(layout: DetailsLayoutMetrics) -> some View {
        VStack(spacing: 20) {
            VStack(spacing: 0) {
                DetailsHeroSection(
                    vm: vm,
                    item: item,
                    trailers: vm.trailers,
                    onPlay: playContent,
                    onStremio: openHeroStremioSources,
                    showsStremioButton: canShowStremioAction,
                    onViewShow: viewParentShow,
                    layout: layout
                )

                // Only show tabs bar in tabbed layout
                if profileSettings.detailsScreenLayout == "tabbed" {
                    DetailsTabsBar(tabs: tabsData, activeTab: $activeTab)
                }
            }

            // Tabbed Layout: Show one section at a time based on selected tab
            if profileSettings.detailsScreenLayout == "tabbed" {
                VStack(spacing: 32) {
                    switch activeTab {
                    case "SUGGESTED":
                        SuggestedSections(vm: vm, layout: layout, onBrowse: { context in
                            presentBrowse(context)
                        })
                    case "DETAILS":
                        DetailsTabContent(vm: vm, layout: layout, onPersonTap: { person in
                            presentPerson(person)
                        })
                    case "EPISODES":
                        EpisodesTabContent(vm: vm, layout: layout, onPlayEpisode: playEpisode, onStremioEpisode: openEpisodeStremioSources)
                    default:
                        SuggestedSections(vm: vm, layout: layout, onBrowse: { context in
                            presentBrowse(context)
                        })
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, layout.contentPadding)
                .padding(.bottom, 32)
            } else {
                // Unified Layout: Stack all sections vertically
                // Order: Episodes (for TV) → Suggested → Details
                VStack(spacing: 48) {
                    // Episodes section (only for TV shows/seasons, NOT for single episodes)
                    if (vm.mediaKind == "tv" || vm.isSeason) && !vm.isEpisode {
                        EpisodesTabContent(vm: vm, layout: layout, onPlayEpisode: playEpisode, onStremioEpisode: openEpisodeStremioSources)
                    }

                    // Suggested section
                    if !vm.isSeason && !vm.isEpisode {
                        VStack(alignment: .leading, spacing: 16) {
                            SuggestedSections(vm: vm, layout: layout, onBrowse: { context in
                                presentBrowse(context)
                            })
                        }
                    }

                    // Details section
                    VStack(alignment: .leading, spacing: 16) {
                        DetailsTabContent(vm: vm, layout: layout, onPersonTap: { person in
                            presentPerson(person)
                        })
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, layout.contentPadding)
                .padding(.bottom, 32)
            }
        }
    }
}

// MARK: - Tabs data

private extension DetailsView {
    var tabsData: [DetailsTab] {
        var t: [DetailsTab] = []
        // Show EPISODES tab for TV shows and seasons (but NOT single episodes)
        if (vm.mediaKind == "tv" || vm.isSeason) && !vm.isEpisode {
            t.append(DetailsTab(id: "EPISODES", label: "Episodes", count: nil))
        }
        // Hide SUGGESTED tab for season-only mode and episodes
        if !vm.isSeason && !vm.isEpisode {
            t.append(DetailsTab(id: "SUGGESTED", label: "Suggested", count: nil))
        }
        t.append(DetailsTab(id: "DETAILS", label: "Details", count: nil))
        return t
    }
}
