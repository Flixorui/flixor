import Foundation
import SwiftUI
import FlixorKit

enum TVOverseerrAuthMethod: String, CaseIterable {
    case apiKey = "api_key"
    case plex = "plex"
}

final class AppState: ObservableObject {
    enum Phase { case unauthenticated, linking, authenticated }

    @Published var phase: Phase = .unauthenticated
    @Published var selectedDestination: MainTVDestination = .home

    func startLinking() { phase = .linking }
    func completeAuth() { phase = .authenticated; selectedDestination = .home }
}

@MainActor
final class TVProfileSettings: ObservableObject {
    static let shared = TVProfileSettings()

    private let defaults = UserDefaults.standard

    // MARK: - Discovery
    @Published var discoveryDisabled: Bool { didSet { defaults.discoveryDisabled = discoveryDisabled } }
    @Published var showNewPopularTab: Bool { didSet { defaults.showNewPopularTab = showNewPopularTab } }
    @Published var includeTmdbInSearch: Bool { didSet { defaults.includeTmdbInSearch = includeTmdbInSearch } }

    // MARK: - Home Rows
    @Published var showTrendingRows: Bool { didSet { defaults.showTrendingRows = showTrendingRows } }
    @Published var showTraktRows: Bool { didSet { defaults.showTraktRows = showTraktRows } }
    @Published var showPlexPopular: Bool { didSet { defaults.showPlexPopular = showPlexPopular } }
    @Published var showWatchlist: Bool { didSet { defaults.showWatchlist = showWatchlist } }
    @Published var showCollectionRows: Bool { didSet { defaults.showCollectionRows = showCollectionRows } }
    @Published var showContinueWatching: Bool { didSet { defaults.showContinueWatching = showContinueWatching } }
    @Published var showOnDeckRow: Bool { didSet { defaults.showOnDeckRow = showOnDeckRow } }
    @Published var hiddenCollectionKeys: [String] { didSet { defaults.hiddenCollectionKeys = hiddenCollectionKeys } }
    @Published var groupRecentlyAddedEpisodes: Bool { didSet { defaults.groupRecentlyAddedEpisodes = groupRecentlyAddedEpisodes } }

    // MARK: - Home Appearance
    @Published var showHeroSection: Bool { didSet { defaults.showHeroSection = showHeroSection } }
    @Published var heroAutoRotate: Bool { didSet { defaults.heroAutoRotate = heroAutoRotate } }
    @Published var heroLayout: String { didSet { defaults.heroLayout = heroLayout } }
    @Published var continueWatchingLayout: String { didSet { defaults.continueWatchingLayout = continueWatchingLayout } }
    @Published var rowLayout: String { didSet { defaults.rowLayout = rowLayout } }
    @Published var posterSize: String { didSet { defaults.posterSize = posterSize } }
    @Published var showPosterTitles: Bool { didSet { defaults.showPosterTitles = showPosterTitles } }
    @Published var showLibraryTitles: Bool { didSet { defaults.showLibraryTitles = showLibraryTitles } }
    @Published var posterCornerRadius: String { didSet { defaults.posterCornerRadius = posterCornerRadius } }

    // MARK: - Details
    @Published var detailsScreenLayout: String { didSet { defaults.detailsScreenLayout = detailsScreenLayout } }
    @Published var episodeLayout: String { didSet { defaults.episodeLayout = episodeLayout } }
    @Published var suggestedLayout: String { didSet { defaults.suggestedLayout = suggestedLayout } }
    @Published var showRelatedContent: Bool { didSet { defaults.showRelatedContent = showRelatedContent } }
    @Published var showCastCrew: Bool { didSet { defaults.showCastCrew = showCastCrew } }

    // MARK: - Ratings
    @Published var showIMDbRating: Bool { didSet { defaults.showIMDbRating = showIMDbRating } }
    @Published var showRottenTomatoesCritic: Bool { didSet { defaults.showRottenTomatoesCritic = showRottenTomatoesCritic } }
    @Published var showRottenTomatoesAudience: Bool { didSet { defaults.showRottenTomatoesAudience = showRottenTomatoesAudience } }

