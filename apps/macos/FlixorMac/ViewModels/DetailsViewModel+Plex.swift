//
//  DetailsViewModel+Plex.swift
//  FlixorMac
//
//  TMDB -> Plex mapping and FlixorKit item conversion
//

import Foundation
import SwiftUI
import FlixorKit

extension DetailsViewModel {
    // MARK: - Plex search types

    struct PlexSearchResponse: Codable {
        let MediaContainer: PlexSearchContainer?
        let Metadata: [PlexSearchItem]?

        init(from decoder: Decoder) throws {
            // First, try to decode as a plain array (backend sometimes returns this)
            if let array = try? decoder.singleValueContainer().decode([PlexSearchItem].self) {
                self.MediaContainer = nil
                self.Metadata = array
                return
            }

            // Otherwise, decode as a dictionary with MediaContainer or Metadata fields
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let mc = try? container.decode(PlexSearchContainer.self, forKey: .MediaContainer) {
                self.MediaContainer = mc
            } else {
                self.MediaContainer = nil
            }
            if let array = try? container.decode([PlexSearchItem].self, forKey: .Metadata) {
                self.Metadata = array
            } else if let single = try? container.decode(PlexSearchItem.self, forKey: .Metadata) {
                self.Metadata = [single]
            } else {
                self.Metadata = nil
            }
        }

        init(MediaContainer: PlexSearchContainer?, Metadata: [PlexSearchItem]?) {
            self.MediaContainer = MediaContainer
            self.Metadata = Metadata
        }

        private enum CodingKeys: String, CodingKey { case MediaContainer, Metadata }
    }

    struct PlexSearchContainer: Codable {
        let Metadata: [PlexSearchItem]

        init(Metadata: [PlexSearchItem]) {
            self.Metadata = Metadata
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let items = try? container.decode([PlexSearchItem].self, forKey: .Metadata) {
                self.Metadata = items
            } else if let single = try? container.decode(PlexSearchItem.self, forKey: .Metadata) {
                self.Metadata = [single]
            } else {
                self.Metadata = []
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(Metadata, forKey: .Metadata)
        }

        private enum CodingKeys: String, CodingKey { case Metadata }
    }

    struct PlexSearchItem: Codable {
        let ratingKey: String
        let title: String?
        let grandparentTitle: String?
        let year: Int?
        let summary: String?
        let art: String?
        let thumb: String?
        let parentThumb: String?
        let grandparentThumb: String?
        let type: String?
        let Guid: [PlexGuid]?
        let Media: [PlexMedia]?
        let Role: [PlexRole]?
        // Ratings
        let Rating: [PlexRating]?
        let rating: Double?
        let audienceRating: Double?
    }

    /// The Plex item a TMDB title was mapped to.
    struct PlexMatch {
        let ratingKey: String
        /// Plex art for the hero, if the match has any.
        let backdrop: URL?
        let item: PlexSearchItem
    }

    struct PlexGuidLookup {
        let hits: [PlexSearchItem]
        /// A lookup failed with an error (not just "no match").
        let hadError: Bool
    }

    // MARK: - TMDB -> Plex mapping (web parity)

    /// GUID lookups need only the TMDB id, so they can start before the title is
    /// known. Writes no state; `mapToPlex` merges the hits.
    func startPlexGuidLookup(media: String, tmdbId: String) -> Task<PlexGuidLookup, Never> {
        let t = (media == "movie") ? 1 : 2
        return Task { [api] in
            @Sendable func find(_ guid: String) async -> PlexGuidLookup {
                do {
                    let res: PlexSearchResponse = try await api.get("/api/plex/findByGuid", queryItems: [URLQueryItem(name: "guid", value: guid), URLQueryItem(name: "type", value: String(t))])
                    return PlexGuidLookup(hits: res.MediaContainer?.Metadata ?? res.Metadata ?? [], hadError: false)
                } catch {
                    print("❌ [mapToPlex] GUID lookup failed for '\(guid)': \(error)")
                    return PlexGuidLookup(hits: [], hadError: true)
                }
            }
            @Sendable func externalGuids() async -> [String]? {
                struct Ext: Codable { let imdb_id: String?; let tvdb_id: Int? }
                guard let ex: Ext = try? await api.get("/api/tmdb/\(media)/\(tmdbId)/external_ids") else {
                    print("⚠️ [mapToPlex] Failed to fetch external IDs")
                    return nil
                }
                var guids: [String] = []
                if let imdb = ex.imdb_id, !imdb.isEmpty { guids.append("imdb://\(imdb)") }
                if media == "tv", let tvdb = ex.tvdb_id { guids.append("tvdb://\(tvdb)") }
                return guids
            }

            // tmdb:// and themoviedb:// right away; imdb:// and tvdb:// once external_ids is in.
            async let tmdbHits = find("tmdb://\(tmdbId)")
            async let movieDbHits = find("themoviedb://\(tmdbId)")
            async let external = externalGuids()
            var parts: [PlexGuidLookup] = []
            let externalList = await external
            if let externalList, externalList.count == 2 {
                async let first = find(externalList[0])
                async let second = find(externalList[1])
                parts = await [first, second]
            } else if let only = externalList?.first {
                parts = [await find(only)]
            }
            // Same order as the old one-by-one lookups, so ties score the same.
            let all = await [tmdbHits, movieDbHits] + parts
            return PlexGuidLookup(
                hits: all.flatMap(\.hits),
                hadError: externalList == nil || all.contains(where: \.hadError)
            )
        }
    }

