//
//  LiveTVStore.swift
//  FlixorMac
//
//  Personal build only (FLIXOR_LIVE_TV). State for Live TV mode: on/off, the
//  curated lineup, browsing filters and sort (tv-app.tsx logic), favorites,
//  recents, custom order, watch counts, and the guide.
//

#if FLIXOR_LIVE_TV
import Foundation
import CryptoKit
import SwiftUI

enum LiveTVSection: String, CaseIterable, Identifiable {
    case channels, favorites, recent
    var id: String { rawValue }
}

enum LiveTVScreen: String {
    case channels = "Channels"
    case guide = "Guide"
}

enum LiveTVSort: String, CaseIterable, Identifiable {
    case `default` = "Default"
    case custom = "Custom"
    case mostWatched = "Most watched"
    case az = "A–Z"
    case za = "Z–A"
    var id: String { rawValue }
}

@MainActor
final class LiveTVStore: ObservableObject {
    static let shared = LiveTVStore()

    /// US filters, from tv-app.tsx.
    static let usGenres = ["All", "News", "Sports", "Movies", "Shows", "Family", "Local", "Premium"]
    /// India categories and their labels, from tv-app.tsx.
    static let indiaGenres = ["All", "Shows", "Movies", "Family", "Music", "News", "Sports", "Factual", "Devotional"]
    static let indiaLanguages = ["All", "Hindi", "English"]
    nonisolated static func genreLabel(_ genre: String, market: LiveTVMarket) -> String {
        guard market == .india else { return genre }
        switch genre {
        case "All": return "All channels"
        case "Shows": return "Entertainment"
        case "Family": return "Kids"
        default: return genre
        }
    }

    // MARK: Mode

    /// Settings switch inside the personal build. Hides every entry point.
    @Published var featureEnabled: Bool {
        didSet {
            UserDefaults.standard.set(featureEnabled, forKey: Keys.enabled)
            if !featureEnabled { exit() }
        }
    }
    @Published var openOnLaunch: Bool {
        didSet { UserDefaults.standard.set(openOnLaunch, forKey: Keys.openOnLaunch) }
    }
    @Published private(set) var isActive = false
    @Published var screen: LiveTVScreen = .channels
    /// The channel on screen in the player, or nil when browsing.
    @Published var playing: LiveChannel?

    // MARK: Account

    @Published private(set) var account: LiveTVAccount?
    @Published private(set) var guideServer: LiveTVGuideServer?

    // MARK: Catalog

    enum LoadState: Equatable { case idle, loading, loaded, failed(String) }
    @Published private(set) var lineup: [LiveChannel] = []
    @Published private(set) var loadState: LoadState = .idle
    @Published private(set) var catalogUpdatedAt: Date?
    @Published private(set) var rulesMissing = false

    // MARK: Browsing (tv-app.tsx state)

    @Published var section: LiveTVSection = .channels
    @Published var market: LiveTVMarket = .us {
        didSet { if oldValue != market { genre = "All"; language = "All"; query = "" ; saveMarket() } }
    }
    @Published var genre = "All"
    @Published var language = "All"
    @Published var query = ""
    @Published var sort: LiveTVSort = .default {
        didSet { UserDefaults.standard.set(sort.rawValue, forKey: UserDefaults.standard.profileKey(Keys.sort)) }
    }

    // MARK: Library (profile-scoped)

    @Published private(set) var favorites: [String] = []
    @Published private(set) var recents: [String] = []
    @Published private(set) var customOrder: [String] = []
    @Published private(set) var watchCounts: [String: Int] = [:]

    // MARK: Guide

    @Published private(set) var guide: [String: LiveGuideEntry] = [:]
    @Published private(set) var now = Date()
    @Published private(set) var guideServerError: String?
    private var guideFetchedAt: [String: Date] = [:]
    private var guideInFlight: Set<String> = []
    private var clock: Timer?
    private var guideRefresh: Timer?
    private var visibleGuideIds = Set<String>()
    private var pendingGuideIds = Set<String>()
    private var guideFlush: Task<Void, Never>?
    private var catalogTask: Task<Void, Never>?

