//
//  PhysicalCollectionView.swift
//  FlixorMac
//
//  Library → Physical: the person's Blu-ray.com collection through MyBluray
//  (owned discs, wishlist and the other lists) as a cover grid. Its controls
//  (search, list chips, format and sort) live in the Library header like the
//  Movies and TV Shows tabs. Clicking a disc opens its edition page.
//
//  PhysicalCollectionStore is also the one record of which list each disc is
//  in, so Details, the edition page and this tab always agree after a change.
//

import SwiftUI

// MARK: - Store

@MainActor
final class PhysicalCollectionStore: ObservableObject {
    static let shared = PhysicalCollectionStore()

    enum Phase: Equatable { case idle, loading, loaded, notConnected, failed(String) }

    enum Sort: String, CaseIterable, Identifiable {
        case added, title, release
        var id: String { rawValue }
        var title: String {
            switch self {
            case .added: return String(localized: "Date added")
            case .title: return String(localized: "Title")
            case .release: return String(localized: "Release date")
            }
        }
        var shortTitle: String {
            switch self {
            case .added: return String(localized: "Newest added")
            case .title: return String(localized: "Title")
            case .release: return String(localized: "Newest release")
            }
        }
    }

    enum FormatFilter: String, CaseIterable, Identifiable {
        case all, uhd, bluray
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return String(localized: "All formats")
            case .uhd: return "4K"
            case .bluray: return "Blu-ray"
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var entries: [MBCollectionEntry] = [] {
        didSet { rebuildIndex() }
    }
    @Published private(set) var lists: [MBCollectionList] = []
    /// Product id → the list it's in.
    @Published private(set) var listFor: [String: MBCollectionEntry.ListRef] = [:]
    /// Result of the last add or remove, shown briefly where it happened.
    @Published var message: String?

    // Library tab filters (shared by the header and the grid).
    @Published var listFilter: String? = "bluray:1"   // Owned
    @Published var query = ""
    @Published var sort: Sort = .added
    @Published var format: FormatFilter = .all

    var isConnected: Bool { phase == .loaded }

    /// Loads the collection (MyBlurayService caches it for 5 minutes).
    func load(force: Bool = false) async {
        if phase == .loading { return }
        if !force, phase == .loaded || phase == .notConnected { return }
        let settings = MyBluraySettingsStore.shared
        guard settings.isOn(.librarySection) || settings.isOn(.quickAdd) else {
            phase = .idle
            return
        }
        if entries.isEmpty { phase = .loading }
        do {
            async let lists = MyBlurayService.shared.collectionLists()
            async let entries = MyBlurayService.shared.collection()
            let (loadedLists, loadedEntries) = try await (lists, entries)
            self.lists = loadedLists.sorted { ($0.displayOrder ?? 0) < ($1.displayOrder ?? 0) }
            self.entries = loadedEntries
            phase = .loaded
        } catch MyBlurayError.collectionNotConnected {
            phase = .notConnected
        } catch {
            if entries.isEmpty { phase = .failed(MyBluraySettingsStore.message(for: error)) }
        }
    }

    private func rebuildIndex() {
        var map: [String: MBCollectionEntry.ListRef] = [:]
        for entry in entries { if let list = entry.list { map[entry.id] = list } }
        listFor = map
    }

    // MARK: Changes

    func add(_ edition: MBEditionSummary, to list: MBCollectionList) async {
        let done = String(localized: "Added to \(list.name ?? String(localized: "your collection")).")
        message = String(localized: "Saving…")
        do {
            try await MyBlurayService.shared.addToCollection(MBCollectionChange(productId: edition.id, listId: list.id))
            setLocally(edition, list: MBCollectionEntry.ListRef(id: list.id, alias: list.alias, name: list.name))
            message = done
        } catch {
            // MyBluray can save a change and still answer with an error (a 502
            // after the write), so check the collection before saying it failed.
            await load(force: true)
            message = listFor[edition.id]?.id == list.id ? done : MyBluraySettingsStore.message(for: error)
        }
    }

    func remove(_ edition: MBEditionSummary) async {
        let done = String(localized: "Removed from your collection.")
        message = String(localized: "Saving…")
        do {
            try await MyBlurayService.shared.removeFromCollection(productId: edition.id)
            entries.removeAll { $0.id == edition.id }
            message = done
        } catch {
            await load(force: true)
            message = listFor[edition.id] == nil && phase == .loaded ? done : MyBluraySettingsStore.message(for: error)
        }
    }

