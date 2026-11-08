//
//  UserDefaults+Extensions.swift
//  FlixorMac
//
//  UserDefaults extensions for app preferences
//  Settings are profile-scoped for Plex Home multi-profile support
//

import Foundation
import Security
import FlixorKit

// MARK: - Secret Store (Keychain)

/// Synchronous Keychain storage for user-entered secrets (API keys, session
/// cookies) that must not live in UserDefaults plists. Values are cached in
/// memory so frequent reads (view bodies, `isReady()` checks) stay cheap.
enum SecretStore {
    private static let service = "com.flixor.mac.secrets"
    private static let lock = NSLock()
    private static var cache: [String: String] = [:]

    static func string(_ account: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        if let cached = cache[account] { return cached.isEmpty ? nil : cached }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        let value = (status == errSecSuccess ? (result as? Data).flatMap { String(data: $0, encoding: .utf8) } : nil) ?? ""
        cache[account] = value
        return value.isEmpty ? nil : value
    }

    /// Stores `value`, or deletes the item when `value` is empty.
    static func set(_ value: String, for account: String) {
        lock.lock(); defer { lock.unlock() }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        if !value.isEmpty, let data = value.data(using: .utf8) {
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let status = SecItemAdd(add as CFDictionary, nil)
            if status != errSecSuccess {
                print("❌ [SecretStore] Failed to save \(account): status \(status)")
            }
        }
        cache[account] = value
    }
}

extension UserDefaults {
    /// Reads a secret from the Keychain, migrating any legacy plaintext value
    /// stored in UserDefaults under the same key (then removing it).
    func secret(forKey key: String) -> String {
        if let value = SecretStore.string(key) { return value }
        if let legacy = string(forKey: key), !legacy.isEmpty {
            SecretStore.set(legacy, for: key)
            removeObject(forKey: key)
            return legacy
        }
        return ""
    }

    func setSecret(_ value: String, forKey key: String) {
        SecretStore.set(value, for: key)
        removeObject(forKey: key)
    }
}

extension UserDefaults {
    // MARK: - Profile-Scoped Key Helper

    /// Get a profile-scoped key for settings that should be isolated per profile
    private func profileKey(_ baseKey: String) -> String {
        return ProfileStorage.shared.getProfileKey(baseKey)
    }

    // MARK: - Keys

    private enum Keys {
        static let backendBaseURL = "backendBaseURL"
        static let defaultQuality = "defaultQuality"
        static let autoPlayNext = "autoPlayNext"
        static let skipIntroAutomatically = "skipIntroAutomatically"
        static let skipCreditsAutomatically = "skipCreditsAutomatically"
        static let traktAutoSyncWatched = "traktAutoSyncWatched"
        static let traktSyncRatings = "traktSyncRatings"
        static let traktSyncWatchlist = "traktSyncWatchlist"
        static let traktScrobbleEnabled = "traktScrobbleEnabled"
    }

    // MARK: - Backend URL

    var backendBaseURL: String {
        get { string(forKey: Keys.backendBaseURL) ?? "http://localhost:3001" }
        set { set(newValue, forKey: Keys.backendBaseURL) }
    }

    // MARK: - Playback Preferences (Profile-Scoped)

    var defaultQuality: Int {
        get { integer(forKey: profileKey(Keys.defaultQuality)) != 0 ? integer(forKey: profileKey(Keys.defaultQuality)) : 12000 }
        set { set(newValue, forKey: profileKey(Keys.defaultQuality)) }
    }

    var autoPlayNext: Bool {
        get { object(forKey: profileKey(Keys.autoPlayNext)) as? Bool ?? true }
        set { set(newValue, forKey: profileKey(Keys.autoPlayNext)) }
    }

    var skipIntroAutomatically: Bool {
        get { object(forKey: profileKey(Keys.skipIntroAutomatically)) as? Bool ?? true }  // Default: enabled
        set { set(newValue, forKey: profileKey(Keys.skipIntroAutomatically)) }
    }

    var skipCreditsAutomatically: Bool {
        get { object(forKey: profileKey(Keys.skipCreditsAutomatically)) as? Bool ?? true }  // Default: enabled
        set { set(newValue, forKey: profileKey(Keys.skipCreditsAutomatically)) }
    }
}

extension UserDefaults {
    // Trakt sync settings (Profile-Scoped)
    var traktAutoSyncWatched: Bool {
        get { object(forKey: profileKey(Keys.traktAutoSyncWatched)) as? Bool ?? true }
        set { set(newValue, forKey: profileKey(Keys.traktAutoSyncWatched)) }
    }

    var traktSyncRatings: Bool {
        get { object(forKey: profileKey(Keys.traktSyncRatings)) as? Bool ?? true }
        set { set(newValue, forKey: profileKey(Keys.traktSyncRatings)) }
    }

    var traktSyncWatchlist: Bool {
        get { object(forKey: profileKey(Keys.traktSyncWatchlist)) as? Bool ?? true }
        set { set(newValue, forKey: profileKey(Keys.traktSyncWatchlist)) }
    }

    var traktScrobbleEnabled: Bool {
        get { object(forKey: profileKey(Keys.traktScrobbleEnabled)) as? Bool ?? true }
        set { set(newValue, forKey: profileKey(Keys.traktScrobbleEnabled)) }
    }
}

