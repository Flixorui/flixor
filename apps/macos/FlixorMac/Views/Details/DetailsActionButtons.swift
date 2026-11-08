//
//  DetailsActionButtons.swift
//  FlixorMac
//
//  Hero action row: Play, Stremio, View Show, watchlist, request, download
//

import SwiftUI
import FlixorKit

extension DetailsHeroSection {
    // MARK: - Action Buttons (Apple TV+ style)
    @ViewBuilder var actionButtonsRow: some View {
        HStack(spacing: 16) {
            // For seasons, show "View Show" button
            if vm.isSeason {
                if let parentKey = vm.parentShowKey {
                    Button(action: {
                        let showItem = MediaItem(
                            id: "plex:\(parentKey)",
                            title: vm.title,
                            type: "show",
                            thumb: nil,
                            art: nil,
                            year: nil,
                            rating: nil,
                            duration: nil,
                            viewOffset: nil,
                            summary: nil,
                            grandparentTitle: nil,
                            grandparentThumb: nil,
                            grandparentArt: nil,
                            grandparentRatingKey: nil,
                            parentIndex: nil,
                            index: nil,
                            parentRatingKey: nil,
                            parentTitle: nil,
                            leafCount: nil,
                            viewedLeafCount: nil
                        )
                        Task { await vm.load(for: showItem) }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "tv.fill")
                                .font(.system(size: 16, weight: .semibold))
                            Text("View Show")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                // With no local Plex copy, Stremio is the only way to play this, so it
                // becomes the primary button instead of sitting next to a dead one.
                let stremioIsPrimary = showsStremioButton && !hasResolvedPlexSource

                if !stremioIsPrimary {
                    // Play button - large, white (Apple TV+ style)
                    Button(action: onPlay) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Play")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(hasResolvedPlexSource ? .black : .gray)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(hasResolvedPlexSource ? Color.white : Color.white.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasResolvedPlexSource)
                }

                if showsStremioButton {
                    Button(action: onStremio) {
                        HStack(spacing: 8) {
                            Image(systemName: stremioIsPrimary ? "play.fill" : "puzzlepiece.extension.fill")
                                .font(.system(size: 16, weight: .semibold))
                            Text(stremioIsPrimary ? "Play" : "Stremio")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(stremioIsPrimary ? .black : .white)
                        .padding(.horizontal, stremioIsPrimary ? 32 : 22)
                        .padding(.vertical, 12)
                        .background(stremioIsPrimary ? Color.white : Color.orange.opacity(0.22))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }

                // View Show button for episodes
                if isEpisode, item.grandparentRatingKey != nil {
                    Button(action: onViewShow) {
                        HStack(spacing: 8) {
                            Image(systemName: "tv.fill")
                                .font(.system(size: 16, weight: .semibold))
                            Text("View Show")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }

                // Watchlist button - circular (Apple TV+ style)
                if let watchlistId = canonicalWatchlistId,
                   let mediaType = watchlistMediaType {
                    WatchlistButton(
                        canonicalId: watchlistId,
                        mediaType: mediaType,
                        plexRatingKey: vm.plexRatingKey,
                        plexGuid: vm.plexGuid,
                        tmdbId: vm.tmdbId,
                        imdbId: nil,
                        title: vm.title,
                        year: vm.year.flatMap { Int($0) },
                        posterURL: vm.posterURL?.absoluteString,
                        style: .circle
                    )
                }

                // Overseerr request button - circular (Apple TV+ style)
                if let tmdbIdStr = vm.tmdbId, let tmdbIdInt = Int(tmdbIdStr) {
                    let overseerrMediaType = vm.mediaKind == "tv" ? "tv" : "movie"
                    RequestButton(
                        tmdbId: tmdbIdInt,
                        mediaType: overseerrMediaType,
                        title: vm.title,
                        style: .circle
                    )
                }

                // Download button - circular (Apple TV+ style)
                // Only show for movies and episodes (not TV shows or seasons) with a Plex source
                if hasResolvedPlexSource,
                   let ratingKey = effectivePlexRatingKey,
                   let serverId = FlixorCore.shared.server?.id,
                   (vm.mediaKind == "movie" || item.type == "movie" || isEpisode) {
                    let downloadType: DownloadMediaType = isEpisode ? .episode : .movie
                    DetailsDownloadButton(
                        ratingKey: ratingKey,
                        serverId: serverId,
                        type: downloadType,
                        title: vm.title,
                        year: vm.year.flatMap { Int($0) },
                        thumb: vm.posterURL?.absoluteString,
                        grandparentTitle: item.grandparentTitle,
                        grandparentRatingKey: item.grandparentRatingKey,
                        parentIndex: item.parentIndex,
                        index: item.index
                    )
                }
            }
        }
    }

    private var hasResolvedPlexSource: Bool {
        effectivePlexRatingKey != nil
    }

    // Get the Plex rating key from either plexRatingKey or playableId (format: "plex:12345")
    private var effectivePlexRatingKey: String? {
        if let rk = vm.plexRatingKey {
            return rk
        }
        // Extract from playableId if it's a plex ID
        if let playableId = vm.playableId, playableId.hasPrefix("plex:") {
            return String(playableId.dropFirst(5))
        }
        return nil
    }

    private var canonicalWatchlistId: String? {
        if let playable = vm.playableId, playable.hasPrefix("plex:") { return playable }
        if let tmdb = vm.tmdbId {
            let prefix = (vm.mediaKind == "tv") ? "tmdb:tv:" : "tmdb:movie:"
            return prefix + tmdb
        }
        return nil
    }

    private var watchlistMediaType: MyListViewModel.MediaType? {
        if vm.mediaKind == "tv" { return .show }
        if vm.mediaKind == "movie" { return .movie }
        return .movie
    }
}
