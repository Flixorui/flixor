//
//  StreamingAvailabilityStore.swift
//  FlixorMac
//
//  Settings and data for the Top 10 and "New on" rows. Two kinds of source,
//  both supplied by the user:
//  - FlixPatrol JSON APIs (URL + key): tried first for Top 10 rows, in the
//    order added. No call limit, so no budget.
//  - Streaming Availability (Movie of the Night) keys: "New on" rows, and the
//    Top 10 fallback when no FlixPatrol source has the list. Budgeted.
//  Everything is read from the disk cache first; an entry is fetched again
//  only when it is older than its refresh interval (and, for Streaming
//  Availability, when the call budget allows).
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
        /// JSON array of FlixPatrolSource (URL + key), in the Keychain.
        static let flixPatrolSources = "flixPatrol.sources"
    }

    /// FlixPatrol charts update about once a day and calls are free: check every 6 hours.
    static let flixPatrolMaxAge: TimeInterval = 6 * 3600

    private let defaults = UserDefaults.standard
    private let cache = StreamingAvailabilityCache.shared
    private let budget = StreamingAvailabilityBudget.shared
    private var isLoading = false
    private var profileObserver: AnyCancellable?

    // MARK: Settings (per profile; the key is shared and lives in the Keychain)

    @Published private(set) var hasKey = false
    @Published var enabled = true { didSet { save(enabled, Keys.enabled) } }
    @Published var region = "us" {
        didSet {
            save(region, Keys.region)
            guard !loadingSettings, region != oldValue else { return }
            regionServices = cachedCountry(region).map { Set($0.services.map(\.id)) }
            flixPatrolServices = cachedFlixPatrolCountry(region).map { Set($0.services.map(\.id)) }
        }
    }
    @Published var topServices: [String] = StreamingService.defaultTopServices.map(\.rawValue) { didSet { save(topServices, Keys.topServices) } }
    @Published var splitByType = true { didSet { save(splitByType, Keys.splitByType) } }
    @Published var newServices: [String] = [] { didSet { save(newServices, Keys.newServices) } }
    @Published var refreshHours = 24 { didSet { save(refreshHours, Keys.refreshHours) } }

    /// Services the region has on Streaming Availability (from /countries), or nil before it is known.
    @Published private(set) var regionServices: Set<String>?
    /// FlixPatrol sources, tried in this order.
    @Published private(set) var flixPatrolSources: [FlixPatrolSource] = []
    /// Services with FlixPatrol charts in the region, or nil before it is known.
    @Published private(set) var flixPatrolServices: Set<String>?
    @Published private(set) var flixPatrolError: String?
    @Published private(set) var lastError: String?
    @Published private(set) var lastRefresh: Date?

    var hasFlixPatrol: Bool { !flixPatrolSources.isEmpty }
    /// At least one source of either kind.
    var hasAnySource: Bool { hasKey || hasFlixPatrol }
    var isActive: Bool { hasAnySource && enabled }

    private init() {
        reload()
        profileObserver = ProfileSettings.shared.objectWillChange
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in Task { @MainActor [weak self] in self?.reload() } }
    }

    private var loadingSettings = false

    /// Runs on every ProfileSettings change, so it only assigns what changed (no needless redraws).
    func reload() {
        loadingSettings = true
        defer { loadingSettings = false }
        migrateSingleKey()
        let newHasKey = !storedKeys.isEmpty
        if hasKey != newHasKey { hasKey = newHasKey }
        let sources = storedFlixPatrolSources
        if flixPatrolSources != sources { flixPatrolSources = sources }
        let newEnabled = defaults.object(forKey: defaults.profileKey(Keys.enabled)) as? Bool ?? true
        if enabled != newEnabled { enabled = newEnabled }
        let newRegion = defaults.string(forKey: defaults.profileKey(Keys.region)) ?? Self.defaultRegion
        if region != newRegion { region = newRegion }
        let newTop = defaults.stringArray(forKey: defaults.profileKey(Keys.topServices)) ?? StreamingService.defaultTopServices.map(\.rawValue)
        if topServices != newTop { topServices = newTop }
        let newSplit = defaults.object(forKey: defaults.profileKey(Keys.splitByType)) as? Bool ?? true
        if splitByType != newSplit { splitByType = newSplit }
        let newNew = defaults.stringArray(forKey: defaults.profileKey(Keys.newServices)) ?? []
        if newServices != newNew { newServices = newNew }
        let hours = defaults.integer(forKey: defaults.profileKey(Keys.refreshHours))
        let newHours = [12, 24, 48].contains(hours) ? hours : 24
        if refreshHours != newHours { refreshHours = newHours }
        let newRegionServices = cachedCountry(region).map { Set($0.services.map(\.id)) }
        if regionServices != newRegionServices { regionServices = newRegionServices }
        let newFlixPatrolServices = cachedFlixPatrolCountry(region).map { Set($0.services.map(\.id)) }
        if flixPatrolServices != newFlixPatrolServices { flixPatrolServices = newFlixPatrolServices }
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

    // MARK: FlixPatrol sources (tried in order; the next one is the fallback)

    private var storedFlixPatrolSources: [FlixPatrolSource] {
        guard let json = SecretStore.string(Keys.flixPatrolSources), let data = json.data(using: .utf8),
              let sources = try? JSONDecoder().decode([FlixPatrolSource].self, from: data) else { return [] }
        sources.forEach { AppLogger.shared.registerSensitiveValue($0.key) }
        return sources
    }

    private func saveFlixPatrolSources(_ sources: [FlixPatrolSource]) {
        let json = (try? JSONEncoder().encode(sources)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        SecretStore.set(sources.isEmpty ? "" : json, for: Keys.flixPatrolSources)
        sources.forEach { AppLogger.shared.registerSensitiveValue($0.key) }
        flixPatrolSources = sources
    }

    /// Adds a FlixPatrol API after checking it with one call. Returns an error message, or nil.
    func addFlixPatrolSource(url rawURL: String, key rawKey: String) async -> String? {
        let url = FlixPatrolSource.normalizedURL(rawURL)
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, !key.isEmpty else { return String(localized: "Enter both the URL and the API key.") }
        guard let parsed = URL(string: url), parsed.host != nil, parsed.scheme?.hasPrefix("http") == true else {
            return FlixPatrolError.invalidURL.errorDescription
        }
        AppLogger.shared.registerSensitiveValue(key)
        let source = FlixPatrolSource(url: url, key: key)
        if flixPatrolSources.contains(where: { $0.id == source.id }) { return String(localized: "That API is already added.") }
        do {
            let data = try await FlixPatrolClient(source: source).get("countries/\(region)", query: [])
            guard let country = try? JSONDecoder().decode(SACountry.self, from: data) else {
                return FlixPatrolError.invalidResponse.errorDescription
            }
            cache.write(data, for: flixPatrolCountryKey(region))
            flixPatrolServices = Set(country.services.map(\.id))
            saveFlixPatrolSources(flixPatrolSources + [source])
            flixPatrolError = nil
            listVersion += 1
            return nil
        } catch FlixPatrolError.http(404, _) {
            // The API works but has no charts for this region: keep it for other regions.
            saveFlixPatrolSources(flixPatrolSources + [source])
            flixPatrolServices = []
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func removeFlixPatrolSource(_ id: String) {
        saveFlixPatrolSources(flixPatrolSources.filter { $0.id != id })
        if flixPatrolSources.isEmpty { flixPatrolServices = nil; flixPatrolError = nil }
        listVersion += 1
    }

    /// Moves a source to the top, so it's tried first.
    func preferFlixPatrolSource(_ id: String) {
        guard let source = flixPatrolSources.first(where: { $0.id == id }) else { return }
        saveFlixPatrolSources([source] + flixPatrolSources.filter { $0.id != id })
    }

    /// Cached FlixPatrol data for `key`, refreshed first when older than `maxAge`.
    /// Sources are tried in order; if all fail, the saved copy is returned.
    private func flixPatrolData(_ key: String, path: String, query: [URLQueryItem], maxAge: TimeInterval, force: Bool = false) async -> Data? {
        let cached = cache.read(key)
        let due = force || cached.map { Date().timeIntervalSince($0.fetchedAt) > maxAge } ?? true
        guard due, hasFlixPatrol else { return cached?.data }
        var failure: Error?
        for source in flixPatrolSources {
            do {
                let data = try await FlixPatrolClient(source: source).get(path, query: query)
                cache.write(data, for: key)
                flixPatrolError = nil
                AppLogger.shared.info("[FlixPatrol] Fetched \(path)", data: ["host": source.host])
                return data
            } catch {
                failure = error
            }
        }
        flixPatrolError = failure?.localizedDescription
        return cached?.data
    }

    private func flixPatrolCountryKey(_ code: String) -> String { "fp-country|\(code)" }

    private func cachedFlixPatrolCountry(_ code: String) -> SACountry? {
        decodedCountry(flixPatrolCountryKey(code))
    }

    /// Decoded /countries entries, reused while the cached entry is unchanged.
    private var decodedCountries: [String: (fetchedAt: Date, country: SACountry?)] = [:]

    private func decodedCountry(_ key: String) -> SACountry? {
        guard let entry = cache.read(key) else { return nil }
        if let memo = decodedCountries[key], memo.fetchedAt == entry.fetchedAt { return memo.country }
        let country = try? JSONDecoder().decode(SACountry.self, from: entry.data)
        decodedCountries[key] = (entry.fetchedAt, country)
        return country
    }

    /// The region's FlixPatrol services: saved for a week, then asked again.
    private func loadFlixPatrolCountry(force: Bool = false) async {
        let key = flixPatrolCountryKey(region)
        if !force, let cached = cache.read(key), Date().timeIntervalSince(cached.fetchedAt) < 7 * 86_400,
           let country = try? JSONDecoder().decode(SACountry.self, from: cached.data) {
            flixPatrolServices = Set(country.services.map(\.id))
            return
        }
        for source in flixPatrolSources {
            do {
                let data = try await FlixPatrolClient(source: source).get("countries/\(region)", query: [])
                guard let country = try? JSONDecoder().decode(SACountry.self, from: data) else { continue }
                cache.write(data, for: key)
                flixPatrolServices = Set(country.services.map(\.id))
                return
            } catch FlixPatrolError.http(404, _) {
                // FlixPatrol doesn't cover this region.
                flixPatrolServices = []
                return
            } catch {
                flixPatrolError = error.localizedDescription
            }
        }
    }

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
        decodedCountry("country|\(code)")
    }

    private func loadCountry() async {
        guard let data = await data("country|\(region)", path: "countries/\(region)", query: [], maxAge: 30 * 86_400),
              let country = try? JSONDecoder().decode(SACountry.self, from: data) else { return }
        regionServices = Set(country.services.map(\.id))
    }

    /// A FlixPatrol source has charts for the service in the region (assumed until known).
    func flixPatrolCovers(_ service: StreamingService) -> Bool {
        hasFlixPatrol && (flixPatrolServices?.contains(service.rawValue) ?? true)
    }

    /// A Streaming Availability key can fetch the service's lists in the region (assumed until known).
    func streamingAvailabilityCovers(_ service: StreamingService) -> Bool {
        hasKey && service.hasStreamingAvailability && (regionServices?.contains(service.rawValue) ?? true)
    }

    /// Services with a Top 10 list from any source.
    var availableServices: [StreamingService] {
        StreamingService.allCases.filter { flixPatrolCovers($0) || streamingAvailabilityCovers($0) }
    }

    /// Services with "New on" rows (Streaming Availability only).
    var newRowServices: [StreamingService] {
        StreamingService.allCases.filter(streamingAvailabilityCovers)
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
        for service in newRowServices where newServices.contains(service.rawValue) {
            specs.append(RowSpec(id: "\(Self.rowIdPrefix)new-\(service.rawValue)", title: String(localized: "New on \(service.displayName)"), service: service))
        }
        return specs
    }

    /// The Home rows: from the cache, refreshing whatever is due within the budget.
    func sections(force: Bool = false) async -> [LibrarySection] {
        // The first Keychain read can fail (e.g. while macOS asks for access); try again.
        if !hasKey { migrateSingleKey(); hasKey = !storedKeys.isEmpty }
        if flixPatrolSources.isEmpty { flixPatrolSources = storedFlixPatrolSources }
        guard isActive, !isLoading else { return isActive ? cachedSections() : [] }
        isLoading = true
        defer { isLoading = false }

        if hasFlixPatrol, flixPatrolServices == nil || force { await loadFlixPatrolCountry(force: force) }
        if hasKey, regionServices == nil || force { await loadCountry() }
        let maxAge = TimeInterval(refreshHours) * 3600
        var sections: [LibrarySection] = []

        // A few lists at a time. Each Streaming Availability call reserves its budget
        // before it awaits, so the budget holds with several in flight.
        let specs = rowSpecs
        var results = [LibrarySection?](repeating: nil, count: specs.count)
        await withTaskGroup(of: (Int, LibrarySection?).self) { group in
            var next = 0
            func addNext() {
                guard next < specs.count else { return }
                let index = next
                next += 1
                group.addTask { (index, await self.fetchList(specs[index], maxAge: maxAge, force: force)) }
            }
            for _ in 0..<3 { addNext() }
            while let (index, section) = await group.next() {
                results[index] = section
                addNext()
            }
        }
        sections = results.compactMap { $0 }
        lastRefresh = Date()
        return sections
    }

    /// One list: cached, or fetched when due (or forced) within the budget.
    private func fetchList(_ spec: RowSpec, maxAge: TimeInterval, force: Bool) async -> LibrarySection? {
        if spec.id.hasPrefix("\(Self.rowIdPrefix)top-") {
            let type: String? = spec.id.hasSuffix("-movie") ? "movie" : (spec.id.hasSuffix("-series") ? "series" : nil)
            if flixPatrolCovers(spec.service) {
                var query = [URLQueryItem(name: "country", value: region), URLQueryItem(name: "service", value: spec.service.rawValue)]
                if let type { query.append(URLQueryItem(name: "show_type", value: type)) }
                if let data = await flixPatrolData(flixPatrolCacheKey(for: spec), path: "shows/top", query: query,
                                                  maxAge: min(maxAge, Self.flixPatrolMaxAge), force: force),
                   let shows = try? JSONDecoder().decode([SAShow].self, from: data),
                   let section = section(spec, shows: Self.flixPatrolRanked(shows, type: type)) {
                    return section
                }
            }
            // Fallback: Streaming Availability, within its budget.
            guard streamingAvailabilityCovers(spec.service) else { return nil }
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

    /// FlixPatrol's top 10 in chart order. Asked without a type it sends the
    /// movie and show charts separately; a mixed row alternates them by rank.
    static func flixPatrolRanked(_ shows: [SAShow], type: String?) -> [SAShow] {
        // A title can be ranked in several charts: use the movie or TV chart that
        // matches, else its best rank (some services only have "overall").
        func rank(_ show: SAShow) -> Int {
            let rankings = show.rankings ?? []
            let chart = show.isSeries ? "tv-shows" : "movies"
            return (rankings.first { $0.category == chart } ?? rankings.min { $0.rank < $1.rank })?.rank ?? .max
        }
        let ordered = shows.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
        guard type == nil else { return Array(ordered.prefix(10)) }
        let movies = ordered.filter { !$0.isSeries }
        let series = ordered.filter(\.isSeries)
        var mixed: [SAShow] = []
        for index in 0..<max(movies.count, series.count) {
            if index < movies.count { mixed.append(movies[index]) }
            if index < series.count { mixed.append(series[index]) }
        }
        return Array(mixed.prefix(10))
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
                if flixPatrolCovers(spec.service), let data = cache.read(flixPatrolCacheKey(for: spec))?.data,
                   let shows = try? JSONDecoder().decode([SAShow].self, from: data),
                   let section = section(spec, shows: Self.flixPatrolRanked(shows, type: type == "all" ? nil : type)) {
                    return section
                }
                guard streamingAvailabilityCovers(spec.service),
                      let data = cache.read("top|\(region)|\(spec.service.rawValue)|\(type)")?.data,
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
        /// "FlixPatrol" or "Streaming Availability".
        let source: String
        /// Refetching it costs a Streaming Availability call.
        let usesBudget: Bool
    }

    private func flixPatrolCacheKey(for spec: RowSpec) -> String {
        let type = spec.id.hasSuffix("-movie") ? "movie" : (spec.id.hasSuffix("-series") ? "series" : "all")
        return "fp|top|\(region)|\(spec.service.rawValue)|\(type)"
    }

    /// Top 10 rows a FlixPatrol source serves; everything else uses Streaming Availability.
    private func servedByFlixPatrol(_ spec: RowSpec) -> Bool {
        spec.id.hasPrefix("\(Self.rowIdPrefix)top-") && flixPatrolCovers(spec.service)
    }

    private func cacheKey(for spec: RowSpec) -> String {
        if spec.id.hasPrefix("\(Self.rowIdPrefix)new-") { return "new2|\(region)|\(spec.service.rawValue)" }
        let type = spec.id.hasSuffix("-movie") ? "movie" : (spec.id.hasSuffix("-series") ? "series" : "all")
        return "top|\(region)|\(spec.service.rawValue)|\(type)"
    }

    private var savedListsMemo: (key: String, lists: [SavedList])?

    /// Memoised: Settings reads this several times per redraw, and building it decodes every cached list.
    var savedLists: [SavedList] {
        let specs = rowSpecs
        let memoKey = "\(listVersion)|\(cache.generation)|\(region)|" + specs.map {
            "\($0.id):\(flixPatrolCovers($0.service)):\(streamingAvailabilityCovers($0.service))"
        }.joined(separator: ",")
        if let memo = savedListsMemo, memo.key == memoKey { return memo.lists }
        let lists = buildSavedLists(specs)
        savedListsMemo = (memoKey, lists)
        return lists
    }

    private func buildSavedLists(_ specs: [RowSpec]) -> [SavedList] {
        let sections = Dictionary(cachedSections().map { ($0.id, $0.items.count) }, uniquingKeysWith: { a, _ in a })
        return specs.map { spec in
            let flixPatrolEntry = servedByFlixPatrol(spec) ? cache.read(flixPatrolCacheKey(for: spec)) : nil
            let entry = flixPatrolEntry ?? cache.read(cacheKey(for: spec))
            return SavedList(id: spec.id, title: spec.title, fetchedAt: entry?.fetchedAt, count: sections[spec.id] ?? 0,
                             source: flixPatrolEntry != nil || (entry == nil && servedByFlixPatrol(spec))
                                 ? "FlixPatrol" : "Streaming Availability",
                             usesBudget: !servedByFlixPatrol(spec))
        }
    }

    /// Bumps after a refetch, so Settings shows new ages.
    @Published private(set) var listVersion = 0

    /// Fetches one list now (free from FlixPatrol, else 1 call), then asks Home to reload.
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
        regionServices = nil
        flixPatrolServices = nil
        NotificationCenter.default.post(name: Self.didUpdateNotification, object: nil)
    }

    /// Streaming Availability calls a full refresh costs (FlixPatrol lists are free).
    var callsPerRefresh: Int {
        guard isActive else { return 0 }
        return rowSpecs.filter { !servedByFlixPatrol($0) }.count
    }
}
