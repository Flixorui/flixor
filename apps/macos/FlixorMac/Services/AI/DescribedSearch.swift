//
//  DescribedSearch.swift
//  FlixorMac
//
//  Search by description: the AI turns "90s heist movies under 2 hours,
//  nothing too gory" into TMDB Discover filters. It never names titles; the
//  results are an ordinary Discover query, so everything shown is real.
//

import Foundation
import FlixorKit

/// A genre or keyword with its TMDB id.
struct DiscoverNamedId: Codable, Hashable {
    let id: Int
    let name: String
}

/// The filters a description added on top of the usual Discover ones.
struct DescribedFilters: Codable, Equatable {
    /// What the user typed.
    var prompt: String
    /// More genres that must all match, besides the main Genre chip.
    var extraGenres: [DiscoverNamedId] = []
    var excludedGenres: [DiscoverNamedId] = []
    /// Any of these keywords.
    var keywords: [DiscoverNamedId] = []
    var minRuntime: Int?
    var maxRuntime: Int?
    /// ISO 639-1.
    var originalLanguage: String?
    /// US certification ceiling (movies).
    var maxCertification: String?

    var isEmpty: Bool {
        extraGenres.isEmpty && excludedGenres.isEmpty && keywords.isEmpty && minRuntime == nil
            && maxRuntime == nil && originalLanguage == nil && maxCertification == nil
    }

    /// TMDB discover parameters beyond `TMDBDiscoverQuery`'s own fields.
    func parameters(for mediaType: DiscoverMediaType) -> [String: String] {
        var params: [String: String] = [:]
        if !excludedGenres.isEmpty { params["without_genres"] = excludedGenres.map { String($0.id) }.joined(separator: ",") }
        if !keywords.isEmpty { params["with_keywords"] = keywords.map { String($0.id) }.joined(separator: "|") }
        if let minRuntime { params["with_runtime.gte"] = String(minRuntime) }
        if let maxRuntime { params["with_runtime.lte"] = String(maxRuntime) }
        if let originalLanguage { params["with_original_language"] = originalLanguage }
        if mediaType == .movie, let maxCertification {
            params["certification_country"] = "US"
            params["certification.lte"] = maxCertification
        }
        return params
    }

    /// Chip label for the runtime limit.
    var runtimeLabel: String? {
        switch (minRuntime, maxRuntime) {
        case (nil, nil): return nil
        case let (min?, max?): return String(localized: "\(min)–\(max) min")
        case let (min?, nil): return String(localized: "Over \(min) min")
        case let (nil, max?): return String(localized: "Under \(max) min")
        }
    }

    var languageLabel: String? {
        guard let code = originalLanguage else { return nil }
        return Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()
    }
}