// MARK: - MDBList Settings (Profile-Scoped)

extension UserDefaults {
    private enum MDBListKeys {
        static let enabled = "mdblistEnabled"
        static let apiKey = "mdblistApiKey"
    }

    var mdblistEnabled: Bool {
        get { bool(forKey: profileKey(MDBListKeys.enabled)) }
        set { set(newValue, forKey: profileKey(MDBListKeys.enabled)) }
    }

    var mdblistApiKey: String {
        get { secret(forKey: profileKey(MDBListKeys.apiKey)) }
        set { setSecret(newValue, forKey: profileKey(MDBListKeys.apiKey)) }
    }
}

// MARK: - Overseerr Settings (Profile-Scoped)

enum OverseerrAuthMethod: String {
    case apiKey = "api_key"
    case plex = "plex"
}

extension UserDefaults {
    private enum OverseerrKeys {
        static let enabled = "overseerrEnabled"
        static let url = "overseerrUrl"
        static let authMethod = "overseerrAuthMethod"
        static let apiKey = "overseerrApiKey"
        static let sessionCookie = "overseerrSessionCookie"
        static let plexUsername = "overseerrPlexUsername"
    }

    var overseerrEnabled: Bool {
        get { bool(forKey: profileKey(OverseerrKeys.enabled)) }
        set { set(newValue, forKey: profileKey(OverseerrKeys.enabled)) }
    }

    var overseerrUrl: String {
        get { string(forKey: profileKey(OverseerrKeys.url)) ?? "" }
        set { set(newValue, forKey: profileKey(OverseerrKeys.url)) }
    }

    var overseerrAuthMethod: OverseerrAuthMethod {
        get {
            guard let rawValue = string(forKey: profileKey(OverseerrKeys.authMethod)),
                  let method = OverseerrAuthMethod(rawValue: rawValue) else {
                // Plex auth needs a Plex token, so it can't be the default without one.
                return appMode == .stremio ? .apiKey : .plex
            }
            return method
        }
        set { set(newValue.rawValue, forKey: profileKey(OverseerrKeys.authMethod)) }
    }

    var overseerrApiKey: String {
        get { secret(forKey: profileKey(OverseerrKeys.apiKey)) }
        set { setSecret(newValue, forKey: profileKey(OverseerrKeys.apiKey)) }
    }

    var overseerrSessionCookie: String {
        get { secret(forKey: profileKey(OverseerrKeys.sessionCookie)) }
        set { setSecret(newValue, forKey: profileKey(OverseerrKeys.sessionCookie)) }
    }

    var overseerrPlexUsername: String {
        get { string(forKey: profileKey(OverseerrKeys.plexUsername)) ?? "" }
        set { set(newValue, forKey: profileKey(OverseerrKeys.plexUsername)) }
    }

    /// Clear Overseerr authentication data
    func clearOverseerrAuth() {
        overseerrApiKey = ""
        overseerrSessionCookie = ""
        overseerrPlexUsername = ""
    }
}

// MARK: - TMDB Settings (Mixed: API key global, preferences profile-scoped)

extension UserDefaults {
    private enum TMDBKeys {
        static let apiKey = "tmdbApiKey"
        static let language = "tmdbLanguage"
        static let enrichMetadata = "tmdbEnrichMetadata"
        static let localizedMetadata = "tmdbLocalizedMetadata"
    }

    /// TMDB API key (global - shared across all profiles)
    var tmdbApiKey: String {
        get { string(forKey: TMDBKeys.apiKey) ?? "" }
        set { set(newValue, forKey: TMDBKeys.apiKey) }
    }

    /// TMDB language preference (profile-scoped)
    var tmdbLanguage: String {
        get { string(forKey: profileKey(TMDBKeys.language)) ?? "en" }
        set { set(newValue, forKey: profileKey(TMDBKeys.language)) }
    }

    /// Enrich metadata from TMDB (profile-scoped)
    var tmdbEnrichMetadata: Bool {
        get { object(forKey: profileKey(TMDBKeys.enrichMetadata)) as? Bool ?? true }
        set { set(newValue, forKey: profileKey(TMDBKeys.enrichMetadata)) }
    }

    /// Use localized metadata from TMDB (profile-scoped)
    var tmdbLocalizedMetadata: Bool {
        get { bool(forKey: profileKey(TMDBKeys.localizedMetadata)) }
        set { set(newValue, forKey: profileKey(TMDBKeys.localizedMetadata)) }
    }
}

// MARK: - Home Screen Settings (Profile-Scoped)

extension UserDefaults {
    private enum HomeKeys {
        static let heroLayout = "heroLayout"
        static let showHeroSection = "showHeroSection"
        static let heroAutoRotate = "heroAutoRotate"
        static let showContinueWatching = "showContinueWatching"
        static let continueWatchingLayout = "continueWatchingLayout"
        static let rowLayout = "rowLayout"
        static let showTrendingRows = "showTrendingRows"
        static let showTraktRows = "showTraktRows"
        static let showPlexPopular = "showPlexPopular"
        static let showWatchlist = "showWatchlist"
        static let showCollectionRows = "showCollectionRows"
        static let hiddenCollectionKeys = "hiddenCollectionKeys"
        static let posterSize = "posterSize"
        static let showPosterTitles = "showPosterTitles"
        static let showLibraryTitles = "showLibraryTitles"
        static let posterCornerRadius = "posterCornerRadius"
        static let groupRecentlyAddedEpisodes = "groupRecentlyAddedEpisodes"
    }