    // MARK: - Continue Watching / Playback
    @Published var useCachedStreams: Bool { didSet { defaults.useCachedStreams = useCachedStreams } }
    @Published var streamCacheTTL: Int { didSet { defaults.streamCacheTTL = streamCacheTTL } }
    @Published var defaultQuality: Int { didSet { defaults.defaultQuality = defaultQuality } }
    @Published var autoPlayNext: Bool { didSet { defaults.autoPlayNext = autoPlayNext } }
    @Published var skipIntroAutomatically: Bool { didSet { defaults.skipIntroAutomatically = skipIntroAutomatically } }
    @Published var skipCreditsAutomatically: Bool { didSet { defaults.skipCreditsAutomatically = skipCreditsAutomatically } }
    @Published var seekTimeSmall: Int { didSet { defaults.seekTimeSmall = seekTimeSmall } }
    @Published var seekTimeLarge: Int { didSet { defaults.seekTimeLarge = seekTimeLarge } }
    @Published var defaultPlaybackSpeed: Double { didSet { defaults.defaultPlaybackSpeed = defaultPlaybackSpeed } }
    @Published var rememberTrackSelections: Bool { didSet { defaults.rememberTrackSelections = rememberTrackSelections } }

    // MARK: - TMDB / Trakt / MDBList / Overseerr
    @Published var tmdbLanguage: String { didSet { defaults.tmdbLanguage = tmdbLanguage } }
    @Published var tmdbEnrichMetadata: Bool { didSet { defaults.tmdbEnrichMetadata = tmdbEnrichMetadata } }
    @Published var tmdbLocalizedMetadata: Bool { didSet { defaults.tmdbLocalizedMetadata = tmdbLocalizedMetadata } }
    @Published var enabledLibraryKeys: [String] { didSet { defaults.enabledLibraryKeys = enabledLibraryKeys } }
    @Published var traktAutoSyncWatched: Bool { didSet { defaults.traktAutoSyncWatched = traktAutoSyncWatched } }
    @Published var traktSyncRatings: Bool { didSet { defaults.traktSyncRatings = traktSyncRatings } }
    @Published var traktSyncWatchlist: Bool { didSet { defaults.traktSyncWatchlist = traktSyncWatchlist } }
    @Published var traktScrobbleEnabled: Bool { didSet { defaults.traktScrobbleEnabled = traktScrobbleEnabled } }
    @Published var mdblistEnabled: Bool { didSet { defaults.mdblistEnabled = mdblistEnabled } }
    @Published var mdblistApiKey: String { didSet { defaults.mdblistApiKey = mdblistApiKey } }
    @Published var overseerrEnabled: Bool { didSet { defaults.overseerrEnabled = overseerrEnabled } }
    @Published var overseerrUrl: String { didSet { defaults.overseerrUrl = overseerrUrl } }
    @Published var overseerrAuthMethod: TVOverseerrAuthMethod { didSet { defaults.overseerrAuthMethod = overseerrAuthMethod } }
    @Published var overseerrApiKey: String { didSet { defaults.overseerrApiKey = overseerrApiKey } }
    @Published var overseerrSessionCookie: String { didSet { defaults.overseerrSessionCookie = overseerrSessionCookie } }
    @Published var overseerrPlexUsername: String { didSet { defaults.overseerrPlexUsername = overseerrPlexUsername } }

