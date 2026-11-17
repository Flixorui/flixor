//
//  AIRecap.swift
//  FlixorMac
//
//  "Previously on": a short recap of a show up to the last episode the user
//  watched, written only from TMDB's summaries of those episodes, so it can't
//  reveal anything later. Recaps are kept for the session.
//

import Foundation
import FlixorKit

struct AIRecap: Codable, Equatable {
    struct Bullet: Codable, Equatable, Hashable {
        let label: String
        let text: String
    }
    let bullets: [Bullet]
}

/// The last episode watched, and whether there's more after it.
struct RecapProgress: Equatable {
    let season: Int
    let episode: Int
    var code: String { "S\(season) E\(episode)" }
}

enum AIRecapService {
    @MainActor private static var cache: [String: AIRecap] = [:]

    /// Last watched episode of a show the user is partway through, from local
    /// watch state and Trakt. nil when not started or finished.
    static func progress(tmdbId: Int, imdbId: String?) async -> RecapProgress? {
        var best: (Int, Int)?
        func consider(_ s: Int, _ e: Int) {
            guard s > 0, e > 0 else { return }
            if let current = best, (current.0, current.1) >= (s, e) { return }
            best = (s, e)
        }

        let local = await LocalLibraryStore.shared.watchedEpisodes(tmdbId: tmdbId, imdbId: imdbId)
        for entry in local {
            if let s = entry.seasonNumber, let e = entry.episodeNumber { consider(s, e) }
        }

        let trakt = await FlixorCore.shared.trakt
        var finished = false
        if await trakt.isAuthenticated,
           let show = try? await trakt.lookupByTmdb(tmdbId: tmdbId, type: "show")?.show,
           let showId = show.ids.trakt.map(String.init) ?? show.ids.slug,
           let next = try? await trakt.getShowNextUp(showId: showId) {
            if next.completed > 0 {
                if let up = next.nextEpisode {
                    if up.number > 1 {
                        consider(up.season, up.number - 1)
                    } else if up.season > 1, let count = await episodeCount(tmdbId: tmdbId, season: up.season - 1) {
                        consider(up.season - 1, count)
                    }
                } else if next.completed >= next.aired {
                    finished = true
                }
            }
        }
        guard !finished, let best else { return nil }
        return RecapProgress(season: best.0, episode: best.1)
    }

    private static func episodeCount(tmdbId: Int, season: Int) async -> Int? {
        let tmdb = await FlixorCore.shared.tmdb
        guard let details = try? await tmdb.getTVDetails(id: tmdbId) else { return nil }
        return details.seasons.first { $0.seasonNumber == season }?.episodeCount
    }

    /// The recap up to `progress`. Throws when the AI is off or fails.
    static func recap(tmdbId: Int, title: String, upTo progress: RecapProgress) async throws -> AIRecap {
        let cacheKey = "\(tmdbId):\(progress.season):\(progress.episode)"
        if let cached = await MainActor.run(body: { cache[cacheKey] }) { return cached }

        let tmdb = await FlixorCore.shared.tmdb
        let details = try? await tmdb.getTVDetails(id: tmdbId)
        var sections: [String] = []

        // Earlier seasons: their overviews (the last three before this one).
        let earlier = (details?.seasons ?? [])
            .filter { ($0.seasonNumber ?? 0) > 0 && ($0.seasonNumber ?? 0) < progress.season }
            .suffix(3)
        for season in earlier {
            if let overview = season.overview, !overview.isEmpty {
                sections.append("Season \(season.seasonNumber ?? 0): \(clip(overview, 500))")
            } else if let number = season.seasonNumber,
                      let full = try? await tmdb.getSeasonDetails(tvId: tmdbId, seasonNumber: number) {
                let lines = full.episodes.suffix(4).compactMap { ep -> String? in
                    guard let o = ep.overview, !o.isEmpty else { return nil }
                    return "S\(number) E\(ep.episodeNumber ?? 0): \(clip(o, 200))"
                }
                if !lines.isEmpty { sections.append(lines.joined(separator: "\n")) }
            }
        }

        // This season: each watched episode, up to the last ten.
        if let current = try? await tmdb.getSeasonDetails(tvId: tmdbId, seasonNumber: progress.season) {
            let watched = current.episodes
                .filter { ($0.episodeNumber ?? 0) >= 1 && ($0.episodeNumber ?? 0) <= progress.episode }
                .suffix(10)
            for ep in watched {
                guard let overview = ep.overview, !overview.isEmpty else { continue }
                sections.append("S\(progress.season) E\(ep.episodeNumber ?? 0) \"\(ep.name)\": \(clip(overview, 300))")
            }
        }
        guard !sections.isEmpty else {
            throw AIError.unavailable(String(localized: "TMDB has no episode summaries for this show yet."))
        }

        let schema = AISchema.object(name: "Recap", properties: [
            AISchemaProperty(
                name: "bullets",
                description: "3 to 5 recap points in story order",
                schema: .array(.object(name: "Bullet", properties: [
                    AISchemaProperty(name: "label", description: "Where this happens, like Season 1 or S2 E1-2", schema: .string()),
                    AISchemaProperty(name: "text", description: "One or two sentences, at most 35 words", schema: .string())
                ]))
            )
        ])
        let instructions = """
        You write a short "previously on" recap of a TV show for a viewer about to keep watching. \
        Use only the episode and season summaries given. Do not add events, names or outcomes that aren't in them, \
        and never hint at anything after the last episode listed. Plain, friendly sentences.
        """
        let prompt = "Show: \(title)\nThe viewer has watched up to \(progress.code).\n\nSummaries:\n" + sections.joined(separator: "\n")
        let data = try await AIService.generateJSON(AIStructuredRequest(instructions: instructions, prompt: prompt, schema: schema, quick: false))
        let recap = try JSONDecoder().decode(AIRecap.self, from: data)
        guard !recap.bullets.isEmpty else { throw AIError.badResponse("empty recap") }
        await MainActor.run { cache[cacheKey] = recap }
        return recap
    }

    private static func clip(_ text: String, _ limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit)) + "…"
    }
}
