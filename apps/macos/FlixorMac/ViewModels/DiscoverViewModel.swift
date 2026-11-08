//
//  DiscoverViewModel.swift
//  FlixorMac
//
//  Discover mode of the Search screen: TMDB discover with type, genre, sort,
//  year range and minimum rating filters, paged for an infinite poster grid.
//  Filters persist per profile.
//

import Foundation
import SwiftUI
import FlixorKit

// MARK: - Filter model

enum DiscoverMediaType: String, Codable, CaseIterable, Identifiable {
    case movie
    case tv

    var id: String { rawValue }

    var label: String {
        switch self {
        case .movie: return String(localized: "Movies")
        case .tv: return String(localized: "TV Shows")
        }
    }

    var tmdb: TMDBDiscoverMediaType {
        switch self {
        case .movie: return .movie
        case .tv: return .tv
        }
    }
}

enum DiscoverSortOption: String, Codable, CaseIterable, Identifiable {
    case popular
    case topRated
    case newest
    case oldest
    case title

    var id: String { rawValue }

    var label: String {
        switch self {
        case .popular: return String(localized: "Popular")
        case .topRated: return String(localized: "Top Rated")
        case .newest: return String(localized: "Newest")
        case .oldest: return String(localized: "Oldest")
        case .title: return String(localized: "Title (A-Z)")
        }
    }
}

struct DiscoverGenre: Identifiable, Hashable {
    let id: Int
    let name: String
}

struct DiscoverFilters: Codable, Equatable {
    var mediaType: DiscoverMediaType = .movie
    var genreId: Int?
    /// Kept with the id so the chip has a label before the genre list loads.
    var genreName: String?
    var sort: DiscoverSortOption = .popular
    var yearFrom: Int?
    var yearTo: Int?
    var minimumRating: Double?

    static let `default` = DiscoverFilters()

    init() {}

    init(from decoder: Decoder) throws {
        // Tolerant decoding: unknown or missing values fall back to defaults.
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mediaType = (try? container.decodeIfPresent(DiscoverMediaType.self, forKey: .mediaType)) ?? .movie
        genreId = try? container.decodeIfPresent(Int.self, forKey: .genreId)
        genreName = try? container.decodeIfPresent(String.self, forKey: .genreName)
        sort = (try? container.decodeIfPresent(DiscoverSortOption.self, forKey: .sort)) ?? .popular
        yearFrom = try? container.decodeIfPresent(Int.self, forKey: .yearFrom)
        yearTo = try? container.decodeIfPresent(Int.self, forKey: .yearTo)
        minimumRating = try? container.decodeIfPresent(Double.self, forKey: .minimumRating)
        normalize()
    }

    /// True when nothing but the media type differs from the defaults.
    var hasActiveFilters: Bool {
        genreId != nil || sort != .popular || yearFrom != nil || yearTo != nil || minimumRating != nil
    }

    /// Keeps the year range ordered.
    mutating func normalize() {
        if let from = yearFrom, let to = yearTo, from > to {
            yearFrom = to
            yearTo = from
        }
    }

    /// TMDB discover query for one page.
    func query(page: Int) -> TMDBDiscoverQuery {
        var query = TMDBDiscoverQuery(
            mediaType: mediaType.tmdb,
            page: page,
            genreIds: genreId.map { [$0] } ?? [],
            yearFrom: yearFrom,
            yearTo: yearTo,
            minimumRating: minimumRating
        )
        // Minimum vote counts keep unrated placeholders out of the less
        // popularity-driven orders.
        var minimumVotes: Int?
        switch sort {
        case .popular:
            query.sort = .popularity
        case .topRated:
            query.sort = .rating // FlixorKit applies 200 votes by default
        case .newest:
            query.sort = .newest
        case .oldest:
            query.sort = .oldest
            minimumVotes = 50
        case .title:
            query.sort = .popularity
            query.sortByOverride = mediaType == .movie ? "title.asc" : "name.asc"
            minimumVotes = 100
        }
        if minimumRating != nil {
            minimumVotes = max(minimumVotes ?? 0, 50)
        }
        if let minimumVotes {
            query.minimumVoteCount = max(minimumVotes, sort == .topRated ? 200 : 0)
        }
        return query
    }

