//
//  UpcomingEpisodesStore.swift
//  FlixorMac
//
//  The next episodes of the user's shows: what came out in the last week and
//  hasn't been watched, and what airs in the next 30 days. With Trakt it reads
//  the user's show calendar (air times included) and watched progress; without
//  it, TMDB's next and last episode for shows in the local watch history and
//  watchlist (days only, no times). Feeds the Home "Upcoming" row, the
//  Upcoming page and the next-episode strip on show Details.
//

import Combine
import Foundation
import FlixorKit

/// Which new (out, unwatched) episodes get a "New" card on Home and the page.
struct UpcomingNewEpisodeRules: Equatable {
    /// Show new episodes at all.
    var showNew: Bool = true
    /// Only for shows the user has watched some of.
    var onlyStartedShows: Bool = true
    /// Leave out shows more episodes behind than this; 0 means no limit.
    var maxEpisodesBehind: Int = 5

    static let behindChoices = [1, 3, 5, 10, 20, 0]

    static func behindLabel(_ value: Int) -> String {
        value == 0 ? String(localized: "No limit") : (value == 1 ? String(localized: "1 episode") : String(localized: "\(value) episodes"))
    }

    func allows(_ episode: UpcomingEpisode) -> Bool {
        guard showNew else { return false }
        // Unknown (no watched progress) counts as started: there's nothing to judge by.
        if onlyStartedShows, episode.hasStartedShow == false { return false }
        if maxEpisodesBehind > 0, let behind = episode.episodesBehind, behind > maxEpisodesBehind { return false }
        return true
    }
}

extension UserDefaults {
    private enum UpcomingKeys {
        static let showNew = "upcomingShowNew"
        static let onlyStarted = "upcomingNewOnlyStarted"
        static let maxBehind = "upcomingNewMaxBehind"
    }

    /// Profile-scoped. Read and write through `UpcomingEpisodesStore.shared.newRules` in UI code.
    var upcomingNewEpisodeRules: UpcomingNewEpisodeRules {
        get {
            var rules = UpcomingNewEpisodeRules()
            if let value = object(forKey: profileKey(UpcomingKeys.showNew)) as? Bool { rules.showNew = value }
            if let value = object(forKey: profileKey(UpcomingKeys.onlyStarted)) as? Bool { rules.onlyStartedShows = value }
            if let value = object(forKey: profileKey(UpcomingKeys.maxBehind)) as? Int { rules.maxEpisodesBehind = value }
            return rules
        }
        set {
            set(newValue.showNew, forKey: profileKey(UpcomingKeys.showNew))
            set(newValue.onlyStartedShows, forKey: profileKey(UpcomingKeys.onlyStarted))
            set(newValue.maxEpisodesBehind, forKey: profileKey(UpcomingKeys.maxBehind))
        }
    }
}

struct UpcomingEpisode: Identifiable, Hashable {
    let showTmdbId: Int
    let showImdbId: String?
    let showTitle: String
    let showYear: Int?
    let season: Int
    let number: Int
    let title: String?
    /// Air time; only the day is meaningful when `hasTime` is false.
    let airDate: Date
    let hasTime: Bool
    let runtimeMinutes: Int?
    let isFinale: Bool
    /// Show backdrop (w780) and poster (w500) URLs.
    let backdropURL: String?
    let posterURL: String?
    /// Out, and the user hasn't watched it. Whether it is shown depends on
    /// `UpcomingNewEpisodeRules`.
    let isNewUnwatched: Bool
    /// The user has watched at least one episode of the show, when known.
    let hasStartedShow: Bool?
    /// Aired episodes the user hasn't watched yet, when known.
    let episodesBehind: Int?
    /// Share of aired episodes watched (0...1), when known.
    let watchedFraction: Double?

    var id: String { "\(showTmdbId):\(season):\(number)" }
    var isPremiere: Bool { number == 1 }
    var episodeCode: String { "S\(season) E\(number)" }

    func isOut(now: Date = Date()) -> Bool {
        hasTime ? airDate <= now : Calendar.current.startOfDay(for: airDate) <= now
    }

    /// The show, for opening its Details page.
    var showItem: MediaItem {
        MediaItem(
            id: "tmdb:tv:\(showTmdbId)", title: showTitle, type: "show", thumb: posterURL, art: backdropURL,
            year: showYear, rating: nil, duration: nil, viewOffset: nil, summary: nil,
            grandparentTitle: nil, grandparentThumb: nil, grandparentArt: nil, grandparentRatingKey: nil,
            parentIndex: nil, index: nil, parentRatingKey: nil, parentTitle: nil, leafCount: nil, viewedLeafCount: nil
        )
    }
}

@MainActor
final class UpcomingEpisodesStore: ObservableObject {
    static let shared = UpcomingEpisodesStore()

