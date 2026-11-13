//
//  MergedRatings.swift
//  FlixorMac
//
//  One list of ratings for Details, built from every source the app has:
//  MyBluray (main), Plex, MDBList (extra, and the only source of Metacritic
//  and Trakt) and TMDB. Each rating comes from the source the person picked in
//  Settings → Details, or, on Automatic (and when the picked source has
//  nothing), from the first source in `RatingSource.priority` that has it.
//

import Foundation

/// A rating the Details page can show.
enum RatingKind: String, CaseIterable, Identifiable {
    case imdb
    case rtCritics
    case rtAudience
    case letterboxd
    case metacritic
    case tmdb
    case trakt

    var id: String { rawValue }

    var title: String {
        switch self {
        case .imdb: return "IMDb"
        case .rtCritics: return String(localized: "Rotten Tomatoes (Critics)")
        case .rtAudience: return String(localized: "Rotten Tomatoes (Audience)")
        case .letterboxd: return "Letterboxd"
        case .metacritic: return "Metacritic"
        case .tmdb: return "TMDB"
        case .trakt: return "Trakt"
        }
    }

    var subtitle: String {
        switch self {
        case .imdb: return String(localized: "Out of 10, from IMDb users")
        case .rtCritics: return String(localized: "Tomatometer")
        case .rtAudience: return String(localized: "Popcornmeter")
        case .letterboxd: return String(localized: "Out of 5, from Letterboxd members")
        case .metacritic: return String(localized: "Metascore from critics")
        case .tmdb: return String(localized: "Out of 10, from TMDB users")
        case .trakt: return String(localized: "From Trakt users")
        }
    }

    /// Shown unless turned off. IMDb and both Rotten Tomatoes scores were
    /// always shown; Letterboxd is new and on; the rest are opt-in.
    var defaultShown: Bool {
        switch self {
        case .imdb, .rtCritics, .rtAudience, .letterboxd: return true
        case .metacritic, .tmdb, .trakt: return false
        }
    }

    /// Sources that can supply this rating, in automatic priority order.
    var sources: [RatingSource] {
        switch self {
        case .imdb, .rtCritics, .rtAudience: return [.mybluray, .plex, .mdblist]
        case .letterboxd: return [.mybluray, .mdblist]
        case .metacritic, .trakt: return [.mdblist]
        case .tmdb: return [.mybluray, .tmdb, .mdblist]
        }
    }
}

/// Where a rating comes from. `.automatic` is a setting, never a result.
enum RatingSource: String, CaseIterable, Identifiable {
    case automatic
    case mybluray
    case plex
    case mdblist
    case tmdb

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return String(localized: "Automatic")
        case .mybluray: return "MyBluray"
        case .plex: return "Plex"
        case .mdblist: return "MDBList"
        case .tmdb: return "TMDB"
        }
    }
}

/// One rating ready to draw.
struct MergedRating: Identifiable, Equatable {
    let kind: RatingKind
    /// On the kind's own scale: IMDb, TMDB 0–10; Rotten Tomatoes, Metacritic,
    /// Trakt 0–100; Letterboxd 0–5.
    let value: Double
    let source: RatingSource
    var votes: Int? = nil
    var certifiedFresh = false
    /// Rotten Tomatoes' fresh and rotten review counts, and the critics' consensus.
    var reviews: (fresh: Int, rotten: Int)? = nil
    var consensus: String? = nil

    static func == (lhs: MergedRating, rhs: MergedRating) -> Bool {
        lhs.kind == rhs.kind && lhs.value == rhs.value && lhs.source == rhs.source
            && lhs.votes == rhs.votes && lhs.certifiedFresh == rhs.certifiedFresh
            && lhs.reviews?.fresh == rhs.reviews?.fresh && lhs.reviews?.rotten == rhs.reviews?.rotten
            && lhs.consensus == rhs.consensus
    }

    var id: String { kind.rawValue }

    var text: String {
        switch kind {
        case .imdb, .tmdb, .letterboxd: return String(format: "%.1f", value)
        case .rtCritics, .rtAudience, .trakt: return "\(Int(value.rounded()))%"
        case .metacritic: return "\(Int(value.rounded()))"
        }
    }

    /// Tooltip: what the score is and where it came from.
    var help: String {
        var parts = [kind.title + " " + text]
        if certifiedFresh { parts.append(String(localized: "Certified Fresh")) }
        if let votes { parts.append(String(localized: "\(votes.formatted()) votes")) }
        if let reviews { parts.append(String(localized: "\(reviews.fresh + reviews.rotten) reviews")) }
        parts.append(String(localized: "via \(source.title)"))
        let line = parts.joined(separator: " · ")
        guard let consensus, !consensus.isEmpty else { return line }
        return line + "\n\n" + consensus
    }
}

