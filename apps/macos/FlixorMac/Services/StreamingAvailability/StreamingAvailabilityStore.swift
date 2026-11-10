//
//  StreamingAvailabilityStore.swift
//  FlixorMac
//
//  Settings and data for the Streaming Availability integration: Top 10 rows
//  per service (movies and shows, or mixed) and "New on" rows. Everything is
//  read from the disk cache first; an entry is fetched again only when it is
//  older than its refresh interval and the call budget allows.
//

import Foundation
import Combine

@MainActor
final class StreamingAvailabilityStore: ObservableObject {
    static let shared = StreamingAvailabilityStore()

    static let rowIdPrefix = "sa-"
    static let didUpdateNotification = Notification.Name("StreamingAvailabilityDidUpdate")

    private enum Keys {
        /// First version: one key. Moved into `apiKeys` on first launch.
        static let apiKey = "streamingAvailability.apiKey"
        /// JSON array of keys, in the Keychain.
        static let apiKeys = "streamingAvailability.apiKeys"
        static let enabled = "streamingAvailability.enabled"
        static let region = "streamingAvailability.region"
        static let topServices = "streamingAvailability.topServices"
        static let splitByType = "streamingAvailability.splitByType"
        static let newServices = "streamingAvailability.newServices"
        static let refreshHours = "streamingAvailability.refreshHours"
    }

    private let defaults = UserDefaults.standard
    private let cache = StreamingAvailabilityCache.shared
    private let budget = StreamingAvailabilityBudget.shared
    private var isLoading = false
    private var profileObserver: AnyCancellable?

    // MARK: Settings (per profile; the key is shared and lives in the Keychain)

    @Published private(set) var hasKey = false
    @Published var enabled = true { didSet { save(enabled, Keys.enabled) } }
    @Published var region = "us" { didSet { save(region, Keys.region) } }
    @Published var topServices: [String] = StreamingService.allCases.map(\.rawValue) { didSet { save(topServices, Keys.topServices) } }
    @Published var splitByType = true { didSet { save(splitByType, Keys.splitByType) } }
    @Published var newServices: [String] = [] { didSet { save(newServices, Keys.newServices) } }
    @Published var refreshHours = 24 { didSet { save(refreshHours, Keys.refreshHours) } }

    /// Services the region has (from /countries), or nil before it is known.
    @Published private(set) var regionServices: Set<String>?
    @Published private(set) var lastError: String?
    @Published private(set) var lastRefresh: Date?
    /// Deep links ("Open in Netflix") by Flixor item id.
    private(set) var links: [String: (service: StreamingService, url: URL)] = [:]

    var isActive: Bool { hasKey && enabled }