    var heroLayout: String {
        get { string(forKey: profileKey(HomeKeys.heroLayout)) ?? "billboard" }
        set { set(newValue, forKey: profileKey(HomeKeys.heroLayout)) }
    }

    var showHeroSection: Bool {
        get { object(forKey: profileKey(HomeKeys.showHeroSection)) as? Bool ?? true }
        set { set(newValue, forKey: profileKey(HomeKeys.showHeroSection)) }
    }

    var heroAutoRotate: Bool {
        get { object(forKey: profileKey(HomeKeys.heroAutoRotate)) as? Bool ?? true }
        set { set(newValue, forKey: profileKey(HomeKeys.heroAutoRotate)) }
    }

    var showContinueWatching: Bool {
        get { object(forKey: profileKey(HomeKeys.showContinueWatching)) as? Bool ?? true }
        set { set(newValue, forKey: profileKey(HomeKeys.showContinueWatching)) }
    }

    var continueWatchingLayout: String {
        get { string(forKey: profileKey(HomeKeys.continueWatchingLayout)) ?? "landscape" }
        set { set(newValue, forKey: profileKey(HomeKeys.continueWatchingLayout)) }
    }

    var rowLayout: String {
        get { string(forKey: profileKey(HomeKeys.rowLayout)) ?? "landscape" }
        set { set(newValue, forKey: profileKey(HomeKeys.rowLayout)) }
    }

    var showTrendingRows: Bool {
        get { object(forKey: profileKey(HomeKeys.showTrendingRows)) as? Bool ?? true }
        set { set(newValue, forKey: profileKey(HomeKeys.showTrendingRows)) }
    }

    var showTraktRows: Bool {
        get { object(forKey: profileKey(HomeKeys.showTraktRows)) as? Bool ?? true }
        set { set(newValue, forKey: profileKey(HomeKeys.showTraktRows)) }
    }

    var showPlexPopular: Bool {
        get { object(forKey: profileKey(HomeKeys.showPlexPopular)) as? Bool ?? true }
        set { set(newValue, forKey: profileKey(HomeKeys.showPlexPopular)) }
    }

    var showWatchlist: Bool {
        get { object(forKey: profileKey(HomeKeys.showWatchlist)) as? Bool ?? true }
        set { set(newValue, forKey: profileKey(HomeKeys.showWatchlist)) }
    }

    var showCollectionRows: Bool {
        get { object(forKey: profileKey(HomeKeys.showCollectionRows)) as? Bool ?? true }
        set { set(newValue, forKey: profileKey(HomeKeys.showCollectionRows)) }
    }

    var hiddenCollectionKeys: [String] {
        get { stringArray(forKey: profileKey(HomeKeys.hiddenCollectionKeys)) ?? [] }
        set { set(newValue, forKey: profileKey(HomeKeys.hiddenCollectionKeys)) }
    }

    var posterSize: String {
        get { string(forKey: profileKey(HomeKeys.posterSize)) ?? "medium" }
        set { set(newValue, forKey: profileKey(HomeKeys.posterSize)) }
    }

    var showPosterTitles: Bool {
        get { object(forKey: profileKey(HomeKeys.showPosterTitles)) as? Bool ?? true }
        set { set(newValue, forKey: profileKey(HomeKeys.showPosterTitles)) }
    }

    var showLibraryTitles: Bool {
        get { object(forKey: profileKey(HomeKeys.showLibraryTitles)) as? Bool ?? true }
        set { set(newValue, forKey: profileKey(HomeKeys.showLibraryTitles)) }
    }

    var posterCornerRadius: String {
        get { string(forKey: profileKey(HomeKeys.posterCornerRadius)) ?? "medium" }
        set { set(newValue, forKey: profileKey(HomeKeys.posterCornerRadius)) }
    }

    /// Group recently added TV episodes by series (default: true)
    var groupRecentlyAddedEpisodes: Bool {
        get { object(forKey: profileKey(HomeKeys.groupRecentlyAddedEpisodes)) as? Bool ?? true }
        set { set(newValue, forKey: profileKey(HomeKeys.groupRecentlyAddedEpisodes)) }
    }
}

// MARK: - Catalog Settings (Profile-Scoped)

extension UserDefaults {
    private enum CatalogKeys {
        static let enabledLibraryKeys = "enabledLibraryKeys"
    }

    /// Enabled library keys (profile-scoped - each profile can have different library access)
    var enabledLibraryKeys: [String] {
        get { stringArray(forKey: profileKey(CatalogKeys.enabledLibraryKeys)) ?? [] }
        set { set(newValue, forKey: profileKey(CatalogKeys.enabledLibraryKeys)) }
    }
}

// MARK: - Sidebar Settings (Profile-Scoped)

extension UserDefaults {
    private enum SidebarKeys {
        static let showNewPopularTab = "showNewPopularTab"
    }