    /// Maps a TMDB title to its Plex copy and applies the match (playable id,
    /// versions, Plex summary and cast). The backdrop and the ratings request are
    /// left to the caller.
    func mapToPlex(media: String, tmdbId: String, title: String, year: String?, guidLookup: Task<PlexGuidLookup, Never>? = nil) async throws -> PlexMatch {
        print("🔍 [mapToPlex] Starting TMDB → Plex mapping for '\(title)' (year: \(year ?? "nil"), tmdbId: \(tmdbId), media: \(media))")
        let lookup = guidLookup ?? startPlexGuidLookup(media: media, tmdbId: tmdbId)

        // Title search (skipped when the TMDB details didn't load)
        let t = (media == "movie") ? 1 : 2
        var candidates: [PlexSearchItem] = []
        var searchFailed = false
        if !title.isEmpty {
            do {
                let res: PlexSearchResponse = try await api.get("/api/plex/search", queryItems: [URLQueryItem(name: "query", value: title), URLQueryItem(name: "type", value: String(t))])
                let merged = (res.MediaContainer?.Metadata ?? []) + (res.Metadata ?? [])
                if !merged.isEmpty {
                    var seen = Set<String>()
                    candidates = merged.filter { seen.insert($0.ratingKey).inserted }
                } else {
                    print("⚠️ [mapToPlex] Title search returned no results")
                }
            } catch {
                print("❌ [mapToPlex] Title search failed: \(error)")
                searchFailed = true
            }
        }

        func norm(_ s: String) -> String { s.lowercased().replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression) }
        func score(_ it: PlexSearchItem) -> Int {
            let ht = norm(it.title ?? it.grandparentTitle ?? "")
            let qt = norm(title)
            var s = 0
            if ht == qt { s += 100 } else if ht.contains(qt) || qt.contains(ht) { s += 60 }
            if let y = year, let iy = it.year, String(iy) == y { s += 30 }
            if let kind = it.type?.lowercased() {
                if media == "movie" && kind.contains("movie") { s += 20 }
                if media == "tv" && (kind.contains("show") || kind.contains("episode")) { s += 20 }
            }
            return s
        }
        // Merge GUID-based matches into the candidates for scoring
        var pool = candidates
        let guidResult = await lookup.value
        let guidHits = guidResult.hits
        if !guidHits.isEmpty {
            var seen = Set(pool.map { $0.ratingKey })
            for item in guidHits {
                if seen.insert(item.ratingKey).inserted {
                    pool.append(item)
                }
            }
        } else {
            print("⚠️ [mapToPlex] No GUID matches found")
        }

        guard !pool.isEmpty else {
            // No match because a lookup errored (not because Plex lacks the
            // title): the next appearance retries the whole load.
            if searchFailed || guidResult.hadError {
                loadHadPartialFailure = true
            }
            print("❌ [mapToPlex] No candidates in pool, mapping failed")
            throw NSError(domain: "map", code: 404)
        }

        // Prefer exact TMDB GUID match
        var match: PlexSearchItem? = pool.first(where: { item in
            let guids = item.Guid?.compactMap { $0.id?.lowercased() } ?? []
            return guids.contains("tmdb://\(tmdbId)") || guids.contains("themoviedb://\(tmdbId)")
        })

        // Score-based fallback
        if match == nil {
            var bestScore = -1
            for c in pool {
                let sc = score(c)
                if sc > bestScore {
                    bestScore = sc
                    match = c
                }
            }
        }

        guard let match = match else {
            print("❌ [mapToPlex] No suitable match found in pool")
            throw NSError(domain: "map", code: 404)
        }

