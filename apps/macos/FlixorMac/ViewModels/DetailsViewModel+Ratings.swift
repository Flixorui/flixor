//
//  DetailsViewModel+Ratings.swift
//  FlixorMac
//
//  Plex ratings parsing and MDBList ratings
//

import Foundation
import SwiftUI
import FlixorKit

extension DetailsViewModel {
    /// Parse ratings directly from Plex metadata (like mobile app)
    func parseRatingsFromPlexMeta(_ meta: PlexMeta) {
        parseRatings(from: meta.Rating, fallbackRating: meta.rating, fallbackAudienceRating: meta.audienceRating)
    }

    /// Parse ratings from any type with Rating, rating, audienceRating fields
    func parseRatings(from plexRatings: [PlexRating]?, fallbackRating: Double?, fallbackAudienceRating: Double?) {
        var imdbRating: Double?
        var rtCriticRating: Int?
        var rtAudienceRating: Int?

        // Debug: log what we're receiving
        print("🎬 [parseRatings] Input - Rating array count: \(plexRatings?.count ?? 0), fallbackRating: \(fallbackRating ?? 0), fallbackAudienceRating: \(fallbackAudienceRating ?? 0)")

        // Parse from Rating array (matching mobile's exact approach)
        if let ratings = plexRatings {
            for r in ratings {
                let img = (r.image ?? "").lowercased()
                guard let value = r.value else { continue }
                print("🔍 [parseRatings] Rating entry - image: '\(img)', value: \(value)")

                // IMDb rating - match mobile's 'imdb://image.rating' pattern
                if img.contains("imdb://image.rating") || (img.contains("imdb") && img.contains("rating")) {
                    imdbRating = value
                    print("✓ [parseRatings] Matched IMDb: \(value)")
                }
                // RT Critic - match mobile's 'rottentomatoes://image.rating.ripe' or 'rotten' patterns
                else if img.contains("rottentomatoes://image.rating.ripe") ||
                        img.contains("rottentomatoes://image.rating.rotten") ||
                        img.contains("rottentomatoes://image.rating.certified") ||
                        (img.contains("rottentomatoes") && (img.contains("ripe") || img.contains("rotten") || img.contains("certified"))) {
                    rtCriticRating = Int(value * 10)
                    print("✓ [parseRatings] Matched RT Critic: \(Int(value * 10))%")
                }
                // RT Audience - match mobile's 'rottentomatoes://image.rating.upright' or 'spilled' patterns
                else if img.contains("rottentomatoes://image.rating.upright") ||
                        img.contains("rottentomatoes://image.rating.spilled") ||
                        (img.contains("rottentomatoes") && (img.contains("upright") || img.contains("spilled") || img.contains("audience"))) {
                    rtAudienceRating = Int(value * 10)
                    print("✓ [parseRatings] Matched RT Audience: \(Int(value * 10))%")
                } else {
                    print("⚠️ [parseRatings] Unmatched rating image: '\(img)'")
                }
            }
        } else {
            print("⚠️ [parseRatings] Rating array is nil")
        }

        // Fallbacks from top-level fields (always set these for direct access)
        if let topRating = fallbackRating {
            plexImdbRating = topRating
            if imdbRating == nil {
                imdbRating = topRating
            }
        }
        if let audienceRating = fallbackAudienceRating {
            plexAudienceRating = Int(audienceRating * 10)
            if rtAudienceRating == nil {
                rtAudienceRating = Int(audienceRating * 10)
            }
        }

        // Set external ratings if any found
        if imdbRating != nil || rtCriticRating != nil || rtAudienceRating != nil {
            let imdbModel = imdbRating.map { ExternalRatings.IMDb(score: $0, votes: nil) }
            let rtModel: ExternalRatings.RottenTomatoes?
            if rtCriticRating != nil || rtAudienceRating != nil {
                rtModel = ExternalRatings.RottenTomatoes(critic: rtCriticRating, audience: rtAudienceRating)
            } else {
                rtModel = nil
            }
            externalRatings = ExternalRatings(imdb: imdbModel, rottenTomatoes: rtModel)
            print("✅ [Details] Parsed ratings - IMDb: \(imdbRating ?? 0), RT Critic: \(rtCriticRating ?? 0)%, RT Audience: \(rtAudienceRating ?? 0)%")
        } else {
            print("⚠️ [Details] No ratings parsed from Plex metadata")
        }
    }

    // MARK: - MDBList Ratings

    /// Extract IMDB ID from Plex Guids array
    func extractImdbId(from guids: [PlexGuid]?) {
        guard let guids = guids else { return }
        for guid in guids {
            if let id = guid.id, (id.contains("imdb://") || id.contains("imdb.com/title/")) {
                if let imdb = id.components(separatedBy: "://").last {
                    // Handle formats like "imdb://tt1234567" or "imdb.com/title/tt1234567"
                    let cleaned = imdb.replacingOccurrences(of: "title/", with: "")
                    if cleaned.hasPrefix("tt") {
                        imdbId = cleaned
                        print("🎬 [Details] Extracted IMDB ID: \(cleaned)")
                        return
                    }
                }
            }
        }
    }

    /// Load ratings from MDBList (if enabled and IMDB ID available)
    func loadMDBListRatings() async {
        guard MDBListService.shared.isReady() else { return }
        guard let imdb = imdbId, !imdb.isEmpty else {
            // Try to get IMDB ID from TMDB external_ids if we have tmdbId
            if let tid = tmdbId, let media = mediaKind {
                await fetchImdbIdFromTMDB(tmdbId: tid, mediaType: media)
            }
            guard let imdb = imdbId, !imdb.isEmpty else {
                print("⚠️ [Details] No IMDB ID available for MDBList lookup")
                return
            }
            await fetchMDBListRatings(imdbId: imdb)
            return
        }
        await fetchMDBListRatings(imdbId: imdb)
    }

    private func fetchImdbIdFromTMDB(tmdbId: String, mediaType: String) async {
        struct ExtIds: Codable { let imdb_id: String? }
        do {
            let ext: ExtIds = try await api.get("/api/tmdb/\(mediaType)/\(tmdbId)/external_ids")
            if let imdb = ext.imdb_id, !imdb.isEmpty {
                self.imdbId = imdb
                print("🎬 [Details] Got IMDB ID from TMDB: \(imdb)")
            }
        } catch {
            print("⚠️ [Details] Failed to fetch IMDB ID from TMDB: \(error)")
        }
    }

    private func fetchMDBListRatings(imdbId: String) async {
        let mediaType = (mediaKind == "movie") ? "movie" : "show"
        mdblistRatings = await MDBListService.shared.fetchRatings(imdbId: imdbId, mediaType: mediaType)
        if mdblistRatings != nil {
            print("✅ [Details] Loaded MDBList ratings for \(imdbId)")
        }
    }
}
