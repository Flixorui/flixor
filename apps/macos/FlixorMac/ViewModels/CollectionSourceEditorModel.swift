//
//  CollectionSourceEditorModel.swift
//  FlixorMac
//
//  State for adding or editing one collection source. Requests only follow user
//  input: typing in a search field (debounced) or pressing Preview.
//

import Foundation
import FlixorKit

@MainActor
final class CollectionSourceEditorModel: ObservableObject {
    typealias Template = UserCollectionSource.Template
    typealias Kind = UserCollectionSource.Kind

    enum PreviewState {
        case idle
        case loading
        case loaded(items: [MediaItem], hasMore: Bool)
        case empty
        case failed(String)
    }

    /// Well-known TV networks. TMDB has no network search, so these are listed.
    static let networks: [(id: Int, name: String)] = [
        (213, "Netflix"), (1024, "Prime Video"), (2739, "Disney+"), (2552, "Apple TV+"),
        (453, "Hulu"), (3186, "HBO Max"), (49, "HBO"), (4330, "Paramount+"), (3353, "Peacock"),
        (67, "Showtime"), (318, "Starz"), (88, "FX"), (174, "AMC"),
        (6, "NBC"), (2, "ABC"), (16, "CBS"), (19, "FOX"), (71, "The CW"), (4, "BBC One")
    ]

    let template: Template
    private let sourceId: String?

    // Addon catalog
    @Published var addonCatalogs: [StremioService.InstalledCatalog] = []
    @Published var isLoadingAddons = false
    @Published var addonFilter = ""
    @Published var selectedAddon: UserCollectionSource.AddonCatalog?

    // Discover
    @Published var discover = UserCollectionSource.Discover()
    @Published var yearFromText = ""
    @Published var yearToText = ""
    @Published var genres: [FlixorKit.TMDBGenre] = []
    @Published var companyText = ""
    @Published var companyResults: [TMDBCompanySearchResult] = []
    @Published var isSearchingCompanies = false

    // Name search (movie collection, person, Trakt list)
    @Published var searchText = ""
    @Published var isSearching = false
    @Published var searchError: String?
    @Published var collectionResults: [TMDBCollectionSearchResult] = []
    @Published var peopleResults: [TMDBPersonSummary] = []
    @Published var traktResults: [TraktPublicList] = []
    @Published var hasSearched = false

    @Published var selectedCollection: UserCollectionSource.MovieCollection?
    @Published var selectedPerson: UserCollectionSource.Person?
    @Published var selectedTraktList: UserCollectionSource.TraktList?

    @Published private(set) var preview: PreviewState = .idle

    private var searchTask: Task<Void, Never>?
    private var companyTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private static let debounce: UInt64 = 350_000_000

    init(template: Template, existing: UserCollectionSource?) {
        self.template = template
        sourceId = existing?.id
        switch existing?.kind {
        case .addonCatalog(let catalog):
            selectedAddon = catalog
        case .tmdbDiscover(let value):
            discover = value
            yearFromText = value.yearFrom.map(String.init) ?? ""
            yearToText = value.yearTo.map(String.init) ?? ""
        case .tmdbCollection(let value):
            selectedCollection = value
        case .person(let value):
            selectedPerson = value
        case .traktList(let value):
            selectedTraktList = value
        case nil:
            break
        }
    }

    deinit {
        searchTask?.cancel()
        companyTask?.cancel()
        previewTask?.cancel()
    }

    // MARK: - Draft

    var draftKind: Kind? {
        switch template {
        case .addonCatalog:
            return selectedAddon.map(Kind.addonCatalog)
        case .tmdbDiscover:
            var value = discover
            value.yearFrom = Self.year(from: yearFromText)
            value.yearTo = Self.year(from: yearToText)
            if value.mediaType == .movie {
                value.networkId = nil
                value.networkName = nil
            }
            return .tmdbDiscover(value)
        case .tmdbCollection:
            return selectedCollection.map(Kind.tmdbCollection)
        case .person:
            return selectedPerson.map(Kind.person)
        case .traktList:
            return selectedTraktList.map(Kind.traktList)
        }
    }

    var draftSource: UserCollectionSource? {
        guard let draftKind else { return nil }
        return UserCollectionSource(id: sourceId ?? UUID().uuidString, kind: draftKind)
    }

    private static func year(from text: String) -> Int? {
        guard let year = Int(text.trimmingCharacters(in: .whitespaces)), (1870...2200).contains(year) else { return nil }
        return year
    }

    // MARK: - Addon catalogs

    func loadAddonCatalogs() async {
        guard template == .addonCatalog, addonCatalogs.isEmpty else { return }
        isLoadingAddons = true
        addonCatalogs = await StremioService.shared.getBrowsableCatalogs()
        isLoadingAddons = false
    }

