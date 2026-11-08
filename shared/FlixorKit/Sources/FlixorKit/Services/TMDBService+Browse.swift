//
//  TMDBService+Browse.swift
//  FlixorKit
//
//  Metadata endpoints for browsing: movie collections, people, companies and
//  networks, filtered discover, genre lists and person search.
//
//  All calls go through `TMDBService.get`, so they share the API key, language,
//  cache and error handling with the rest of the service. Every call is async and
//  cancellable (URLSession honours task cancellation).
//

import Foundation

// MARK: - Endpoints

extension TMDBService {

    // MARK: Collections

    /// The collection a movie belongs to (`belongs_to_collection`), or nil when the
    /// movie isn't part of one.
    public func getMovieCollectionRef(movieId: Int) async throws -> TMDBCollectionRef? {
        let response: TMDBMovieCollectionLookup = try await get(
            path: "/movie/\(movieId)",
            ttl: CacheTTL.static,
            cacheTag: "collection-ref"
        )
        return response.belongsToCollection
    }

    /// Collection details with its parts ordered by release date (undated parts last).
    public func getCollection(id: Int) async throws -> TMDBCollectionDetails {
        let details: TMDBCollectionDetails = try await get(
            path: "/collection/\(id)",
            ttl: CacheTTL.static
        )
        return details.sortedByRelease()
    }

    /// Convenience: the collection for a movie, with ordered parts. Nil when the movie
    /// isn't in a collection.
    public func getCollection(forMovieId movieId: Int) async throws -> TMDBCollectionDetails? {
        guard let ref = try await getMovieCollectionRef(movieId: movieId) else { return nil }
        return try await getCollection(id: ref.id)
    }

    // MARK: People

    /// Person details plus combined (movie + TV) credits and external ids, in one request.
    public func getPersonProfile(id: Int) async throws -> TMDBPersonProfile {
        return try await get(
            path: "/person/\(id)",
            params: ["append_to_response": "combined_credits,external_ids"],
            ttl: CacheTTL.trending
        )
    }

    /// Search people by name.
    public func searchPeople(query: String, page: Int = 1) async throws -> TMDBPeopleSearchResponse {
        return try await get(
            path: "/search/person",
            params: ["query": query, "page": String(page)],
            ttl: CacheTTL.short
        )
    }

    // MARK: Companies & Networks

    /// Production company details (logo, headquarters, parent company).
    public func getCompany(id: Int) async throws -> TMDBCompanyDetails {
        return try await get(path: "/company/\(id)", ttl: CacheTTL.static)
    }

    /// TV network details (logo, headquarters). `description`/`parentCompany` are nil.
    public func getNetwork(id: Int) async throws -> TMDBCompanyDetails {
        return try await get(path: "/network/\(id)", ttl: CacheTTL.static)
    }

    /// One page of titles from a company. `mediaType` picks movies or shows.
    public func discoverByCompany(
        companyId: Int,
        mediaType: TMDBDiscoverMediaType,
        sort: TMDBDiscoverSort = .popularity,
        page: Int = 1
    ) async throws -> TMDBResultsResponse {
        var query = TMDBDiscoverQuery(mediaType: mediaType, sort: sort, page: page)
        query.companyIds = [companyId]
        return try await discover(query)
    }

    /// One page of shows from a TV network.
    public func discoverByNetwork(
        networkId: Int,
        sort: TMDBDiscoverSort = .popularity,
        page: Int = 1
    ) async throws -> TMDBResultsResponse {
        var query = TMDBDiscoverQuery(mediaType: .tv, sort: sort, page: page)
        query.networkIds = [networkId]
        return try await discover(query)
    }

    // MARK: Discover & Genres

    /// Filtered discover (media type, genres, sort, year range, company/network, page).
    /// Results carry no `media_type`; use `query.mediaType`.
    public func discover(_ query: TMDBDiscoverQuery) async throws -> TMDBResultsResponse {
        return try await get(
            path: "/discover/\(query.mediaType.rawValue)",
            params: query.parameters(),
            ttl: CacheTTL.trending
        )
    }

    /// Official genre list for movies or TV (localized to the service language).
    public func getGenres(mediaType: TMDBDiscoverMediaType) async throws -> [TMDBGenre] {
        let response: TMDBGenreListResponse = try await get(
            path: "/genre/\(mediaType.rawValue)/list",
            ttl: CacheTTL.static
        )
        return response.genres
    }
}

// MARK: - Discover Query