    /// Short label for the year chip.
    var yearLabel: String {
        switch (yearFrom, yearTo) {
        case (nil, nil): return String(localized: "Any")
        case let (from?, to?) where from == to: return String(from)
        case let (from?, to?): return "\(from)-\(to)"
        case let (from?, nil): return "\(from)+"
        case let (nil, to?): return String(localized: "Before \(String(to + 1))")
        }
    }

    var ratingLabel: String {
        guard let minimumRating else { return String(localized: "Any") }
        return "\(Int(minimumRating))+"
    }
}

// MARK: - View model

@MainActor
final class DiscoverViewModel: ObservableObject {
    @Published private(set) var filters: DiscoverFilters
    @Published private(set) var items: [SearchViewModel.SearchResult] = []
    @Published private(set) var genres: [DiscoverGenre] = []
    /// Loading the first page.
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    /// First page failed.
    @Published private(set) var errorMessage: String?
    /// A later page failed; the grid keeps what it has.
    @Published private(set) var loadMoreFailed = false
    @Published private(set) var hasMore = false

    static let ratingOptions: [Double] = [5, 6, 7, 8]
    static let earliestYear = 1900

    static var currentYear: Int {
        Calendar(identifier: .gregorian).component(.year, from: Date())
    }

    private var page = 0
    private var loadTask: Task<Void, Never>?
    private var genreCache: [DiscoverMediaType: [DiscoverGenre]] = [:]
    private var genreLoading: Set<DiscoverMediaType> = []
    private var seenIds = Set<String>()
    private var generation = 0
    private var hasActivated = false
    private var profileScopeToken: String

    init() {
        filters = UserDefaults.standard.searchDiscoverFilters ?? .default
        profileScopeToken = UserDefaults.standard.searchProfileScopeToken
    }

    // MARK: Lifecycle

    /// Called when Discover becomes visible. Loads the first page once.
    func activate() {
        refreshProfileScopedState()
        loadGenres(for: filters.mediaType)
        guard !hasActivated else { return }
        hasActivated = true
        reload()
    }

    /// Picks up the active profile's filters after a profile switch.
    func refreshProfileScopedState() {
        let token = UserDefaults.standard.searchProfileScopeToken
        guard token != profileScopeToken else { return }
        profileScopeToken = token
        filters = UserDefaults.standard.searchDiscoverFilters ?? .default
        genres = genreCache[filters.mediaType] ?? []
        if hasActivated {
            reload()
        }
    }

    // MARK: Filters

    func setMediaType(_ type: DiscoverMediaType) {
        update { filters in
            filters.mediaType = type
            // Movie and TV genre ids differ; keep the genre only if it exists for both.
            if let cached = self.genreCache[type], let id = filters.genreId,
               !cached.contains(where: { $0.id == id }) {
                filters.genreId = nil
                filters.genreName = nil
            }
        }
        loadGenres(for: type)
    }

    func setGenre(_ genre: DiscoverGenre?) {
        update {
            $0.genreId = genre?.id
            $0.genreName = genre?.name
        }
    }

    func setSort(_ sort: DiscoverSortOption) {
        update { $0.sort = sort }
    }

    func setYears(from: Int?, to: Int?) {
        update {
            $0.yearFrom = from
            $0.yearTo = to
        }
    }

    func setMinimumRating(_ rating: Double?) {
        update { $0.minimumRating = rating }
    }

    /// Clears every filter except the media type.
    func resetFilters() {
        update { filters in
            let type = filters.mediaType
            filters = .default
            filters.mediaType = type
        }
    }

    private func update(_ change: (inout DiscoverFilters) -> Void) {
        var newFilters = filters
        change(&newFilters)
        newFilters.normalize()
        guard newFilters != filters else { return }
        filters = newFilters
        UserDefaults.standard.searchDiscoverFilters = newFilters
        genres = genreCache[newFilters.mediaType] ?? []
        reload()
    }

    // MARK: Genres