    var filteredAddonCatalogs: [StremioService.InstalledCatalog] {
        let query = addonFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return addonCatalogs }
        return addonCatalogs.filter {
            $0.catalog.displayName.localizedCaseInsensitiveContains(query)
                || $0.addonName.localizedCaseInsensitiveContains(query)
        }
    }

    func select(_ entry: StremioService.InstalledCatalog) {
        selectedAddon = UserCollectionSource.AddonCatalog(
            installationId: entry.installationId,
            addonId: entry.addonId,
            addonName: entry.addonName,
            type: entry.catalog.type,
            catalogId: entry.catalog.catalogId,
            displayName: entry.catalog.displayName
        )
    }

    func isSelected(_ entry: StremioService.InstalledCatalog) -> Bool {
        selectedAddon?.addonId == entry.addonId
            && selectedAddon?.type == entry.catalog.type
            && selectedAddon?.catalogId == entry.catalog.catalogId
    }

    // MARK: - Discover

    func loadGenres() async {
        guard template == .tmdbDiscover else { return }
        genres = (try? await FlixorCore.shared.tmdb.getGenres(mediaType: discover.mediaType)) ?? []
    }

    /// Genre ids differ between movies and TV, so a switch clears the selection.
    func setMediaType(_ mediaType: TMDBDiscoverMediaType) {
        guard mediaType != discover.mediaType else { return }
        discover.mediaType = mediaType
        discover.genreIds = []
        discover.genreNames = []
        Task { await loadGenres() }
    }

    func toggleGenre(_ genre: FlixorKit.TMDBGenre) {
        if let index = discover.genreIds.firstIndex(of: genre.id) {
            discover.genreIds.remove(at: index)
            discover.genreNames.removeAll { $0 == genre.name }
        } else {
            discover.genreIds.append(genre.id)
            discover.genreNames.append(genre.name)
        }
    }

    func setNetwork(id: Int?) {
        discover.networkId = id
        discover.networkName = Self.networks.first { $0.id == id }?.name
    }

    func selectCompany(_ company: TMDBCompanySearchResult) {
        discover.companyId = company.id
        discover.companyName = company.name
        companyText = ""
        companyResults = []
    }

    func clearCompany() {
        discover.companyId = nil
        discover.companyName = nil
    }

    func companyTextChanged() {
        companyTask?.cancel()
        let query = companyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            companyResults = []
            isSearchingCompanies = false
            return
        }
        companyTask = Task {
            try? await Task.sleep(nanoseconds: Self.debounce)
            guard !Task.isCancelled else { return }
            isSearchingCompanies = true
            let results = (try? await FlixorCore.shared.tmdb.searchCompanies(query: query)) ?? []
            guard !Task.isCancelled else { return }
            companyResults = Array(results.prefix(8))
            isSearchingCompanies = false
        }
    }

    // MARK: - Name search

    func searchTextChanged() {
        searchTask?.cancel()
        searchError = nil
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            collectionResults = []
            peopleResults = []
            traktResults = []
            isSearching = false
            hasSearched = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: Self.debounce)
            guard !Task.isCancelled else { return }
            isSearching = true
            await runSearch(query)
            guard !Task.isCancelled else { return }
            isSearching = false
            hasSearched = true
        }
    }

    private func runSearch(_ query: String) async {
        do {
            switch template {
            case .tmdbCollection:
                let results = try await FlixorCore.shared.tmdb.searchCollections(query: query)
                guard !Task.isCancelled else { return }
                collectionResults = results
            case .person:
                let results = try await FlixorCore.shared.tmdb.searchPeople(query: query).results
                guard !Task.isCancelled else { return }
                peopleResults = results
            case .traktList:
                let trakt = FlixorCore.shared.trakt
                let results: [TraktPublicList]
                if let reference = TraktListReference(input: query) {
                    results = [try await trakt.getPublicList(reference)]
                } else {
                    results = try await trakt.searchPublicLists(query: query)
                }
                guard !Task.isCancelled else { return }
                traktResults = results
            case .addonCatalog, .tmdbDiscover:
                break
            }
        } catch {
            guard !Task.isCancelled else { return }
            collectionResults = []
            peopleResults = []
            traktResults = []
            searchError = UserCollectionSourceResolver.message(for: error)
        }
    }

    func select(_ result: TMDBCollectionSearchResult) {
        selectedCollection = .init(id: result.id, name: result.name, posterPath: result.posterPath)
    }

    func select(_ person: TMDBPersonSummary) {
        selectedPerson = .init(id: person.id, name: person.name, profilePath: person.profilePath)
    }

    func select(_ list: TraktPublicList) {
        selectedTraktList = .init(id: list.id, name: list.name, owner: list.user?.username ?? list.user?.name)
    }

    // MARK: - Preview

    func resetPreview() {
        previewTask?.cancel()
        preview = .idle
    }

    func runPreview() {
        guard let source = draftSource else { return }
        previewTask?.cancel()
        preview = .loading
        previewTask = Task {
            do {
                let page = try await UserCollectionSourceResolver.fetchPage(source, limit: 20)
                guard !Task.isCancelled else { return }
                preview = page.items.isEmpty ? .empty : .loaded(items: page.items, hasMore: page.nextCursor != nil)
            } catch {
                guard !Task.isCancelled else { return }
                preview = .failed(UserCollectionSourceResolver.message(for: error))
            }
        }
    }
}
