//
//  UserDefaults+Extensions.swift
//  FlixorMac
//
//  UserDefaults extensions for app preferences
//

import Foundation

extension UserDefaults {
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
    }

    // MARK: - Backend URL

    var backendBaseURL: String {
        get { string(forKey: Keys.backendBaseURL) ?? "http://localhost:3001" }
        set { set(newValue, forKey: Keys.backendBaseURL) }
    }

    // MARK: - Playback Preferences

    var defaultQuality: Int {
        get { integer(forKey: Keys.defaultQuality) != 0 ? integer(forKey: Keys.defaultQuality) : 12000 }
        set { set(newValue, forKey: Keys.defaultQuality) }
    }

    var autoPlayNext: Bool {
        get { bool(forKey: Keys.autoPlayNext) }
        set { set(newValue, forKey: Keys.autoPlayNext) }
    }

    var skipIntroAutomatically: Bool {
        get { bool(forKey: Keys.skipIntroAutomatically) }
        set { set(newValue, forKey: Keys.skipIntroAutomatically) }
    }

    var skipCreditsAutomatically: Bool {
        get { bool(forKey: Keys.skipCreditsAutomatically) }
        set { set(newValue, forKey: Keys.skipCreditsAutomatically) }
    }
}

extension UserDefaults {
    var traktAutoSyncWatched: Bool {
        get { object(forKey: Keys.traktAutoSyncWatched) as? Bool ?? true }
        set { set(newValue, forKey: Keys.traktAutoSyncWatched) }
    }

    var traktSyncRatings: Bool {
        get { object(forKey: Keys.traktSyncRatings) as? Bool ?? true }
        set { set(newValue, forKey: Keys.traktSyncRatings) }
    }

    var traktSyncWatchlist: Bool {
        get { object(forKey: Keys.traktSyncWatchlist) as? Bool ?? true }
        set { set(newValue, forKey: Keys.traktSyncWatchlist) }
    }
}

// MARK: - MDBList Settings

extension UserDefaults {
    private enum MDBListKeys {
        static let enabled = "mdblistEnabled"
        static let apiKey = "mdblistApiKey"
    }

    var mdblistEnabled: Bool {
        get { bool(forKey: MDBListKeys.enabled) }
        set { set(newValue, forKey: MDBListKeys.enabled) }
    }

    var mdblistApiKey: String {
        get { string(forKey: MDBListKeys.apiKey) ?? "" }
        set { set(newValue, forKey: MDBListKeys.apiKey) }
    }
}

// MARK: - Overseerr Settings

extension UserDefaults {
    private enum OverseerrKeys {
        static let enabled = "overseerrEnabled"
        static let url = "overseerrUrl"
        static let apiKey = "overseerrApiKey"
    }

    var overseerrEnabled: Bool {
        get { bool(forKey: OverseerrKeys.enabled) }
        set { set(newValue, forKey: OverseerrKeys.enabled) }
    }

    var overseerrUrl: String {
        get { string(forKey: OverseerrKeys.url) ?? "" }
        set { set(newValue, forKey: OverseerrKeys.url) }
    }

    var overseerrApiKey: String {
        get { string(forKey: OverseerrKeys.apiKey) ?? "" }
        set { set(newValue, forKey: OverseerrKeys.apiKey) }
    }
}

// MARK: - TMDB Settings

extension UserDefaults {
    private enum TMDBKeys {
        static let apiKey = "tmdbApiKey"
        static let language = "tmdbLanguage"
        static let enrichMetadata = "tmdbEnrichMetadata"
        static let localizedMetadata = "tmdbLocalizedMetadata"
    }

    var tmdbApiKey: String {
        get { string(forKey: TMDBKeys.apiKey) ?? "" }
        set { set(newValue, forKey: TMDBKeys.apiKey) }
    }

    var tmdbLanguage: String {
        get { string(forKey: TMDBKeys.language) ?? "en" }
        set { set(newValue, forKey: TMDBKeys.language) }
    }

    var tmdbEnrichMetadata: Bool {
        get { object(forKey: TMDBKeys.enrichMetadata) as? Bool ?? true }
        set { set(newValue, forKey: TMDBKeys.enrichMetadata) }
    }

    var tmdbLocalizedMetadata: Bool {
        get { bool(forKey: TMDBKeys.localizedMetadata) }
        set { set(newValue, forKey: TMDBKeys.localizedMetadata) }
    }
}

// MARK: - Home Screen Settings

extension UserDefaults {
    private enum HomeKeys {
        static let heroLayout = "heroLayout"
        static let showHeroSection = "showHeroSection"
        static let showContinueWatching = "showContinueWatching"
        static let showTrendingRows = "showTrendingRows"
        static let showTraktRows = "showTraktRows"
        static let showPlexPopular = "showPlexPopular"
        static let posterSize = "posterSize"
        static let showPosterTitles = "showPosterTitles"
    }

    var heroLayout: String {
        get { string(forKey: HomeKeys.heroLayout) ?? "billboard" }
        set { set(newValue, forKey: HomeKeys.heroLayout) }
    }

    var showHeroSection: Bool {
        get { object(forKey: HomeKeys.showHeroSection) as? Bool ?? true }
        set { set(newValue, forKey: HomeKeys.showHeroSection) }
    }

    var showContinueWatching: Bool {
        get { object(forKey: HomeKeys.showContinueWatching) as? Bool ?? true }
        set { set(newValue, forKey: HomeKeys.showContinueWatching) }
    }

    var showTrendingRows: Bool {
        get { object(forKey: HomeKeys.showTrendingRows) as? Bool ?? true }
        set { set(newValue, forKey: HomeKeys.showTrendingRows) }
    }

    var showTraktRows: Bool {
        get { object(forKey: HomeKeys.showTraktRows) as? Bool ?? true }
        set { set(newValue, forKey: HomeKeys.showTraktRows) }
    }

    var showPlexPopular: Bool {
        get { object(forKey: HomeKeys.showPlexPopular) as? Bool ?? true }
        set { set(newValue, forKey: HomeKeys.showPlexPopular) }
    }

    var posterSize: String {
        get { string(forKey: HomeKeys.posterSize) ?? "medium" }
        set { set(newValue, forKey: HomeKeys.posterSize) }
    }

    var showPosterTitles: Bool {
        get { object(forKey: HomeKeys.showPosterTitles) as? Bool ?? true }
        set { set(newValue, forKey: HomeKeys.showPosterTitles) }
    }
}

// MARK: - Catalog Settings

extension UserDefaults {
    private enum CatalogKeys {
        static let enabledLibraryKeys = "enabledLibraryKeys"
    }

    var enabledLibraryKeys: [String] {
        get { stringArray(forKey: CatalogKeys.enabledLibraryKeys) ?? [] }
        set { set(newValue, forKey: CatalogKeys.enabledLibraryKeys) }
    }
}