    private init() {
        defaults.runTVSettingsMigrationIfNeeded()

        discoveryDisabled = defaults.discoveryDisabled
        showNewPopularTab = defaults.showNewPopularTab
        includeTmdbInSearch = defaults.includeTmdbInSearch

        showTrendingRows = defaults.showTrendingRows
        showTraktRows = defaults.showTraktRows
        showPlexPopular = defaults.showPlexPopular
        showWatchlist = defaults.showWatchlist
        showCollectionRows = defaults.showCollectionRows
        showContinueWatching = defaults.showContinueWatching
        showOnDeckRow = defaults.showOnDeckRow
        hiddenCollectionKeys = defaults.hiddenCollectionKeys
        groupRecentlyAddedEpisodes = defaults.groupRecentlyAddedEpisodes

        showHeroSection = defaults.showHeroSection
        heroAutoRotate = defaults.heroAutoRotate
        heroLayout = defaults.heroLayout
        continueWatchingLayout = defaults.continueWatchingLayout
        rowLayout = defaults.rowLayout
        posterSize = defaults.posterSize
        showPosterTitles = defaults.showPosterTitles
        showLibraryTitles = defaults.showLibraryTitles
        posterCornerRadius = defaults.posterCornerRadius

        detailsScreenLayout = defaults.detailsScreenLayout
        episodeLayout = defaults.episodeLayout
        suggestedLayout = defaults.suggestedLayout
        showRelatedContent = defaults.showRelatedContent
        showCastCrew = defaults.showCastCrew

        showIMDbRating = defaults.showIMDbRating
        showRottenTomatoesCritic = defaults.showRottenTomatoesCritic
        showRottenTomatoesAudience = defaults.showRottenTomatoesAudience

        useCachedStreams = defaults.useCachedStreams
        streamCacheTTL = defaults.streamCacheTTL
        defaultQuality = defaults.defaultQuality
        autoPlayNext = defaults.autoPlayNext
        skipIntroAutomatically = defaults.skipIntroAutomatically
        skipCreditsAutomatically = defaults.skipCreditsAutomatically
        seekTimeSmall = defaults.seekTimeSmall
        seekTimeLarge = defaults.seekTimeLarge
        defaultPlaybackSpeed = defaults.defaultPlaybackSpeed
        rememberTrackSelections = defaults.rememberTrackSelections

        tmdbLanguage = defaults.tmdbLanguage
        tmdbEnrichMetadata = defaults.tmdbEnrichMetadata
        tmdbLocalizedMetadata = defaults.tmdbLocalizedMetadata
        enabledLibraryKeys = defaults.enabledLibraryKeys
        traktAutoSyncWatched = defaults.traktAutoSyncWatched
        traktSyncRatings = defaults.traktSyncRatings
        traktSyncWatchlist = defaults.traktSyncWatchlist
        traktScrobbleEnabled = defaults.traktScrobbleEnabled
        mdblistEnabled = defaults.mdblistEnabled
        mdblistApiKey = defaults.mdblistApiKey
        overseerrEnabled = defaults.overseerrEnabled
        overseerrUrl = defaults.overseerrUrl
        overseerrAuthMethod = defaults.overseerrAuthMethod
        overseerrApiKey = defaults.overseerrApiKey
        overseerrSessionCookie = defaults.overseerrSessionCookie
        overseerrPlexUsername = defaults.overseerrPlexUsername
    }

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

extension UserDefaults {
    private enum TVKeys {
        static let discoveryDisabled = "tvos.discoveryDisabled"
        static let showNewPopularTab = "tvos.showNewPopularTab"
        static let includeTmdbInSearch = "tvos.includeTmdbInSearch"
        static let showTrendingRows = "tvos.showTrendingRows"
        static let showTraktRows = "tvos.showTraktRows"
        static let showPlexPopular = "tvos.showPlexPopular"
        static let showWatchlist = "tvos.showWatchlist"
        static let showCollectionRows = "tvos.showCollectionRows"
        static let showContinueWatching = "tvos.showContinueWatching"
        static let showOnDeckRow = "tvos.showOnDeckRow"
        static let hiddenCollectionKeys = "tvos.hiddenCollectionKeys"
        static let showHeroSection = "tvos.showHeroSection"
        static let heroAutoRotate = "tvos.heroAutoRotate"
        static let heroLayout = "tvos.heroLayout"
        static let continueWatchingLayout = "tvos.continueWatchingLayout"
        static let rowLayout = "tvos.rowLayout"
        static let posterSize = "tvos.posterSize"
        static let showPosterTitles = "tvos.showPosterTitles"
        static let showLibraryTitles = "tvos.showLibraryTitles"
        static let posterCornerRadius = "tvos.posterCornerRadius"
        static let groupRecentlyAddedEpisodes = "tvos.groupRecentlyAddedEpisodes"
        static let detailsScreenLayout = "tvos.detailsScreenLayout"
        static let episodeLayout = "tvos.episodeLayout"
        static let suggestedLayout = "tvos.suggestedLayout"
        static let showRelatedContent = "tvos.showRelatedContent"
        static let showCastCrew = "tvos.showCastCrew"
        static let showIMDbRating = "tvos.showIMDbRating"
        static let showRottenTomatoesCritic = "tvos.showRottenTomatoesCritic"
        static let showRottenTomatoesAudience = "tvos.showRottenTomatoesAudience"
        static let useCachedStreams = "tvos.useCachedStreams"
        static let streamCacheTTL = "tvos.streamCacheTTL"
        static let defaultQuality = "tvos.defaultQuality"
        static let autoPlayNext = "tvos.autoPlayNext"
        static let skipIntroAutomatically = "tvos.skipIntroAutomatically"
        static let skipCreditsAutomatically = "tvos.skipCreditsAutomatically"
        static let seekTimeSmall = "tvos.seekTimeSmall"
        static let seekTimeLarge = "tvos.seekTimeLarge"
        static let defaultPlaybackSpeed = "tvos.defaultPlaybackSpeed"
        static let rememberTrackSelections = "tvos.rememberTrackSelections"
        static let tmdbLanguage = "tvos.tmdbLanguage"
        static let tmdbEnrichMetadata = "tvos.tmdbEnrichMetadata"
        static let tmdbLocalizedMetadata = "tvos.tmdbLocalizedMetadata"
        static let enabledLibraryKeys = "tvos.enabledLibraryKeys"
        static let traktAutoSyncWatched = "tvos.traktAutoSyncWatched"
        static let traktSyncRatings = "tvos.traktSyncRatings"
        static let traktSyncWatchlist = "tvos.traktSyncWatchlist"
        static let traktScrobbleEnabled = "tvos.traktScrobbleEnabled"
        static let mdblistEnabled = "tvos.mdblistEnabled"
        static let mdblistApiKey = "tvos.mdblistApiKey"
        static let overseerrEnabled = "tvos.overseerrEnabled"
        static let overseerrUrl = "tvos.overseerrUrl"
        static let overseerrAuthMethod = "tvos.overseerrAuthMethod"
        static let overseerrApiKey = "tvos.overseerrApiKey"
        static let overseerrSessionCookie = "tvos.overseerrSessionCookie"
        static let overseerrPlexUsername = "tvos.overseerrPlexUsername"
        static let tmdbApiKey = "tvos.tmdbApiKey"
        static let traktClientId = "tvos.traktClientId"
        static let traktClientSecret = "tvos.traktClientSecret"
        static let playerBackend = "playerBackend"
        static let preferDirectPlay = "preferDirectPlay"
        static let allowDirectStream = "allowDirectStream"
        static let showDebugInfo = "showDebugInfo"
    }

