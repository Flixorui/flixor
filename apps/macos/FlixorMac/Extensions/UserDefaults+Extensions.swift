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
        get { object(forKey: Keys.skipIntroAutomatically) as? Bool ?? true }  // Default: enabled
        set { set(newValue, forKey: Keys.skipIntroAutomatically) }
    }

    var skipCreditsAutomatically: Bool {
        get { object(forKey: Keys.skipCreditsAutomatically) as? Bool ?? true }  // Default: enabled
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

// MARK: - Sidebar Settings

extension UserDefaults {
    private enum SidebarKeys {
        static let showNewPopularTab = "showNewPopularTab"
    }

    var showNewPopularTab: Bool {
        get { object(forKey: SidebarKeys.showNewPopularTab) as? Bool ?? true }
        set { set(newValue, forKey: SidebarKeys.showNewPopularTab) }
    }
}

// MARK: - Search Settings

extension UserDefaults {
    private enum SearchKeys {
        static let includeTmdbInSearch = "includeTmdbInSearch"
    }

    var includeTmdbInSearch: Bool {
        get { object(forKey: SearchKeys.includeTmdbInSearch) as? Bool ?? true }
        set { set(newValue, forKey: SearchKeys.includeTmdbInSearch) }
    }
}

// MARK: - Discovery Mode Settings

extension UserDefaults {
    private enum DiscoveryKeys {
        static let discoveryDisabled = "discoveryDisabled"
    }

    /// When true, disables all discovery features (Library Only Mode)
    var discoveryDisabled: Bool {
        get { bool(forKey: DiscoveryKeys.discoveryDisabled) }
        set { set(newValue, forKey: DiscoveryKeys.discoveryDisabled) }
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

// MARK: - Onboarding Settings

extension UserDefaults {
    private enum OnboardingKeys {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    var hasCompletedOnboarding: Bool {
        get { bool(forKey: OnboardingKeys.hasCompletedOnboarding) }
        set { set(newValue, forKey: OnboardingKeys.hasCompletedOnboarding) }
    }

    /// Resets all app settings to defaults (for logout)
    func resetAllSettings() {
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
        posterSize = "medium"
        showPosterTitles = true

        // Reset player settings
        resetPlayerSettings()
    }
}

// MARK: - Player Settings

extension UserDefaults {
    private enum PlayerKeys {
        // MPV Core
        static let bufferSize = "mpvBufferSize"
        static let hardwareDecoding = "mpvHardwareDecoding"
        static let hdrEnabled = "mpvHdrEnabled"

        // Seek
        static let seekTimeSmall = "seekTimeSmall"
        static let seekTimeLarge = "seekTimeLarge"

        // Volume
        static let maxVolume = "maxVolume"
        static let playerVolume = "playerVolume"

        // Playback
        static let defaultPlaybackSpeed = "defaultPlaybackSpeed"

        // Auto-Skip
        static let autoSkipDelay = "autoSkipDelay"
        static let creditsCountdownFallback = "creditsCountdownFallback"

        // Track Preferences
        static let rememberTrackSelections = "rememberTrackSelections"

        // Subtitle Styling
        static let subtitleFontSize = "subtitleFontSize"
        static let subtitleTextColor = "subtitleTextColor"
        static let subtitleBorderSize = "subtitleBorderSize"
        static let subtitleBorderColor = "subtitleBorderColor"
        static let subtitleBackgroundColor = "subtitleBackgroundColor"
        static let subtitleBackgroundOpacity = "subtitleBackgroundOpacity"

        // Custom MPV Config
        static let mpvConfigEntries = "mpvConfigEntries"
        static let mpvConfigPresets = "mpvConfigPresets"
    }

    // MARK: MPV Core Settings

    /// Buffer size in MB (64, 128, 256, 512, 1024)
    var bufferSize: Int {
        get { object(forKey: PlayerKeys.bufferSize) as? Int ?? 128 }
        set { set(newValue, forKey: PlayerKeys.bufferSize) }
    }

    /// Hardware decoding enabled (VideoToolbox on macOS)
    var hardwareDecoding: Bool {
        get { object(forKey: PlayerKeys.hardwareDecoding) as? Bool ?? true }
        set { set(newValue, forKey: PlayerKeys.hardwareDecoding) }
    }

    /// HDR/Dolby Vision support enabled
    var hdrEnabled: Bool {
        get { object(forKey: PlayerKeys.hdrEnabled) as? Bool ?? true }
        set { set(newValue, forKey: PlayerKeys.hdrEnabled) }
    }

    // MARK: Seek Settings

    /// Small seek duration in seconds (1-120, default: 10)
    var seekTimeSmall: Int {
        get { object(forKey: PlayerKeys.seekTimeSmall) as? Int ?? 10 }
        set { set(newValue, forKey: PlayerKeys.seekTimeSmall) }
    }

    /// Large seek duration in seconds (1-120, default: 30)
    var seekTimeLarge: Int {
        get { object(forKey: PlayerKeys.seekTimeLarge) as? Int ?? 30 }
        set { set(newValue, forKey: PlayerKeys.seekTimeLarge) }
    }

    // MARK: Volume Settings

    /// Maximum volume percentage (100-300, for volume boost)
    var maxVolume: Int {
        get { object(forKey: PlayerKeys.maxVolume) as? Int ?? 100 }
        set { set(newValue, forKey: PlayerKeys.maxVolume) }
    }

    /// Current player volume (0-100)
    var playerVolume: Double {
        get { object(forKey: PlayerKeys.playerVolume) as? Double ?? 100.0 }
        set { set(newValue, forKey: PlayerKeys.playerVolume) }
    }

    // MARK: Playback Settings

    /// Default playback speed (0.5-3.0)
    var defaultPlaybackSpeed: Double {
        get { object(forKey: PlayerKeys.defaultPlaybackSpeed) as? Double ?? 1.0 }
        set { set(newValue, forKey: PlayerKeys.defaultPlaybackSpeed) }
    }

    // MARK: Auto-Skip Settings

    /// Delay before auto-skipping markers in seconds (1-30)
    var autoSkipDelay: Int {
        get { object(forKey: PlayerKeys.autoSkipDelay) as? Int ?? 5 }
        set { set(newValue, forKey: PlayerKeys.autoSkipDelay) }
    }

    /// Credits countdown fallback when no credits marker exists (seconds before end)
    var creditsCountdownFallback: Int {
        get { object(forKey: PlayerKeys.creditsCountdownFallback) as? Int ?? 30 }
        set { set(newValue, forKey: PlayerKeys.creditsCountdownFallback) }
    }

    // MARK: Track Preferences

    /// Remember audio/subtitle track language selections
    var rememberTrackSelections: Bool {
        get { object(forKey: PlayerKeys.rememberTrackSelections) as? Bool ?? true }
        set { set(newValue, forKey: PlayerKeys.rememberTrackSelections) }
    }

    // MARK: Subtitle Styling

    /// Subtitle font size (30-80)
    var subtitleFontSize: Int {
        get { object(forKey: PlayerKeys.subtitleFontSize) as? Int ?? 55 }
        set { set(newValue, forKey: PlayerKeys.subtitleFontSize) }
    }

    /// Subtitle text color (hex string, default white)
    var subtitleTextColor: String {
        get { string(forKey: PlayerKeys.subtitleTextColor) ?? "#FFFFFF" }
        set { set(newValue, forKey: PlayerKeys.subtitleTextColor) }
    }

    /// Subtitle border/outline size (0-5)
    var subtitleBorderSize: Double {
        get { object(forKey: PlayerKeys.subtitleBorderSize) as? Double ?? 3.0 }
        set { set(newValue, forKey: PlayerKeys.subtitleBorderSize) }
    }

    /// Subtitle border color (hex string, default black)
    var subtitleBorderColor: String {
        get { string(forKey: PlayerKeys.subtitleBorderColor) ?? "#000000" }
        set { set(newValue, forKey: PlayerKeys.subtitleBorderColor) }
    }

    /// Subtitle background color (hex string, default black)
    var subtitleBackgroundColor: String {
        get { string(forKey: PlayerKeys.subtitleBackgroundColor) ?? "#000000" }
        set { set(newValue, forKey: PlayerKeys.subtitleBackgroundColor) }
    }

    /// Subtitle background opacity (0-1)
    var subtitleBackgroundOpacity: Double {
        get { object(forKey: PlayerKeys.subtitleBackgroundOpacity) as? Double ?? 0.0 }
        set { set(newValue, forKey: PlayerKeys.subtitleBackgroundOpacity) }
    }

    // MARK: Custom MPV Config

    /// Get custom MPV config entries
    func getMpvConfigEntries() -> [MpvConfigEntry] {
        guard let data = data(forKey: PlayerKeys.mpvConfigEntries) else { return [] }
        return (try? JSONDecoder().decode([MpvConfigEntry].self, from: data)) ?? []
    }

    /// Save custom MPV config entries
    func setMpvConfigEntries(_ entries: [MpvConfigEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        set(data, forKey: PlayerKeys.mpvConfigEntries)
    }

    /// Get enabled MPV config entries only
    func getEnabledMpvConfigEntries() -> [MpvConfigEntry] {
        return getMpvConfigEntries().filter { $0.isEnabled }
    }

    /// Get saved MPV presets
    func getMpvPresets() -> [MpvPreset] {
        guard let data = data(forKey: PlayerKeys.mpvConfigPresets) else { return [] }
        return (try? JSONDecoder().decode([MpvPreset].self, from: data)) ?? []
    }

    /// Save MPV presets
    func setMpvPresets(_ presets: [MpvPreset]) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        set(data, forKey: PlayerKeys.mpvConfigPresets)
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
        subtitleFontSize = 55
        subtitleTextColor = "#FFFFFF"
        subtitleBorderSize = 3.0
        subtitleBorderColor = "#000000"
        subtitleBackgroundColor = "#000000"
        subtitleBackgroundOpacity = 0.0
        setMpvConfigEntries([])
    }
}