/// Everything the merger reads, gathered by DetailsViewModel.
struct RatingInputs {
    var mybluray: [MBRating] = []
    var plexImdb: Double?
    var plexCritics: Int?
    var plexAudience: Int?
    var mdblist: MDBListRatings?
    var tmdb: Double?
}

enum RatingsMerger {
    /// Shown ratings in display order.
    static func merge(_ inputs: RatingInputs, shown: (RatingKind) -> Bool, source: (RatingKind) -> RatingSource) -> [MergedRating] {
        RatingKind.allCases.compactMap { kind in
            guard shown(kind) else { return nil }
            let picked = source(kind)
            if picked != .automatic, let rating = rating(kind, from: picked, inputs) {
                return rating
            }
            // Automatic, or the picked source has nothing for this title.
            for candidate in kind.sources {
                if let rating = rating(kind, from: candidate, inputs) { return rating }
            }
            return nil
        }
    }

    static func rating(_ kind: RatingKind, from source: RatingSource, _ inputs: RatingInputs) -> MergedRating? {
        func make(_ value: Double?, votes: Int? = nil, certified: Bool = false) -> MergedRating? {
            guard let value, value > 0 else { return nil }
            return MergedRating(kind: kind, value: value, source: source, votes: votes, certifiedFresh: certified)
        }

        switch source {
        case .automatic:
            return nil

        case .mybluray:
            guard let match = myblurayRating(kind, inputs.mybluray),
                  var rating = make(normalized(match.value, scale: match.scale, kind: kind),
                                    votes: match.voteCount,
                                    certified: match.certifiedFresh == true || match.freshness == "CertifiedFresh")
            else { return nil }
            if let fresh = match.freshReviews, let rotten = match.rottenReviews { rating.reviews = (fresh, rotten) }
            rating.consensus = match.consensus
            return rating

        case .plex:
            switch kind {
            case .imdb: return make(inputs.plexImdb)
            case .rtCritics: return make(inputs.plexCritics.map(Double.init))
            case .rtAudience: return make(inputs.plexAudience.map(Double.init))
            default: return nil
            }

        case .mdblist:
            guard let m = inputs.mdblist else { return nil }
            switch kind {
            case .imdb: return make(m.imdb)
            case .rtCritics: return make(m.tomatoes)
            case .rtAudience: return make(m.audience)
            case .letterboxd: return make(m.letterboxd)
            case .metacritic: return make(m.metacritic)
            // MDBList gives TMDB out of 100 for some titles and 10 for others.
            case .tmdb: return make(m.tmdb.map { $0 > 10 ? $0 / 10 : $0 })
            case .trakt: return make(m.trakt.map { $0 <= 10 ? $0 * 10 : $0 })
            }

        case .tmdb:
            return kind == .tmdb ? make(inputs.tmdb) : nil
        }
    }

    /// MyBluray can list the same score twice (Rotten Tomatoes from Apple and
    /// from JustWatch); Apple's copy is preferred.
    private static func myblurayRating(_ kind: RatingKind, _ ratings: [MBRating]) -> MBRating? {
        let matches = ratings.filter { rating in
            switch kind {
            case .imdb: return rating.provider == "imdb"
            case .rtCritics: return rating.provider == "rotten-tomatoes" && rating.kind == "critics-percentage"
            case .rtAudience: return rating.provider == "rotten-tomatoes" && rating.kind == "audience-percentage"
            case .letterboxd: return rating.provider == "letterboxd"
            case .tmdb: return rating.provider == "tmdb"
            case .metacritic: return rating.provider == "metacritic"
            case .trakt: return rating.provider == "trakt"
            }
        }
        return matches.first(where: { $0.provenance?.provider == "apple-tv" }) ?? matches.first
    }

    /// Puts a MyBluray value on the kind's own scale.
    private static func normalized(_ value: Double?, scale: Double?, kind: RatingKind) -> Double? {
        guard let value else { return nil }
        let target: Double
        switch kind {
        case .imdb, .tmdb: target = 10
        case .letterboxd: target = 5
        case .rtCritics, .rtAudience, .metacritic, .trakt: target = 100
        }
        guard let scale, scale > 0, scale != target else { return value }
        return value / scale * target
    }
}