    enum State: Equatable {
        case idle
        case loading
        case loaded([UpcomingEpisode])
        case failed
    }

    @Published private(set) var state: State = .idle

    /// Which out-but-unwatched episodes get a "New" card. Applied to the
    /// loaded list as it changes, without refetching.
    @Published var newRules: UpcomingNewEpisodeRules {
        didSet {
            guard newRules != oldValue else { return }
            UserDefaults.standard.upcomingNewEpisodeRules = newRules
        }
    }

    private var profileObserver: AnyCancellable?
    private var fetchedAt: Date?
    private var fetchedProfile: String?
    private var task: Task<Void, Never>?

    private static let lifetime: TimeInterval = 10 * 60

    private init() {
        newRules = UserDefaults.standard.upcomingNewEpisodeRules
        // Profile switches republish ProfileSettings; re-read our settings then.
        profileObserver = ProfileSettings.shared.objectWillChange
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let rules = UserDefaults.standard.upcomingNewEpisodeRules
                    if rules != self.newRules { self.newRules = rules }
                }
            }
    }

    /// The loaded list with the "New" rules applied.
    var episodes: [UpcomingEpisode] {
        guard case .loaded(let list) = state else { return [] }
        return list.filter { !$0.isNewUnwatched || newRules.allows($0) }
    }

    /// New episodes the current rules leave out (for the page's note).
    var hiddenNewCount: Int {
        guard case .loaded(let list) = state else { return 0 }
        return list.filter { $0.isNewUnwatched && !newRules.allows($0) }.count
    }

    /// The next episode of a show still to come, if the list has one.
    func nextEpisode(showTmdbId: Int) -> UpcomingEpisode? {
        let now = Date()
        return episodes.first { $0.showTmdbId == showTmdbId && !$0.isOut(now: now) }
    }

    /// Loads the list unless it is fresh for this profile.
    func refreshIfStale() {
        let profile = UserDefaults.standard.profileKey("upcomingEpisodes")
        if let fetchedAt, fetchedProfile == profile, Date().timeIntervalSince(fetchedAt) < Self.lifetime { return }
        guard task == nil else { return }
        if case .loaded = state {} else { state = .loading }
        task = Task { [weak self] in
            let list = await UpcomingEpisodesLoader.load()
            guard let self else { return }
            self.task = nil
            if let list {
                self.state = .loaded(list)
                self.fetchedAt = Date()
                self.fetchedProfile = profile
            } else if case .loaded = self.state {
                // Keep what we had.
            } else {
                self.state = .failed
            }
        }
    }

    func invalidate() {
        fetchedAt = nil
    }
}

// MARK: - Loading

enum UpcomingEpisodesLoader {
    /// Days back for "out, not watched" and days ahead for upcoming.
    static let daysBack = 7
    static let daysAhead = 30
    private static let maxShows = 30
    private static let concurrency = 6

    /// nil when nothing could be read at all.
    static func load() async -> [UpcomingEpisode]? {
        let trakt = await FlixorCore.shared.trakt
        if await trakt.isAuthenticated, let list = await loadFromTrakt(trakt) {
            return list
        }
        return await loadFromTMDB()
    }

    // MARK: Trakt

    private struct ShowProgress {
        let aired: Int
        let completed: Int
        let next: (season: Int, number: Int)?
    }

    private static func loadFromTrakt(_ trakt: TraktService) async -> [UpcomingEpisode]? {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -daysBack, to: calendar.startOfDay(for: Date())) ?? Date()
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let entries = try? await trakt.getMyShowsCalendar(
            startDate: formatter.string(from: start), days: daysBack + daysAhead + 1
        ) else { return nil }

        let now = Date()
        let dated: [(entry: TraktCalendarShowEntry, date: Date, tmdbId: Int)] = entries.compactMap { entry in
            guard let tmdbId = entry.show.ids.tmdb, let date = parseISO(entry.firstAired) else { return nil }
            return (entry, date, tmdbId)
        }

        // Watched progress per show: which aired episodes are still unwatched.
        var showIds: [Int: String] = [:]
        for item in dated where showIds[item.tmdbId] == nil {
            if let id = item.entry.show.ids.trakt.map(String.init) ?? item.entry.show.ids.slug {
                showIds[item.tmdbId] = id
            }
        }
        let progress = await collect(Array(showIds.prefix(maxShows))) { pair -> (Int, ShowProgress)? in
            guard let p = try? await trakt.getShowNextUp(showId: pair.value) else { return nil }
            let next = p.nextEpisode.map { (season: $0.season, number: $0.number) }
            return (pair.key, ShowProgress(aired: p.aired, completed: p.completed, next: next))
        }
        let progressByShow = Dictionary(progress, uniquingKeysWith: { a, _ in a })
        let art = await artwork(for: Set(dated.map(\.tmdbId)))