enum DescribedSearch {
    /// True for text that reads like a description rather than a title.
    /// Three or more words with a describing word ("movies", "like", "under"…),
    /// or five or more words. "Wonder Woman 1984" stays a title search.
    static func looksLikeDescription(_ text: String) -> Bool {
        let words = text.lowercased().split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init).filter { !$0.isEmpty }
        guard words.count >= 3 else { return false }
        if words.count >= 5 { return true }
        let describing: Set<String> = [
            "movie", "movies", "film", "films", "show", "shows", "series", "tv", "anime", "documentary", "documentaries",
            "like", "without", "under", "starring", "featuring",
            "thriller", "thrillers", "comedy", "comedies", "drama", "dramas", "horror", "romance", "romcom", "action",
            "animated", "cartoons", "kids", "family", "feel-good", "funny", "scary", "dark", "short", "long", "recent", "old",
        ]
        return words.contains { describing.contains($0) || $0.hasSuffix("s") && $0.count > 3 && $0.first?.isNumber == true }
    }

    private static let certifications = ["G", "PG", "PG-13", "R", "NC-17"]

    /// Filters for `description`. Throws when the AI is off, unavailable or fails.
    static func filters(for description: String) async throws -> DiscoverFilters {
        let tmdb = await FlixorCore.shared.tmdb
        async let movieGenres = tmdb.getGenres(mediaType: .movie)
        async let tvGenres = tmdb.getGenres(mediaType: .tv)
        let movies = (try? await movieGenres) ?? []
        let shows = (try? await tvGenres) ?? []
        let genreNames = Array(Set((movies + shows).map(\.name))).sorted()
        let year = Calendar(identifier: .gregorian).component(.year, from: Date())

        let schema = AISchema.object(name: "DiscoverFilters", properties: [
            AISchemaProperty(name: "mediaType", description: "movie, or tv for TV shows and series", schema: .string(choices: ["movie", "tv"])),
            AISchemaProperty(name: "genres", description: "Genres the titles must have, most important first. Usually one.", schema: .array(.string(choices: genreNames))),
            AISchemaProperty(name: "excludedGenres", description: "Genres to leave out", schema: .array(.string(choices: genreNames))),
            AISchemaProperty(name: "keywords", description: "Up to 3 short themes no genre covers, 1-2 words each, like heist, time loop, serial killer", schema: .array(.string())),
            AISchemaProperty(name: "yearFrom", description: "First release year", schema: .integer, isOptional: true),
            AISchemaProperty(name: "yearTo", description: "Last release year", schema: .integer, isOptional: true),
            AISchemaProperty(name: "minRuntime", description: "Shortest runtime in minutes", schema: .integer, isOptional: true),
            AISchemaProperty(name: "maxRuntime", description: "Longest runtime in minutes", schema: .integer, isOptional: true),
            AISchemaProperty(name: "originalLanguage", description: "Two-letter ISO 639-1 code of the original language, like ko or ml", schema: .string(), isOptional: true),
            AISchemaProperty(name: "maxCertification", description: "Highest US movie rating allowed", schema: .string(choices: certifications), isOptional: true),
            AISchemaProperty(name: "minimumRating", description: "Lowest TMDB rating out of 10, only when asked for good or acclaimed titles", schema: .number, isOptional: true),
            AISchemaProperty(name: "sort", description: "popular unless the viewer asks for best, newest or oldest", schema: .string(choices: ["popular", "topRated", "newest", "oldest"]))
        ])

        let instructions = """
        You turn a viewer's description of what they want to watch into filters for TMDB Discover. \
        Never name titles. Only use genres from the allowed list. \
        Only set a field when the description mentions it; otherwise leave it empty. \
        This year is \(year). A decade like "the eighties" covers its ten years; "recent" means the last 3 years. \
        Runtime limits are in minutes, only when the description talks about length. \
        Wanting nothing scary, gory or too violent means excluding the Horror genre. \
        Set maxCertification only when the viewer mentions kids, family or a rating. \
        Set originalLanguage only when a language or country is named. Use keywords only for themes no genre covers.
        """
        let data = try await AIService.generateJSON(AIStructuredRequest(instructions: instructions, prompt: description, schema: schema, quick: true))
        let plan = try JSONDecoder().decode(Plan.self, from: data)
        let filters = await resolve(plan, description: description, movieGenres: movies, tvGenres: shows)
        return await relaxedUntilNotEmpty(filters)
    }

    /// When the filters find nothing, drops the narrowest extras (keywords, then
    /// extra genres, then the runtime limit) until something matches.
    private static func relaxedUntilNotEmpty(_ start: DiscoverFilters) async -> DiscoverFilters {
        let tmdb = await FlixorCore.shared.tmdb
        func hasResults(_ f: DiscoverFilters) async -> Bool {
            guard let page = try? await tmdb.discover(f.query(page: 1)) else { return true } // offline: leave as is
            return !page.results.isEmpty
        }
        var filters = start
        if await hasResults(filters) { return filters }
        let steps: [(inout DescribedFilters) -> Void] = [
            { $0.keywords = [] },
            { $0.extraGenres = [] },
            { $0.minRuntime = nil; $0.maxRuntime = nil },
        ]
        for step in steps {
            guard var described = filters.described else { break }
            let before = described
            step(&described)
            guard described != before else { continue }
            filters.described = described
            if await hasResults(filters) { break }
        }
        return filters
    }

    private struct Plan: Decodable {
        var mediaType: String?
        var genres: [String]?
        var excludedGenres: [String]?
        var keywords: [String]?
        var yearFrom: Int?
        var yearTo: Int?
        var minRuntime: Int?
        var maxRuntime: Int?
        var originalLanguage: String?
        var maxCertification: String?
        var minimumRating: Double?
        var sort: String?
    }

    /// Plan → Discover filters, with genre and keyword names turned into TMDB ids.
    private static func resolve(_ plan: Plan, description: String, movieGenres: [FlixorKit.TMDBGenre], tvGenres: [FlixorKit.TMDBGenre]) async -> DiscoverFilters {
        var filters = DiscoverFilters()
        filters.mediaType = plan.mediaType == "tv" ? .tv : .movie
        let genres = filters.mediaType == .tv ? tvGenres : movieGenres
        func ids(_ names: [String]?) -> [DiscoverNamedId] {
            (names ?? []).compactMap { name in
                genres.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
                    .map { DiscoverNamedId(id: $0.id, name: $0.name) }
            }
        }
        var wanted = ids(plan.genres)
        let excluded = ids(plan.excludedGenres).filter { e in !wanted.contains { $0.id == e.id } }
        if let main = wanted.first {
            filters.genreId = main.id
            filters.genreName = main.name
            wanted.removeFirst()
        }

        // Small models over-reach (and copy examples): keep a field only when the
        // description talks about it.
        let lower = description.lowercased()
        func mentions(_ words: [String]) -> Bool { words.contains { lower.contains($0) } }
        let asksYears = lower.contains(where: \.isNumber)
            || mentions(["recent", "new ", "newer", "latest", "old ", "older", "classic", "vintage", "decade", "eighties", "nineties", "seventies", "sixties", "fifties", "this year", "last year", "century"])
        let asksLength = mentions(["hour", "min", "short", "long", "quick", "epic", "runtime", "length"])
        let asksLong = mentions(["long", "over ", "at least", "more than", "epic", "longer"])
        let asksRating = mentions(["kid", "child", "family", "pg", "rated", "teen", "toddler", "all ages"])

        let currentYear = Calendar(identifier: .gregorian).component(.year, from: Date())
        func validYear(_ y: Int?) -> Int? { y.flatMap { (1900...currentYear + 2).contains($0) ? $0 : nil } }
        filters.yearFrom = asksYears ? validYear(plan.yearFrom) : nil
        filters.yearTo = asksYears ? validYear(plan.yearTo) : nil
        filters.minimumRating = plan.minimumRating.flatMap { (1...9.5).contains($0) ? $0.rounded(.down) : nil }
        filters.sort = DiscoverSortOption(rawValue: plan.sort ?? "") ?? .popular

        var described = DescribedFilters(prompt: description)
        described.extraGenres = wanted
        described.excludedGenres = excluded
        // Keywords that only repeat a genre or a language add nothing but risk.
        let genreNames = Set(genres.map { $0.name.lowercased() })
        let keywordNames = (plan.keywords ?? []).filter { kw in
            let k = kw.lowercased()
            return !genreNames.contains(k) && languageNamed(in: k) == nil
        }
        described.keywords = await keywordIds(Array(keywordNames.prefix(3)))
        described.minRuntime = asksLength && asksLong ? plan.minRuntime.flatMap { (1...600).contains($0) ? $0 : nil } : nil
        described.maxRuntime = asksLength ? plan.maxRuntime.flatMap { (1...600).contains($0) ? $0 : nil } : nil
        // A named language or nationality decides; the model's guess is used only
        // when the text says "language".
        if let named = languageNamed(in: lower) {
            described.originalLanguage = named
        } else if lower.contains("language"), let code = plan.originalLanguage?.lowercased(), code.count == 2, code.allSatisfy(\.isLetter) {
            described.originalLanguage = code
        }
        if asksRating, filters.mediaType == .movie, let cert = plan.maxCertification, certifications.contains(cert) {
            described.maxCertification = cert
        }
        filters.described = described
        filters.normalize()
        return filters
    }

    /// ISO 639-1 code for a language or nationality named in the text.
    private static func languageNamed(in text: String) -> String? {
        let names: [(String, String)] = [
            ("korean", "ko"), ("k-drama", "ko"), ("japanese", "ja"), ("anime", "ja"), ("hindi", "hi"), ("bollywood", "hi"),
            ("malayalam", "ml"), ("tamil", "ta"), ("telugu", "te"), ("kannada", "kn"), ("bengali", "bn"), ("marathi", "mr"),
            ("punjabi", "pa"), ("french", "fr"), ("spanish", "es"), ("mexican", "es"), ("german", "de"), ("italian", "it"),
            ("portuguese", "pt"), ("brazilian", "pt"), ("mandarin", "zh"), ("chinese", "zh"), ("cantonese", "cn"),
            ("hong kong", "cn"), ("thai", "th"), ("turkish", "tr"), ("danish", "da"), ("swedish", "sv"), ("norwegian", "no"),
            ("finnish", "fi"), ("icelandic", "is"), ("dutch", "nl"), ("polish", "pl"), ("russian", "ru"), ("arabic", "ar"),
            ("persian", "fa"), ("iranian", "fa"), ("hebrew", "he"), ("israeli", "he"), ("indonesian", "id"), ("filipino", "tl"),
            ("vietnamese", "vi"), ("greek", "el"), ("czech", "cs"), ("hungarian", "hu"), ("romanian", "ro"), ("ukrainian", "uk"),
        ]
        return names.first { text.contains($0.0) }?.1
    }

    /// TMDB keyword ids, exact name matches only ("slow-burn" may match "slow burn").
    private static func keywordIds(_ names: [String]) async -> [DiscoverNamedId] {
        let tmdb = await FlixorCore.shared.tmdb
        var result: [DiscoverNamedId] = []
        for name in names where !name.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let matches = try? await tmdb.searchKeywords(name), !matches.isEmpty else { continue }
            func norm(_ s: String) -> String { s.lowercased().replacingOccurrences(of: "-", with: " ") }
            guard let pick = matches.first(where: { norm($0.name) == norm(name) }) else { continue }
            if !result.contains(where: { $0.id == pick.id }) {
                result.append(DiscoverNamedId(id: pick.id, name: pick.name))
            }
        }
        return result
    }
}
