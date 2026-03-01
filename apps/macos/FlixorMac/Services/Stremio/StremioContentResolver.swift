//
//  StremioContentResolver.swift
//  FlixorMac
//
//  Resolves Plex and TMDB items into Stremio request IDs.
//

import Foundation

enum StremioResolverError: String {
    case noStreamAddons = "no_stream_addons"
    case unsupportedID = "unsupported_id"
    case unresolved = "unresolved"
}

struct StremioResolverResult {
    let identity: StremioContentIdentity?
    let error: StremioResolverError?
}

private struct StremioDetailsSnapshot {
    let playableId: String?
    let mediaKind: String?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let imdbId: String?
    let tmdbId: String?
}

enum StremioContentResolver {
    static func buildContentKey(identity: StremioContentIdentity) -> String {
        if identity.requestType == StremioRequestType.movie.rawValue {
            return "movie:\(identity.baseId)"
        }
        return "series:\(identity.baseId):\(identity.seasonNumber ?? 1):\(identity.episodeNumber ?? 1)"
    }

    static func resolve(
        item: MediaItem,
        details: DetailsViewModel,
        episode: DetailsViewModel.Episode? = nil
    ) async -> StremioResolverResult {
        let snapshot = await MainActor.run {
            StremioDetailsSnapshot(
                playableId: details.playableId,
                mediaKind: details.mediaKind,
                seasonNumber: details.seasonNumber,
                episodeNumber: details.episodeNumber,
                imdbId: details.imdbId,
                tmdbId: details.tmdbId
            )
        }

        let hasProviders = await StremioService.shared.hasStreamProviders()
        guard hasProviders else {
            return StremioResolverResult(identity: nil, error: .noStreamAddons)
        }

        if item.id.hasPrefix("tmdb:") || snapshot.playableId == nil {
            return await resolveFromTMDB(item: item, snapshot: snapshot, episode: episode)
        }
        return await resolveFromPlex(item: item, snapshot: snapshot, episode: episode)
    }

    private static func resolveFromPlex(
        item: MediaItem,
        snapshot: StremioDetailsSnapshot,
        episode: DetailsViewModel.Episode?
    ) async -> StremioResolverResult {
        let requestType: StremioRequestType = snapshot.mediaKind == "movie" || item.type == "movie" ? .movie : .series
        let seasonNumber = episode?.seasonNumber ?? snapshot.seasonNumber ?? item.parentIndex
        let episodeNumber = episode?.episodeNumber ?? snapshot.episodeNumber ?? item.index

        let imdbId = snapshot.imdbId
        let tmdbId = Int(snapshot.tmdbId ?? "")

        var candidates: [(String, String)] = []
        if let imdbId, !imdbId.isEmpty {
            candidates.append((imdbId, "plex-guid"))
        }
        if let tmdbId {
            candidates.append(("tmdb:\(tmdbId)", "plex-guid"))
        }

        for candidate in candidates {
            let supported = await StremioService.shared.canResolveId(requestType: requestType, contentId: candidate.0)
            if supported {
                return StremioResolverResult(
                    identity: buildIdentity(
                        requestType: requestType,
                        baseId: candidate.0,
                        source: candidate.1,
                        imdbId: imdbId,
                        tmdbId: tmdbId,
                        seasonNumber: seasonNumber,
                        episodeNumber: episodeNumber
                    ),
                    error: nil
                )
            }
        }

        return StremioResolverResult(identity: nil, error: candidates.isEmpty ? .unresolved : .unsupportedID)
    }

    private static func resolveFromTMDB(
        item: MediaItem,
        snapshot: StremioDetailsSnapshot,
        episode: DetailsViewModel.Episode?
    ) async -> StremioResolverResult {
        let parts = item.id.split(separator: ":")
        let mediaSegment = parts.count > 1 ? String(parts[1]) : (snapshot.mediaKind == "movie" ? "movie" : "tv")
        let mediaType = mediaSegment == "movie" ? "movie" : "tv"

        let tmdbId = Int(snapshot.tmdbId ?? "") ?? (parts.count > 2 ? Int(parts[2]) : nil)
        guard let tmdbId else {
            return StremioResolverResult(identity: nil, error: .unresolved)
        }

        let requestType: StremioRequestType = mediaType == "movie" ? .movie : .series
        let seasonNumber = episode?.seasonNumber ?? snapshot.seasonNumber
        let episodeNumber = episode?.episodeNumber ?? snapshot.episodeNumber

        var imdbId = snapshot.imdbId
        if imdbId == nil || imdbId?.isEmpty == true {
            struct ExternalIDs: Decodable { let imdb_id: String? }
            do {
                let ext: ExternalIDs = try await APIClient.shared.get("/api/tmdb/\(mediaType)/\(tmdbId)/external_ids")
                imdbId = ext.imdb_id
            } catch {
                AppLogger.shared.warn("[Stremio] Failed to fetch TMDB external IDs during resolver", data: [
                    "mediaType": mediaType,
                    "tmdbId": tmdbId,
                    "error": error.localizedDescription,
                ])
            }
        }

        var candidates: [(String, String)] = []
        if let imdbId, !imdbId.isEmpty {
            candidates.append((imdbId, "tmdb-external-ids"))
        }
        candidates.append(("tmdb:\(tmdbId)", "tmdb"))

        for candidate in candidates {
            let supported = await StremioService.shared.canResolveId(requestType: requestType, contentId: candidate.0)
            if supported {
                return StremioResolverResult(
                    identity: buildIdentity(
                        requestType: requestType,
                        baseId: candidate.0,
                        source: candidate.1,
                        imdbId: imdbId,
                        tmdbId: tmdbId,
                        seasonNumber: seasonNumber,
                        episodeNumber: episodeNumber
                    ),
                    error: nil
                )
            }
        }

        return StremioResolverResult(identity: nil, error: .unsupportedID)
    }

    private static func buildIdentity(
        requestType: StremioRequestType,
        baseId: String,
        source: String,
        imdbId: String?,
        tmdbId: Int?,
        seasonNumber: Int?,
        episodeNumber: Int?
    ) -> StremioContentIdentity {
        let requestId: String
        if requestType == .series, let seasonNumber, let episodeNumber {
            requestId = "\(baseId):\(seasonNumber):\(episodeNumber)"
        } else {
            requestId = baseId
        }

        return StremioContentIdentity(
            requestType: requestType.rawValue,
            baseId: baseId,
            requestId: requestId,
            imdbId: imdbId,
            tmdbId: tmdbId,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            source: source
        )
    }
}
