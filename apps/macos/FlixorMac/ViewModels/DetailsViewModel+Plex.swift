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
    // MARK: - TMDB -> Plex mapping (web parity)
    func mapToPlex(media: String, tmdbId: String, title: String, year: String?) async throws {
        print("🔍 [mapToPlex] Starting TMDB → Plex mapping for '\(title)' (year: \(year ?? "nil"), tmdbId: \(tmdbId), media: \(media))")

        // First: Title search (as requested)
        struct SearchResponse: Codable {
            let MediaContainer: SearchContainer?
            let Metadata: [SearchItem]?

            init(from decoder: Decoder) throws {
                // First, try to decode as a plain array (backend sometimes returns this)
                if let array = try? decoder.singleValueContainer().decode([SearchItem].self) {
                    self.MediaContainer = nil
                    self.Metadata = array
                    return
                }

                // Otherwise, decode as a dictionary with MediaContainer or Metadata fields
                let container = try decoder.container(keyedBy: CodingKeys.self)
                if let mc = try? container.decode(SearchContainer.self, forKey: .MediaContainer) {
                    self.MediaContainer = mc
                } else {
                    self.MediaContainer = nil
                }
                if let array = try? container.decode([SearchItem].self, forKey: .Metadata) {
                    self.Metadata = array
                } else if let single = try? container.decode(SearchItem.self, forKey: .Metadata) {
                    self.Metadata = [single]
                } else {
                    self.Metadata = nil
                }
            }

            init(MediaContainer: SearchContainer?, Metadata: [SearchItem]?) {
                self.MediaContainer = MediaContainer
                self.Metadata = Metadata
            }

            private enum CodingKeys: String, CodingKey { case MediaContainer, Metadata }
        }
        struct SearchContainer: Codable {
            let Metadata: [SearchItem]

            init(Metadata: [SearchItem]) {
                self.Metadata = Metadata
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                if let items = try? container.decode([SearchItem].self, forKey: .Metadata) {
                    self.Metadata = items
                } else if let single = try? container.decode(SearchItem.self, forKey: .Metadata) {
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
        struct SearchItem: Codable {
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

        let t = (media == "movie") ? 1 : 2
        var candidates: [SearchItem] = []
        do {
            let res: SearchResponse = try await api.get("/api/plex/search", queryItems: [URLQueryItem(name: "query", value: title), URLQueryItem(name: "type", value: String(t))])
            let merged = (res.MediaContainer?.Metadata ?? []) + (res.Metadata ?? [])
            if !merged.isEmpty {
                var seen = Set<String>()
                candidates = merged.filter { seen.insert($0.ratingKey).inserted }
                print("📋 [mapToPlex] Title search found \(candidates.count) candidates: \(candidates.map { "\($0.title ?? "?") (\($0.ratingKey))" }.joined(separator: ", "))")
            } else {
                print("⚠️ [mapToPlex] Title search returned no results")
            }
        } catch {
            print("❌ [mapToPlex] Title search failed: \(error)")
        }

        func norm(_ s: String) -> String { s.lowercased().replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression) }
        func score(_ it: SearchItem) -> Int {
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
        // Gather GUID-based matches and merge into candidates for scoring
        var pool = candidates
        // Build GUID list
        var guids = ["tmdb://\(tmdbId)", "themoviedb://\(tmdbId)"]
        do {
            struct Ext: Codable { let imdb_id: String?; let tvdb_id: Int? }
            let ex: Ext = try await api.get("/api/tmdb/\(media)/\(tmdbId)/external_ids")
            if let imdb = ex.imdb_id, !imdb.isEmpty { guids.append("imdb://\(imdb)") }
            if media == "tv", let tvdb = ex.tvdb_id { guids.append("tvdb://\(tvdb)") }
        } catch {
            print("⚠️ [mapToPlex] Failed to fetch external IDs")
        }
        print("🔑 [mapToPlex] GUID list: \(guids.joined(separator: ", "))")
        var guidHits: [SearchItem] = []
        for g in guids {
            do {
                let res: SearchResponse = try await api.get("/api/plex/findByGuid", queryItems: [URLQueryItem(name: "guid", value: g), URLQueryItem(name: "type", value: String(t))])
                let matches = res.MediaContainer?.Metadata ?? res.Metadata ?? []
                if !matches.isEmpty {
                    print("✅ [mapToPlex] GUID '\(g)' found \(matches.count) match(es): \(matches.map { "\($0.title ?? "?") (\($0.ratingKey))" }.joined(separator: ", "))")
                    guidHits.append(contentsOf: matches)
                }
            } catch {
                print("❌ [mapToPlex] GUID lookup failed for '\(g)': \(error)")
            }
        }
        if !guidHits.isEmpty {
            var seen = Set(pool.map { $0.ratingKey })
            for item in guidHits {
                if seen.insert(item.ratingKey).inserted {
                    pool.append(item)
                }
            }
            print("🔀 [mapToPlex] Merged GUID hits into pool. Total pool size: \(pool.count)")
        } else {
            print("⚠️ [mapToPlex] No GUID matches found")
        }

        guard !pool.isEmpty else {
            print("❌ [mapToPlex] No candidates in pool, mapping failed")
            throw NSError(domain: "map", code: 404)
        }

        // Prefer exact TMDB GUID match
        var match: SearchItem? = pool.first(where: { item in
            let guids = item.Guid?.compactMap { $0.id?.lowercased() } ?? []
            return guids.contains("tmdb://\(tmdbId)") || guids.contains("themoviedb://\(tmdbId)")
        })

        if let exactMatch = match {
            print("🎯 [mapToPlex] Found exact TMDB GUID match: '\(exactMatch.title ?? "?")' (ratingKey: \(exactMatch.ratingKey))")
        }

        // Score-based fallback
        if match == nil {
            print("🔢 [mapToPlex] No exact GUID match, using score-based matching...")
            var bestScore = -1
            for c in pool {
                let sc = score(c)
                print("   - '\(c.title ?? "?")' (\(c.ratingKey)): score \(sc)")
                if sc > bestScore {
                    bestScore = sc
                    match = c
                }
            }
            if let scoreMatch = match {
                print("🏆 [mapToPlex] Best score match: '\(scoreMatch.title ?? "?")' (ratingKey: \(scoreMatch.ratingKey), score: \(bestScore))")
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
        // Prefer Plex backdrop
        let art = match.art ?? match.thumb ?? match.parentThumb ?? match.grandparentThumb ?? ""
        if let u = ImageService.shared.plexImageURL(path: art, width: 1920, height: 1080) {
            self.backdropURL = u
        }
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
            print("📊 [mapToPlex] Loaded \(mediaArr.count) media version(s) for technical details")
        } else {
            print("⚠️ [mapToPlex] No media versions found in Plex match")
        }

        // Fetch full metadata to get Rating array (search results don't include ratings)
        if let plexServer = FlixorCore.shared.plexServer {
            do {
                let fullMeta = try await plexServer.getMetadata(ratingKey: rk)
                let meta = plexItemToMeta(fullMeta)
                parseRatingsFromPlexMeta(meta)
                print("✅ [mapToPlex] Fetched full metadata for ratings - Rating count: \(fullMeta.ratings.count)")
            } catch {
                print("⚠️ [mapToPlex] Failed to fetch full metadata for ratings: \(error)")
                // Fallback to search results (likely empty for ratings)
                parseRatings(from: match.Rating, fallbackRating: match.rating, fallbackAudienceRating: match.audienceRating)
            }
        } else {
            parseRatings(from: match.Rating, fallbackRating: match.rating, fallbackAudienceRating: match.audienceRating)
        }

        await loadPlexExtras(ratingKey: rk)
        print("✅ [mapToPlex] TMDB → Plex mapping complete for '\(match.title ?? title)' (ratingKey: \(rk))")
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