public enum TMDBDiscoverMediaType: String, Codable, CaseIterable, Sendable {
    case movie
    case tv
}

/// Sort orders that make sense for both movies and TV. Translated to the right
/// TMDB field per media type (e.g. release date vs first air date).
public enum TMDBDiscoverSort: String, Codable, CaseIterable, Sendable {
    case popularity
    case rating
    case newest
    case oldest
    case voteCount
    /// Movies only; falls back to popularity for TV.
    case revenue

    public func parameter(for mediaType: TMDBDiscoverMediaType) -> String {
        let dateField = mediaType == .movie ? "primary_release_date" : "first_air_date"
        switch self {
        case .popularity: return "popularity.desc"
        case .rating: return "vote_average.desc"
        case .newest: return "\(dateField).desc"
        case .oldest: return "\(dateField).asc"
        case .voteCount: return "vote_count.desc"
        case .revenue: return mediaType == .movie ? "revenue.desc" : "popularity.desc"
        }
    }
}

public struct TMDBDiscoverQuery: Hashable, Sendable {
    public var mediaType: TMDBDiscoverMediaType
    public var sort: TMDBDiscoverSort
    public var page: Int
    /// Matches titles with ALL of these genres (TMDB `with_genres`, comma = AND).
    public var genreIds: [Int]
    /// Inclusive year range on release date (movies) or first air date (TV).
    public var yearFrom: Int?
    public var yearTo: Int?
    /// Production companies (OR).
    public var companyIds: [Int]
    /// TV networks (OR). Ignored for movies.
    public var networkIds: [Int]
    /// ISO 639-1 original language, e.g. "ja".
    public var originalLanguage: String?
    /// Minimum vote count. Defaults to 200 for `.rating` so obscure 10/10 titles
    /// don't dominate; set explicitly to override.
    public var minimumVoteCount: Int?
    /// Minimum average rating (0-10).
    public var minimumRating: Double?
    /// Raw TMDB `sort_by` value that replaces `sort` (e.g. "title.asc" / "name.asc").
    public var sortByOverride: String? = nil

    public init(
        mediaType: TMDBDiscoverMediaType,
        sort: TMDBDiscoverSort = .popularity,
        page: Int = 1,
        genreIds: [Int] = [],
        yearFrom: Int? = nil,
        yearTo: Int? = nil,
        companyIds: [Int] = [],
        networkIds: [Int] = [],
        originalLanguage: String? = nil,
        minimumVoteCount: Int? = nil,
        minimumRating: Double? = nil
    ) {
        self.mediaType = mediaType
        self.sort = sort
        self.page = page
        self.genreIds = genreIds
        self.yearFrom = yearFrom
        self.yearTo = yearTo
        self.companyIds = companyIds
        self.networkIds = networkIds
        self.originalLanguage = originalLanguage
        self.minimumVoteCount = minimumVoteCount
        self.minimumRating = minimumRating
    }

    /// TMDB query parameters for this query.
    public func parameters() -> [String: String] {
        var params: [String: String] = [
            "sort_by": sortByOverride ?? sort.parameter(for: mediaType),
            "page": String(max(1, min(page, 500))), // TMDB caps discover at page 500
            "include_adult": "false",
        ]
        if !genreIds.isEmpty {
            params["with_genres"] = genreIds.map(String.init).joined(separator: ",")
        }
        let dateField = mediaType == .movie ? "primary_release_date" : "first_air_date"
        if let yearFrom {
            params["\(dateField).gte"] = "\(yearFrom)-01-01"
        }
        if let yearTo {
            params["\(dateField).lte"] = "\(yearTo)-12-31"
        }
        if !companyIds.isEmpty {
            params["with_companies"] = companyIds.map(String.init).joined(separator: "|")
        }
        if mediaType == .tv, !networkIds.isEmpty {
            params["with_networks"] = networkIds.map(String.init).joined(separator: "|")
        }
        if let originalLanguage, !originalLanguage.isEmpty {
            params["with_original_language"] = originalLanguage
        }
        if let votes = minimumVoteCount ?? (sort == .rating ? 200 : nil) {
            params["vote_count.gte"] = String(votes)
        }
        if let minimumRating {
            params["vote_average.gte"] = String(minimumRating)
        }
        // Sorting by date without an upper bound surfaces unreleased placeholders.
        if (sort == .newest), yearTo == nil {
            params["\(dateField).lte"] = Self.todayString()
        }
        return params
    }

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

// MARK: - Collection Models

/// `belongs_to_collection` on a movie.
public struct TMDBCollectionRef: Codable, Hashable, Identifiable {
    public let id: Int
    public let name: String?
    public let posterPath: String?
    public let backdropPath: String?