    var showNewPopularTab: Bool {
        get { object(forKey: profileKey(SidebarKeys.showNewPopularTab)) as? Bool ?? true }
        set { set(newValue, forKey: profileKey(SidebarKeys.showNewPopularTab)) }
    }
}

// MARK: - Search Settings (Profile-Scoped)

extension UserDefaults {
    private enum SearchKeys {
        static let includeTmdbInSearch = "includeTmdbInSearch"
    }

    var includeTmdbInSearch: Bool {
        get { object(forKey: profileKey(SearchKeys.includeTmdbInSearch)) as? Bool ?? true }
        set { set(newValue, forKey: profileKey(SearchKeys.includeTmdbInSearch)) }
    }
}

// MARK: - Details Screen Settings (Profile-Scoped)

extension UserDefaults {
    private enum DetailsKeys {
        static let detailsScreenLayout = "detailsScreenLayout"
        static let episodeLayout = "episodeLayout"
        static let suggestedLayout = "suggestedLayout"
        static let showRelatedContent = "showRelatedContent"
        static let showCastCrew = "showCastCrew"
    }

    var detailsScreenLayout: String {
        get { string(forKey: profileKey(DetailsKeys.detailsScreenLayout)) ?? "tabbed" }
        set { set(newValue, forKey: profileKey(DetailsKeys.detailsScreenLayout)) }
    }

    var episodeLayout: String {
        get { string(forKey: profileKey(DetailsKeys.episodeLayout)) ?? "horizontal" }
        set { set(newValue, forKey: profileKey(DetailsKeys.episodeLayout)) }
    }

    var suggestedLayout: String {
        get { string(forKey: profileKey(DetailsKeys.suggestedLayout)) ?? "landscape" }
        set { set(newValue, forKey: profileKey(DetailsKeys.suggestedLayout)) }
    }

    var showRelatedContent: Bool {
        get { object(forKey: profileKey(DetailsKeys.showRelatedContent)) as? Bool ?? true }
        set { set(newValue, forKey: profileKey(DetailsKeys.showRelatedContent)) }
    }

    var showCastCrew: Bool {
        get { object(forKey: profileKey(DetailsKeys.showCastCrew)) as? Bool ?? true }
        set { set(newValue, forKey: profileKey(DetailsKeys.showCastCrew)) }
    }
}

// MARK: - Ratings Display Settings (Profile-Scoped)

extension UserDefaults {
    private enum RatingsKeys {
        static let showIMDbRating = "showIMDbRating"
        static let showRottenTomatoesCritic = "showRottenTomatoesCritic"
        static let showRottenTomatoesAudience = "showRottenTomatoesAudience"
    }

    var showIMDbRating: Bool {
        get { object(forKey: profileKey(RatingsKeys.showIMDbRating)) as? Bool ?? true }
        set { set(newValue, forKey: profileKey(RatingsKeys.showIMDbRating)) }
    }

    var showRottenTomatoesCritic: Bool {
        get { object(forKey: profileKey(RatingsKeys.showRottenTomatoesCritic)) as? Bool ?? true }
        set { set(newValue, forKey: profileKey(RatingsKeys.showRottenTomatoesCritic)) }
    }

    var showRottenTomatoesAudience: Bool {
        get { object(forKey: profileKey(RatingsKeys.showRottenTomatoesAudience)) as? Bool ?? true }
        set { set(newValue, forKey: profileKey(RatingsKeys.showRottenTomatoesAudience)) }
    }
}

// MARK: - Continue Watching Settings (Profile-Scoped)

extension UserDefaults {
    private enum ContinueWatchingKeys {
        static let useCachedStreams = "useCachedStreams"
        static let streamCacheTTL = "streamCacheTTL"
    }

    var useCachedStreams: Bool {
        get { bool(forKey: profileKey(ContinueWatchingKeys.useCachedStreams)) }
        set { set(newValue, forKey: profileKey(ContinueWatchingKeys.useCachedStreams)) }
    }

    var streamCacheTTL: Int {
        get { object(forKey: profileKey(ContinueWatchingKeys.streamCacheTTL)) as? Int ?? 3600 }
        set { set(newValue, forKey: profileKey(ContinueWatchingKeys.streamCacheTTL)) }
    }
}

// MARK: - Stremio Settings (Profile-Scoped)

extension UserDefaults {
    private enum StremioKeys {
        static let playbackEnabled = "stremioPlaybackEnabled"
        static let autoPlayBestSource = "stremioAutoPlayBestSource"
        static let showOnTmdbDetails = "stremioShowOnTmdbDetails"
        static let preferCachedSourceResume = "stremioPreferCachedSourceResume"
        static let subtitleAddonsEnabled = "stremioSubtitleAddonsEnabled"
        static let unsupportedSourceVisibility = "stremioUnsupportedSourceVisibility"
        static let stremioAddons = "stremioAddons"
        static let stremioAddonOrder = "stremioAddonOrder"
        static let stremioStreamCache = "stremioStreamCache"
        static let stremioResumeStates = "stremioResumeStates"
        static let stremioRemovedDefaultAddons = "stremioRemovedDefaultAddons"
        static let showCatalogRows = "stremioShowCatalogRows"
        static let catalogSearch = "stremioCatalogSearch"
    }

