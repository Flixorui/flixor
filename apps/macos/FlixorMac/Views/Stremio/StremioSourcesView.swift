//
//  StremioSourcesView.swift
//  FlixorMac
//
//  Dedicated source browser for Stremio streams on macOS.
//

import SwiftUI

struct StremioSourcesView: View {
    @EnvironmentObject private var router: NavigationRouter
    @EnvironmentObject private var mainViewState: MainViewState
    @Environment(\.flixorTheme) private var theme
    @StateObject private var viewModel: StremioSourcesViewModel

    init(destination: StremioSourcesDestination) {
        _viewModel = StateObject(wrappedValue: StremioSourcesViewModel(destination: destination))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s24) {
                heroSection

                if let notice = viewModel.destination.autoSelectNotice {
                    autoSelectNoticeBanner(notice)
                }

                if !viewModel.providerFilters.isEmpty, viewModel.groupedResults.count > 1 {
                    StremioProviderFilterBar(
                        providers: viewModel.groupedResults,
                        selectedProvider: $viewModel.selectedProviderFilter
                    )
                }

                if let cached = viewModel.cachedSource {
                    cachedResumeCard(cached)
                }

                if viewModel.isLoading {
                    ProgressView("Loading sources…")
                        .progressViewStyle(.circular)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, DS.Space.s40)
                } else if case .none = viewModel.emptyState {
                    playableSections
                    unsupportedSections
                } else {
                    emptyStateView
                }
            }
            .padding(.horizontal, DS.Space.s28)
            .padding(.top, DS.Space.s28)
            .padding(.bottom, DS.Space.s48)
        }
        .background(Color.black)
        .navigationTitle("Stremio Sources")
        .task {
            await viewModel.load()
        }
        .alert("Stremio", isPresented: Binding(get: { viewModel.alertMessage != nil }, set: { if !$0 { viewModel.alertMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s14) {
            Text("Choose a Stremio source")
                .font(.flixor(.largeTitle, weight: .bold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: DS.Space.s6) {
                Text(viewModel.destination.title)
                    .font(.flixor(.title3, weight: .semibold))
                    .foregroundStyle(.white)
                if viewModel.destination.mediaType == .episode,
                   let season = viewModel.destination.seasonNumber,
                   let episode = viewModel.destination.episodeNumber {
                    Text("Season \(season), Episode \(episode) • \(viewModel.destination.episodeTitle ?? "Episode")")
                        .font(.flixor(.callout))
                        .foregroundStyle(.secondary)
                } else if let imdbId = viewModel.destination.imdbId {
                    Text("IMDb \(imdbId)")
                        .font(.flixor(.callout))
                        .foregroundStyle(.secondary)
                } else if let tmdbId = viewModel.destination.tmdbId {
                    Text("TMDB \(tmdbId)")
                        .font(.flixor(.callout))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func autoSelectNoticeBanner(_ notice: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.controlGap) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(theme.warning)
                .accessibilityHidden(true)
            Text(notice)
                .flixorFont(.callout)
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(DS.Space.itemGap)
        .background(theme.warning.opacity(DS.Opacity.hover), in: RoundedRectangle(cornerRadius: DS.Radius.compactCard, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var playableSections: some View {
        VStack(alignment: .leading, spacing: DS.Space.s18) {
            ForEach(viewModel.playableGroups) { group in
                VStack(alignment: .leading, spacing: DS.Space.s12) {
                    sectionHeader(title: group.addonName, subtitle: group.error)
                    VStack(spacing: DS.Space.s12) {
                        ForEach(group.streams) { stream in
                            StremioStreamRow(stream: stream, addonName: group.addonName) {
                                Task {
                                    if let destination = await viewModel.select(stream: stream) {
                                        appendToCurrentTabPath(destination)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var unsupportedSections: some View {
        Group {
            if !viewModel.unsupportedGroups.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s18) {
                    sectionHeader(title: "Alternate Platforms", subtitle: "Returned by addons but not currently playable in-app")
                    ForEach(viewModel.unsupportedGroups) { group in
                        VStack(alignment: .leading, spacing: DS.Space.s12) {
                            Text(group.addonName)
                                .font(.flixor(.body, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                            VStack(spacing: DS.Space.s12) {
                                ForEach(group.streams) { stream in
                                    StremioStreamRow(stream: stream, addonName: group.addonName) {}
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(alignment: .leading, spacing: DS.Space.s10) {
            Text(viewModel.emptyState.title)
                .font(.flixor(.title3, weight: .semibold))
                .foregroundStyle(.white)
            Text(viewModel.emptyState.message)
                .font(.flixor(.callout))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Space.s18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: DS.Radius.r16, style: .continuous))
    }

    private func cachedResumeCard(_ cached: CachedPlaybackSource) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s10) {
            HStack {
                VStack(alignment: .leading, spacing: DS.Space.s4) {
                    Text("Resume Cached Source")
                        .font(.flixor(.bodyLarge, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(cached.playbackItem.streamLabel ?? cached.playbackItem.addonName ?? "Previously selected source")
                        .font(.flixor(.footnote))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Resume") {
                    Task {
                        if let destination = await viewModel.resumeCachedPlayback() {
                            appendToCurrentTabPath(destination)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            Text("Cached until \(cached.expiresAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.flixor(.caption))
                .foregroundStyle(.secondary)
        }
        .padding(DS.Space.s16)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.Radius.r16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.r16, style: .continuous)
                .stroke(Color.orange.opacity(0.22), lineWidth: 1)
        )
    }

    private func sectionHeader(title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            Text(title)
                .font(.flixor(.headline, weight: .bold))
                .foregroundStyle(.white)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.flixor(.caption))
                    .foregroundStyle(.orange)
            }
        }
    }

    private func appendToCurrentTabPath(_ destination: PlayerDestination) {
        switch mainViewState.selectedTab {
        case .home:
            router.homePath.append(destination)
        case .search:
            router.searchPath.append(destination)
        case .library:
            router.libraryPath.append(destination)
        case .myList:
            router.myListPath.append(destination)
        case .newPopular:
            router.newPopularPath.append(destination)
        case .downloads:
            router.downloadsPath.append(destination)
        }
    }
}