    private enum Keys {
        static let enabled = "liveTV.enabled"
        static let openOnLaunch = "liveTV.openOnLaunch"
        static let favorites = "liveTV.favorites"      // tuned-library-v1
        static let recents = "liveTV.recents"
        static let order = "liveTV.order"              // tuned-order-v1
        static let counts = "liveTV.watchCounts"       // tuned-watch-counts-v1
        static let sort = "liveTV.sort"
        static let market = "liveTV.market"
    }

    private init() {
        let defaults = UserDefaults.standard
        featureEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        openOnLaunch = defaults.bool(forKey: Keys.openOnLaunch)
        account = LiveTVSecrets.account
        guideServer = LiveTVSecrets.guideServer
        reloadProfileState()
        registerSecretsWithLogger()
    }

    /// Stream URLs carry the account credentials; keep them out of every log.
    private func registerSecretsWithLogger() {
        if let account {
            for value in [account.password, account.username, account.serverURL, account.baseURL?.host ?? "", account.baseURL?.absoluteString ?? ""] {
                AppLogger.shared.registerSensitiveValue(value)
            }
        }
        if let guideServer { AppLogger.shared.registerSensitiveValue(guideServer.password) }
        if let cookie = LiveTVSecrets.guideSessionCookie { AppLogger.shared.registerSensitiveValue(cookie) }
    }

    var isConfigured: Bool { account?.isComplete == true }

    // MARK: Enter / exit

    func enter() {
        guard featureEnabled else { return }
        reloadProfileState()
        withAnimation(DS.Motion.emphasized) { isActive = true }
        startClock()
        if lineup.isEmpty || isCatalogStale { loadCatalog() }
    }

    func exit() {
        playing = nil
        screen = .channels
        stopClock()
        withAnimation(DS.Motion.emphasized) { isActive = false }
    }

    func toggle() { isActive ? exit() : enter() }

    // MARK: Account

    func saveAccount(_ value: LiveTVAccount?) {
        let changed = value != account
        LiveTVSecrets.account = value
        account = value
        registerSecretsWithLogger()
        if changed {
            lineup = []
            guide = [:]
            guideFetchedAt = [:]
            loadState = .idle
            if value != nil && isActive { loadCatalog(force: true) }
        }
    }

    func saveGuideServer(_ value: LiveTVGuideServer?) {
        LiveTVSecrets.guideServer = value
        guideServer = value
        registerSecretsWithLogger()
        guide = [:]
        guideFetchedAt = [:]
        guideServerError = nil
    }

    // MARK: Catalog