    private init() {
        reload()
        profileObserver = ProfileSettings.shared.objectWillChange
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in Task { @MainActor [weak self] in self?.reload() } }
    }

    private var loadingSettings = false

    func reload() {
        loadingSettings = true
        defer { loadingSettings = false }
        migrateSingleKey()
        hasKey = !storedKeys.isEmpty
        enabled = defaults.object(forKey: defaults.profileKey(Keys.enabled)) as? Bool ?? true
        region = defaults.string(forKey: defaults.profileKey(Keys.region)) ?? Self.defaultRegion
        topServices = defaults.stringArray(forKey: defaults.profileKey(Keys.topServices)) ?? StreamingService.allCases.map(\.rawValue)
        splitByType = defaults.object(forKey: defaults.profileKey(Keys.splitByType)) as? Bool ?? true
        newServices = defaults.stringArray(forKey: defaults.profileKey(Keys.newServices)) ?? []
        let hours = defaults.integer(forKey: defaults.profileKey(Keys.refreshHours))
        refreshHours = [12, 24, 48].contains(hours) ? hours : 24
        regionServices = cachedCountry(region).map { Set($0.services.map(\.id)) }
    }

    private func save(_ value: Any, _ key: String) {
        guard !loadingSettings else { return }
        defaults.set(value, forKey: defaults.profileKey(key))
    }

    static var defaultRegion: String {
        (Locale.current.region?.identifier ?? "US").lowercased()
    }

    /// Countries the API covers (subset shown in Settings).
    static let regions: [(code: String, name: String)] = [
        ("us", "United States"), ("in", "India"), ("gb", "United Kingdom"), ("ca", "Canada"), ("au", "Australia"),
        ("de", "Germany"), ("fr", "France"), ("es", "Spain"), ("it", "Italy"), ("br", "Brazil"), ("mx", "Mexico"),
        ("jp", "Japan"), ("kr", "South Korea"), ("nl", "Netherlands"), ("se", "Sweden"), ("ie", "Ireland"),
        ("nz", "New Zealand"), ("sg", "Singapore"), ("ae", "United Arab Emirates"), ("za", "South Africa"),
    ]

    // MARK: Keys (several keys add up: each request uses the one with the most calls left)

    struct KeyInfo: Identifiable {
        let id: String          // fingerprint
        let masked: String      // "••••••••sPUA"
    }

    private var storedKeys: [String] {
        guard let json = SecretStore.string(Keys.apiKeys), let data = json.data(using: .utf8),
              let keys = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return keys.filter { !$0.isEmpty }
    }

    private func saveKeys(_ keys: [String]) {
        let json = (try? JSONEncoder().encode(keys)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        SecretStore.set(keys.isEmpty ? "" : json, for: Keys.apiKeys)
        keys.forEach { AppLogger.shared.registerSensitiveValue($0) }
        hasKey = !keys.isEmpty
        keyListVersion += 1
    }

    /// Moves the first version's single key (and its counters) into the list.
    private func migrateSingleKey() {
        guard let old = SecretStore.string(Keys.apiKey), !old.isEmpty else { return }
        if !storedKeys.contains(old) { saveKeys(storedKeys + [old]) }
        budget.adoptLegacyCounters(for: StreamingAvailabilityBudget.fingerprint(old))
        SecretStore.set("", for: Keys.apiKey)
    }

    /// Bumps when keys are added or removed, so Settings redraws.
    @Published private(set) var keyListVersion = 0

    var keys: [KeyInfo] {
        _ = keyListVersion
        return storedKeys.map { KeyInfo(id: StreamingAvailabilityBudget.fingerprint($0),
                                        masked: String(repeating: "•", count: 8) + $0.suffix(4)) }
    }

    var keyFingerprints: [String] { keys.map(\.id) }

    /// Adds a key after checking it with one call. Returns an error message, or nil.
    func addKey(_ raw: String) async -> String? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        if storedKeys.contains(key) { return String(localized: "That key is already added.") }
        AppLogger.shared.registerSensitiveValue(key)
        let fingerprint = StreamingAvailabilityBudget.fingerprint(key)
        do {
            let (data, quota) = try await StreamingAvailabilityClient(apiKey: key).get("countries/\(region)", query: [])
            budget.record(quota, for: fingerprint)
            cache.write(data, for: "country|\(region)")
            regionServices = (try? JSONDecoder().decode(SACountry.self, from: data)).map { Set($0.services.map(\.id)) }
            saveKeys(storedKeys + [key])
            lastError = nil
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func removeKey(_ fingerprint: String) {
        saveKeys(storedKeys.filter { StreamingAvailabilityBudget.fingerprint($0) != fingerprint })
        budget.forget(fingerprint)
    }

    /// Picks the key for the next request and reserves a call on it.
    private func reserveClient() -> (StreamingAvailabilityClient, String)? {
        let keys = storedKeys
        guard let fingerprint = budget.spend(among: keys.map(StreamingAvailabilityBudget.fingerprint)),
              let key = keys.first(where: { StreamingAvailabilityBudget.fingerprint($0) == fingerprint }) else { return nil }
        return (StreamingAvailabilityClient(apiKey: key), fingerprint)
    }

    /// Calls left today across every key.
    var allowanceToday: Int { budget.totalAllowance(keyFingerprints) }

    // MARK: Fetching (cache first, within budget)

    /// Cached data for `key`, refreshed first when it is older than `maxAge`
    /// and a call is allowed. `force` ignores the age (Refresh now), not the budget.
    private func data(_ key: String, path: String, query: [URLQueryItem], maxAge: TimeInterval, force: Bool = false) async -> Data? {
        let cached = cache.read(key)
        let due = force || cached.map { Date().timeIntervalSince($0.fetchedAt) > maxAge } ?? true
        guard due, hasKey else { return cached?.data }
        guard let (client, fingerprint) = reserveClient() else {
            lastError = StreamingAvailabilityError.overBudget.errorDescription
            return cached?.data
        }
        do {
            let (data, quota) = try await client.get(path, query: query)
            budget.record(quota, for: fingerprint)
            cache.write(data, for: key)
            lastError = nil
            AppLogger.shared.info("[StreamingAvailability] Fetched \(path)", data: ["calls_today": budget.totalCallsToday(keyFingerprints)])
            return data
        } catch {
            if case StreamingAvailabilityError.http(429, _) = error { budget.markExhausted(fingerprint) }
            lastError = error.localizedDescription
            return cached?.data
        }
    }

    private func cachedCountry(_ code: String) -> SACountry? {
        cache.read("country|\(code)").flatMap { try? JSONDecoder().decode(SACountry.self, from: $0.data) }
    }

    private func loadCountry() async {
        guard let data = await data("country|\(region)", path: "countries/\(region)", query: [], maxAge: 30 * 86_400),
              let country = try? JSONDecoder().decode(SACountry.self, from: data) else { return }
        regionServices = Set(country.services.map(\.id))
    }

    /// Services shown in Settings: supported ones the region has (all of them until known).
    var availableServices: [StreamingService] {
        StreamingService.allCases.filter { regionServices?.contains($0.rawValue) ?? true }
    }

    // MARK: Rows

    struct RowSpec {
        let id: String
        let title: String
        let service: StreamingService
    }

    /// Row ids and titles for the current settings, without any network (for Rows Settings).
    var rowSpecs: [RowSpec] {
        guard isActive else { return [] }
        var specs: [RowSpec] = []
        for service in availableServices where topServices.contains(service.rawValue) {
            if splitByType {
                specs.append(RowSpec(id: "\(Self.rowIdPrefix)top-\(service.rawValue)-movie", title: String(localized: "Top 10 Movies on \(service.displayName)"), service: service))
                specs.append(RowSpec(id: "\(Self.rowIdPrefix)top-\(service.rawValue)-series", title: String(localized: "Top 10 Shows on \(service.displayName)"), service: service))
            } else {
                specs.append(RowSpec(id: "\(Self.rowIdPrefix)top-\(service.rawValue)", title: String(localized: "Top 10 on \(service.displayName)"), service: service))
            }
        }
        for service in availableServices where newServices.contains(service.rawValue) {
            specs.append(RowSpec(id: "\(Self.rowIdPrefix)new-\(service.rawValue)", title: String(localized: "New on \(service.displayName)"), service: service))
        }
        return specs
    }

    /// The Home rows: from the cache, refreshing whatever is due within the budget.
    func sections(force: Bool = false) async -> [LibrarySection] {
        // The first Keychain read can fail (e.g. while macOS asks for access); try again.
        if !hasKey { migrateSingleKey(); hasKey = !storedKeys.isEmpty }
        guard isActive, !isLoading else { return isActive ? cachedSections() : [] }
        isLoading = true
        defer { isLoading = false }

        if regionServices == nil || force { await loadCountry() }
        let maxAge = TimeInterval(refreshHours) * 3600
        var sections: [LibrarySection] = []

        for spec in rowSpecs {
            if let section = await fetchList(spec, maxAge: maxAge, force: force) { sections.append(section) }
        }
        lastRefresh = Date()
        return sections
    }

    /// One list: cached, or fetched when due (or forced) within the budget.
    private func fetchList(_ spec: RowSpec, maxAge: TimeInterval, force: Bool) async -> LibrarySection? {
        if spec.id.hasPrefix("\(Self.rowIdPrefix)top-") {
            let type: String? = spec.id.hasSuffix("-movie") ? "movie" : (spec.id.hasSuffix("-series") ? "series" : nil)
            var query = [URLQueryItem(name: "country", value: region), URLQueryItem(name: "service", value: spec.service.rawValue)]
            if let type { query.append(URLQueryItem(name: "show_type", value: type)) }
            guard let data = await data(cacheKey(for: spec), path: "shows/top", query: query, maxAge: maxAge, force: force),
                  let shows = try? JSONDecoder().decode([SAShow].self, from: data) else { return nil }
            return section(spec, shows: Array(shows.prefix(10)))
        }
        let weekAgo = Int(Date().addingTimeInterval(-7 * 86_400).timeIntervalSince1970)
        let query = [
            URLQueryItem(name: "country", value: region),
            // ".subscription": the service itself, not its rent/buy store or the
            // channels sold through it (Apple TV's Hallmark+, Prime's AMC+, ...).
            URLQueryItem(name: "catalogs", value: "\(spec.service.rawValue).subscription"),
            URLQueryItem(name: "change_type", value: "new"),
            URLQueryItem(name: "item_type", value: "show"),
            URLQueryItem(name: "from", value: String(weekAgo)),
            URLQueryItem(name: "order_direction", value: "desc"),
        ]
        guard let data = await data(cacheKey(for: spec), path: "changes", query: query, maxAge: max(maxAge, 48 * 3600), force: force),
              let result = try? JSONDecoder().decode(SAChangesResult.self, from: data) else { return nil }
        return section(spec, shows: Array(Self.newShows(in: result).prefix(20)))
    }

    /// Titles new on the service's own subscription, once each, newest first.
    static func newShows(in result: SAChangesResult) -> [SAShow] {
        var seen = Set<String>()
        return result.changes.compactMap { change -> SAShow? in
            guard change.streamingOptionType == nil || change.streamingOptionType == "subscription",
                  seen.insert(change.showId).inserted else { return nil }
            return result.shows[change.showId]
        }
    }

    /// Rows from whatever is cached, with no network at all.
    func cachedSections() -> [LibrarySection] {
        rowSpecs.compactMap { spec in
            let type = spec.id.hasSuffix("-movie") ? "movie" : (spec.id.hasSuffix("-series") ? "series" : "all")
            if spec.id.hasPrefix("\(Self.rowIdPrefix)top-") {
                guard let data = cache.read("top|\(region)|\(spec.service.rawValue)|\(type)")?.data,
                      let shows = try? JSONDecoder().decode([SAShow].self, from: data) else { return nil }
                return section(spec, shows: Array(shows.prefix(10)))
            }
            guard let data = cache.read(cacheKey(for: spec))?.data,
                  let result = try? JSONDecoder().decode(SAChangesResult.self, from: data) else { return nil }
            return section(spec, shows: Array(Self.newShows(in: result).prefix(20)))
        }
    }

    private func section(_ spec: RowSpec, shows: [SAShow]) -> LibrarySection? {
        let items = shows.compactMap { show -> MediaItem? in
            guard let id = show.flixorId else { return nil }
            if let url = show.link(service: spec.service, country: region) { links[id] = (spec.service, url) }
            return MediaItem(
                id: id, title: show.title, type: show.isSeries ? "show" : "movie",
                thumb: show.posterURL, art: show.backdropURL, year: show.year,
                rating: show.rating.map { Double($0) / 10 }, duration: nil, viewOffset: nil,
                summary: show.overview, grandparentTitle: nil, grandparentThumb: nil, grandparentArt: nil,
                grandparentRatingKey: nil, parentIndex: nil, index: nil, parentRatingKey: nil,
                parentTitle: nil, leafCount: nil, viewedLeafCount: nil
            )
        }
        guard !items.isEmpty else { return nil }
        return LibrarySection(id: spec.id, title: spec.title, items: items, totalCount: items.count, libraryKey: nil)
    }

    // MARK: Actions

    /// Checks one key (or the next usable one) with a single call.
    func testKey(_ fingerprint: String? = nil) async -> String? {
        let keys = storedKeys
        guard !keys.isEmpty else { return StreamingAvailabilityError.noKey.errorDescription }
        let key = fingerprint.flatMap { fp in keys.first { StreamingAvailabilityBudget.fingerprint($0) == fp } } ?? keys[0]
        let fp = StreamingAvailabilityBudget.fingerprint(key)
        guard budget.allowance(fp) > 0, budget.spend(among: [fp]) != nil else { return StreamingAvailabilityError.overBudget.errorDescription }
        do {
            let (data, quota) = try await StreamingAvailabilityClient(apiKey: key).get("countries/\(region)", query: [])
            budget.record(quota, for: fp)
            cache.write(data, for: "country|\(region)")
            regionServices = (try? JSONDecoder().decode(SACountry.self, from: data)).map { Set($0.services.map(\.id)) }
            lastError = nil
            return nil
        } catch {
            lastError = error.localizedDescription
            return error.localizedDescription
        }
    }

    // MARK: Saved lists (Settings shows each with its age and a Refetch button)

    struct SavedList: Identifiable {
        let id: String
        let title: String
        let fetchedAt: Date?
        let count: Int
    }

    private func cacheKey(for spec: RowSpec) -> String {
        if spec.id.hasPrefix("\(Self.rowIdPrefix)new-") { return "new2|\(region)|\(spec.service.rawValue)" }
        let type = spec.id.hasSuffix("-movie") ? "movie" : (spec.id.hasSuffix("-series") ? "series" : "all")
        return "top|\(region)|\(spec.service.rawValue)|\(type)"
    }

    var savedLists: [SavedList] {
        _ = listVersion
        let sections = Dictionary(cachedSections().map { ($0.id, $0.items.count) }, uniquingKeysWith: { a, _ in a })
        return rowSpecs.map { spec in
            SavedList(id: spec.id, title: spec.title, fetchedAt: cache.read(cacheKey(for: spec))?.fetchedAt, count: sections[spec.id] ?? 0)
        }
    }

    /// Bumps after a refetch, so Settings shows new ages.
    @Published private(set) var listVersion = 0

    /// Fetches one list now (1 call), then asks Home to reload.
    func refetch(_ rowId: String) async {
        guard let spec = rowSpecs.first(where: { $0.id == rowId }) else { return }
        _ = await fetchList(spec, maxAge: 0, force: true)
        listVersion += 1
        NotificationCenter.default.post(name: Self.didUpdateNotification, object: nil)
    }

    /// Refreshes every row now (still within the budget) and asks Home to reload.
    func refreshNow() async {
        _ = await sections(force: true)
        listVersion += 1
        NotificationCenter.default.post(name: Self.didUpdateNotification, object: nil)
    }

    func clearCache() {
        cache.clear()
        listVersion += 1
        links = [:]
        regionServices = nil
        NotificationCenter.default.post(name: Self.didUpdateNotification, object: nil)
    }

    /// Calls a full refresh of the current settings costs.
    var callsPerRefresh: Int {
        guard isActive else { return 0 }
        return rowSpecs.count
    }
}