    var stremioPlaybackEnabled: Bool {
        get { bool(forKey: profileKey(StremioKeys.playbackEnabled)) }
        set { set(newValue, forKey: profileKey(StremioKeys.playbackEnabled)) }
    }

    var stremioAutoPlayBestSource: Bool {
        get { bool(forKey: profileKey(StremioKeys.autoPlayBestSource)) }
        set { set(newValue, forKey: profileKey(StremioKeys.autoPlayBestSource)) }
    }

    /// Show a home row per browsable addon catalog. Defaults on - a user who
    /// installed a catalog addon wants to see it.
    var showStremioCatalogRows: Bool {
        get { object(forKey: profileKey(StremioKeys.showCatalogRows)) as? Bool ?? true }
        set { set(newValue, forKey: profileKey(StremioKeys.showCatalogRows)) }
    }

    /// Merge addon catalog search results into the Search screen.
    var stremioCatalogSearchEnabled: Bool {
        get { object(forKey: profileKey(StremioKeys.catalogSearch)) as? Bool ?? true }
        set { set(newValue, forKey: profileKey(StremioKeys.catalogSearch)) }
    }

    var stremioShowOnTmdbDetails: Bool {
        get { object(forKey: profileKey(StremioKeys.showOnTmdbDetails)) as? Bool ?? true }
        set { set(newValue, forKey: profileKey(StremioKeys.showOnTmdbDetails)) }
    }

    var stremioPreferCachedSourceResume: Bool {
        get { object(forKey: profileKey(StremioKeys.preferCachedSourceResume)) as? Bool ?? true }
        set { set(newValue, forKey: profileKey(StremioKeys.preferCachedSourceResume)) }
    }

    var stremioSubtitleAddonsEnabled: Bool {
        get { object(forKey: profileKey(StremioKeys.subtitleAddonsEnabled)) as? Bool ?? true }
        set { set(newValue, forKey: profileKey(StremioKeys.subtitleAddonsEnabled)) }
    }

    var stremioUnsupportedSourceVisibility: StremioUnsupportedSourceVisibility {
        get {
            guard let rawValue = string(forKey: profileKey(StremioKeys.unsupportedSourceVisibility)),
                  let visibility = StremioUnsupportedSourceVisibility(rawValue: rawValue) else {
                return .showDisabled
            }
            return visibility
        }
        set { set(newValue.rawValue, forKey: profileKey(StremioKeys.unsupportedSourceVisibility)) }
    }

    func getStremioAddons() -> [StremioAddonManifest] {
        guard let data = data(forKey: profileKey(StremioKeys.stremioAddons)) else { return [] }
        return (try? JSONDecoder().decode([StremioAddonManifest].self, from: data)) ?? []
    }

    func setStremioAddons(_ addons: [StremioAddonManifest]) {
        guard let data = try? JSONEncoder().encode(addons) else { return }
        set(data, forKey: profileKey(StremioKeys.stremioAddons))
    }

    func getStremioAddonOrder() -> [String] {
        guard let data = data(forKey: profileKey(StremioKeys.stremioAddonOrder)) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    func setStremioAddonOrder(_ order: [String]) {
        guard let data = try? JSONEncoder().encode(order) else { return }
        set(data, forKey: profileKey(StremioKeys.stremioAddonOrder))
    }

    func getStremioStreamCache() -> [String: CachedPlaybackSource] {
        guard let data = data(forKey: profileKey(StremioKeys.stremioStreamCache)) else { return [:] }
        return (try? JSONDecoder().decode([String: CachedPlaybackSource].self, from: data)) ?? [:]
    }

    func setStremioStreamCache(_ cache: [String: CachedPlaybackSource]) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        set(data, forKey: profileKey(StremioKeys.stremioStreamCache))
    }

    func getStremioResumeStates() -> [String: ResumeState] {
        guard let data = data(forKey: profileKey(StremioKeys.stremioResumeStates)) else { return [:] }
        return (try? JSONDecoder().decode([String: ResumeState].self, from: data)) ?? [:]
    }

    func setStremioResumeStates(_ states: [String: ResumeState]) {
        guard let data = try? JSONEncoder().encode(states) else { return }
        set(data, forKey: profileKey(StremioKeys.stremioResumeStates))
    }

    func getRemovedStremioDefaultAddons() -> [String] {
        guard let data = data(forKey: profileKey(StremioKeys.stremioRemovedDefaultAddons)) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    func setRemovedStremioDefaultAddons(_ addonIds: [String]) {
        guard let data = try? JSONEncoder().encode(addonIds) else { return }
        set(data, forKey: profileKey(StremioKeys.stremioRemovedDefaultAddons))
    }
}

// MARK: - Local Library (Profile-Scoped)

/// Watch history and watchlist kept on this Mac, so Continue Watching and My List
/// work with no Plex server and no linked Trakt account.
extension UserDefaults {
    private enum LocalLibraryKeys {
        static let watchHistory = "localWatchHistory"
        static let watchlist = "localWatchlist"
    }

