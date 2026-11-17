//
//  AskFlixor.swift
//  FlixorMac
//
//  Ask Flixor: a chat that answers from the user's own data. The model can
//  call tools (TMDB search and details, the Plex library, the watchlist, watch
//  history, Upcoming) and must not state facts about titles without them.
//  Every title a tool returned and the answer names becomes a card.
//

import Foundation
import FlixorKit

/// A title a tool returned, for cards under the answer.
struct AskTitleCard: Identifiable, Hashable {
    let item: MediaItem
    let posterURL: URL?
    let subtitle: String
    var id: String { item.id }

    static func == (a: Self, b: Self) -> Bool { a.item.id == b.item.id }
    func hash(into hasher: inout Hasher) { hasher.combine(item.id) }
}

struct AskMessage: Identifiable, Equatable {
    let id = UUID()
    let role: AIChatTurn.Role
    let text: String
    var cards: [AskTitleCard] = []
    /// "Used: your Plex library · TMDB"
    var used: [String] = []
}

@MainActor
final class AskFlixorModel: ObservableObject {
    @Published private(set) var messages: [AskMessage] = []
    @Published private(set) var isSending = false
    @Published var error: String?

    static let suggestions = [
        String(localized: "Something light for tonight, about 90 minutes"),
        String(localized: "What's new from my shows?"),
        String(localized: "What should I watch next from my watchlist?"),
    ]