        var result: [UpcomingEpisode] = []
        for item in dated {
            let episode = item.entry.episode
            guard episode.season > 0 else { continue }
            let p = progressByShow[item.tmdbId]
            let out = item.date <= now
            var unwatched = false
            if out {
                // Out and unwatched: the first unwatched episode is this one or earlier.
                // Whether it gets a card is up to UpcomingNewEpisodeRules.
                guard let next = p?.next,
                      (next.season, next.number) <= (episode.season, episode.number) else { continue }
                unwatched = true
            }
            result.append(UpcomingEpisode(
                showTmdbId: item.tmdbId,
                showImdbId: item.entry.show.ids.imdb,
                showTitle: item.entry.show.title,
                showYear: item.entry.show.year,
                season: episode.season,
                number: episode.number,
                title: episode.title,
                airDate: item.date,
                hasTime: true,
                runtimeMinutes: episode.runtime ?? item.entry.show.runtime,
                isFinale: false,
                backdropURL: art[item.tmdbId]?.backdrop,
                posterURL: art[item.tmdbId]?.poster,
                isNewUnwatched: unwatched,
                hasStartedShow: p.map { $0.completed > 0 },
                episodesBehind: p.map { max(0, $0.aired - $0.completed) },
                watchedFraction: p.flatMap { $0.aired > 0 ? Double($0.completed) / Double($0.aired) : nil }
            ))
        }
        return sorted(result)
    }

    // MARK: TMDB fallback

    private static func loadFromTMDB() async -> [UpcomingEpisode]? {
        let library = LocalLibraryStore.shared
        let history = await library.watchHistory()
        let watched = await library.watchedEntries()
        let watchlist = await library.watchlist()

        // Shows by most recent activity.
        var lastActivity: [Int: Date] = [:]
        for entry in history where entry.mediaType != .movie {
            guard let id = entry.tmdbId else { continue }
            lastActivity[id] = max(lastActivity[id] ?? .distantPast, entry.updatedAt)
        }
        for entry in watched where entry.mediaType == .episode {
            guard let id = entry.tmdbId else { continue }
            lastActivity[id] = max(lastActivity[id] ?? .distantPast, entry.watchedAt)
        }
        for entry in watchlist where entry.type == "show" {
            guard let id = entry.tmdbId else { continue }
            lastActivity[id] = max(lastActivity[id] ?? .distantPast, entry.addedAt)
        }
        let showIds = lastActivity.sorted { $0.value > $1.value }.prefix(maxShows).map(\.key)
        guard !showIds.isEmpty else { return [] }

        let tmdb = await FlixorCore.shared.tmdb
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let earliest = calendar.date(byAdding: .day, value: -daysBack, to: today) ?? today
        let latest = calendar.date(byAdding: .day, value: daysAhead, to: today) ?? today
        let watchedKeys = Set(watched.compactMap { entry -> String? in
            guard let id = entry.tmdbId, let s = entry.seasonNumber, let e = entry.episodeNumber else { return nil }
            return "\(id):\(s):\(e)"
        })

        let lists = await collect(showIds) { id -> [UpcomingEpisode]? in
            guard let details = try? await tmdb.getTVDetails(id: id) else { return nil }
            let backdrop = TMDBImageURL.url(details.backdropPath ?? details.posterPath, size: .w780)?.absoluteString
            let poster = TMDBImageURL.url(details.posterPath, size: .w500)?.absoluteString
            func make(_ ep: TMDBAiringEpisode?, out: Bool) -> UpcomingEpisode? {
                guard let ep, let season = ep.seasonNumber, season > 0, let number = ep.episodeNumber,
                      let day = parseDay(ep.airDate), day >= earliest, day <= latest else { return nil }
                if out {
                    guard day <= today, !watchedKeys.contains("\(id):\(season):\(number)") else { return nil }
                } else if day < today {
                    return nil
                }
                return UpcomingEpisode(
                    showTmdbId: id, showImdbId: details.externalIds?.imdbId, showTitle: details.name ?? "",
                    showYear: details.firstAirDate.flatMap { Int($0.prefix(4)) },
                    season: season, number: number, title: ep.name, airDate: day, hasTime: false,
                    runtimeMinutes: ep.runtime, isFinale: ep.episodeType == "finale",
                    backdropURL: backdrop, posterURL: poster, isNewUnwatched: out,
                    hasStartedShow: out ? true : nil, episodesBehind: nil, watchedFraction: nil
                )
            }
            // Only count "out" for shows the user has watched, not just listed.
            let hasWatched = history.contains { $0.tmdbId == id } || watched.contains { $0.tmdbId == id }
            return [hasWatched ? make(details.lastEpisodeToAir, out: true) : nil, make(details.nextEpisodeToAir, out: false)]
                .compactMap { $0 }
        }
        if lists.isEmpty { return nil }
        return sorted(lists.flatMap { $0 })
    }

    // MARK: Helpers

    private static func artwork(for ids: Set<Int>) async -> [Int: (backdrop: String?, poster: String?)] {
        let tmdb = await FlixorCore.shared.tmdb
        let pairs = await collect(Array(ids.prefix(maxShows * 2))) { id -> (Int, (backdrop: String?, poster: String?))? in
            guard let details = try? await tmdb.getTVDetails(id: id) else { return nil }
            return (id, (
                TMDBImageURL.url(details.backdropPath ?? details.posterPath, size: .w780)?.absoluteString,
                TMDBImageURL.url(details.posterPath, size: .w500)?.absoluteString
            ))
        }
        return Dictionary(pairs, uniquingKeysWith: { a, _ in a })
    }

    /// New unwatched episodes first (newest first), then upcoming by air time.
    static func sorted(_ list: [UpcomingEpisode]) -> [UpcomingEpisode] {
        let fresh = list.filter(\.isNewUnwatched).sorted { $0.airDate > $1.airDate }
        let coming = list.filter { !$0.isNewUnwatched }.sorted {
            $0.airDate != $1.airDate ? $0.airDate < $1.airDate : $0.showTitle < $1.showTitle
        }
        // One "new" card per show: the earliest unwatched one says where to pick up.
        var seenShows = Set<Int>()
        let freshPerShow = fresh.reversed().filter { seenShows.insert($0.showTmdbId).inserted }.reversed()
        return Array(freshPerShow) + coming
    }

    private static func collect<Input, Output>(
        _ inputs: [Input], _ work: @escaping (Input) async -> Output?
    ) async -> [Output] {
        var results: [Output] = []
        var index = 0
        while index < inputs.count {
            let batch = inputs[index..<min(index + concurrency, inputs.count)]
            index += concurrency
            await withTaskGroup(of: Output?.self) { group in
                for input in batch { group.addTask { await work(input) } }
                for await output in group { if let output { results.append(output) } }
            }
        }
        return results
    }

    private static func parseISO(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }

    /// "2026-11-20" as the start of that day in the user's time zone.
    static func parseDay(_ value: String?) -> Date? {
        guard let value, value.count >= 10 else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(value.prefix(10)))
    }
}