    func getLocalWatchHistory() -> [String: WatchHistoryEntry] {
        guard let data = data(forKey: profileKey(LocalLibraryKeys.watchHistory)) else { return [:] }
        return (try? JSONDecoder().decode([String: WatchHistoryEntry].self, from: data)) ?? [:]
    }

    func setLocalWatchHistory(_ entries: [String: WatchHistoryEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        set(data, forKey: profileKey(LocalLibraryKeys.watchHistory))
    }

    func getLocalWatchlist() -> [String: LocalWatchlistEntry] {
        guard let data = data(forKey: profileKey(LocalLibraryKeys.watchlist)) else { return [:] }
        return (try? JSONDecoder().decode([String: LocalWatchlistEntry].self, from: data)) ?? [:]
    }

    func setLocalWatchlist(_ entries: [String: LocalWatchlistEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        set(data, forKey: profileKey(LocalLibraryKeys.watchlist))
    }
}

// MARK: - Discovery Mode Settings (Profile-Scoped)

extension UserDefaults {
    private enum DiscoveryKeys {
        static let discoveryDisabled = "discoveryDisabled"
    }

    /// When true, disables all discovery features (Library Only Mode)
    /// Profile-scoped: each profile can have different discovery settings
    var discoveryDisabled: Bool {
        get { bool(forKey: profileKey(DiscoveryKeys.discoveryDisabled)) }
        set { set(newValue, forKey: profileKey(DiscoveryKeys.discoveryDisabled)) }
    }

    /// Sets discovery disabled mode and updates all related settings
    func setDiscoveryDisabled(_ disabled: Bool) {
        discoveryDisabled = disabled
        if disabled {
            showTrendingRows = false
            showTraktRows = false
            showPlexPopular = false
            showNewPopularTab = false
            includeTmdbInSearch = false
        }
    }
}

// MARK: - Debug Logging Settings

extension UserDefaults {
    private enum DebugKeys {
        static let debugLoggingEnabled = "debugLoggingEnabled"
    }

    var debugLoggingEnabled: Bool {
        get { bool(forKey: DebugKeys.debugLoggingEnabled) }
        set { set(newValue, forKey: DebugKeys.debugLoggingEnabled) }
    }
}

// MARK: - Onboarding Settings (Profile-Scoped)

extension UserDefaults {
    private enum OnboardingKeys {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    /// Has the profile completed onboarding (profile-scoped)
    var hasCompletedOnboarding: Bool {
        get { bool(forKey: profileKey(OnboardingKeys.hasCompletedOnboarding)) }
        set { set(newValue, forKey: profileKey(OnboardingKeys.hasCompletedOnboarding)) }
    }

    /// Resets all app settings to defaults (for logout)
    func resetAllSettings() {
        resetNonStremioSettings()
        resetStremioSettings()
    }

    /// Resets everything except the Stremio configuration.
    /// Used when signing out of Plex, so a Stremio-only user keeps their addons,
    /// watch history and playback preferences.
    func resetNonStremioSettings() {
        // Reset discovery settings
        discoveryDisabled = false
        showTrendingRows = true
        showTraktRows = true
        showPlexPopular = true
        showNewPopularTab = true
        includeTmdbInSearch = true

        // Reset onboarding
        hasCompletedOnboarding = false

        // Reset home screen settings
        heroLayout = "billboard"
        showHeroSection = true
        showContinueWatching = true
        showCollectionRows = true
        hiddenCollectionKeys = []
        posterSize = "medium"
        showPosterTitles = true

        // Reset player settings
        resetPlayerSettings()
    }

    func resetStremioSettings() {
        stremioPlaybackEnabled = false
        stremioAutoPlayBestSource = false
        stremioShowOnTmdbDetails = true
        stremioPreferCachedSourceResume = true
        stremioSubtitleAddonsEnabled = true
        stremioUnsupportedSourceVisibility = .showDisabled
    }
}

// MARK: - Player Settings (Mixed: hardware global, preferences profile-scoped)

extension UserDefaults {
    private enum PlayerKeys {
        // MPV Core (Global - hardware settings)
        // Note: playerBackend key is defined in PlayerBackend.swift
        static let bufferSize = "mpvBufferSize"
        static let hardwareDecoding = "mpvHardwareDecoding"
        static let hdrEnabled = "mpvHdrEnabled"
        static let maxVolume = "maxVolume"

        // Seek (Profile-Scoped)
        static let seekTimeSmall = "seekTimeSmall"
        static let seekTimeLarge = "seekTimeLarge"

        // Volume (Profile-Scoped)
        static let playerVolume = "playerVolume"

        // Playback (Profile-Scoped)
        static let defaultPlaybackSpeed = "defaultPlaybackSpeed"

        // Auto-Skip (Profile-Scoped)
        static let autoSkipDelay = "autoSkipDelay"
        static let creditsCountdownFallback = "creditsCountdownFallback"

        // Track Preferences (Profile-Scoped)
        static let rememberTrackSelections = "rememberTrackSelections"
        static let preferredSubtitleLanguage = "preferredSubtitleLanguage"
        static let preferredAudioLanguage = "preferredAudioLanguage"
        static let subtitleSourcePreference = "subtitleSourcePreference"
        static let enableSubtitleAutoSelect = "enableSubtitleAutoSelect"

        // Subtitle Styling (Profile-Scoped)
        static let subtitleFontSize = "subtitleFontSize"
        static let subtitleTextColor = "subtitleTextColor"
        static let subtitleBorderSize = "subtitleBorderSize"
        static let subtitleBorderColor = "subtitleBorderColor"
        static let subtitleBackgroundColor = "subtitleBackgroundColor"
        static let subtitleBackgroundOpacity = "subtitleBackgroundOpacity"

        // Custom MPV Config (Profile-Scoped)
        static let mpvConfigEntries = "mpvConfigEntries"
        static let mpvConfigPresets = "mpvConfigPresets"
    }

    // MARK: MPV Core Settings (Global - hardware/device specific)
    // Note: playerBackend property is defined in PlayerBackend.swift

    /// Buffer size in MB (64, 128, 256, 512, 1024) - Global
    var bufferSize: Int {
        get { object(forKey: PlayerKeys.bufferSize) as? Int ?? 128 }
        set { set(newValue, forKey: PlayerKeys.bufferSize) }
    }

    /// Hardware decoding enabled (VideoToolbox on macOS) - Global
    var hardwareDecoding: Bool {
        get { object(forKey: PlayerKeys.hardwareDecoding) as? Bool ?? true }
        set { set(newValue, forKey: PlayerKeys.hardwareDecoding) }
    }

    /// HDR/Dolby Vision support enabled - Global
    var hdrEnabled: Bool {
        get { object(forKey: PlayerKeys.hdrEnabled) as? Bool ?? true }
        set { set(newValue, forKey: PlayerKeys.hdrEnabled) }
    }

    /// Maximum volume percentage (100-300, for volume boost) - Global
    var maxVolume: Int {
        get { object(forKey: PlayerKeys.maxVolume) as? Int ?? 100 }
        set { set(newValue, forKey: PlayerKeys.maxVolume) }
    }

    // MARK: Seek Settings (Profile-Scoped)

    /// Small seek duration in seconds (1-120, default: 10)
    var seekTimeSmall: Int {
        get { object(forKey: profileKey(PlayerKeys.seekTimeSmall)) as? Int ?? 10 }
        set { set(newValue, forKey: profileKey(PlayerKeys.seekTimeSmall)) }
    }

    /// Large seek duration in seconds (1-120, default: 30)
    var seekTimeLarge: Int {
        get { object(forKey: profileKey(PlayerKeys.seekTimeLarge)) as? Int ?? 30 }
        set { set(newValue, forKey: profileKey(PlayerKeys.seekTimeLarge)) }
    }

    // MARK: Volume Settings (Profile-Scoped)

    /// Current player volume (0-100)
    var playerVolume: Double {
        get { object(forKey: profileKey(PlayerKeys.playerVolume)) as? Double ?? 100.0 }
        set { set(newValue, forKey: profileKey(PlayerKeys.playerVolume)) }
    }

    // MARK: Playback Settings (Profile-Scoped)

    /// Default playback speed (0.5-3.0)
    var defaultPlaybackSpeed: Double {
        get { object(forKey: profileKey(PlayerKeys.defaultPlaybackSpeed)) as? Double ?? 1.0 }
        set { set(newValue, forKey: profileKey(PlayerKeys.defaultPlaybackSpeed)) }
    }

    // MARK: Auto-Skip Settings (Profile-Scoped)

    /// Delay before auto-skipping markers in seconds (1-30)
    var autoSkipDelay: Int {
        get { object(forKey: profileKey(PlayerKeys.autoSkipDelay)) as? Int ?? 5 }
        set { set(newValue, forKey: profileKey(PlayerKeys.autoSkipDelay)) }
    }

    /// Credits countdown fallback when no credits marker exists (seconds before end)
    var creditsCountdownFallback: Int {
        get { object(forKey: profileKey(PlayerKeys.creditsCountdownFallback)) as? Int ?? 30 }
        set { set(newValue, forKey: profileKey(PlayerKeys.creditsCountdownFallback)) }
    }

    // MARK: Track Preferences (Profile-Scoped)

    /// Remember audio/subtitle track language selections
    var rememberTrackSelections: Bool {
        get { object(forKey: profileKey(PlayerKeys.rememberTrackSelections)) as? Bool ?? true }
        set { set(newValue, forKey: profileKey(PlayerKeys.rememberTrackSelections)) }
    }

    var preferredSubtitleLanguage: String {
        get { string(forKey: profileKey(PlayerKeys.preferredSubtitleLanguage)) ?? "en" }
        set { set(newValue, forKey: profileKey(PlayerKeys.preferredSubtitleLanguage)) }
    }

    var preferredAudioLanguage: String {
        get { string(forKey: profileKey(PlayerKeys.preferredAudioLanguage)) ?? "" }
        set { set(newValue, forKey: profileKey(PlayerKeys.preferredAudioLanguage)) }
    }

    var subtitleSourcePreference: SubtitleSourcePreference {
        get {
            guard let rawValue = string(forKey: profileKey(PlayerKeys.subtitleSourcePreference)),
                  let preference = SubtitleSourcePreference(rawValue: rawValue) else {
                return .internal
            }
            return preference
        }
        set { set(newValue.rawValue, forKey: profileKey(PlayerKeys.subtitleSourcePreference)) }
    }

    var enableSubtitleAutoSelect: Bool {
        get { object(forKey: profileKey(PlayerKeys.enableSubtitleAutoSelect)) as? Bool ?? true }
        set { set(newValue, forKey: profileKey(PlayerKeys.enableSubtitleAutoSelect)) }
    }

    // MARK: Subtitle Styling (Profile-Scoped)

    /// Subtitle font size (30-80)
    var subtitleFontSize: Int {
        get { object(forKey: profileKey(PlayerKeys.subtitleFontSize)) as? Int ?? 55 }
        set { set(newValue, forKey: profileKey(PlayerKeys.subtitleFontSize)) }
    }

    /// Subtitle text color (hex string, default white)
    var subtitleTextColor: String {
        get { string(forKey: profileKey(PlayerKeys.subtitleTextColor)) ?? "#FFFFFF" }
        set { set(newValue, forKey: profileKey(PlayerKeys.subtitleTextColor)) }
    }

    /// Subtitle border/outline size (0-5)
    var subtitleBorderSize: Double {
        get { object(forKey: profileKey(PlayerKeys.subtitleBorderSize)) as? Double ?? 3.0 }
        set { set(newValue, forKey: profileKey(PlayerKeys.subtitleBorderSize)) }
    }

    /// Subtitle border color (hex string, default black)
    var subtitleBorderColor: String {
        get { string(forKey: profileKey(PlayerKeys.subtitleBorderColor)) ?? "#000000" }
        set { set(newValue, forKey: profileKey(PlayerKeys.subtitleBorderColor)) }
    }

    /// Subtitle background color (hex string, default black)
    var subtitleBackgroundColor: String {
        get { string(forKey: profileKey(PlayerKeys.subtitleBackgroundColor)) ?? "#000000" }
        set { set(newValue, forKey: profileKey(PlayerKeys.subtitleBackgroundColor)) }
    }

    /// Subtitle background opacity (0-1)
    var subtitleBackgroundOpacity: Double {
        get { object(forKey: profileKey(PlayerKeys.subtitleBackgroundOpacity)) as? Double ?? 0.0 }
        set { set(newValue, forKey: profileKey(PlayerKeys.subtitleBackgroundOpacity)) }
    }

    // MARK: Custom MPV Config (Profile-Scoped)

    /// Get custom MPV config entries
    func getMpvConfigEntries() -> [MpvConfigEntry] {
        guard let data = data(forKey: profileKey(PlayerKeys.mpvConfigEntries)) else { return [] }
        return (try? JSONDecoder().decode([MpvConfigEntry].self, from: data)) ?? []
    }

    /// Save custom MPV config entries
    func setMpvConfigEntries(_ entries: [MpvConfigEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        set(data, forKey: profileKey(PlayerKeys.mpvConfigEntries))
    }

    /// Get enabled MPV config entries only
    func getEnabledMpvConfigEntries() -> [MpvConfigEntry] {
        return getMpvConfigEntries().filter { $0.isEnabled }
    }

    /// Get saved MPV presets
    func getMpvPresets() -> [MpvPreset] {
        guard let data = data(forKey: profileKey(PlayerKeys.mpvConfigPresets)) else { return [] }
        return (try? JSONDecoder().decode([MpvPreset].self, from: data)) ?? []
    }

    /// Save MPV presets
    func setMpvPresets(_ presets: [MpvPreset]) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        set(data, forKey: profileKey(PlayerKeys.mpvConfigPresets))
    }

    /// Save current config entries as a preset
    func saveMpvPreset(name: String) {
        var presets = getMpvPresets()
        presets.removeAll { $0.name == name }
        let preset = MpvPreset(name: name, entries: getMpvConfigEntries(), createdAt: Date())
        presets.append(preset)
        setMpvPresets(presets)
    }

    /// Load a preset by name
    func loadMpvPreset(name: String) {
        guard let preset = getMpvPresets().first(where: { $0.name == name }) else { return }
        setMpvConfigEntries(preset.entries)
    }

    /// Delete a preset by name
    func deleteMpvPreset(name: String) {
        var presets = getMpvPresets()
        presets.removeAll { $0.name == name }
        setMpvPresets(presets)
    }

    // MARK: Reset Player Settings

    func resetPlayerSettings() {
        bufferSize = 128
        hardwareDecoding = true
        hdrEnabled = true
        seekTimeSmall = 10
        seekTimeLarge = 30
        maxVolume = 100
        playerVolume = 100.0
        defaultPlaybackSpeed = 1.0
        skipIntroAutomatically = true
        skipCreditsAutomatically = true
        autoSkipDelay = 5
        creditsCountdownFallback = 30
        rememberTrackSelections = true
        preferredSubtitleLanguage = "en"
        preferredAudioLanguage = ""
        subtitleSourcePreference = .internal
        enableSubtitleAutoSelect = true
        subtitleFontSize = 55
        subtitleTextColor = "#FFFFFF"
        subtitleBorderSize = 3.0
        subtitleBorderColor = "#000000"
        subtitleBackgroundColor = "#000000"
        subtitleBackgroundOpacity = 0.0
        setMpvConfigEntries([])
    }
}