    nonisolated private static let catalogTTL: TimeInterval = 30 * 60   // snapshot-cache.ts default
    nonisolated static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Flixor/LiveTV", isDirectory: true)
    }
    nonisolated static var rulesURL: URL { supportDirectory.appendingPathComponent("curated-lineup.json") }

    private var isCatalogStale: Bool {
        guard let at = catalogUpdatedAt else { return true }
        return Date().timeIntervalSince(at) >= Self.catalogTTL
    }

    nonisolated private static func cacheDirectory(for account: LiveTVAccount) -> URL {
        let digest = SHA256.hash(data: Data("\(account.baseURL?.absoluteString ?? "")\n\(account.username)".utf8))
        let name = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return supportDirectory.appendingPathComponent("cache-\(name)", isDirectory: true)
    }

    /// Shows the cached lineup at once and refreshes it in the background when
    /// older than 30 minutes, like xtream-web's snapshot cache.
    func loadCatalog(force: Bool = false) {
        guard let account, account.isComplete else { loadState = .failed(LiveTVError.notConfigured.localizedDescription); return }
        catalogTask?.cancel()
        if lineup.isEmpty { loadState = .loading }
        catalogTask = Task { [weak self] in
            let result = await Self.buildLineup(account: account, force: force)
            guard let self, !Task.isCancelled, self.account == account else { return }
            switch result {
            case .success(let built):
                self.rulesMissing = false
                self.lineup = built.lineup
                self.catalogUpdatedAt = built.updatedAt
                self.loadState = .loaded
                if built.needsRefresh { self.refreshCatalogInBackground(account: account) }
            case .failure(let error):
                if case .rulesMissing = error { self.rulesMissing = true }
                if self.lineup.isEmpty { self.loadState = .failed(error.localizedDescription) }
                AppLogger.shared.error("[LiveTV] Catalog load failed: \(LiveTVRedactor.redact(error.localizedDescription, account: account))")
            }
        }
    }

    private func refreshCatalogInBackground(account: LiveTVAccount) {
        Task { [weak self] in
            let result = await Self.buildLineup(account: account, force: true)
            guard let self, self.account == account, case .success(let built) = result else { return }
            self.lineup = built.lineup
            self.catalogUpdatedAt = built.updatedAt
            self.loadState = .loaded
        }
    }

    enum CatalogError: LocalizedError {
        case rulesMissing
        case other(String)
        var errorDescription: String? {
            switch self {
            case .rulesMissing: return "The curated lineup file is missing. Run the xtream-web lineup export for this Mac."
            case .other(let message): return message
            }
        }
    }

    private struct BuiltLineup: Sendable {
        let lineup: [LiveChannel]
        let updatedAt: Date
        let needsRefresh: Bool
    }

    private nonisolated static func buildLineup(account: LiveTVAccount, force: Bool) async -> Result<BuiltLineup, CatalogError> {
        await Task.detached(priority: .userInitiated) { () -> Result<BuiltLineup, CatalogError> in
            let fm = FileManager.default
            guard let rulesData = try? Data(contentsOf: rulesURL) else { return .failure(.rulesMissing) }
            guard let rules = try? JSONDecoder().decode(CuratedLineupRules.self, from: rulesData) else {
                return .failure(.other("The curated lineup file could not be read. Export it again from xtream-web."))
            }
            let dir = cacheDirectory(for: account)
            let streamsFile = dir.appendingPathComponent("get_live_streams.json")
            let categoriesFile = dir.appendingPathComponent("get_live_categories.json")
            var streamsData = try? Data(contentsOf: streamsFile)
            var categoriesData = try? Data(contentsOf: categoriesFile)
            let modified = (try? fm.attributesOfItem(atPath: streamsFile.path)[.modificationDate] as? Date) ?? .distantPast
            let stale = Date().timeIntervalSince(modified) >= catalogTTL
            var updatedAt = modified
            var needsRefresh = false
            if force || streamsData == nil || categoriesData == nil {
                do {
                    let client = XtreamClient(account: account)
                    async let categories = client.liveCategoriesData()
                    async let streams = client.liveStreamsData()
                    let (c, s) = try await (categories, streams)
                    guard (try? JSONSerialization.jsonObject(with: s)) is [Any], (try? JSONSerialization.jsonObject(with: c)) is [Any] else {
                        throw LiveTVError.provider("The provider's channel list could not be read.")
                    }
                    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                    try s.write(to: streamsFile, options: [.atomic])
                    try c.write(to: categoriesFile, options: [.atomic])
                    try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: streamsFile.path)
                    try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: categoriesFile.path)
                    streamsData = s
                    categoriesData = c
                    updatedAt = Date()
                } catch {
                    // Existing lineup stays available during outages.
                    if streamsData == nil || categoriesData == nil {
                        return .failure(.other(error.localizedDescription))
                    }
                }
            } else if stale {
                needsRefresh = true
            }
            guard let sData = streamsData, let cData = categoriesData,
                  let rawJSON = try? JSONSerialization.jsonObject(with: sData) as? [[String: Any]],
                  let catJSON = try? JSONSerialization.jsonObject(with: cData) as? [[String: Any]] else {
                return .failure(.other("The cached channel list could not be read."))
            }
            let raw = rawJSON.compactMap(XtreamRawStream.init(json:))
            let categories = catJSON.compactMap(XtreamRawCategory.init(json:))
            let lineup = LiveTVLineupBuilder(rules: rules).lineup(raw: raw, categories: categories)
            return .success(BuiltLineup(lineup: lineup, updatedAt: updatedAt, needsRefresh: needsRefresh))
        }.value
    }

    // MARK: Filtering and sorting (tv-app.tsx)

    var filteredChannels: [LiveChannel] {
        let q = query.lowercased()
        let saved = Set(favorites)
        let recentSet = Set(recents)
        let filtered = lineup.filter { c in
            c.market == market
                && (market != .india || language == "All" || c.language == language)
                && (section != .favorites || saved.contains(c.id))
                && (section != .recent || recentSet.contains(c.id))
                && (genre == "All" || (genre == "Premium" ? c.premium : c.genre == genre))
                && (q.isEmpty || "\(c.displayName) \(c.originalName)".lowercased().contains(q))
        }
        if section == .recent {
            return filtered.sorted { (recents.firstIndex(of: $0.id) ?? .max) < (recents.firstIndex(of: $1.id) ?? .max) }
        }
        switch sort {
        case .default:
            return filtered
        case .custom:
            let index = Dictionary(lineup.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { a, _ in a })
            func rank(_ c: LiveChannel) -> Int { customOrder.firstIndex(of: c.id) ?? (customOrder.count + (index[c.id] ?? 0)) }
            return filtered.jsStableSorted { rank($0) - rank($1) }
        case .mostWatched:
            return filtered.jsStableSorted { (watchCounts[$1.id] ?? 0) - (watchCounts[$0.id] ?? 0) }
        case .az, .za:
            let sign = sort == .za ? -1 : 1
            return filtered.jsStableSorted { JSString.localeCompare($0.displayName, $1.displayName) * sign }
        }
    }

    func count(market: LiveTVMarket, genre: String) -> Int {
        lineup.filter { $0.market == market && (genre == "All" || (genre == "Premium" ? $0.premium : $0.genre == genre)) }.count
    }

    func channel(id: String) -> LiveChannel? { lineup.first { $0.id == id } }

    // MARK: Library

    func isFavorite(_ c: LiveChannel) -> Bool { favorites.contains(c.id) }

    func toggleFavorite(_ c: LiveChannel) {
        favorites = favorites.contains(c.id) ? favorites.filter { $0 != c.id } : favorites + [c.id]
        saveList(favorites, Keys.favorites)
    }

    /// Called when playback starts (setWatch in tv-app.tsx, plus recents).
    func recordWatch(_ c: LiveChannel) {
        watchCounts[c.id, default: 0] += 1
        recents = [c.id] + recents.filter { $0 != c.id }
        if recents.count > 30 { recents = Array(recents.prefix(30)) }
        let defaults = UserDefaults.standard
        defaults.set(watchCounts, forKey: defaults.profileKey(Keys.counts))
        saveList(recents, Keys.recents)
    }

    /// moveChannel in tv-app.tsx.
    func moveChannel(_ id: String, by direction: Int) {
        var ids = customOrder.filter { id in lineup.contains { $0.id == id } }
        ids += lineup.map(\.id).filter { !customOrder.contains($0) && !ids.contains($0) }
        guard let from = ids.firstIndex(of: id) else { return }
        let to = from + direction
        guard to >= 0, to < ids.count else { return }
        ids.swapAt(from, to)
        customOrder = ids
        saveList(ids, Keys.order)
        sort = .custom
    }

    /// The lineup in custom-order rank, for the reorder sheet.
    var customOrderedLineup: [LiveChannel] {
        let index = Dictionary(lineup.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { a, _ in a })
        func rank(_ c: LiveChannel) -> Int { customOrder.firstIndex(of: c.id) ?? (customOrder.count + (index[c.id] ?? 0)) }
        return lineup.jsStableSorted { rank($0) - rank($1) }
    }

    func reloadProfileState() {
        let d = UserDefaults.standard
        favorites = d.stringArray(forKey: d.profileKey(Keys.favorites)) ?? []
        recents = d.stringArray(forKey: d.profileKey(Keys.recents)) ?? []
        customOrder = d.stringArray(forKey: d.profileKey(Keys.order)) ?? []
        watchCounts = (d.dictionary(forKey: d.profileKey(Keys.counts)) as? [String: Int]) ?? [:]
        sort = LiveTVSort(rawValue: d.string(forKey: d.profileKey(Keys.sort)) ?? "") ?? .default
        if let raw = d.string(forKey: d.profileKey(Keys.market)), let value = LiveTVMarket(rawValue: raw), value != market {
            market = value
        }
    }

    private func saveList(_ ids: [String], _ key: String) {
        let d = UserDefaults.standard
        d.set(ids, forKey: d.profileKey(key))
    }

    private func saveMarket() {
        let d = UserDefaults.standard
        d.set(market.rawValue, forKey: d.profileKey(Keys.market))
    }

    // MARK: Guide

    private func startClock() {
        now = Date()
        clock?.invalidate()
        clock = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
        guideRefresh?.invalidate()
        // tv-app.tsx polls guides every two minutes while open.
        guideRefresh = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.requestGuide(for: Array(self.visibleGuideIds))
            }
        }
    }

    private func stopClock() {
        clock?.invalidate(); clock = nil
        guideRefresh?.invalidate(); guideRefresh = nil
    }

    /// Rows call this as they appear; requests go out in one batch shortly after.
    func noteGuideVisible(_ id: String) {
        visibleGuideIds.insert(id)
        pendingGuideIds.insert(id)
        guideFlush?.cancel()
        guideFlush = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self, !Task.isCancelled else { return }
            let ids = Array(self.pendingGuideIds)
            self.pendingGuideIds = []
            self.requestGuide(for: ids)
        }
    }

    func noteGuideHidden(_ id: String) { visibleGuideIds.remove(id) }

    /// Loads guide entries for the given channel ids when missing or older than 2 minutes.
    func requestGuide(for ids: [String]) {
        let due = Array(NSOrderedSet(array: ids)).compactMap { $0 as? String }.filter { id in
            !guideInFlight.contains(id) && (guideFetchedAt[id].map { Date().timeIntervalSince($0) >= 120 } ?? true)
        }
        guard !due.isEmpty, let account else { return }
        guideInFlight.formUnion(due)
        let server = guideServer?.isComplete == true ? guideServer : nil
        // Small batches, three at a time, each shown as soon as it arrives, so
        // one slow batch never holds up the rest of the screen.
        let chunks = stride(from: 0, to: due.count, by: 12).map { Array(due[$0..<min($0 + 12, due.count)]) }
        Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                var running = 0
                for chunk in chunks {
                    if running >= 3 { await group.next(); running -= 1 }
                    running += 1
                    group.addTask { [weak self] in
                        var results: [String: LiveGuideEntry] = [:]
                        var serverError: String?
                        if let server {
                            do { results = try await XtreamWebGuideClient(server: server).guide(ids: chunk) }
                            catch { serverError = error.localizedDescription }
                        }
                        // Provider fallback for anything the server did not answer (or no server set up).
                        let missing = chunk.filter { results[$0] == nil }
                        if !missing.isEmpty {
                            results.merge(await Self.providerGuide(ids: missing, account: account, labelled: server != nil)) { _, new in new }
                        }
                        let finished = results
                        let error = serverError
                        await MainActor.run { [weak self] in
                            guard let self else { return }
                            let fetchedAt = Date()
                            for id in chunk {
                                self.guideInFlight.remove(id)
                                self.guideFetchedAt[id] = fetchedAt
                            }
                            self.guide.merge(finished.mapValues { $0.normalized() }) { _, new in new }
                            if server != nil { self.guideServerError = error }
                            if let error { AppLogger.shared.info("[LiveTV] Guide server: \(error)") }
                        }
                    }
                }
            }
        }
    }

    private nonisolated static func providerGuide(ids: [String], account: LiveTVAccount, labelled: Bool) async -> [String: LiveGuideEntry] {
        let client = XtreamClient(account: account)
        var out: [String: LiveGuideEntry] = [:]
        // Four at a time, like /api/guide.
        for start in stride(from: 0, to: ids.count, by: 4) {
            let slice = Array(ids[start..<min(start + 4, ids.count)])
            await withTaskGroup(of: (String, LiveGuideEntry).self) { group in
                for id in slice {
                    group.addTask {
                        do {
                            let programs = try await client.shortEPG(streamId: id).filter { $0.end > Date() }
                            return (id, LiveGuideEntry(programs: programs, unavailable: false, source: labelled ? "Provider guide (xtream-web server unavailable)" : "Provider guide"))
                        } catch {
                            return (id, LiveGuideEntry(programs: [], unavailable: true, source: nil))
                        }
                    }
                }
                for await (id, entry) in group { out[id] = entry }
            }
        }
        return out
    }

    /// Guide entry for a channel. xtream-web keys the guide by the channel id.
    func guideEntry(for c: LiveChannel) -> LiveGuideEntry? { guide[c.id] }
}
#endif