    func clear() {
        messages = []
        error = nil
    }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        messages.append(AskMessage(role: .user, text: trimmed))
        isSending = true
        error = nil
        let history = messages.suffix(12).map { AIChatTurn(role: $0.role, text: $0.text) }
        Task { @MainActor in
            defer { isSending = false }
            let toolbox = AskToolbox()
            do {
                let reply = try await AIService.chat(instructions: Self.instructions(), history: history, tools: toolbox.tools())
                let cards = await toolbox.cards(mentionedIn: reply)
                let used = await toolbox.usedSources()
                messages.append(AskMessage(role: .assistant, text: reply, cards: cards, used: used))
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private static func instructions() -> String {
        let today = DateFormatter.localizedString(from: Date(), dateStyle: .full, timeStyle: .none)
        return """
        You are the assistant inside Flixor, a movie and TV app. Today is \(today). \
        Answer the viewer's questions about movies, shows and their own library. \
        Use the tools to look things up: never state a title's year, runtime, cast, rating or availability unless a tool returned it. \
        When recommending, prefer titles from the viewer's watchlist, library and history, and skip ones they have watched. \
        Write the exact title as the tool returned it. Keep answers short: one to three sentences, then up to five titles. \
        Don't use markdown headings or tables.
        """
    }
}

// MARK: - Tools

/// Tools for one reply; remembers the titles they returned.
actor AskToolbox {
    private var found: [String: AskTitleCard] = [:]
    private var order: [String] = []
    private var used: [String] = []

    nonisolated func tools() -> [AITool] {
        [
            AITool(
                name: "search_titles",
                description: "Search TMDB for movies and TV shows by title, person or topic. Returns refs to use with title_details.",
                parameters: .object(name: "SearchTitles", properties: [
                    AISchemaProperty(name: "query", description: "What to search for", schema: .string()),
                    AISchemaProperty(name: "type", description: "movie, tv or any", schema: .string(choices: ["movie", "tv", "any"]))
                ]),
                run: { [self] data in await self.searchTitles(data) }
            ),
            AITool(
                name: "title_details",
                description: "Details of one title by ref: runtime, genres, overview, director, main cast, and whether it's in the viewer's Plex library.",
                parameters: .object(name: "TitleDetails", properties: [
                    AISchemaProperty(name: "ref", description: "A ref from another tool, like tmdb:movie:603", schema: .string())
                ]),
                run: { [self] data in await self.titleDetails(data) }
            ),
            AITool(
                name: "search_my_library",
                description: "Search the viewer's own Plex library by title. Returns what they own and its video quality.",
                parameters: .object(name: "SearchLibrary", properties: [
                    AISchemaProperty(name: "query", description: "Title to look for", schema: .string())
                ]),
                run: { [self] data in await self.searchLibrary(data) }
            ),
            AITool(
                name: "my_watchlist",
                description: "The viewer's watchlist: titles they saved to watch later.",
                parameters: .object(name: "Watchlist", properties: []),
                run: { [self] _ in await self.watchlist() }
            ),
            AITool(
                name: "my_recent_history",
                description: "What the viewer watched recently, newest first.",
                parameters: .object(name: "History", properties: []),
                run: { [self] _ in await self.history() }
            ),
            AITool(
                name: "upcoming_episodes",
                description: "New episodes of the viewer's shows that they haven't watched, and episodes airing in the next 30 days.",
                parameters: .object(name: "Upcoming", properties: []),
                run: { [self] _ in await self.upcoming() }
            ),
        ]
    }

    // MARK: Results for the panel

    func cards(mentionedIn reply: String) -> [AskTitleCard] {
        let text = reply.lowercased()
        let mentioned = order.compactMap { id -> (AskTitleCard, String.Index)? in
            guard let card = found[id] else { return nil }
            let title = (card.item.type == "episode" ? (card.item.grandparentTitle ?? card.item.title) : card.item.title).lowercased()
            guard title.count >= 2, let range = text.range(of: title) else { return nil }
            return (card, range.lowerBound)
        }
        var seenTitles = Set<String>()
        return mentioned
            .sorted { $0.1 < $1.1 }
            .map(\.0)
            .filter { seenTitles.insert($0.item.title.lowercased()).inserted }
            .prefix(6)
            .map { $0 }
    }

    func usedSources() -> [String] { used }

    // MARK: Tool bodies

    private func note(_ source: String) {
        if !used.contains(source) { used.append(source) }
    }

    private func remember(_ card: AskTitleCard) {
        if found[card.id] == nil { order.append(card.id) }
        found[card.id] = card
    }

    private static func args(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func json(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }

    private static func clip(_ text: String?, _ limit: Int) -> String {
        guard let text else { return "" }
        return text.count <= limit ? text : String(text.prefix(limit)) + "…"
    }

    private func tmdbCard(_ m: TMDBMedia, type: String) -> AskTitleCard {
        let isMovie = type == "movie"
        let title = m.title ?? m.name ?? ""
        let year = (m.releaseDate ?? m.firstAirDate).flatMap { Int($0.prefix(4)) }
        let item = MediaItem(
            id: "tmdb:\(isMovie ? "movie" : "tv"):\(m.id)", title: title, type: isMovie ? "movie" : "show",
            thumb: TMDBImageURL.url(m.posterPath, size: .w500)?.absoluteString,
            art: TMDBImageURL.url(m.backdropPath, size: .w780)?.absoluteString,
            year: year, rating: m.voteAverage, duration: nil, viewOffset: nil, summary: m.overview,
            grandparentTitle: nil, grandparentThumb: nil, grandparentArt: nil, grandparentRatingKey: nil,
            parentIndex: nil, index: nil, parentRatingKey: nil, parentTitle: nil, leafCount: nil, viewedLeafCount: nil
        )
        return AskTitleCard(
            item: item,
            posterURL: TMDBImageURL.url(m.posterPath, size: .w185),
            subtitle: [year.map(String.init), isMovie ? String(localized: "Movie") : String(localized: "TV show")].compactMap { $0 }.joined(separator: " · ")
        )
    }

    private func searchTitles(_ data: Data) async -> String {
        note("TMDB")
        let a = Self.args(data)
        let query = a["query"] as? String ?? ""
        let type = a["type"] as? String ?? "any"
        let tmdb = await FlixorCore.shared.tmdb
        guard let page = try? await tmdb.searchMulti(query: query) else { return "Search failed." }
        let results = page.results
            .filter { ($0.mediaType == "movie" || $0.mediaType == "tv") && (type == "any" || $0.mediaType == type) }
            .prefix(6)
        return Self.json(results.map { m -> [String: Any] in
            let card = tmdbCard(m, type: m.mediaType ?? "movie")
            remember(card)
            return [
                "ref": card.id, "title": card.item.title, "year": card.item.year ?? 0,
                "type": m.mediaType ?? "", "rating": ((m.voteAverage ?? 0) * 10).rounded() / 10,
                "overview": Self.clip(m.overview, 160)
            ]
        })
    }

    private func titleDetails(_ data: Data) async -> String {
        note("TMDB")
        let ref = Self.args(data)["ref"] as? String ?? ""
        let parts = ref.split(separator: ":")
        guard parts.count == 3, parts[0] == "tmdb", let id = Int(parts[2]) else {
            return "Use a tmdb:movie:ID or tmdb:tv:ID ref from search_titles."
        }
        let tmdb = await FlixorCore.shared.tmdb
        var info: [String: Any] = ["ref": ref]
        var title = ""
        var year: Int?
        if parts[1] == "movie", let d = try? await tmdb.getMovieDetails(id: id) {
            title = d.title ?? ""
            year = d.releaseDate.flatMap { Int($0.prefix(4)) }
            info["title"] = title
            info["year"] = year ?? 0
            info["runtime_minutes"] = d.runtime ?? 0
            info["genres"] = d.genres.map(\.name)
            info["overview"] = Self.clip(d.overview, 400)
            info["rating"] = ((d.voteAverage ?? 0) * 10).rounded() / 10
            if let credits = try? await tmdb.getMovieCredits(id: id) {
                info["director"] = credits.crew.filter { $0.job == "Director" }.map(\.name)
                info["cast"] = credits.cast.prefix(5).map(\.name)
            }
        } else if parts[1] == "tv", let d = try? await tmdb.getTVDetails(id: id) {
            title = d.name ?? ""
            year = d.firstAirDate.flatMap { Int($0.prefix(4)) }
            info["title"] = title
            info["first_aired"] = d.firstAirDate ?? ""
            info["seasons"] = d.numberOfSeasons ?? 0
            info["episode_minutes"] = d.episodeRunTime?.first ?? 0
            info["status"] = d.status ?? ""
            info["genres"] = d.genres.map(\.name)
            info["overview"] = Self.clip(d.overview, 400)
            info["rating"] = ((d.voteAverage ?? 0) * 10).rounded() / 10
            if let next = d.nextEpisodeToAir, let s = next.seasonNumber, let e = next.episodeNumber {
                info["next_episode"] = "S\(s) E\(e) on \(next.airDate ?? "?")"
            }
            if let credits = try? await tmdb.getTVCredits(id: id) {
                info["cast"] = credits.cast.prefix(5).map(\.name)
            }
        } else {
            return "Not found."
        }
        if let owned = await plexMatches(title).first(where: { year == nil || $0.year == nil || abs(($0.year ?? 0) - (year ?? 0)) <= 1 }) {
            info["in_plex_library"] = true
            if let quality = owned.quality { info["plex_quality"] = quality }
        } else {
            info["in_plex_library"] = false
        }
        return Self.json(info)
    }

    private struct PlexHit: Decodable {
        struct MediaInfo: Decodable { let videoResolution: String?; let height: Int? }
        let ratingKey: String
        let title: String?
        let year: Int?
        let type: String?
        let thumb: String?
        let Media: [MediaInfo]?
        var quality: String? {
            guard let media = Media?.first else { return nil }
            if let r = media.videoResolution { return r.lowercased() == "4k" ? "4K" : "\(r)p" }
            return media.height.map { $0 >= 2000 ? "4K" : "\($0)p" }
        }
    }

    private func plexMatches(_ query: String) async -> [PlexHit] {
        guard !query.isEmpty else { return [] }
        var hits: [PlexHit] = []
        for type in ["1", "2"] {
            let result: [PlexHit]? = try? await APIClient.shared.get(
                "/api/plex/search",
                queryItems: [URLQueryItem(name: "query", value: query), URLQueryItem(name: "type", value: type)]
            )
            hits += result ?? []
        }
        return hits
    }

    private func searchLibrary(_ data: Data) async -> String {
        note(String(localized: "your Plex library"))
        let query = Self.args(data)["query"] as? String ?? ""
        let hits = Array(await plexMatches(query).prefix(8))
        guard !hits.isEmpty else { return "Nothing in the Plex library matches \"\(query)\" (or no Plex library is connected)." }
        let posters = await MainActor.run {
            hits.map { ImageService.shared.plexImageURL(path: $0.thumb, width: 120, height: 180) }
        }
        return Self.json(hits.enumerated().map { index, hit -> [String: Any] in
            let isMovie = hit.type == "movie"
            let item = MediaItem(
                id: "plex:\(hit.ratingKey)", title: hit.title ?? "", type: isMovie ? "movie" : "show", thumb: hit.thumb, art: nil,
                year: hit.year, rating: nil, duration: nil, viewOffset: nil, summary: nil,
                grandparentTitle: nil, grandparentThumb: nil, grandparentArt: nil, grandparentRatingKey: nil,
                parentIndex: nil, index: nil, parentRatingKey: nil, parentTitle: nil, leafCount: nil, viewedLeafCount: nil
            )
            remember(AskTitleCard(
                item: item,
                posterURL: posters[index],
                subtitle: [hit.year.map(String.init), String(localized: "On your Plex"), hit.quality].compactMap { $0 }.joined(separator: " · ")
            ))
            return ["ref": "plex:\(hit.ratingKey)", "title": hit.title ?? "", "year": hit.year ?? 0,
                    "type": isMovie ? "movie" : "tv", "quality": hit.quality ?? "unknown"]
        })
    }

    private func watchlist() async -> String {
        note(String(localized: "your watchlist"))
        var rows: [[String: Any]] = []
        let trakt = await FlixorCore.shared.trakt
        if await trakt.isAuthenticated, let items = try? await trakt.getWatchlist() {
            for entry in items.prefix(30) {
                if let movie = entry.movie, let id = movie.ids.tmdb {
                    rows.append(["ref": "tmdb:movie:\(id)", "title": movie.title, "year": movie.year ?? 0, "type": "movie"])
                    await rememberTMDB(id: id, type: "movie")
                } else if let show = entry.show, let id = show.ids.tmdb {
                    rows.append(["ref": "tmdb:tv:\(id)", "title": show.title, "year": show.year ?? 0, "type": "tv"])
                    await rememberTMDB(id: id, type: "tv")
                }
            }
        }
        for entry in await LocalLibraryStore.shared.watchlist().prefix(30) {
            guard let id = entry.tmdbId, !rows.contains(where: { ($0["ref"] as? String)?.hasSuffix(":\(id)") == true }) else { continue }
            let type = entry.type == "movie" ? "movie" : "tv"
            rows.append(["ref": "tmdb:\(type):\(id)", "title": entry.title, "year": entry.year ?? 0, "type": type])
            await rememberTMDB(id: id, type: type)
        }
        return rows.isEmpty ? "The watchlist is empty." : Self.json(rows)
    }

    /// Card for a TMDB id that came from Trakt or the local store.
    private func rememberTMDB(id: Int, type: String) async {
        let ref = "tmdb:\(type):\(id)"
        guard found[ref] == nil else { return }
        let tmdb = await FlixorCore.shared.tmdb
        if type == "movie", let d = try? await tmdb.getMovieDetails(id: id) {
            let media = TMDBMediaShim(id: d.id, title: d.title, name: nil, posterPath: d.posterPath, backdropPath: d.backdropPath,
                                      date: d.releaseDate, vote: d.voteAverage, overview: d.overview)
            remember(tmdbCard(media.media, type: "movie"))
        } else if type == "tv", let d = try? await tmdb.getTVDetails(id: id) {
            let media = TMDBMediaShim(id: d.id, title: nil, name: d.name, posterPath: d.posterPath, backdropPath: d.backdropPath,
                                      date: d.firstAirDate, vote: d.voteAverage, overview: d.overview)
            remember(tmdbCard(media.media, type: "tv"))
        }
    }

    private func history() async -> String {
        note(String(localized: "your watch history"))
        var rows: [[String: Any]] = []
        let trakt = await FlixorCore.shared.trakt
        if await trakt.isAuthenticated, let items = try? await trakt.getHistory(page: 1, limit: 25) {
            for item in items {
                if let movie = item.movie {
                    rows.append(["title": movie.title, "year": movie.year ?? 0, "type": "movie", "watched": String(item.watchedAt.prefix(10))])
                } else if let show = item.show, let ep = item.episode {
                    rows.append(["title": show.title, "type": "tv", "episode": "S\(ep.season) E\(ep.number)", "watched": String(item.watchedAt.prefix(10))])
                }
            }
        }
        if rows.isEmpty {
            for entry in await LocalLibraryStore.shared.watchHistory().prefix(25) {
                var row: [String: Any] = ["title": entry.title, "type": entry.mediaType == .movie ? "movie" : "tv"]
                if let s = entry.seasonNumber, let e = entry.episodeNumber { row["episode"] = "S\(s) E\(e)" }
                rows.append(row)
            }
        }
        return rows.isEmpty ? "No watch history yet." : Self.json(rows)
    }

    private func upcoming() async -> String {
        note(String(localized: "Upcoming"))
        let list = await MainActor.run { () -> [UpcomingEpisode] in
            UpcomingEpisodesStore.shared.refreshIfStale()
            return UpcomingEpisodesStore.shared.episodes
        }
        guard !list.isEmpty else { return "No new or upcoming episodes in the next 30 days." }
        return Self.json(list.prefix(15).map { ep -> [String: Any] in
            [
                "show": ep.showTitle, "ref": "tmdb:tv:\(ep.showTmdbId)", "episode": ep.episodeCode,
                "title": ep.title ?? "",
                "airs": ep.hasTime
                    ? DateFormatter.localizedString(from: ep.airDate, dateStyle: .medium, timeStyle: .short) + " (viewer's local time)"
                    : DateFormatter.localizedString(from: ep.airDate, dateStyle: .medium, timeStyle: .none),
                "new_unwatched": ep.isNewUnwatched
            ]
        })
    }
}

/// Builds a TMDBMedia from details, for one card code path.
private struct TMDBMediaShim {
    let id: Int
    let title: String?
    let name: String?
    let posterPath: String?
    let backdropPath: String?
    let date: String?
    let vote: Double?
    let overview: String?

    var media: TMDBMedia {
        var dict: [String: Any] = ["id": id]
        if let title { dict["title"] = title }
        if let name { dict["name"] = name }
        if let posterPath { dict["poster_path"] = posterPath }
        if let backdropPath { dict["backdrop_path"] = backdropPath }
        if let date { dict["release_date"] = date; dict["first_air_date"] = date }
        if let vote { dict["vote_average"] = vote }
        if let overview { dict["overview"] = overview }
        let data = (try? JSONSerialization.data(withJSONObject: dict)) ?? Data("{\"id\":\(id)}".utf8)
        return (try? JSONDecoder().decode(TMDBMedia.self, from: data))
            ?? (try! JSONDecoder().decode(TMDBMedia.self, from: Data("{\"id\":\(id)}".utf8)))
    }
}