    private enum CodingKeys: String, CodingKey {
        case id, name
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
    }
}

struct TMDBMovieCollectionLookup: Codable {
    let belongsToCollection: TMDBCollectionRef?

    private enum CodingKeys: String, CodingKey {
        case belongsToCollection = "belongs_to_collection"
    }
}

public struct TMDBCollectionDetails: Codable, Identifiable {
    public let id: Int
    public let name: String?
    public let overview: String?
    public let posterPath: String?
    public let backdropPath: String?
    /// Movies in the collection. `getCollection` returns them in release order.
    public let parts: [TMDBMedia]

    private enum CodingKeys: String, CodingKey {
        case id, name, overview, parts
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
    }

    public init(id: Int, name: String?, overview: String?, posterPath: String?, backdropPath: String?, parts: [TMDBMedia]) {
        self.id = id
        self.name = name
        self.overview = overview
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.parts = parts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        overview = try container.decodeIfPresent(String.self, forKey: .overview)
        posterPath = try container.decodeIfPresent(String.self, forKey: .posterPath)
        backdropPath = try container.decodeIfPresent(String.self, forKey: .backdropPath)
        parts = try container.decodeIfPresent([TMDBMedia].self, forKey: .parts) ?? []
    }

    /// Parts ordered by release date ascending; undated (unannounced) parts go last.
    public func sortedByRelease() -> TMDBCollectionDetails {
        let sorted = parts.enumerated().sorted { lhs, rhs in
            let l = lhs.element.releaseDate.flatMap { $0.isEmpty ? nil : $0 }
            let r = rhs.element.releaseDate.flatMap { $0.isEmpty ? nil : $0 }
            switch (l, r) {
            case let (l?, r?): return l == r ? lhs.offset < rhs.offset : l < r
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return lhs.offset < rhs.offset
            }
        }.map(\.element)
        return TMDBCollectionDetails(
            id: id, name: name, overview: overview,
            posterPath: posterPath, backdropPath: backdropPath, parts: sorted
        )
    }
}

// MARK: - Person Models

/// Person details with combined credits (`/person/{id}?append_to_response=combined_credits,external_ids`).
public struct TMDBPersonProfile: Codable, Identifiable {
    public let id: Int
    public let name: String
    public let biography: String?
    public let birthday: String?
    public let deathday: String?
    public let placeOfBirth: String?
    public let profilePath: String?
    public let knownForDepartment: String?
    public let alsoKnownAs: [String]?
    public let homepage: String?
    public let popularity: Double?
    public let imdbId: String?
    public let combinedCredits: TMDBPersonCombinedCredits?
    public let externalIds: TMDBPersonExternalIds?

    private enum CodingKeys: String, CodingKey {
        case id, name, biography, birthday, deathday, homepage, popularity
        case placeOfBirth = "place_of_birth"
        case profilePath = "profile_path"
        case knownForDepartment = "known_for_department"
        case alsoKnownAs = "also_known_as"
        case imdbId = "imdb_id"
        case combinedCredits = "combined_credits"
        case externalIds = "external_ids"
    }

    /// Acting credits, de-duplicated per title (TV roles repeat per character),
    /// sorted by `order`.
    public func castCredits(sortedBy order: TMDBPersonCreditOrder = .popularity) -> [TMDBPersonCredit] {
        TMDBPersonCredit.dedupe(combinedCredits?.cast ?? []).sorted(by: order.areInIncreasingOrder)
    }

    /// Crew credits, de-duplicated per title (jobs merged into `job`), sorted by `order`.
    public func crewCredits(sortedBy order: TMDBPersonCreditOrder = .popularity) -> [TMDBPersonCredit] {
        TMDBPersonCredit.dedupe(combinedCredits?.crew ?? []).sorted(by: order.areInIncreasingOrder)
    }

    /// The credits matching the person's known department (crew for directors,
    /// cast for actors), falling back to the other list when empty.
    public func knownForCredits(sortedBy order: TMDBPersonCreditOrder = .popularity) -> [TMDBPersonCredit] {
        let preferCrew = (knownForDepartment ?? "Acting") != "Acting"
        let primary = preferCrew ? crewCredits(sortedBy: order) : castCredits(sortedBy: order)
        if !primary.isEmpty { return primary }
        return preferCrew ? castCredits(sortedBy: order) : crewCredits(sortedBy: order)
    }
}

public struct TMDBPersonExternalIds: Codable, Hashable {
    public let imdbId: String?
    public let instagramId: String?
    public let twitterId: String?