    private func loadGenres(for type: DiscoverMediaType) {
        if let cached = genreCache[type] {
            if type == filters.mediaType {
                genres = cached
                validateGenre()
            }
            return
        }
        guard !genreLoading.contains(type) else { return }
        genreLoading.insert(type)
        Task { [weak self] in
            do {
                let list = try await FlixorCore.shared.tmdb.getGenres(mediaType: type.tmdb)
                guard let self else { return }
                self.genreLoading.remove(type)
                let mapped = list
                    .map { DiscoverGenre(id: $0.id, name: $0.name) }
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                self.genreCache[type] = mapped
                if type == self.filters.mediaType {
                    self.genres = mapped
                    self.validateGenre()
                }
            } catch {
                self?.genreLoading.remove(type)
                print("❌ [Discover] Failed to load \(type.rawValue) genres: \(error)")
            }
        }
    }

    /// Drops a saved genre that doesn't exist for the current media type.
    private func validateGenre() {
        guard let id = filters.genreId, !genres.isEmpty else { return }
        if let match = genres.first(where: { $0.id == id }) {
            if filters.genreName != match.name {
                filters.genreName = match.name
                UserDefaults.standard.searchDiscoverFilters = filters
            }
        } else {
            setGenre(nil)
        }
    }

    // MARK: Paging

    func reload() {
        loadTask?.cancel()
        generation += 1
        let currentGeneration = generation
        items = []
        seenIds = []
        page = 0
        hasMore = false
        errorMessage = nil
        loadMoreFailed = false
        isLoadingMore = false
        isLoading = true
        loadTask = Task { [weak self] in
            await self?.fetch(page: 1, generation: currentGeneration)
        }
    }

    /// Loads the next page if there is one and nothing is loading.
    func loadMore() {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        isLoadingMore = true
        loadMoreFailed = false
        let currentGeneration = generation
        let next = page + 1
        loadTask = Task { [weak self] in
            await self?.fetch(page: next, generation: currentGeneration)
        }
    }

    /// Retries whatever failed (first page or the next page).
    func retry() {
        if items.isEmpty {
            reload()
        } else {
            loadMoreFailed = false
            loadMore()
        }
    }

    private func fetch(page startPage: Int, generation currentGeneration: Int) async {
        let currentFilters = filters
        var nextPage = startPage
        // A page can be all duplicates or poster-less titles; then fetch the
        // next one too (bounded) so the grid's paging trigger keeps working.
        for _ in 0..<3 {
            do {
                let response = try await FlixorCore.shared.tmdb.discover(currentFilters.query(page: nextPage))
                guard !Task.isCancelled, currentGeneration == generation else { return }

                let mapped = response.results
                    .compactMap { Self.result(from: $0, type: currentFilters.mediaType) }
                    .filter { seenIds.insert($0.id).inserted }
                items.append(contentsOf: mapped)
                page = nextPage
                let totalPages = min(response.totalPages ?? nextPage, 500)
                hasMore = nextPage < totalPages && !response.results.isEmpty

                if mapped.isEmpty && hasMore {
                    nextPage += 1
                    continue
                }
                break
            } catch {
                guard !Task.isCancelled, currentGeneration == generation else { return }
                print("❌ [Discover] Page \(nextPage) failed: \(error)")
                if items.isEmpty {
                    errorMessage = String(localized: "Couldn't load titles. Check your connection and try again.")
                } else {
                    loadMoreFailed = true
                }
                break
            }
        }
        guard currentGeneration == generation else { return }
        isLoading = false
        isLoadingMore = false
    }

    private static func result(from media: TMDBMedia, type: DiscoverMediaType) -> SearchViewModel.SearchResult? {
        guard let posterPath = media.posterPath, !posterPath.isEmpty else { return nil }
        let title = media.title ?? media.name ?? ""
        guard !title.isEmpty else { return nil }
        let date = type == .movie ? media.releaseDate : media.firstAirDate
        return SearchViewModel.SearchResult(
            id: "tmdb:\(type.rawValue):\(media.id)",
            title: title,
            type: type == .movie ? .movie : .tv,
            imageURL: ImageService.shared.proxyImageURL(url: "https://image.tmdb.org/t/p/w500\(posterPath)"),
            year: date.flatMap { $0.count >= 4 ? String($0.prefix(4)) : nil },
            overview: media.overview,
            available: false,
            genreIds: media.genreIds ?? [],
            editionTitle: nil
        )
    }
}
