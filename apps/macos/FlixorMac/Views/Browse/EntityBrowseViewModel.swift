//
//  EntityBrowseViewModel.swift
//  FlixorMac
//
//  Paged TMDB discover for a production company (movies or TV) or a TV
//  network (TV only), with sort options. Works in Plex and Stremio-only mode
//  (TMDB is always configured).
//

import Foundation
import FlixorKit

@MainActor
final class EntityBrowseViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case loaded
        case empty
        case failed(String)
    }

    enum Sort: String, CaseIterable, Identifiable {
        case popular, topRated, newest
        var id: String { rawValue }
        var title: String {
            switch self {
            case .popular: return "Popular"
            case .topRated: return "Top rated"
            case .newest: return "Newest"
            }
        }
        var tmdbSort: TMDBDiscoverSort {
            switch self {
            case .popular: return .popularity
            case .topRated: return .rating
            case .newest: return .newest
            }
        }
    }

    let route: EntityBrowseRoute

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var details: TMDBCompanyDetails?
    @Published private(set) var items: [MediaItem] = []
    @Published private(set) var totalResults: Int?
    @Published private(set) var isLoadingMore = false
    /// Error while loading a further page; the grid stays, with a retry row.
    @Published private(set) var pagingError: String?

    @Published var mediaType: TMDBDiscoverMediaType {
        didSet { if oldValue != mediaType { reload() } }
    }
    @Published var sort: Sort = .popular {
        didSet { if oldValue != sort { reload() } }
    }

    private var page = 0
    private var totalPages = 1
    private var seenIds = Set<String>()
    private var generation = 0
    private var pageTask: Task<Void, Never>?
    private var hasStarted = false
    /// Companies that mostly make TV (e.g. a TV studio) switch to TV once if
    /// the first movie page comes back empty.
    private var didAutoSwitchMediaType = false

    init(route: EntityBrowseRoute) {
        self.route = route
        self.mediaType = route.kind == .network ? .tv : .movie
    }

    // MARK: - Display

    /// Networks only have TV; companies can toggle.
    var canToggleMediaType: Bool { route.kind == .company }

    var displayName: String {
        if let name = details?.name, !name.isEmpty { return name }
        return route.name
    }

    var logoURL: URL? {
        TMDBImageURL.url(details?.logoPath, size: .w500) ?? TMDBImageURL.url(route.logoPath, size: .w500)
    }

    var subtitle: String {
        var parts: [String] = [route.kind == .network ? "TV network" : "Production company"]
        if let headquarters = details?.headquarters, !headquarters.isEmpty {
            parts.append(headquarters)
        } else if let country = details?.originCountry, !country.isEmpty {
            parts.append(Locale.current.localizedString(forRegionCode: country) ?? country)
        }
        return parts.joined(separator: " · ")
    }

    var countText: String? {
        guard let totalResults, totalResults > 0 else { return nil }
        let noun: String
        switch mediaType {
        case .movie: noun = totalResults == 1 ? "movie" : "movies"
        case .tv: noun = totalResults == 1 ? "show" : "shows"
        }
        return "\(totalResults.formatted()) \(noun)"
    }

    var backdropURL: URL? {
        items.lazy.compactMap { $0.art }.first.flatMap(URL.init(string:))
    }

    var canLoadMore: Bool { page < totalPages && page < 500 }

    // MARK: - Loading

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        loadDetails()
        reload()
    }

    func reload() {
        pageTask?.cancel()
        generation += 1
        page = 0
        totalPages = 1
        totalResults = nil
        seenIds = []
        items = []
        pagingError = nil
        isLoadingMore = false
        phase = .loading
        fetchNextPage()
    }

    /// Call when the item at `index` appears; prefetches well before the end.
    func itemAppeared(at index: Int, prefetchDistance: Int) {
        guard index >= items.count - max(prefetchDistance, 1) else { return }
        loadMore()
    }

    func loadMore() {
        guard phase == .loaded, !isLoadingMore, pagingError == nil, canLoadMore else { return }
        fetchNextPage()
    }

    func retryPaging() {
        pagingError = nil
        loadMore()
    }

    private func loadDetails() {
        let route = self.route
        Task { [weak self] in
            // The header falls back to the route's name and logo if this fails.
            do {
                let details: TMDBCompanyDetails
                switch route.kind {
                case .company: details = try await FlixorCore.shared.tmdb.getCompany(id: route.id)
                case .network: details = try await FlixorCore.shared.tmdb.getNetwork(id: route.id)
                }
                self?.details = details
            } catch {
                return
            }
        }
    }

    private func fetchNextPage() {
        let generation = self.generation
        let nextPage = page + 1
        let route = self.route
        let mediaType = self.mediaType
        let sort = self.sort.tmdbSort
        if nextPage > 1 { isLoadingMore = true }

        pageTask = Task { [weak self] in
            do {
                let response: TMDBResultsResponse
                switch route.kind {
                case .company:
                    response = try await FlixorCore.shared.tmdb.discoverByCompany(
                        companyId: route.id, mediaType: mediaType, sort: sort, page: nextPage
                    )
                case .network:
                    response = try await FlixorCore.shared.tmdb.discoverByNetwork(
                        networkId: route.id, sort: sort, page: nextPage
                    )
                }
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                self.apply(response, page: nextPage, mediaType: mediaType)
            } catch {
                guard let self, self.generation == generation, !Task.isCancelled else { return }
                let message = TMDBErrorMessage.message(for: error, fallback: "Couldn't load titles from TMDB.")
                self.isLoadingMore = false
                if nextPage == 1 {
                    self.phase = .failed(message)
                } else {
                    self.pagingError = message
                }
            }
        }
    }

    private func apply(_ response: TMDBResultsResponse, page: Int, mediaType: TMDBDiscoverMediaType) {
        self.page = page
        totalPages = max(response.totalPages ?? page, page)
        if page == 1 { totalResults = response.totalResults }

        let newItems = response.results
            .map { MediaItem.fromTMDB($0, mediaType: mediaType) }
            .filter { seenIds.insert($0.id).inserted }
        items.append(contentsOf: newItems)
        isLoadingMore = false

        if items.isEmpty {
            if page == 1, canToggleMediaType, mediaType == .movie, !didAutoSwitchMediaType, sort == .popular {
                didAutoSwitchMediaType = true
                self.mediaType = .tv // didSet reloads
                return
            }
            if canLoadMore, page < 3 {
                // Every result on this page was a duplicate; try the next one.
                fetchNextPage()
                return
            }
            phase = .empty
        } else {
            phase = .loaded
        }
    }
}
