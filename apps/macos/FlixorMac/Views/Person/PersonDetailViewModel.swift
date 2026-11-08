//
//  PersonDetailViewModel.swift
//  FlixorMac
//
//  Loads a TMDB person (details + combined credits in one request) and
//  exposes the filmography filtered by department, media type and sort.
//  TMDB is configured at launch from the bundled key, so this works in Plex
//  and Stremio-only mode alike.
//

import Foundation
import FlixorKit

/// One poster in the person's filmography.
struct PersonCreditItem: Identifiable, Equatable {
    let id: String
    let item: MediaItem
    /// Character, job, or episode count shown under the poster.
    let subtitle: String?
    let isTV: Bool

    static func == (lhs: PersonCreditItem, rhs: PersonCreditItem) -> Bool {
        lhs.id == rhs.id && lhs.subtitle == rhs.subtitle
    }
}

@MainActor
final class PersonDetailViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    enum Department: String, CaseIterable, Identifiable {
        case acting, crew
        var id: String { rawValue }
        var title: String { self == .acting ? "Acting" : "Crew" }
    }

    enum MediaFilter: String, CaseIterable, Identifiable {
        case all, movies, tv
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "All"
            case .movies: return "Movies"
            case .tv: return "TV"
            }
        }
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        case popular, newest, oldest
        var id: String { rawValue }
        var title: String {
            switch self {
            case .popular: return "Popular"
            case .newest: return "Newest"
            case .oldest: return "Oldest"
            }
        }
        var tmdbOrder: TMDBPersonCreditOrder {
            switch self {
            case .popular: return .popularity
            case .newest: return .newest
            case .oldest: return .oldest
            }
        }
    }

    let route: PersonRoute

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var profile: TMDBPersonProfile?
    @Published private(set) var credits: [PersonCreditItem] = []
    @Published private(set) var knownFor: [PersonCreditItem] = []
    @Published private(set) var castCount = 0
    @Published private(set) var crewCount = 0
    /// Counts for the media filter chips, for the current department.
    @Published private(set) var filterCounts: [MediaFilter: Int] = [:]
    /// "48 movies · 12 shows" across acting and crew.
    @Published private(set) var creditSummary: String?

    @Published var department: Department = .acting {
        didSet { if oldValue != department { rebuildCredits() } }
    }
    @Published var mediaFilter: MediaFilter = .all {
        didSet { if oldValue != mediaFilter { rebuildCredits() } }
    }
    @Published var sort: SortOrder = .popular {
        didSet { if oldValue != sort { rebuildCredits() } }
    }

    private var loadTask: Task<Void, Never>?

    init(route: PersonRoute) {
        self.route = route
    }

    // MARK: - Derived display values

    var displayName: String {
        if let name = profile?.name, !name.isEmpty { return name }
        return route.name
    }

    /// Profile photo: TMDB profile first, then whatever the caller passed in
    /// (a TMDB path or a full URL from the cast row).
    var profileImageURL: URL? {
        TMDBImageURL.url(profile?.profilePath, size: .w500) ?? TMDBImageURL.url(route.profilePath, size: .w500)
    }

    /// Backdrop of the best-known title, for the faded page background.
    var backdropURL: URL? {
        guard let item = knownFor.first(where: { $0.item.art != nil })?.item else { return nil }
        return item.art.flatMap(URL.init(string:))
    }

    var biography: String? {
        guard let bio = profile?.biography?.trimmingCharacters(in: .whitespacesAndNewlines), !bio.isEmpty else {
            return nil
        }
        return bio
    }

    var knownForDepartment: String? {
        guard let department = profile?.knownForDepartment, !department.isEmpty else { return nil }
        return department
    }

    var hasBothDepartments: Bool { castCount > 0 && crewCount > 0 }

    var imdbURL: URL? {
        guard let id = profile?.imdbId ?? profile?.externalIds?.imdbId, !id.isEmpty else { return nil }
        return URL(string: "https://www.imdb.com/name/\(id)/")
    }

    var homepageURL: URL? {
        guard let page = profile?.homepage, !page.isEmpty, let url = URL(string: page),
              url.scheme == "https" || url.scheme == "http" else { return nil }
        return url
    }

    var instagramURL: URL? {
        guard let handle = profile?.externalIds?.instagramId, !handle.isEmpty else { return nil }
        return URL(string: "https://www.instagram.com/\(handle)/")
    }

    // MARK: - Loading

    func loadIfNeeded() {
        guard profile == nil, loadTask == nil else { return }
        load()
    }

    func load() {
        loadTask?.cancel()
        phase = .loading
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let personId = try await self.resolvePersonId()
                let profile = try await FlixorCore.shared.tmdb.getPersonProfile(id: personId)
                try Task.checkCancellation()
                self.apply(profile)
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                self.phase = .failed(Self.message(for: error))
            }
            self.loadTask = nil
        }
    }

    private func resolvePersonId() async throws -> Int {
        if let id = Int(route.tmdbId), id > 0 {
            return id
        }
        // Plex cast entries carry no TMDB id: fall back to a name search.
        let name = route.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw PersonLookupError.notFound(route.name) }
        let response = try await FlixorCore.shared.tmdb.searchPeople(query: name)
        let exact = response.results.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        guard let match = exact ?? response.results.first else {
            throw PersonLookupError.notFound(name)
        }
        return match.id
    }

    private func apply(_ profile: TMDBPersonProfile) {
        self.profile = profile
        let cast = profile.castCredits()
        let crew = profile.crewCredits()
        castCount = cast.count
        crewCount = crew.count
        creditSummary = Self.creditSummary(cast: cast, crew: crew)

        // Default tab follows what the person is known for.
        let prefersCrew = (profile.knownForDepartment ?? "Acting") != "Acting"
        if prefersCrew, !crew.isEmpty {
            department = .crew
        } else if cast.isEmpty, !crew.isEmpty {
            department = .crew
        } else {
            department = .acting
        }

        knownFor = Self.knownForItems(profile)
        rebuildCredits()
        phase = .loaded
    }

    private static func creditSummary(cast: [TMDBPersonCredit], crew: [TMDBPersonCredit]) -> String? {
        var seen = Set<String>()
        let unique = (cast + crew).filter { seen.insert($0.canonicalMediaId).inserted }
        let shows = unique.filter { $0.mediaType == "tv" }.count
        let movies = unique.count - shows
        var parts: [String] = []
        if movies > 0 { parts.append("\(movies) movie\(movies == 1 ? "" : "s")") }
        if shows > 0 { parts.append("\(shows) show\(shows == 1 ? "" : "s")") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Filmography

    private func rebuildCredits() {
        guard let profile else {
            credits = []
            filterCounts = [:]
            return
        }
        let source = department == .acting
            ? profile.castCredits(sortedBy: sort.tmdbOrder)
            : profile.crewCredits(sortedBy: sort.tmdbOrder)

        let movieCount = source.filter { $0.mediaType != "tv" }.count
        filterCounts = [.all: source.count, .movies: movieCount, .tv: source.count - movieCount]

        let filtered: [TMDBPersonCredit]
        switch mediaFilter {
        case .all: filtered = source
        case .movies: filtered = source.filter { $0.mediaType != "tv" }
        case .tv: filtered = source.filter { $0.mediaType == "tv" }
        }
        let department = self.department
        credits = filtered.map { Self.item(for: $0, department: department) }
    }

    private static func item(for credit: TMDBPersonCredit, department: Department) -> PersonCreditItem {
        PersonCreditItem(
            id: credit.canonicalMediaId,
            item: MediaItem.fromTMDB(credit),
            subtitle: subtitle(for: credit, department: department),
            isTV: credit.mediaType == "tv"
        )
    }

    private static func subtitle(for credit: TMDBPersonCredit, department: Department) -> String? {
        var parts: [String] = []
        switch department {
        case .acting:
            if let character = credit.character?.trimmingCharacters(in: .whitespaces), !character.isEmpty {
                parts.append(character)
            }
        case .crew:
            if let job = credit.job, !job.isEmpty {
                parts.append(job)
            } else if let dept = credit.department, !dept.isEmpty {
                parts.append(dept)
            }
        }
        if credit.mediaType == "tv", let episodes = credit.episodeCount, episodes > 0 {
            parts.append("\(episodes) ep\(episodes == 1 ? "" : "s")")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Talk shows, news and reality appearances ("Self") crowd out the roles
    /// people are actually known for, so they are left out of this row.
    private static let nonFictionGenres: Set<Int> = [10763, 10764, 10767]

    private static func knownForItems(_ profile: TMDBPersonProfile) -> [PersonCreditItem] {
        let prefersCrew = (profile.knownForDepartment ?? "Acting") != "Acting"
        let department: Department = {
            if prefersCrew { return profile.crewCredits().isEmpty ? .acting : .crew }
            return profile.castCredits().isEmpty ? .crew : .acting
        }()
        let candidates = profile.knownForCredits(sortedBy: .popularity).filter { credit in
            guard credit.posterPath != nil else { return false }
            if let genres = credit.genreIds, !nonFictionGenres.isDisjoint(with: genres) { return false }
            if let character = credit.character?.lowercased(),
               character == "self" || character.hasPrefix("self ") || character.hasPrefix("himself") || character.hasPrefix("herself") {
                return false
            }
            return true
        }
        // Vote count tracks lasting recognition better than current popularity.
        let ranked = candidates.sorted { ($0.voteCount ?? 0) > ($1.voteCount ?? 0) }
        return ranked.prefix(12).map { item(for: $0, department: department) }
    }

    // MARK: - Errors

    private enum PersonLookupError: LocalizedError {
        case notFound(String)
        var errorDescription: String? {
            switch self {
            case .notFound(let name):
                return name.isEmpty
                    ? "This person couldn't be found on TMDB."
                    : "Couldn't find \(name) on TMDB."
            }
        }
    }

    private static func message(for error: Error) -> String {
        TMDBErrorMessage.message(for: error, fallback: "Couldn't load this person from TMDB.")
    }
}