    private func setLocally(_ edition: MBEditionSummary, list: MBCollectionEntry.ListRef) {
        let entry = MBCollectionEntry(id: edition.id, title: edition.title, year: edition.year, country: edition.country,
                                      coverImage: edition.coverImage, releaseDate: edition.releaseDate, format: edition.format,
                                      list: list, addedAt: ISO8601DateFormatter().string(from: Date()))
        if let index = entries.firstIndex(where: { $0.id == edition.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
    }

    // MARK: Library tab

    /// Lists that hold at least one disc, in Blu-ray.com's order, with counts.
    var listsInUse: [(list: MBCollectionList, count: Int)] {
        var counts: [String: Int] = [:]
        for entry in entries { if let id = entry.list?.id { counts[id, default: 0] += 1 } }
        return lists.compactMap { list in counts[list.id].map { (list, $0) } }
    }

    var shown: [MBCollectionEntry] {
        var items = entries
        if let listFilter { items = items.filter { $0.list?.id == listFilter } }
        switch format {
        case .all: break
        case .uhd: items = items.filter { $0.isUHD }
        case .bluray: items = items.filter { !$0.isUHD }
        }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty { items = items.filter { ($0.title ?? "").lowercased().contains(q) } }
        switch sort {
        case .added: items.sort { ($0.addedAt ?? "") > ($1.addedAt ?? "") }
        case .title: items.sort { ($0.title ?? "").localizedStandardCompare($1.title ?? "") == .orderedAscending }
        case .release: items.sort { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }
        }
        return items
    }
}

// MARK: - View

struct PhysicalCollectionView: View {
    let horizontalPadding: CGFloat
    let minItemWidth: CGFloat
    let spacing: CGFloat

    @ObservedObject private var store = PhysicalCollectionStore.shared
    @EnvironmentObject private var router: NavigationRouter
    @EnvironmentObject private var mainViewState: MainViewState
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        Group {
            switch store.phase {
            case .idle, .loading:
                VStack(spacing: DS.Space.s12) {
                    ProgressView().controlSize(.large)
                    Text("Loading your collection…").flixorFont(.callout).foregroundStyle(theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .notConnected:
                BrowseMessageView(systemImage: "person.crop.circle.badge.exclamationmark",
                                  title: "No Blu-ray.com login on your key",
                                  message: "Attach your Blu-ray.com login to your MyBluray key in the portal, then come back here.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let text):
                BrowseMessageView(systemImage: "exclamationmark.triangle", title: "Couldn't load your collection",
                                  message: .init(text), retryTitle: "Try Again",
                                  onRetry: { Task { await store.load(force: true) } })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                grid
            }
        }
        .task { await store.load() }
    }

    // The width comes from a GeometryReader (what the window offers), not from
    // measuring the scroll view: a fixed-width grid would size the scroll view
    // and the measurement would only ever confirm itself.
    private var grid: some View {
        GeometryReader { proxy in
            gridContent(width: proxy.size.width)
        }
    }

    private func gridContent(width contentWidth: CGFloat) -> some View {
        let shown = store.shown
        let available = max(320, contentWidth - horizontalPadding * 2)
        let columns = max(2, Int((available + spacing) / (minItemWidth + spacing)))
        let width = ((available - CGFloat(columns - 1) * spacing) / CGFloat(columns)).rounded(.down)
        return ScrollView {
            Group {
                if shown.isEmpty {
                    BrowseMessageView(systemImage: "opticaldisc",
                                      title: store.query.isEmpty ? "Nothing here" : "No discs match “\(store.query)”")
                        .padding(.top, DS.Space.s40)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(width), spacing: spacing, alignment: .top), count: columns),
                              alignment: .leading, spacing: DS.Space.s24) {
                        ForEach(shown) { entry in
                            let summary = entry.summary
                            EditionCoverCard(edition: summary, width: width, showsList: store.listFilter == nil,
                                             showsCountry: entry.country?.code != "US") {
                                router.push(EditionRoute(summary: summary, offersLibraryLink: true), on: mainViewState.selectedTab)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, DS.Space.s24)
            .padding(.bottom, DS.Space.s32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension MBCollectionEntry {
    /// The entry as an edition summary, for the cover card and edition page.
    var summary: MBEditionSummary {
        MBEditionSummary(id: id, title: title, year: year, country: country, websiteUrl: nil,
                         coverImage: coverImage, releaseDate: releaseDate, format: format, bundle: nil)
    }

    /// Collection entries often have no format; a "4K" title says it.
    var isUHD: Bool {
        format == "4k" || (title ?? "").range(of: #"\b4K\b"#, options: .regularExpression) != nil
    }
}

// MARK: - Plex match

enum PlexDiscMatcher {
    private struct Hit: Decodable {
        let ratingKey: String
        let title: String?
        let year: Int?
        let thumb: String?
        let art: String?
        let summary: String?
        let type: String?
    }

    /// The Plex movie for a disc, by title and year (Blu-ray.com titles carry
    /// extras like "4K" or "(Steelbook)", and no IMDb id).
    static func match(title rawTitle: String?, year: Int?) async -> MediaItem? {
        let title = cleaned(rawTitle ?? "")
        guard !title.isEmpty else { return nil }
        guard let hits: [Hit] = try? await APIClient.shared.get(
            "/api/plex/search",
            queryItems: [URLQueryItem(name: "query", value: title), URLQueryItem(name: "type", value: "1")]
        ) else { return nil }
        let wanted = normalized(title)
        let best = hits.first { hit in
            guard normalized(hit.title ?? "") == wanted else { return false }
            guard let year, let hitYear = hit.year else { return true }
            return abs(hitYear - year) <= 1
        }
        guard let best else { return nil }
        return MediaItem(id: best.ratingKey, title: best.title ?? title, type: "movie", thumb: best.thumb, art: best.art,
                         year: best.year, rating: nil, duration: nil, viewOffset: nil, summary: best.summary,
                         grandparentTitle: nil, grandparentThumb: nil, grandparentArt: nil, grandparentRatingKey: nil,
                         parentIndex: nil, index: nil, parentRatingKey: nil, parentTitle: nil, leafCount: nil, viewedLeafCount: nil)
    }

    /// "The Dark Knight 4K (Steelbook)" → "The Dark Knight".
    static func cleaned(_ title: String) -> String {
        var text = title
        if let open = text.firstIndex(of: "(") { text = String(text[..<open]) }
        for suffix in [" 4K", " 3D", " Blu-ray", " Ultra HD"] where text.hasSuffix(suffix) {
            text = String(text.dropLast(suffix.count))
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    static func normalized(_ title: String) -> String {
        var text = title.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        if text.hasPrefix("the ") { text = String(text.dropFirst(4)) }
        return text.filter { $0.isLetter || $0.isNumber }
    }
}