    private enum CodingKeys: String, CodingKey {
        case imdbId = "imdb_id"
        case instagramId = "instagram_id"
        case twitterId = "twitter_id"
    }
}

public struct TMDBPersonCombinedCredits: Codable {
    public let cast: [TMDBPersonCredit]
    public let crew: [TMDBPersonCredit]
}

public enum TMDBPersonCreditOrder: String, CaseIterable, Sendable {
    /// Most popular first.
    case popularity
    /// Newest first; undated (upcoming/unknown) titles first, as TMDB does.
    case newest
    /// Oldest first; undated titles last.
    case oldest

    func areInIncreasingOrder(_ lhs: TMDBPersonCredit, _ rhs: TMDBPersonCredit) -> Bool {
        switch self {
        case .popularity:
            let l = lhs.popularity ?? 0, r = rhs.popularity ?? 0
            if l != r { return l > r }
            return (lhs.voteCount ?? 0) > (rhs.voteCount ?? 0)
        case .newest:
            switch (lhs.date, rhs.date) {
            case let (l?, r?): return l > r
            case (.none, .some): return true
            case (.some, .none): return false
            case (.none, .none): return (lhs.popularity ?? 0) > (rhs.popularity ?? 0)
            }
        case .oldest:
            switch (lhs.date, rhs.date) {
            case let (l?, r?): return l < r
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return (lhs.popularity ?? 0) > (rhs.popularity ?? 0)
            }
        }
    }
}

/// One movie or TV credit for a person.
public struct TMDBPersonCredit: Codable, Identifiable, Hashable {
    /// TMDB id of the movie/show.
    public let id: Int
    /// "movie" or "tv".
    public let mediaType: String
    public let title: String?
    public let name: String?
    public let overview: String?
    public let posterPath: String?
    public let backdropPath: String?
    public let releaseDate: String?
    public let firstAirDate: String?
    public let voteAverage: Double?
    public let voteCount: Int?
    public let popularity: Double?
    public let genreIds: [Int]?
    /// Cast only.
    public let character: String?
    /// Crew only. After `dedupe`, multiple jobs are joined with ", ".
    public let job: String?
    public let department: String?
    /// TV only: number of episodes the person is credited on.
    public let episodeCount: Int?
    /// Unique per credit row (TMDB `credit_id`).
    public let creditId: String?

    private enum CodingKeys: String, CodingKey {
        case id, title, name, overview, popularity, character, job, department
        case mediaType = "media_type"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case genreIds = "genre_ids"
        case episodeCount = "episode_count"
        case creditId = "credit_id"
    }

    public init(
        id: Int, mediaType: String, title: String?, name: String?, overview: String?,
        posterPath: String?, backdropPath: String?, releaseDate: String?, firstAirDate: String?,
        voteAverage: Double?, voteCount: Int?, popularity: Double?, genreIds: [Int]?,
        character: String?, job: String?, department: String?, episodeCount: Int?, creditId: String?
    ) {
        self.id = id
        self.mediaType = mediaType
        self.title = title
        self.name = name
        self.overview = overview
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.releaseDate = releaseDate
        self.firstAirDate = firstAirDate
        self.voteAverage = voteAverage
        self.voteCount = voteCount
        self.popularity = popularity
        self.genreIds = genreIds
        self.character = character
        self.job = job
        self.department = department
        self.episodeCount = episodeCount
        self.creditId = creditId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        mediaType = try c.decodeIfPresent(String.self, forKey: .mediaType) ?? "movie"
        title = try c.decodeIfPresent(String.self, forKey: .title)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        overview = try c.decodeIfPresent(String.self, forKey: .overview)
        posterPath = try c.decodeIfPresent(String.self, forKey: .posterPath)
        backdropPath = try c.decodeIfPresent(String.self, forKey: .backdropPath)
        releaseDate = try c.decodeIfPresent(String.self, forKey: .releaseDate)
        firstAirDate = try c.decodeIfPresent(String.self, forKey: .firstAirDate)
        voteAverage = try c.decodeIfPresent(Double.self, forKey: .voteAverage)
        voteCount = try c.decodeIfPresent(Int.self, forKey: .voteCount)
        popularity = try c.decodeIfPresent(Double.self, forKey: .popularity)
        genreIds = try c.decodeIfPresent([Int].self, forKey: .genreIds)
        character = try c.decodeIfPresent(String.self, forKey: .character)
        job = try c.decodeIfPresent(String.self, forKey: .job)
        department = try c.decodeIfPresent(String.self, forKey: .department)
        episodeCount = try c.decodeIfPresent(Int.self, forKey: .episodeCount)
        creditId = try c.decodeIfPresent(String.self, forKey: .creditId)
    }

