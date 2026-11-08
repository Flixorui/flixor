//
//  SearchViewModel.swift
//  FlixorMac
//
//  ViewModel for Search screen with Popular/Trending/Live results
//
//  Live search runs every source (Plex, addon catalogs, TMDB titles, TMDB
//  people) in parallel. Each source publishes on its own, with its own status,
//  so one failing source never blanks the others. A new query cancels the
//  in-flight search immediately; the next search starts after a short debounce.
//

import Foundation
import SwiftUI
import Combine
import FlixorKit

@MainActor
class SearchViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var query: String = ""
    @Published var plexResults: [SearchResult] = []
    /// Matches from the installed Stremio addons' searchable catalogs.
    @Published var stremioResults: [SearchResult] = []
    @Published var tmdbMovies: [SearchResult] = []
    @Published var tmdbShows: [SearchResult] = []
    /// TMDB people matching the query.
    @Published var people: [TMDBPersonSummary] = []
    @Published var genreRows: [GenreRow] = []
    @Published var popularItems: [SearchResult] = []
    @Published var trendingItems: [SearchResult] = []
    @Published var isLoading = false
    @Published var searchMode: SearchMode = .idle
    /// Status of every source for the current query.
    @Published private(set) var sectionStatus: [SearchSection: SectionStatus] = [:]
    /// Recent queries for the active profile, most recent first.
    @Published private(set) var recentSearches: [String] = []
    /// What the screen shows while the query is empty (persisted per profile).
    @Published var idleTab: IdleTab = .explore {
        didSet {
            guard idleTab != oldValue else { return }
            UserDefaults.standard.searchIdleTab = idleTab.rawValue
        }
    }

    enum IdleTab: String, CaseIterable, Identifiable {
        case explore
        case discover

        var id: String { rawValue }

        var label: String {
            switch self {
            case .explore: return String(localized: "Explore")
            case .discover: return String(localized: "Discover")
            }
        }
    }

    enum SearchMode {
        case idle          // Show Popular/Trending
        case searching     // Actively searching
        case results       // Showing results
    }

    /// A source of live search results.
    enum SearchSection: String, CaseIterable, Identifiable {
        case plex, addons, tmdb, people

        var id: String { rawValue }

        /// Shown in the inline error row when the source fails.
        var failureMessage: String {
            switch self {
            case .plex: return String(localized: "Couldn't search your Plex server.")
            case .addons: return String(localized: "Couldn't search your addons.")
            case .tmdb: return String(localized: "Couldn't load movie and TV results.")
            case .people: return String(localized: "Couldn't load people.")
            }
        }

        /// Shown while the source is still loading after others returned.
        var loadingMessage: String {
            switch self {
            case .plex: return String(localized: "Searching your Plex server")
            case .addons: return String(localized: "Searching your addons")
            case .tmdb: return String(localized: "Searching movies and TV")
            case .people: return String(localized: "Searching people")
            }
        }
    }

    enum SectionStatus: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    struct SearchResult: Identifiable, Hashable {
        let id: String
        let title: String
        let type: MediaType
        let imageURL: URL?
        let year: String?
        let overview: String?
        let available: Bool  // true if in Plex library
        let genreIds: [Int]  // TMDB genre IDs
        let editionTitle: String?  // Edition title for Plex items

        enum MediaType: String {
            case movie, tv, collection
        }
    }

    struct GenreRow: Identifiable {
        let id: String
        let title: String
        let items: [SearchResult]
    }

    // TMDB Genre mapping
    static let genreMap: [Int: String] = [
        28: String(localized: "Action"), 12: String(localized: "Adventure"), 16: String(localized: "Animation"), 35: String(localized: "Comedy"), 80: String(localized: "Crime"),
        99: String(localized: "Documentary"), 18: String(localized: "Drama"), 10751: String(localized: "Family"), 14: String(localized: "Fantasy"), 36: String(localized: "History"),
        27: String(localized: "Horror"), 10402: String(localized: "Music"), 9648: String(localized: "Mystery"), 10749: String(localized: "Romance"), 878: "Sci-Fi",
        10770: String(localized: "TV Movie"), 53: String(localized: "Thriller"), 10752: String(localized: "War"), 37: String(localized: "Western"),
        10759: String(localized: "Action & Adventure"), 10762: String(localized: "Kids"), 10763: String(localized: "News"), 10764: String(localized: "Reality"),
        10765: String(localized: "Sci-Fi & Fantasy"), 10766: String(localized: "Soap"), 10767: String(localized: "Talk"), 10768: String(localized: "War & Politics")
    ]

    private let api = APIClient.shared
    private var searchTask: Task<Void, Never>?
    private var saveRecentTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    /// Normalised query of the search that is running or produced the current results.
    private var activeQuery: String?
    /// Incremented for every search; stale callbacks compare against it.
    private var searchGeneration = 0
    /// Genres seen in the TMDB results of the current search.
    private var pendingGenreIds = Set<Int>()
    private var profileScopeToken: String?

    /// Delay after results appear before a typed query counts as "searched".
    private static let recentSaveDelay: Duration = .milliseconds(2500)

    /// Whether to include TMDB results in search (from settings)
    private var includeTmdbInSearch: Bool {
        UserDefaults.standard.includeTmdbInSearch
    }

    init() {
        setupSearchDebouncing()
        refreshProfileScopedState()
    }

    // MARK: - Setup

    private func setupSearchDebouncing() {
        // Every edit: cancel a search that no longer matches the text right away.
        $query
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] newQuery in
                Task { @MainActor in self?.handleQueryEdited(newQuery) }
            }
            .store(in: &cancellables)

        // Debounced (300ms): start the search for the settled text.
        $query
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] newQuery in
                Task { @MainActor in self?.handleDebouncedQuery(newQuery) }
            }
            .store(in: &cancellables)
    }

    static func normalize(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handleQueryEdited(_ newQuery: String) {
        let normalized = Self.normalize(newQuery)
        saveRecentTask?.cancel()
        if normalized.isEmpty {
            cancelSearch()
            resetResults()
            searchMode = .idle
            return
        }
        if normalized != activeQuery {
            cancelSearch()
        }
    }

    private func handleDebouncedQuery(_ newQuery: String) {
        let normalized = Self.normalize(newQuery)
        guard !normalized.isEmpty, normalized != activeQuery else { return }
        startSearch(normalized)
    }

    // MARK: - Profile-scoped state

    /// Reloads recent searches when the active profile changed since the last call.
    /// The Search tab survives profile switches, so the view calls this when shown.
    func refreshProfileScopedState() {
        let token = UserDefaults.standard.searchProfileScopeToken
        guard token != profileScopeToken else { return }
        profileScopeToken = token
        recentSearches = UserDefaults.standard.recentSearches
        idleTab = UserDefaults.standard.searchIdleTab.flatMap(IdleTab.init(rawValue:)) ?? .explore
    }

    // MARK: - Recent Searches

    /// The user pressed Return in the search field.
    func submitSearch() {
        let normalized = Self.normalize(query)
        guard !normalized.isEmpty else { return }
        if normalized != activeQuery {
            startSearch(normalized)
        }
        recordRecentSearch(normalized)
    }

    /// Runs a recent search (also moves it to the top of the list).
    func runRecentSearch(_ text: String) {
        let normalized = Self.normalize(text)
        guard !normalized.isEmpty else { return }
        query = normalized
        startSearch(normalized)
        recordRecentSearch(normalized)
    }

    /// The user opened a result for the current query, so it counts as searched.
    func commitCurrentQuery() {
        let normalized = Self.normalize(query)
        guard !normalized.isEmpty else { return }
        saveRecentTask?.cancel()
        recordRecentSearch(normalized)
    }

    func removeRecentSearch(_ text: String) {
        recentSearches.removeAll { $0.caseInsensitiveCompare(text) == .orderedSame }
        UserDefaults.standard.recentSearches = recentSearches
    }

    func clearRecentSearches() {
        recentSearches = []
        UserDefaults.standard.recentSearches = []
    }

    private func recordRecentSearch(_ text: String) {
        var list = recentSearches.filter { $0.caseInsensitiveCompare(text) != .orderedSame }
        list.insert(text, at: 0)
        list = Array(list.prefix(UserDefaults.recentSearchesLimit))
        guard list != recentSearches else { return }
        recentSearches = list
        UserDefaults.standard.recentSearches = list
    }

    /// Saves a typed query once the user paused on its results.
    private func scheduleRecentSave(for text: String) {
        saveRecentTask?.cancel()
        guard text.count >= 2, hasResults else { return }
        saveRecentTask = Task { [weak self] in
            try? await Task.sleep(for: Self.recentSaveDelay)
            guard let self, !Task.isCancelled,
                  self.activeQuery == text,
                  Self.normalize(self.query) == text else { return }
            self.recordRecentSearch(text)
        }
    }

    // MARK: - Load Initial Content

    func loadInitialContent() async {
        // Only load TMDB content if the setting is enabled
        guard includeTmdbInSearch else {
            popularItems = []
            trendingItems = []
            return
        }

        await withTaskGroup(of: Void.self) { group in
            // Load popular items
            group.addTask { await self.loadPopularItems() }
            // Load trending items
            group.addTask { await self.loadTrendingItems() }
        }
    }

    private func loadPopularItems() async {
        do {
            // Fetch popular movies and TV shows from TMDB
            struct PopularResponse: Codable {
                let results: [PopularItem]
            }
            struct PopularItem: Codable {
                let id: Int
                let title: String?
                let name: String?
                let backdrop_path: String?
                let poster_path: String?
                let release_date: String?
                let first_air_date: String?
            }

            async let movies: PopularResponse = api.get("/api/tmdb/movie/popular")
            async let shows: PopularResponse = api.get("/api/tmdb/tv/popular")

            let (movieResults, showResults) = try await (movies, shows)

            var popular: [SearchResult] = []

            // Add popular movies (first 6)
            for item in movieResults.results.prefix(6) {
                let imageURL = ImageService.shared.proxyImageURL(
                    url: item.backdrop_path.flatMap { "https://image.tmdb.org/t/p/w780\($0)" }
                ) ?? ImageService.shared.proxyImageURL(
                    url: item.poster_path.flatMap { "https://image.tmdb.org/t/p/w500\($0)" }
                )

                popular.append(SearchResult(
                    id: "tmdb:movie:\(item.id)",
                    title: item.title ?? "",
                    type: .movie,
                    imageURL: imageURL,
                    year: item.release_date?.prefix(4).description,
                    overview: nil,
                    available: false,
                    genreIds: [],
                editionTitle: nil
                ))
            }

            // Add popular TV shows (first 6)
            for item in showResults.results.prefix(6) {
                let imageURL = ImageService.shared.proxyImageURL(
                    url: item.backdrop_path.flatMap { "https://image.tmdb.org/t/p/w780\($0)" }
                ) ?? ImageService.shared.proxyImageURL(
                    url: item.poster_path.flatMap { "https://image.tmdb.org/t/p/w500\($0)" }
                )

                popular.append(SearchResult(
                    id: "tmdb:tv:\(item.id)",
                    title: item.name ?? "",
                    type: .tv,
                    imageURL: imageURL,
                    year: item.first_air_date?.prefix(4).description,
                    overview: nil,
                    available: false,
                    genreIds: [],
                editionTitle: nil
                ))
            }

            self.popularItems = Array(popular.prefix(10))
            print("📊 [Search] Loaded \(self.popularItems.count) popular items")
        } catch {
            print("❌ [Search] Failed to load popular items: \(error)")
        }
    }

    private func loadTrendingItems() async {
        do {
            // Fetch trending movies and shows separately, then interleave for variety
            struct TrendingResponse: Codable {
                let results: [TrendingItem]
            }
            struct TrendingItem: Codable {
                let id: Int
                let title: String?
                let name: String?
                let release_date: String?
                let first_air_date: String?
            }

            async let moviesRes: TrendingResponse = api.get("/api/tmdb/trending/movie/week")
            async let showsRes: TrendingResponse = api.get("/api/tmdb/trending/tv/week")

            let (movieResults, showResults) = try await (moviesRes, showsRes)

            // Fetch backdrop images with non-null iso_639_1 in parallel
            let movies: [SearchResult] = await withTaskGroup(of: SearchResult?.self) { group in
                for item in movieResults.results.prefix(6) {
                    group.addTask {
                        let imageURL = try? await self.fetchTMDBBackdropURL(mediaType: "movie", id: item.id, width: 780, height: 439)
                        return SearchResult(
                            id: "tmdb:movie:\(item.id)",
                            title: item.title ?? "",
                            type: .movie,
                            imageURL: imageURL,
                            year: item.release_date?.prefix(4).description,
                            overview: nil,
                            available: false,
                            genreIds: [],
                        editionTitle: nil
                        )
                    }
                }
                var results: [SearchResult] = []
                for await result in group {
                    if let result = result {
                        results.append(result)
                    }
                }
                return results
            }

            let shows: [SearchResult] = await withTaskGroup(of: SearchResult?.self) { group in
                for item in showResults.results.prefix(6) {
                    group.addTask {
                        let imageURL = try? await self.fetchTMDBBackdropURL(mediaType: "tv", id: item.id, width: 780, height: 439)
                        return SearchResult(
                            id: "tmdb:tv:\(item.id)",
                            title: item.name ?? "",
                            type: .tv,
                            imageURL: imageURL,
                            year: item.first_air_date?.prefix(4).description,
                            overview: nil,
                            available: false,
                            genreIds: [],
                        editionTitle: nil
                        )
                    }
                }
                var results: [SearchResult] = []
                for await result in group {
                    if let result = result {
                        results.append(result)
                    }
                }
                return results
            }

            // Interleave shows and movies for variety
            var combined: [SearchResult] = []
            for i in 0..<max(movies.count, shows.count) {
                if i < shows.count { combined.append(shows[i]) }
                if i < movies.count { combined.append(movies[i]) }
            }

            self.trendingItems = combined
            print("🔥 [Search] Loaded \(self.trendingItems.count) trending items")
        } catch {
            print("❌ [Search] Failed to load trending items: \(error)")
        }
    }

    // MARK: - TMDB Backdrop Helper

    private func fetchTMDBBackdropURL(mediaType: String, id: Int, width: Int, height: Int) async throws -> URL? {
        struct TMDBImages: Codable { let backdrops: [TMDBImage]? }
        struct TMDBImage: Codable { let file_path: String?; let iso_639_1: String?; let vote_average: Double? }

        let imgs: TMDBImages = try await api.get("/api/tmdb/\(mediaType)/\(id)/images", queryItems: [URLQueryItem(name: "include_image_language", value: "en,null")])
        let backdrops = imgs.backdrops ?? []
        if backdrops.isEmpty { return nil }

        let pick: ([TMDBImage]) -> TMDBImage? = { arr in
            return arr.sorted { ($0.vote_average ?? 0) > ($1.vote_average ?? 0) }.first
        }

        // Priority 1: English backdrops (with title text burned in)
        if let en = pick(backdrops.filter { $0.iso_639_1 == "en" }), let path = en.file_path {
            return ImageService.shared.proxyImageURL(url: "https://image.tmdb.org/t/p/original\(path)", width: width, height: height)
        }

        // Priority 2: Any language with title (iso_639_1 is not null)
        if let withLang = pick(backdrops.filter { $0.iso_639_1 != nil }), let path = withLang.file_path {
            return ImageService.shared.proxyImageURL(url: "https://image.tmdb.org/t/p/original\(path)", width: width, height: height)
        }

        // Priority 3: Fallback to any backdrop (including textless)
        guard let any = pick(backdrops), let path = any.file_path else { return nil }
        return ImageService.shared.proxyImageURL(url: "https://image.tmdb.org/t/p/original\(path)", width: width, height: height)
    }

    // MARK: - Search

    /// True when any source returned something for the current query.
    var hasResults: Bool {
        !plexResults.isEmpty || !stremioResults.isEmpty ||
        !tmdbMovies.isEmpty || !tmdbShows.isEmpty || !people.isEmpty
    }

    /// Sources that failed for the current query.
    var failedSections: [SearchSection] {
        SearchSection.allCases.filter {
            if case .failed = sectionStatus[$0] { return true }
            return false
        }
    }

    /// Sources still loading for the current query.
    var loadingSections: [SearchSection] {
        SearchSection.allCases.filter { sectionStatus[$0] == .loading }
    }

    /// The top TMDB person matches the query by name, so People goes first.
    var peopleMatchQuery: Bool {
        guard let first = people.first, let active = activeQuery else { return false }
        return first.name.compare(active, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    private func enabledSections() -> [SearchSection] {
        var sections: [SearchSection] = []
        if !AppModeStore.shared.isStremioOnly { sections.append(.plex) }
        if UserDefaults.standard.stremioCatalogSearchEnabled { sections.append(.addons) }
        if includeTmdbInSearch {
            sections.append(.tmdb)
            sections.append(.people)
        }
        return sections
    }

    private func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        activeQuery = nil
        isLoading = false
    }

    private func resetResults() {
        plexResults = []
        stremioResults = []
        tmdbMovies = []
        tmdbShows = []
        people = []
        genreRows = []
        pendingGenreIds = []
        sectionStatus = [:]
    }

    private func startSearch(_ query: String) {
        searchTask?.cancel()
        saveRecentTask?.cancel()
        activeQuery = query
        searchGeneration += 1
        let generation = searchGeneration

        resetResults()
        let sections = enabledSections()
        for section in sections { sectionStatus[section] = .loading }
        guard !sections.isEmpty else {
            searchMode = .results
            return
        }
        searchMode = .searching
        isLoading = true

        print("🔍 [Search] Searching for: \(query)")

        searchTask = Task { [weak self] in
            guard let self else { return }
            await withTaskGroup(of: SectionOutcome.self) { group in
                for section in sections {
                    group.addTask { await self.fetch(section, query: query) }
                }
                for await outcome in group {
                    guard !Task.isCancelled, generation == self.searchGeneration else {
                        group.cancelAll()
                        break
                    }
                    self.apply(outcome)
                }
            }

            guard !Task.isCancelled, generation == self.searchGeneration else { return }
            self.isLoading = false
            self.searchMode = .results
            self.scheduleRecentSave(for: query)

            print("✅ [Search] Found \(self.plexResults.count) Plex, \(self.stremioResults.count) Stremio, \(self.tmdbMovies.count) TMDB movies, \(self.tmdbShows.count) TMDB shows, \(self.people.count) people")

            // Genre-based recommendations (top 3 genres) - only if TMDB is enabled
            if self.includeTmdbInSearch && !self.pendingGenreIds.isEmpty {
                let rows = await self.loadGenreRecommendations(genreIds: Array(self.pendingGenreIds).prefix(3))
                guard !Task.isCancelled, generation == self.searchGeneration else { return }
                self.genreRows = rows
            }
        }
    }

    /// Retries one failed source for the current query.
    func retry(_ section: SearchSection) {
        guard let query = activeQuery else { return }
        let generation = searchGeneration
        sectionStatus[section] = .loading
        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.fetch(section, query: query)
            guard generation == self.searchGeneration else { return }
            self.apply(outcome)
        }
    }

    private enum SectionOutcome {
        case plex(Result<[SearchResult], Error>)
        case addons([SearchResult])
        case tmdb(Result<TMDBTitleResults, Error>)
        case people(Result<[TMDBPersonSummary], Error>)
    }

    private struct TMDBTitleResults {
        let movies: [SearchResult]
        let shows: [SearchResult]
        let genreIds: Set<Int>
    }

    private func fetch(_ section: SearchSection, query: String) async -> SectionOutcome {
        switch section {
        case .plex:
            return .plex(await capture { try await self.searchPlexSection(query: query) })
        case .addons:
            return .addons(await searchStremioCatalogs(query: query))
        case .tmdb:
            return .tmdb(await capture { try await self.searchTMDBSeparate(query: query) })
        case .people:
            return .people(await capture { try await self.searchPeople(query: query) })
        }
    }

    private func apply(_ outcome: SectionOutcome) {
        switch outcome {
        case .plex(let result):
            switch result {
            case .success(let items):
                plexResults = items
                sectionStatus[.plex] = .loaded
            case .failure(let error):
                print("❌ [Search] Plex search failed: \(error)")
                sectionStatus[.plex] = .failed(SearchSection.plex.failureMessage)
            }
        case .addons(let items):
            stremioResults = items
            sectionStatus[.addons] = .loaded
        case .tmdb(let result):
            switch result {
            case .success(let titles):
                tmdbMovies = titles.movies
                tmdbShows = titles.shows
                pendingGenreIds = titles.genreIds
                sectionStatus[.tmdb] = .loaded
            case .failure(let error):
                print("❌ [Search] TMDB search failed: \(error)")
                sectionStatus[.tmdb] = .failed(SearchSection.tmdb.failureMessage)
            }
        case .people(let result):
            switch result {
            case .success(let found):
                people = found
                sectionStatus[.people] = .loaded
            case .failure(let error):
                print("❌ [Search] People search failed: \(error)")
                sectionStatus[.people] = .failed(SearchSection.people.failureMessage)
            }
        }
        // Show results as soon as one source has something.
        if searchMode == .searching && hasResults {
            searchMode = .results
        }
    }

    private func capture<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }

    /// Movies and shows from Plex. Fails only when both lookups fail.
    private func searchPlexSection(query: String) async throws -> [SearchResult] {
        async let movies = capture { try await self.searchPlex(query: query, type: 1) }
        async let shows = capture { try await self.searchPlex(query: query, type: 2) }
        let (movieResult, showResult) = await (movies, shows)
        if case .failure(let error) = movieResult, case .failure = showResult {
            throw error
        }
        return ((try? movieResult.get()) ?? []) + ((try? showResult.get()) ?? [])
    }

    /// TMDB people for the query: the ones with a photo or known titles, best first.
    private func searchPeople(query: String) async throws -> [TMDBPersonSummary] {
        let response = try await FlixorCore.shared.tmdb.searchPeople(query: query)
        return response.results
            .filter { $0.profilePath != nil || !($0.knownFor ?? []).isEmpty }
            .prefix(20)
            .map { $0 }
    }

    /// Searches every search-capable addon catalog and maps hits into SearchResults.
    /// Ids come back as `tmdb:` where TMDB could match, so tapping a result opens the
    /// normal details screen.
    private func searchStremioCatalogs(query: String) async -> [SearchResult] {
        let previews = await StremioService.shared.searchCatalogs(query: query)
        guard !previews.isEmpty else { return [] }

        let items = await StremioCatalogMapper.shared.mediaItems(from: previews)
        return items.map { item in
            SearchResult(
                id: item.id,
                title: item.title,
                type: item.type == "movie" ? .movie : .tv,
                imageURL: item.thumb.flatMap { URL(string: $0) },
                year: item.year.map(String.init),
                overview: item.summary,
                available: false,
                genreIds: [],
                editionTitle: nil
            )
        }
    }

    private func searchPlex(query: String, type: Int) async throws -> [SearchResult] {
        do {
            // type: 1 = movies, 2 = tv shows
            let response: [PlexSearchItem] = try await api.get(
                "/api/plex/search",
                queryItems: [
                    URLQueryItem(name: "query", value: query),
                    URLQueryItem(name: "type", value: String(type))
                ]
            )

            // Fetch TMDB images for all items in parallel
            let items = response.prefix(20)
            return await withTaskGroup(of: (String, SearchResult).self) { group in
                for item in items {
                    // Extract edition before entering task group (since extractEditionTitle is on self)
                    let edition = self.extractEditionTitle(from: item.Media)
                    group.addTask {
                        let ratingKey = item.ratingKey

                        // Try to get TMDB backdrop
                        var imageURL: URL? = nil
                        do {
                            struct TMDBMatchResponse: Codable {
                                let tmdbId: String?
                                let backdropUrl: String?
                            }

                            let tmdbMatch: TMDBMatchResponse = try await self.api.get(
                                "/api/plex/tmdb-match",
                                queryItems: [URLQueryItem(name: "ratingKey", value: ratingKey)]
                            )

                            if let backdropUrl = tmdbMatch.backdropUrl {
                                imageURL = await ImageService.shared.proxyImageURL(url: backdropUrl)
                            }
                        } catch {
                            // Silently fail - will use Plex image
                        }

                        // Fallback to Plex image if no TMDB image
                        if imageURL == nil {
                            let fallbackPath = item.art ?? item.thumb ?? item.parentThumb ?? item.grandparentThumb ?? ""
                            imageURL = await ImageService.shared.plexImageURL(path: fallbackPath, width: 780, height: 439)
                        }

                        let result = SearchResult(
                            id: "plex:\(ratingKey)",
                            title: item.title ?? "",
                            type: type == 1 ? .movie : .tv,
                            imageURL: imageURL,
                            year: item.year.map(String.init),
                            overview: item.summary,
                            available: true,
                            genreIds: [],
                            editionTitle: edition
                        )

                        return (ratingKey, result)
                    }
                }

                var results: [(String, SearchResult)] = []
                for await result in group {
                    results.append(result)
                }

                // Preserve original order
                let resultMap = Dictionary(results, uniquingKeysWith: { first, _ in first })
                return items.compactMap { resultMap[$0.ratingKey] }
            }
        } catch {
            print("❌ [Search] Plex search failed (type=\(type)): \(error)")
            throw error
        }
    }

    private func searchTMDBSeparate(query: String) async throws -> TMDBTitleResults {
        do {
            struct TMDBSearchResponse: Codable {
                let results: [TMDBSearchItem]
            }
            struct TMDBSearchItem: Codable {
                let id: Int
                let title: String?
                let name: String?
                let media_type: String
                let backdrop_path: String?
                let poster_path: String?
                let release_date: String?
                let first_air_date: String?
                let overview: String?
                let genre_ids: [Int]?
            }

            let response: TMDBSearchResponse = try await api.get(
                "/api/tmdb/search/multi",
                queryItems: [URLQueryItem(name: "query", value: query)]
            )

            var movies: [SearchResult] = []
            var shows: [SearchResult] = []
            var allGenreIds = Set<Int>()

            for item in response.results.prefix(20) {
                let genreIds = item.genre_ids ?? []
                genreIds.forEach { allGenreIds.insert($0) }

                let imageURL = ImageService.shared.proxyImageURL(
                    url: item.poster_path.flatMap { "https://image.tmdb.org/t/p/w500\($0)" }
                ) ?? ImageService.shared.proxyImageURL(
                    url: item.backdrop_path.flatMap { "https://image.tmdb.org/t/p/w780\($0)" }
                )

                let result = SearchResult(
                    id: "tmdb:\(item.media_type):\(item.id)",
                    title: item.title ?? item.name ?? "",
                    type: item.media_type == "movie" ? .movie : .tv,
                    imageURL: imageURL,
                    year: (item.release_date ?? item.first_air_date)?.prefix(4).description,
                    overview: item.overview,
                    available: false,
                    genreIds: genreIds,
                    editionTitle: nil
                )

                if item.media_type == "movie" {
                    movies.append(result)
                } else if item.media_type == "tv" {
                    shows.append(result)
                }
            }

            return TMDBTitleResults(movies: movies, shows: shows, genreIds: allGenreIds)
        }
    }

    private func loadGenreRecommendations(genreIds: ArraySlice<Int>) async -> [GenreRow] {
        var genreRowsData: [GenreRow] = []

        for genreId in genreIds {
            guard let genreName = Self.genreMap[genreId] else { continue }

            do {
                // Fetch movies and TV shows for this genre in parallel
                struct DiscoverResponse: Codable {
                    let results: [DiscoverItem]
                }
                struct DiscoverItem: Codable {
                    let id: Int
                    let title: String?
                    let name: String?
                    let poster_path: String?
                    let release_date: String?
                    let first_air_date: String?
                }

                async let movieRes: DiscoverResponse = api.get(
                    "/api/tmdb/discover/movie",
                    queryItems: [
                        URLQueryItem(name: "with_genres", value: String(genreId)),
                        URLQueryItem(name: "sort_by", value: "popularity.desc"),
                        URLQueryItem(name: "page", value: "1")
                    ]
                )

                async let tvRes: DiscoverResponse = api.get(
                    "/api/tmdb/discover/tv",
                    queryItems: [
                        URLQueryItem(name: "with_genres", value: String(genreId)),
                        URLQueryItem(name: "sort_by", value: "popularity.desc"),
                        URLQueryItem(name: "page", value: "1")
                    ]
                )

                let (movieResults, tvResults) = try await (movieRes, tvRes)

                let movies: [SearchResult] = movieResults.results.prefix(10).map { item in
                    let imageURL = ImageService.shared.proxyImageURL(
                        url: item.poster_path.flatMap { "https://image.tmdb.org/t/p/w500\($0)" }
                    )
                    return SearchResult(
                        id: "tmdb:movie:\(item.id)",
                        title: item.title ?? "",
                        type: .movie,
                        imageURL: imageURL,
                        year: item.release_date?.prefix(4).description,
                        overview: nil,
                        available: false,
                        genreIds: [genreId],
                        editionTitle: nil
                    )
                }

                let shows: [SearchResult] = tvResults.results.prefix(10).map { item in
                    let imageURL = ImageService.shared.proxyImageURL(
                        url: item.poster_path.flatMap { "https://image.tmdb.org/t/p/w500\($0)" }
                    )
                    return SearchResult(
                        id: "tmdb:tv:\(item.id)",
                        title: item.name ?? "",
                        type: .tv,
                        imageURL: imageURL,
                        year: item.first_air_date?.prefix(4).description,
                        overview: nil,
                        available: false,
                        genreIds: [genreId],
                        editionTitle: nil
                    )
                }

                // Combine movies and shows (up to 15 items)
                let combined = Array((movies + shows).prefix(15))

                if !combined.isEmpty {
                    genreRowsData.append(GenreRow(
                        id: "genre:\(genreId)",
                        title: genreName,
                        items: combined
                    ))
                }

                print("🎬 [Search] Loaded \(combined.count) items for genre '\(genreName)'")
            } catch {
                print("❌ [Search] Failed to fetch genre '\(genreName)': \(error)")
            }
        }

        return genreRowsData
    }

    // MARK: - Helper Structs

    private struct PlexSearchItem: Codable {
        let ratingKey: String
        let title: String?
        let year: Int?
        let summary: String?
        let art: String?
        let thumb: String?
        let parentThumb: String?
        let grandparentThumb: String?
        let Media: [PlexSearchMedia]?
    }

    private struct PlexSearchMedia: Codable {
        let editionTitle: String?
        let Part: [PlexSearchPart]?
    }

    private struct PlexSearchPart: Codable {
        let file: String?
    }

    /// Extract edition title from Media array (explicit editionTitle or parsed from filename)
    private func extractEditionTitle(from media: [PlexSearchMedia]?) -> String? {
        guard let first = media?.first else { return nil }
        // Priority 1: Use explicit editionTitle from API
        if let edition = first.editionTitle, !edition.isEmpty {
            return edition
        }
        // Priority 2: Parse from filename {edition-XXX} pattern
        if let filePath = first.Part?.first?.file {
            if let match = filePath.range(of: #"\{edition-([^}]+)\}"#, options: .regularExpression) {
                let fullMatch = String(filePath[match])
                // Extract the edition name between {edition- and }
                let start = fullMatch.index(fullMatch.startIndex, offsetBy: 9) // "{edition-".count
                let end = fullMatch.index(fullMatch.endIndex, offsetBy: -1) // remove "}"
                return String(fullMatch[start..<end])
            }
        }
        return nil
    }
}