        // Update VM with Plex mapping
        let rk = match.ratingKey
        self.playableId = "plex:\(rk)"
        self.plexRatingKey = rk
        if let firstGuid = match.Guid?.compactMap({ $0.id }).first {
            self.plexGuid = firstGuid
        }
        print("✨ [mapToPlex] Setting playableId to: \(self.playableId ?? "nil")")
        self.addBadge("Plex")
        if posterURL == nil {
            let poster = match.thumb ?? match.parentThumb ?? match.grandparentThumb
            if let poster = poster,
               let posterURL = ImageService.shared.plexImageURL(path: poster, width: 600, height: 900) {
                self.posterURL = posterURL
            }
        }
        if let matchYear = match.year {
            self.year = String(matchYear)
        }
        if let summary = match.summary, !summary.isEmpty {
            self.overview = summary
        }
        // Prefer Plex cast roles
        if let roles = match.Role, !roles.isEmpty {
            self.castFromPlexMatch = true
            self.cast = roles.prefix(12).map { r in
                let name = r.tag ?? ""
                return Person(id: name, name: name, role: nil, profile: ImageService.shared.plexImageURL(path: r.thumb, width: 200, height: 200))
            }
        }
        // Versions
        if let mediaArr = match.Media {
            appendTechnicalBadges(from: mediaArr)
            hydrateVersions(from: mediaArr)
            extractEditionTitle(from: mediaArr)
        }

        // Prefer Plex backdrop
        let art = match.art ?? match.thumb ?? match.parentThumb ?? match.grandparentThumb ?? ""
        let backdrop = ImageService.shared.plexImageURL(path: art, width: 1920, height: 1080)
        print("✅ [mapToPlex] TMDB → Plex mapping complete for '\(match.title ?? title)' (ratingKey: \(rk))")
        return PlexMatch(ratingKey: rk, backdrop: backdrop, item: match)
    }

    /// Full metadata for the match's ratings (search results don't include them).
    func loadPlexMatchRatings(_ match: PlexMatch) async {
        let item = match.item
        guard let plexServer = FlixorCore.shared.plexServer else {
            parseRatings(from: item.Rating, fallbackRating: item.rating, fallbackAudienceRating: item.audienceRating)
            return
        }
        do {
            let fullMeta = try await plexServer.getMetadata(ratingKey: match.ratingKey)
            parseRatingsFromPlexMeta(plexItemToMeta(fullMeta))
        } catch {
            print("⚠️ [mapToPlex] Failed to fetch full metadata for ratings: \(error)")
            // Fallback to search results (likely empty for ratings)
            parseRatings(from: item.Rating, fallbackRating: item.rating, fallbackAudienceRating: item.audienceRating)
        }
    }

    // MARK: - FlixorKit Helpers

    func plexItemToMeta(_ item: FlixorKit.PlexMediaItem) -> PlexMeta {
        // Debug: log ratings from FlixorKit item
        print("🔄 [plexItemToMeta] Converting item '\(item.title ?? "unknown")' - ratings count: \(item.ratings.count), rating: \(item.rating ?? 0), audienceRating: \(item.audienceRating ?? 0)")
        for r in item.ratings {
            print("   📊 Rating entry - image: '\(r.image ?? "nil")', value: \(r.value ?? 0)")
        }
        return PlexMeta(
            ratingKey: item.ratingKey,
            type: item.type,
            title: item.title,
            summary: item.summary,
            year: item.year,
            contentRating: item.contentRating,
            duration: item.duration,
            thumb: item.thumb,
            art: item.art,
            Guid: item.guids.map { PlexGuid(id: $0) },
            Genre: item.genres.map { PlexTag(tag: $0.tag) },
            Role: item.roles.map { PlexRole(tag: $0.tag, thumb: $0.thumb) },
            Media: item.media.map { m in
                PlexMedia(
                    id: m.id,
                    width: m.width,
                    height: m.height,
                    duration: m.duration,
                    bitrate: m.bitrate,
                    videoCodec: m.videoCodec,
                    videoProfile: m.videoProfile,
                    audioChannels: m.audioChannels,
                    audioCodec: m.audioCodec,
                    audioProfile: m.audioProfile,
                    container: m.container,
                    editionTitle: m.editionTitle,
                    Part: m.parts.map { p in
                        PlexPart(
                            id: p.id,
                            size: p.size,
                            key: p.key,
                            file: p.file,
                            Stream: (p.Stream ?? []).map { s in
                                PlexStream(
                                    id: s.id,
                                    streamType: s.streamType,
                                    displayTitle: s.displayTitle,
                                    language: s.language,
                                    languageTag: s.languageTag
                                )
                            }
                        )
                    }
                )
            },
            Collection: item.collections.map { PlexTag(tag: $0.tag) },
            studio: item.studio,
            Rating: item.ratings.map { PlexRating(image: $0.image, value: $0.value, type: $0.type) },
            rating: item.rating,
            audienceRating: item.audienceRating,
            parentRatingKey: item.parentRatingKey,
            parentTitle: item.parentTitle,
            index: item.index,
            leafCount: item.leafCount,
            viewedLeafCount: item.viewedLeafCount,
            key: item.key,
            parentIndex: item.parentIndex,
            grandparentRatingKey: item.grandparentRatingKey,
            grandparentTitle: item.grandparentTitle,
            grandparentThumb: item.grandparentThumb,
            grandparentArt: item.grandparentArt,
            originallyAvailableAt: item.originallyAvailableAt
        )
    }
}
