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
    @StateObject private var viewModel: StremioSourcesViewModel

    init(destination: StremioSourcesDestination) {
        _viewModel = StateObject(wrappedValue: StremioSourcesViewModel(destination: destination))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                heroSection

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
                        .padding(.vertical, 40)
                } else if case .none = viewModel.emptyState {
                    playableSections
                    unsupportedSections
                } else {
                    emptyStateView
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 48)
        }
        .background(Color.black)
        .navigationTitle("Stremio Sources")
        .task {
            await viewModel.load()
        }
        .onChange(of: viewModel.autoPlayDestination) { destination in
            guard let destination = destination else { return }
            appendToCurrentTabPath(destination)
        }
        .alert("Stremio", isPresented: Binding(get: { viewModel.alertMessage != nil }, set: { if !$0 { viewModel.alertMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose a Stremio source")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.destination.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                if viewModel.destination.mediaType == .episode,
                   let season = viewModel.destination.seasonNumber,
                   let episode = viewModel.destination.episodeNumber {
                    Text("Season \(season), Episode \(episode) • \(viewModel.destination.episodeTitle ?? "Episode")")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else if let imdbId = viewModel.destination.imdbId {
                    Text("IMDb \(imdbId)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else if let tmdbId = viewModel.destination.tmdbId {
                    Text("TMDB \(tmdbId)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var playableSections: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(viewModel.playableGroups) { group in
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader(title: group.addonName, subtitle: group.error)
                    VStack(spacing: 12) {
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
                VStack(alignment: .leading, spacing: 18) {
                    sectionHeader(title: "Alternate Platforms", subtitle: "Returned by addons but not currently playable in-app")
                    ForEach(viewModel.unsupportedGroups) { group in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(group.addonName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                            VStack(spacing: 12) {
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
        VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.emptyState.title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
            Text(viewModel.emptyState.message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func cachedResumeCard(_ cached: CachedPlaybackSource) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Resume Cached Source")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(cached.playbackItem.streamLabel ?? cached.playbackItem.addonName ?? "Previously selected source")
                        .font(.system(size: 12))
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
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.orange.opacity(0.22), lineWidth: 1)
        )
    }

    private func sectionHeader(title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 11))
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
