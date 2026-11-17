//
//  AIMoodPicks.swift
//  FlixorMac
//
//  Mood picks: the Home "Tonight" row. The model chooses only among titles the
//  user already has at hand (Continue Watching and the watchlist), by mood, and
//  writes a few words for each; it can't add a title of its own.
//

import Foundation
import FlixorKit

enum MoodPickMood: String, CaseIterable, Identifiable {
    case lightShort, edge, started, bigNight

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lightShort: return String(localized: "Light & short")
        case .edge: return String(localized: "Edge of your seat")
        case .started: return String(localized: "Something you started")
        case .bigNight: return String(localized: "Big night in")
        }
    }

    /// What the mood means, for the model.
    fileprivate var brief: String {
        switch self {
        case .lightShort: return "light, warm or funny, and short: movies under about 110 minutes or episodes under 40"
        case .edge: return "tense and gripping: thrillers, crime, mysteries, action, horror"
        case .started: return "titles the viewer is partway through"
        case .bigNight: return "an event watch: long, epic, acclaimed or spectacular"
        }
    }
}

struct MoodPickCandidate: Hashable {
    enum Source: String { case continueWatching = "in progress", watchlist = "in your watchlist" }
    let item: MediaItem
    let source: Source
    /// "Next: S3 E2", "45% watched".
    var note: String?

    static func == (a: Self, b: Self) -> Bool { a.item.id == b.item.id && a.source == b.source }
    func hash(into hasher: inout Hasher) { hasher.combine(item.id); hasher.combine(source.rawValue) }
}

struct MoodPick: Identifiable, Hashable {
    let item: MediaItem
    let reason: String
    var id: String { item.id }

    static func == (a: Self, b: Self) -> Bool { a.item.id == b.item.id && a.reason == b.reason }
    func hash(into hasher: inout Hasher) { hasher.combine(item.id) }
}

enum AIMoodPicksService {
    @MainActor private static var cache: [String: [MoodPick]] = [:]

    static func picks(mood: MoodPickMood, candidates: [MoodPickCandidate]) async throws -> [MoodPick] {
        if mood == .started {
            return candidates.filter { $0.source == .continueWatching }.prefix(12).map {
                MoodPick(item: $0.item, reason: $0.note ?? String(localized: "Pick up where you left off"))
            }
        }
        let pool = Array(candidates.prefix(40))
        guard !pool.isEmpty else { return [] }
        let cacheKey = mood.rawValue + ":" + pool.map(\.item.id).joined(separator: ",")
        if let cached = await MainActor.run(body: { cache[cacheKey] }) { return cached }

        let facts = await describe(pool)
        let schema = AISchema.object(name: "Picks", properties: [
            AISchemaProperty(
                name: "picks",
                description: "Up to 8 choices, best first",
                schema: .array(.object(name: "Pick", properties: [
                    AISchemaProperty(name: "index", description: "The number of the title in the list", schema: .integer),
                    AISchemaProperty(name: "reason", description: "At most 6 words on why it fits, from the facts given", schema: .string())
                ]))
            )
        ])
        let instructions = """
        You pick what to watch tonight from the viewer's own list. Choose only from the numbered list, \
        only titles that fit the mood, best first, at most 8. Each reason is at most 6 words and uses only the facts given \
        (genres, runtime, progress); no praise you can't back up.
        """
        let prompt = "Mood: \(mood.label) (\(mood.brief)).\n\nList:\n" + facts.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let data = try await AIService.generateJSON(AIStructuredRequest(instructions: instructions, prompt: prompt, schema: schema, quick: true))
        struct Answer: Decodable { struct Pick: Decodable { let index: Int; let reason: String }; let picks: [Pick] }
        let answer = try JSONDecoder().decode(Answer.self, from: data)
        var seen = Set<String>()
        let result: [MoodPick] = answer.picks.compactMap { pick in
            let i = pick.index - 1
            guard pool.indices.contains(i), seen.insert(pool[i].item.id).inserted else { return nil }
            return MoodPick(item: pool[i].item, reason: pick.reason.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        await MainActor.run { cache[cacheKey] = result }
        return result
    }

    /// One line per candidate: title, year, type, runtime, genres, where it's from.
    private static func describe(_ pool: [MoodPickCandidate]) async -> [String] {
        let tmdb = await FlixorCore.shared.tmdb
        var lines = Array(repeating: "", count: pool.count)
        await withTaskGroup(of: (Int, String).self) { group in
            for (index, candidate) in pool.enumerated() {
                group.addTask {
                    let item = candidate.item
                    let isShow = item.type == "show" || item.type == "episode"
                    let name = isShow ? (item.grandparentTitle ?? item.title) : item.title
                    var parts = [name + (item.year.map { " (\($0))" } ?? ""), isShow ? "TV show" : "movie"]
                    var runtime = item.duration.map { $0 / 60_000 }
                    var genres: [String] = []
                    let pieces = item.id.split(separator: ":")
                    if pieces.count == 3, pieces[0] == "tmdb", let id = Int(pieces[2]) {
                        if pieces[1] == "movie", let d = try? await tmdb.getMovieDetails(id: id) {
                            runtime = runtime ?? d.runtime
                            genres = d.genres.map(\.name)
                        } else if pieces[1] == "tv", let d = try? await tmdb.getTVDetails(id: id) {
                            runtime = runtime ?? d.episodeRunTime?.first
                            genres = d.genres.map(\.name)
                        }
                    }
                    if let runtime, runtime > 0 { parts.append(isShow ? "\(runtime)-min episodes" : "\(runtime) min") }
                    if !genres.isEmpty { parts.append(genres.prefix(3).joined(separator: ", ")) }
                    parts.append(candidate.source.rawValue + (candidate.note.map { " (\($0))" } ?? ""))
                    return (index, parts.joined(separator: " · "))
                }
            }
            for await (index, line) in group { lines[index] = line }
        }
        return lines
    }
}
