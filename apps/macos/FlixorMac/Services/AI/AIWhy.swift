//
//  AIWhy.swift
//  FlixorMac
//
//  "Why you'd like it": one line on Details tying a title to ones the user
//  rated or watched. The app finds the connections itself (same director,
//  same lead actor, TMDB recommends it to fans of a title the user loved);
//  the model only writes the sentence. No connection, no line.
//

import Foundation
import FlixorKit

enum AIWhyService {
    /// A title the user has seen, with their rating when there is one.
    struct Seen: Hashable {
        let title: String
        let rating: Int?
        /// In progress rather than finished.
        var started = false
    }

    @MainActor private static var lines: [String: String?] = [:]
    @MainActor private static var taste: (seen: [String: Seen], fetchedAt: Date)?

    /// The line for a title, or nil when nothing connects it to the user's taste.
    static func line(tmdbId: Int, isMovie: Bool, title: String) async -> String? {
        let key = "\(isMovie ? "movie" : "tv"):\(tmdbId)"
        if let cached = await MainActor.run(body: { lines[key] }) { return cached }

        let seen = await tasteProfile()
        guard !seen.isEmpty, seen[key] == nil else {
            logInfo("[AI] Why: \(seen.count) titles in taste profile; already seen: \(seen[key] != nil)")
            // Nothing to compare with, or they've seen this one already.
            await MainActor.run { lines[key] = .some(nil) }
            return nil
        }
        let facts = await connections(tmdbId: tmdbId, isMovie: isMovie, seen: seen)
        logInfo("[AI] Why: \(seen.count) titles in taste profile, \(facts.count) connections")
        guard !facts.isEmpty else {
            await MainActor.run { lines[key] = .some(nil) }
            return nil
        }

        let schema = AISchema.object(name: "Why", properties: [
            AISchemaProperty(name: "line", description: "One sentence, at most 16 words, addressed to the viewer", schema: .string())
        ])
        let instructions = """
        You write one short sentence telling a viewer why they might like a title, using only the facts given. \
        Mention the most persuasive fact (a high rating beats a plain watch). Don't add facts, praise or adjectives \
        that aren't given. Address the viewer as "you". At most 16 words.
        """
        let prompt = "Title: \(title)\nFacts:\n" + facts.prefix(4).map { "- \($0)" }.joined(separator: "\n")
        guard let data = try? await AIService.generateJSON(AIStructuredRequest(instructions: instructions, prompt: prompt, schema: schema, quick: true)),
              let answer = try? JSONDecoder().decode([String: String].self, from: data),
              let text = answer["line"]?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil // not cached: a failed request can be retried next time
        }
        await MainActor.run { lines[key] = .some(text) }
        return text
    }

    // MARK: Taste

    /// Titles the user rated (Trakt) or watched (Trakt history, local), by "movie:id" / "tv:id".
    private static func tasteProfile() async -> [String: Seen] {
        if let taste = await MainActor.run(body: { taste }), Date().timeIntervalSince(taste.fetchedAt) < 30 * 60 {
            return taste.seen
        }
        var seen: [String: Seen] = [:]
        let trakt = await FlixorCore.shared.trakt
        if await trakt.isAuthenticated {
            for type in ["movies", "shows"] {
                for item in (try? await trakt.getUserRatings(type: type)) ?? [] {
                    if let movie = item.movie, let id = movie.ids.tmdb {
                        seen["movie:\(id)"] = Seen(title: movie.title, rating: item.rating)
                    } else if let show = item.show, let id = show.ids.tmdb {
                        seen["tv:\(id)"] = Seen(title: show.title, rating: item.rating)
                    }
                }
            }
            for item in (try? await trakt.getWatchedMovieSummaries()) ?? [] {
                if let id = item.movie.ids.tmdb, seen["movie:\(id)"] == nil {
                    seen["movie:\(id)"] = Seen(title: item.movie.title, rating: nil)
                }
            }
            for item in (try? await trakt.getWatchedShowSummaries()) ?? [] {
                if let id = item.show.ids.tmdb, seen["tv:\(id)"] == nil {
                    seen["tv:\(id)"] = Seen(title: item.show.title, rating: nil)
                }
            }
            for item in (try? await trakt.getPausedPlayback()) ?? [] {
                if let movie = item.movie, let id = movie.ids.tmdb, seen["movie:\(id)"] == nil {
                    seen["movie:\(id)"] = Seen(title: movie.title, rating: nil, started: true)
                } else if let show = item.show, let id = show.ids.tmdb, seen["tv:\(id)"] == nil {
                    seen["tv:\(id)"] = Seen(title: show.title, rating: nil, started: true)
                }
            }
        }
        for entry in await LocalLibraryStore.shared.watchHistory() {
            guard let id = entry.tmdbId else { continue }
            let key = entry.mediaType == .movie ? "movie:\(id)" : "tv:\(id)"
            if seen[key] == nil { seen[key] = Seen(title: entry.title, rating: nil, started: entry.positionMs > 0 && entry.positionMs < entry.durationMs * 9 / 10) }
        }
        let result = seen
        await MainActor.run { taste = (result, Date()) }
        return result
    }

    // MARK: Connections

    private static func describe(_ seen: Seen) -> String {
        if let rating = seen.rating { return "\(seen.title) (you rated it \(rating)/10)" }
        if seen.started { return "\(seen.title) (you started watching it)" }
        return "\(seen.title) (you watched it)"
    }

    /// Facts linking the title to what the user has seen, best first.
    private static func connections(tmdbId: Int, isMovie: Bool, seen: [String: Seen]) async -> [String] {
        let tmdb = await FlixorCore.shared.tmdb
        let selfKey = "\(isMovie ? "movie" : "tv"):\(tmdbId)"
        func key(_ media: TMDBMedia) -> String? {
            let type = media.mediaType ?? (media.title != nil ? "movie" : "tv")
            guard type == "movie" || type == "tv" else { return nil }
            return "\(type):\(media.id)"
        }
        /// The best-rated seen title among `media`.
        func bestSeen(_ media: [TMDBMedia]) -> Seen? {
            media.compactMap { m in key(m).flatMap { $0 == selfKey ? nil : seen[$0] } }
                .max { ($0.rating ?? 6) < ($1.rating ?? 6) }
        }

        var facts: [(score: Int, text: String)] = []
        let credits = try? await (isMovie ? tmdb.getMovieCredits(id: tmdbId) : tmdb.getTVCredits(id: tmdbId))

        // Same director (movies) or creator-level crew.
        let directors = (credits?.crew ?? []).filter { $0.job == "Director" }.prefix(1)
        for person in directors {
            guard let theirs = try? await tmdb.getPersonCredits(id: person.id) else { continue }
            let directed = theirs.crew.filter { $0.job == "Director" }
            if let match = bestSeen(directed) {
                facts.append((30 + (match.rating ?? 6), "Directed by \(person.name), who also directed \(describe(match))"))
            }
        }

        // Same lead actors.
        for person in (credits?.cast ?? []).prefix(2) {
            guard let theirs = try? await tmdb.getPersonCredits(id: person.id) else { continue }
            if let match = bestSeen(theirs.cast) {
                facts.append((20 + (match.rating ?? 6), "Stars \(person.name), who is also in \(describe(match))"))
            }
        }

        // TMDB recommends this to fans of something the user loved.
        let recs = try? await (isMovie ? tmdb.getMovieRecommendations(id: tmdbId) : tmdb.getTVRecommendations(id: tmdbId))
        if let match = bestSeen(recs?.results ?? []), (match.rating ?? 8) >= 7 {
            facts.append((10 + (match.rating ?? 6), "Often recommended to people who liked \(describe(match))"))
        }

        return facts.sorted { $0.score > $1.score }.map(\.text)
    }
}