    var discoveryDisabled: Bool { get { bool(forKey: TVKeys.discoveryDisabled) } set { set(newValue, forKey: TVKeys.discoveryDisabled) } }
    var showNewPopularTab: Bool { get { object(forKey: TVKeys.showNewPopularTab) as? Bool ?? true } set { set(newValue, forKey: TVKeys.showNewPopularTab) } }
    var includeTmdbInSearch: Bool { get { object(forKey: TVKeys.includeTmdbInSearch) as? Bool ?? true } set { set(newValue, forKey: TVKeys.includeTmdbInSearch) } }
    var showTrendingRows: Bool { get { object(forKey: TVKeys.showTrendingRows) as? Bool ?? true } set { set(newValue, forKey: TVKeys.showTrendingRows) } }
    var showTraktRows: Bool { get { object(forKey: TVKeys.showTraktRows) as? Bool ?? true } set { set(newValue, forKey: TVKeys.showTraktRows) } }
    var showPlexPopular: Bool { get { object(forKey: TVKeys.showPlexPopular) as? Bool ?? true } set { set(newValue, forKey: TVKeys.showPlexPopular) } }
    var showWatchlist: Bool { get { object(forKey: TVKeys.showWatchlist) as? Bool ?? true } set { set(newValue, forKey: TVKeys.showWatchlist) } }
    var showCollectionRows: Bool { get { object(forKey: TVKeys.showCollectionRows) as? Bool ?? true } set { set(newValue, forKey: TVKeys.showCollectionRows) } }
    var showContinueWatching: Bool { get { object(forKey: TVKeys.showContinueWatching) as? Bool ?? true } set { set(newValue, forKey: TVKeys.showContinueWatching) } }
    var showOnDeckRow: Bool { get { object(forKey: TVKeys.showOnDeckRow) as? Bool ?? true } set { set(newValue, forKey: TVKeys.showOnDeckRow) } }
    var hiddenCollectionKeys: [String] { get { stringArray(forKey: TVKeys.hiddenCollectionKeys) ?? [] } set { set(newValue, forKey: TVKeys.hiddenCollectionKeys) } }
    var showHeroSection: Bool { get { object(forKey: TVKeys.showHeroSection) as? Bool ?? true } set { set(newValue, forKey: TVKeys.showHeroSection) } }
    var heroAutoRotate: Bool { get { object(forKey: TVKeys.heroAutoRotate) as? Bool ?? true } set { set(newValue, forKey: TVKeys.heroAutoRotate) } }
    var heroLayout: String { get { string(forKey: TVKeys.heroLayout) ?? "carousel" } set { set(newValue, forKey: TVKeys.heroLayout) } }
    var continueWatchingLayout: String { get { string(forKey: TVKeys.continueWatchingLayout) ?? "poster" } set { set(newValue, forKey: TVKeys.continueWatchingLayout) } }
    var rowLayout: String { get { string(forKey: TVKeys.rowLayout) ?? "poster" } set { set(newValue, forKey: TVKeys.rowLayout) } }
    var posterSize: String { get { string(forKey: TVKeys.posterSize) ?? "medium" } set { set(newValue, forKey: TVKeys.posterSize) } }
    var showPosterTitles: Bool { get { object(forKey: TVKeys.showPosterTitles) as? Bool ?? true } set { set(newValue, forKey: TVKeys.showPosterTitles) } }
    var showLibraryTitles: Bool { get { object(forKey: TVKeys.showLibraryTitles) as? Bool ?? true } set { set(newValue, forKey: TVKeys.showLibraryTitles) } }
    var posterCornerRadius: String { get { string(forKey: TVKeys.posterCornerRadius) ?? "medium" } set { set(newValue, forKey: TVKeys.posterCornerRadius) } }
    var groupRecentlyAddedEpisodes: Bool { get { object(forKey: TVKeys.groupRecentlyAddedEpisodes) as? Bool ?? true } set { set(newValue, forKey: TVKeys.groupRecentlyAddedEpisodes) } }
    var detailsScreenLayout: String { get { string(forKey: TVKeys.detailsScreenLayout) ?? "unified" } set { set(newValue, forKey: TVKeys.detailsScreenLayout) } }
    var episodeLayout: String { get { string(forKey: TVKeys.episodeLayout) ?? "horizontal" } set { set(newValue, forKey: TVKeys.episodeLayout) } }
    var suggestedLayout: String { get { string(forKey: TVKeys.suggestedLayout) ?? "landscape" } set { set(newValue, forKey: TVKeys.suggestedLayout) } }
    var showRelatedContent: Bool { get { object(forKey: TVKeys.showRelatedContent) as? Bool ?? true } set { set(newValue, forKey: TVKeys.showRelatedContent) } }
    var showCastCrew: Bool { get { object(forKey: TVKeys.showCastCrew) as? Bool ?? true } set { set(newValue, forKey: TVKeys.showCastCrew) } }
    var showIMDbRating: Bool { get { object(forKey: TVKeys.showIMDbRating) as? Bool ?? true } set { set(newValue, forKey: TVKeys.showIMDbRating) } }
    var showRottenTomatoesCritic: Bool { get { object(forKey: TVKeys.showRottenTomatoesCritic) as? Bool ?? true } set { set(newValue, forKey: TVKeys.showRottenTomatoesCritic) } }
    var showRottenTomatoesAudience: Bool { get { object(forKey: TVKeys.showRottenTomatoesAudience) as? Bool ?? true } set { set(newValue, forKey: TVKeys.showRottenTomatoesAudience) } }
    var useCachedStreams: Bool { get { object(forKey: TVKeys.useCachedStreams) as? Bool ?? true } set { set(newValue, forKey: TVKeys.useCachedStreams) } }
    var streamCacheTTL: Int { get { object(forKey: TVKeys.streamCacheTTL) as? Int ?? 3600 } set { set(newValue, forKey: TVKeys.streamCacheTTL) } }
    var defaultQuality: Int { get { object(forKey: TVKeys.defaultQuality) as? Int ?? 0 } set { set(newValue, forKey: TVKeys.defaultQuality) } }
    var autoPlayNext: Bool { get { object(forKey: TVKeys.autoPlayNext) as? Bool ?? true } set { set(newValue, forKey: TVKeys.autoPlayNext) } }
    var skipIntroAutomatically: Bool { get { object(forKey: TVKeys.skipIntroAutomatically) as? Bool ?? true } set { set(newValue, forKey: TVKeys.skipIntroAutomatically) } }
    var skipCreditsAutomatically: Bool { get { object(forKey: TVKeys.skipCreditsAutomatically) as? Bool ?? true } set { set(newValue, forKey: TVKeys.skipCreditsAutomatically) } }
    var seekTimeSmall: Int { get { object(forKey: TVKeys.seekTimeSmall) as? Int ?? 10 } set { set(newValue, forKey: TVKeys.seekTimeSmall) } }
    var seekTimeLarge: Int { get { object(forKey: TVKeys.seekTimeLarge) as? Int ?? 30 } set { set(newValue, forKey: TVKeys.seekTimeLarge) } }
    var defaultPlaybackSpeed: Double { get { object(forKey: TVKeys.defaultPlaybackSpeed) as? Double ?? 1.0 } set { set(newValue, forKey: TVKeys.defaultPlaybackSpeed) } }
    var rememberTrackSelections: Bool { get { object(forKey: TVKeys.rememberTrackSelections) as? Bool ?? true } set { set(newValue, forKey: TVKeys.rememberTrackSelections) } }
    var tmdbLanguage: String { get { string(forKey: TVKeys.tmdbLanguage) ?? "en" } set { set(newValue, forKey: TVKeys.tmdbLanguage) } }
    var tmdbEnrichMetadata: Bool { get { object(forKey: TVKeys.tmdbEnrichMetadata) as? Bool ?? true } set { set(newValue, forKey: TVKeys.tmdbEnrichMetadata) } }
    var tmdbLocalizedMetadata: Bool { get { object(forKey: TVKeys.tmdbLocalizedMetadata) as? Bool ?? true } set { set(newValue, forKey: TVKeys.tmdbLocalizedMetadata) } }
    var enabledLibraryKeys: [String] { get { stringArray(forKey: TVKeys.enabledLibraryKeys) ?? [] } set { set(newValue, forKey: TVKeys.enabledLibraryKeys) } }
    var traktAutoSyncWatched: Bool { get { object(forKey: TVKeys.traktAutoSyncWatched) as? Bool ?? true } set { set(newValue, forKey: TVKeys.traktAutoSyncWatched) } }
    var traktSyncRatings: Bool { get { object(forKey: TVKeys.traktSyncRatings) as? Bool ?? true } set { set(newValue, forKey: TVKeys.traktSyncRatings) } }
    var traktSyncWatchlist: Bool { get { object(forKey: TVKeys.traktSyncWatchlist) as? Bool ?? true } set { set(newValue, forKey: TVKeys.traktSyncWatchlist) } }
    var traktScrobbleEnabled: Bool { get { object(forKey: TVKeys.traktScrobbleEnabled) as? Bool ?? true } set { set(newValue, forKey: TVKeys.traktScrobbleEnabled) } }
    var mdblistEnabled: Bool { get { object(forKey: TVKeys.mdblistEnabled) as? Bool ?? false } set { set(newValue, forKey: TVKeys.mdblistEnabled) } }
    var mdblistApiKey: String { get { string(forKey: TVKeys.mdblistApiKey) ?? "" } set { set(newValue, forKey: TVKeys.mdblistApiKey) } }
    var overseerrEnabled: Bool { get { object(forKey: TVKeys.overseerrEnabled) as? Bool ?? false } set { set(newValue, forKey: TVKeys.overseerrEnabled) } }
    var overseerrUrl: String { get { string(forKey: TVKeys.overseerrUrl) ?? "" } set { set(newValue, forKey: TVKeys.overseerrUrl) } }
    var overseerrAuthMethod: TVOverseerrAuthMethod {
        get {
            guard let raw = string(forKey: TVKeys.overseerrAuthMethod),
                  let method = TVOverseerrAuthMethod(rawValue: raw) else {
                return .plex
            }
            return method
        }
        set { set(newValue.rawValue, forKey: TVKeys.overseerrAuthMethod) }
    }
    var overseerrApiKey: String { get { string(forKey: TVKeys.overseerrApiKey) ?? "" } set { set(newValue, forKey: TVKeys.overseerrApiKey) } }
    var overseerrSessionCookie: String { get { string(forKey: TVKeys.overseerrSessionCookie) ?? "" } set { set(newValue, forKey: TVKeys.overseerrSessionCookie) } }
    var overseerrPlexUsername: String { get { string(forKey: TVKeys.overseerrPlexUsername) ?? "" } set { set(newValue, forKey: TVKeys.overseerrPlexUsername) } }
    var tmdbApiKey: String { get { string(forKey: TVKeys.tmdbApiKey) ?? "" } set { set(newValue, forKey: TVKeys.tmdbApiKey) } }
    var traktClientId: String { get { string(forKey: TVKeys.traktClientId) ?? "" } set { set(newValue, forKey: TVKeys.traktClientId) } }
    var traktClientSecret: String { get { string(forKey: TVKeys.traktClientSecret) ?? "" } set { set(newValue, forKey: TVKeys.traktClientSecret) } }
    var playerBackend: PlayerBackend {
        get { PlayerBackend(rawValue: string(forKey: TVKeys.playerBackend) ?? "") ?? .mpv }
        set { set(newValue.rawValue, forKey: TVKeys.playerBackend) }
    }
    var preferDirectPlay: Bool { get { object(forKey: TVKeys.preferDirectPlay) as? Bool ?? true } set { set(newValue, forKey: TVKeys.preferDirectPlay) } }
    var allowDirectStream: Bool { get { object(forKey: TVKeys.allowDirectStream) as? Bool ?? true } set { set(newValue, forKey: TVKeys.allowDirectStream) } }
    var showDebugInfo: Bool { get { object(forKey: TVKeys.showDebugInfo) as? Bool ?? false } set { set(newValue, forKey: TVKeys.showDebugInfo) } }

    func clearOverseerrAuth() {
        overseerrApiKey = ""
        overseerrSessionCookie = ""
        overseerrPlexUsername = ""
    }

    private enum TVMigrationKeys {
        static let settingsV2Applied = "tvos.settingsMigration.v2.applied"
    }

    func runTVSettingsMigrationIfNeeded() {
        guard object(forKey: TVMigrationKeys.settingsV2Applied) as? Bool != true else { return }
        if object(forKey: TVKeys.skipIntroAutomatically) == nil {
            set(true, forKey: TVKeys.skipIntroAutomatically)
        }
        if object(forKey: TVKeys.skipCreditsAutomatically) == nil {
            set(true, forKey: TVKeys.skipCreditsAutomatically)
        }
        set(true, forKey: TVMigrationKeys.settingsV2Applied)
    }
}