    public var displayTitle: String { title ?? name ?? "" }

    /// Release date (movies) or first air date (TV), nil when unknown/empty.
    public var date: String? {
        let raw = mediaType == "tv" ? (firstAirDate ?? releaseDate) : (releaseDate ?? firstAirDate)
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }

    public var year: Int? { date.flatMap { Int($0.prefix(4)) } }

    /// The app's canonical media id for this credit, e.g. `tmdb:movie:603`.
    public var canonicalMediaId: String { "tmdb:\(mediaType == "tv" ? "tv" : "movie"):\(id)" }

    /// Collapses repeated rows for the same title (TMDB lists one row per character
    /// or job) into one, joining jobs/characters and summing nothing else.
    static func dedupe(_ credits: [TMDBPersonCredit]) -> [TMDBPersonCredit] {
        var order: [String] = []
        var merged: [String: TMDBPersonCredit] = [:]
        for credit in credits {
            let key = "\(credit.mediaType):\(credit.id)"
            guard let existing = merged[key] else {
                merged[key] = credit
                order.append(key)
                continue
            }
            func join(_ a: String?, _ b: String?) -> String? {
                let parts = [a, b].compactMap { $0 }.filter { !$0.isEmpty }
                var seen = Set<String>()
                let unique = parts.flatMap { $0.components(separatedBy: ", ") }.filter { seen.insert($0).inserted }
                return unique.isEmpty ? nil : unique.joined(separator: ", ")
            }
            merged[key] = TMDBPersonCredit(
                id: existing.id, mediaType: existing.mediaType, title: existing.title, name: existing.name,
                overview: existing.overview, posterPath: existing.posterPath ?? credit.posterPath,
                backdropPath: existing.backdropPath ?? credit.backdropPath,
                releaseDate: existing.releaseDate, firstAirDate: existing.firstAirDate,
                voteAverage: existing.voteAverage, voteCount: existing.voteCount,
                popularity: existing.popularity, genreIds: existing.genreIds,
                character: join(existing.character, credit.character),
                job: join(existing.job, credit.job),
                department: existing.department ?? credit.department,
                episodeCount: max(existing.episodeCount ?? 0, credit.episodeCount ?? 0) == 0
                    ? nil : max(existing.episodeCount ?? 0, credit.episodeCount ?? 0),
                creditId: existing.creditId
            )
        }
        return order.compactMap { merged[$0] }
    }
}

/// `/search/person` page.
public struct TMDBPeopleSearchResponse: Codable {
    public let page: Int
    public let results: [TMDBPersonSummary]
    public let totalPages: Int?
    public let totalResults: Int?

    private enum CodingKeys: String, CodingKey {
        case page, results
        case totalPages = "total_pages"
        case totalResults = "total_results"
    }
}

public struct TMDBPersonSummary: Codable, Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let profilePath: String?
    public let knownForDepartment: String?
    public let popularity: Double?
    /// A few titles the person is known for (movies and shows mixed).
    public let knownFor: [TMDBPersonCredit]?

    private enum CodingKeys: String, CodingKey {
        case id, name, popularity
        case profilePath = "profile_path"
        case knownForDepartment = "known_for_department"
        case knownFor = "known_for"
    }
}

// MARK: - Company / Network Models

/// Company (`/company/{id}`) or TV network (`/network/{id}`) details.
public struct TMDBCompanyDetails: Codable, Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let description: String?
    public let headquarters: String?
    public let homepage: String?
    public let logoPath: String?
    public let originCountry: String?
    public let parentCompany: TMDBCompanyParent?

    private enum CodingKeys: String, CodingKey {
        case id, name, description, headquarters, homepage
        case logoPath = "logo_path"
        case originCountry = "origin_country"
        case parentCompany = "parent_company"
    }
}

public struct TMDBCompanyParent: Codable, Hashable {
    public let id: Int?
    public let name: String?
    public let logoPath: String?

    private enum CodingKeys: String, CodingKey {
        case id, name
        case logoPath = "logo_path"
    }
}

// MARK: - Genre Models

public struct TMDBGenreListResponse: Codable {
    public let genres: [TMDBGenre]
}