// MARK: - Labels

enum UpcomingLabels {
    private static func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }

    private static let dayFormatter = formatter("EEEdMMM")
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    static func time(_ date: Date) -> String { timeFormatter.string(from: date) }
    static func day(_ date: Date) -> String { dayFormatter.string(from: date) }

    /// "Today", "Tomorrow", or "Fri 20 Nov".
    static func relativeDay(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "Today") }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return String(localized: "Tomorrow")
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "Yesterday")
        }
        return day(date)
    }

    /// The chip on a card: "New · S2 E4", "Today · 9:00 PM", "Premiere · 2 Dec", "Fri 20 Nov".
    static func chip(for episode: UpcomingEpisode, now: Date = Date()) -> String {
        if episode.isNewUnwatched { return String(localized: "New · \(episode.episodeCode)") }
        let day = relativeDay(episode.airDate, now: now)
        if episode.isPremiere {
            return String(localized: "Premiere · \(day)")
        }
        let calendar = Calendar.current
        let isSoon = calendar.isDate(episode.airDate, inSameDayAs: now)
            || calendar.date(byAdding: .day, value: 1, to: now).map { calendar.isDate(episode.airDate, inSameDayAs: $0) } == true
        if episode.hasTime && isSoon {
            return "\(day) · \(time(episode.airDate))"
        }
        return day
    }

    /// "S3 E6 · Signal Fire", or "Season 2 premiere".
    static func episodeLine(_ episode: UpcomingEpisode) -> String {
        var line = episode.episodeCode
        if let title = episode.title, !title.isEmpty, !title.lowercased().hasPrefix("episode ") {
            line += " · \(title)"
        } else if episode.isPremiere {
            line = episode.season == 1 ? String(localized: "Series premiere") : String(localized: "Season \(episode.season) premiere")
        }
        if episode.isFinale { line += " · " + String(localized: "Finale") }
        return line
    }

    /// "You're up to date", "2 episodes behind", or nil.
    static func progress(_ episode: UpcomingEpisode) -> String? {
        // Far behind (a long-running show watched now and then): not worth a line.
        guard let behind = episode.episodesBehind, behind <= 20 else { return nil }
        if behind == 0 { return String(localized: "You're up to date") }
        return behind == 1 ? String(localized: "1 episode behind") : String(localized: "\(behind) episodes behind")
    }
}
