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
        HStack(spacing: DS.Space.s12) {
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
                        HStack(spacing: DS.Space.s8) {
                            Image(systemName: "tv.fill")
                                .font(.flixorIcon(DS.Icon.md, weight: .semibold))
                            Text("View Show")
                                .font(.flixor(.headline, weight: .semibold))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, DS.Space.s32)
                        .padding(.vertical, DS.Space.s12)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r8))
                    }
                    .buttonStyle(.plain)
                }

                DetailsMoreActionsButton(model: titleActions, title: vm.title, download: nil)
            } else {
                // With no local Plex copy, Stremio is the only way to play this, so it
                // becomes the primary button instead of sitting next to a dead one.
                let stremioIsPrimary = showsStremioButton && !hasResolvedPlexSource

                if !stremioIsPrimary {
                    // Play button - large, white (Apple TV+ style)
                    Button(action: onPlay) {
                        HStack(spacing: DS.Space.s8) {
                            Image(systemName: "play.fill")
                                .font(.flixorIcon(DS.Icon.md, weight: .semibold))
                            Text("Play")
                                .font(.flixor(.headline, weight: .semibold))
                        }
                        .foregroundStyle(hasResolvedPlexSource ? .black : .gray)
                        .padding(.horizontal, DS.Space.s32)
                        .padding(.vertical, DS.Space.s12)
                        .background(hasResolvedPlexSource ? Color.white : Color.white.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r8))
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasResolvedPlexSource)
                }

                if showsStremioButton {
                    Button(action: onStremio) {
                        HStack(spacing: DS.Space.s8) {
                            Image(systemName: stremioIsPrimary ? "play.fill" : "puzzlepiece.extension.fill")
                                .font(.flixorIcon(DS.Icon.md, weight: .semibold))
                            Text(stremioIsPrimary ? "Play" : "Stremio")
                                .font(.flixor(.headline, weight: .semibold))
                        }
                        .foregroundStyle(stremioIsPrimary ? .black : .white)
                        .padding(.horizontal, stremioIsPrimary ? 32 : 22)
                        .padding(.vertical, DS.Space.s12)
                        .background(stremioIsPrimary ? Color.white : Color.orange.opacity(0.22))
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r8))
                    }
                    .buttonStyle(.plain)

                    StremioChooseSourceButton(action: onChooseStremioSource)
                }

                // View Show button for episodes
                if isEpisode, item.grandparentRatingKey != nil {
                    Button(action: onViewShow) {
                        HStack(spacing: DS.Space.s8) {
                            Image(systemName: "tv.fill")
                                .font(.flixorIcon(DS.Icon.md, weight: .semibold))
                            Text("View Show")
                                .font(.flixor(.headline, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, DS.Space.s24)
                        .padding(.vertical, DS.Space.s12)
                        .background(Color.white.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r8))
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

                // Download shows here only while it has a state (progress,
                // done, failed); starting one is in the ⋯ menu.
                if let download = downloadRequest {
                    DetailsDownloadSlot(request: download)
                }

                // Watched, Trakt rating and download
                DetailsMoreActionsButton(model: titleActions, title: vm.title, download: downloadRequest)
            }
        }
    }

    /// Movies and episodes with a Plex source can be downloaded (not shows or seasons).
    private var downloadRequest: DetailsDownloadRequest? {
        guard hasResolvedPlexSource,
              let ratingKey = effectivePlexRatingKey,
              let serverId = FlixorCore.shared.server?.id,
              vm.mediaKind == "movie" || item.type == "movie" || isEpisode else { return nil }
        return DetailsDownloadRequest(
            ratingKey: ratingKey,
            serverId: serverId,
            type: isEpisode ? .episode : .movie,
            title: vm.title,
            year: vm.year.flatMap { Int($0) },
            thumb: vm.posterURL?.absoluteString,
            grandparentTitle: item.grandparentTitle,
            grandparentRatingKey: item.grandparentRatingKey,
            parentIndex: item.parentIndex,
            index: item.index
        )
    }

    private var hasResolvedPlexSource: Bool {
        effectivePlexRatingKey != nil
    }

    private var effectivePlexRatingKey: String? { vm.heroPlexRatingKey }

    private var canonicalWatchlistId: String? { vm.heroWatchlistCanonicalId }

    private var watchlistMediaType: MyListViewModel.MediaType? { vm.heroWatchlistMediaType }
}

// Shared by the hero action row and the floating header.
extension DetailsViewModel {
    /// Plex rating key from either plexRatingKey or playableId ("plex:12345").
    var heroPlexRatingKey: String? {
        if let rk = plexRatingKey {
            return rk
        }
        if let playableId, playableId.hasPrefix("plex:") {
            return String(playableId.dropFirst(5))
        }
        return nil
    }

    var heroWatchlistCanonicalId: String? {
        if let playable = playableId, playable.hasPrefix("plex:") { return playable }
        if let tmdb = tmdbId {
            let prefix = (mediaKind == "tv") ? "tmdb:tv:" : "tmdb:movie:"
            return prefix + tmdb
        }
        return nil
    }

    var heroWatchlistMediaType: MyListViewModel.MediaType {
        mediaKind == "tv" ? .show : .movie
    }
}
