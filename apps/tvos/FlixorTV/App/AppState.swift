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
    @Published var voiceInputEnabled: Bool { didSet { defaults.voiceInputEnabled = voiceInputEnabled } }

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

    // MARK: - Theme
    @Published var accentTheme: TVAccentTheme { didSet { defaults.accentTheme = accentTheme } }
    @Published var appFont: TVAppFont { didSet { defaults.appFont = appFont } }

    // MARK: - Layout
    @Published var showHeroSection: Bool { didSet { defaults.showHeroSection = showHeroSection } }
    @Published var heroAutoRotate: Bool { didSet { defaults.heroAutoRotate = heroAutoRotate } }
    @Published var homeLayoutMode: TVHomeLayoutMode { didSet { defaults.homeLayoutMode = homeLayoutMode } }
    @Published var heroPresentationMode: TVHeroPresentationMode { didSet { defaults.heroPresentationMode = heroPresentationMode } }
    @Published var modernLandscapePostersEnabled: Bool { didSet { defaults.modernLandscapePostersEnabled = modernLandscapePostersEnabled } }
    @Published var continueWatchingCardShape: TVRailCardShape { didSet { defaults.continueWatchingCardShape = continueWatchingCardShape } }
    @Published var defaultRailCardShape: TVRailCardShape { didSet { defaults.defaultRailCardShape = defaultRailCardShape } }
    @Published var posterWidthPreset: TVPosterWidthPreset { didSet { defaults.posterWidthPreset = posterWidthPreset } }
    @Published var showPosterLabels: Bool { didSet { defaults.showPosterLabels = showPosterLabels } }
    @Published var showLibraryTitles: Bool { didSet { defaults.showLibraryTitles = showLibraryTitles } }
    @Published var posterCornerPreset: TVPosterCornerPreset { didSet { defaults.posterCornerPreset = posterCornerPreset } }
    @Published var heroSourceKeys: [String] { didSet { defaults.heroSourceKeys = heroSourceKeys } }
    @Published var showSearchDiscoverContent: Bool { didSet { defaults.showSearchDiscoverContent = showSearchDiscoverContent } }
    @Published var showCatalogAddonName: Bool { didSet { defaults.showCatalogAddonName = showCatalogAddonName } }
    @Published var showCatalogTypeSuffix: Bool { didSet { defaults.showCatalogTypeSuffix = showCatalogTypeSuffix } }
    @Published var hideUnreleasedContent: Bool { didSet { defaults.hideUnreleasedContent = hideUnreleasedContent } }
    @Published var focusedPosterExpandEnabled: Bool { didSet { defaults.focusedPosterExpandEnabled = focusedPosterExpandEnabled } }
    @Published var focusedPosterExpandDelaySeconds: Double { didSet { defaults.focusedPosterExpandDelaySeconds = focusedPosterExpandDelaySeconds } }
    @Published var focusedPosterTrailerEnabled: Bool { didSet { defaults.focusedPosterTrailerEnabled = focusedPosterTrailerEnabled } }
    @Published var focusedPosterTrailerMuted: Bool { didSet { defaults.focusedPosterTrailerMuted = focusedPosterTrailerMuted } }
    @Published var focusedPosterTrailerTarget: TVFocusedPosterTrailerTarget { didSet { defaults.focusedPosterTrailerTarget = focusedPosterTrailerTarget } }

    // MARK: - Details
    @Published var blurUnwatchedEpisodes: Bool { didSet { defaults.blurUnwatchedEpisodes = blurUnwatchedEpisodes } }
    @Published var showTrailerButton: Bool { didSet { defaults.showTrailerButton = showTrailerButton } }
    @Published var preferExternalMetadata: Bool { didSet { defaults.preferExternalMetadata = preferExternalMetadata } }
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
        TVSettingsMigration.apply(to: defaults)

        discoveryDisabled = defaults.discoveryDisabled
        showNewPopularTab = defaults.showNewPopularTab
        includeTmdbInSearch = defaults.includeTmdbInSearch
        voiceInputEnabled = defaults.voiceInputEnabled

        showTrendingRows = defaults.showTrendingRows
        showTraktRows = defaults.showTraktRows
        showPlexPopular = defaults.showPlexPopular
        showWatchlist = defaults.showWatchlist
        showCollectionRows = defaults.showCollectionRows
        showContinueWatching = defaults.showContinueWatching
        showOnDeckRow = defaults.showOnDeckRow
        hiddenCollectionKeys = defaults.hiddenCollectionKeys
        groupRecentlyAddedEpisodes = defaults.groupRecentlyAddedEpisodes

        accentTheme = defaults.accentTheme
        appFont = defaults.appFont

        showHeroSection = defaults.showHeroSection
        heroAutoRotate = defaults.heroAutoRotate
        homeLayoutMode = defaults.homeLayoutMode
        heroPresentationMode = defaults.heroPresentationMode
        modernLandscapePostersEnabled = defaults.modernLandscapePostersEnabled
        continueWatchingCardShape = defaults.continueWatchingCardShape
        defaultRailCardShape = defaults.defaultRailCardShape
        posterWidthPreset = defaults.posterWidthPreset
        showPosterLabels = defaults.showPosterLabels
        showLibraryTitles = defaults.showLibraryTitles
        posterCornerPreset = defaults.posterCornerPreset
        heroSourceKeys = defaults.heroSourceKeys
        showSearchDiscoverContent = defaults.showSearchDiscoverContent
        showCatalogAddonName = defaults.showCatalogAddonName
        showCatalogTypeSuffix = defaults.showCatalogTypeSuffix
        hideUnreleasedContent = defaults.hideUnreleasedContent
        focusedPosterExpandEnabled = defaults.focusedPosterExpandEnabled
        focusedPosterExpandDelaySeconds = defaults.focusedPosterExpandDelaySeconds
        focusedPosterTrailerEnabled = defaults.focusedPosterTrailerEnabled
        focusedPosterTrailerMuted = defaults.focusedPosterTrailerMuted
        focusedPosterTrailerTarget = defaults.focusedPosterTrailerTarget

        blurUnwatchedEpisodes = defaults.blurUnwatchedEpisodes
        showTrailerButton = defaults.showTrailerButton
        preferExternalMetadata = defaults.preferExternalMetadata
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

    var themePalette: TVThemePalette {
        TVThemePalette(theme: accentTheme)
    }

    var typography: TVTypographySet {
        TVTypographySet(appFont: appFont)
    }

    var cardVisualTokens: TVCardVisualTokens {
        TVCardVisualTokens(posterCornerPreset: posterCornerPreset)
    }

    var posterWidthMultiplier: CGFloat {
        posterWidthPreset.widthMultiplier
    }

    var posterCornerRadius: CGFloat {
        posterCornerPreset.cornerRadius
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
    fileprivate enum TVKeys {
        static let discoveryDisabled = "tvos.discoveryDisabled"
        static let showNewPopularTab = "tvos.showNewPopularTab"
        static let includeTmdbInSearch = "tvos.includeTmdbInSearch"
        static let voiceInputEnabled = "tvos.voiceInputEnabled"
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
        static let accentTheme = "tvos.accentTheme"
        static let appFont = "tvos.appFont"
        static let homeLayoutMode = "tvos.homeLayoutMode"
        static let heroPresentationMode = "tvos.heroPresentationMode"
        static let modernLandscapePostersEnabled = "tvos.modernLandscapePostersEnabled"
        static let continueWatchingCardShape = "tvos.continueWatchingCardShape"
        static let defaultRailCardShape = "tvos.defaultRailCardShape"
        static let posterWidthPreset = "tvos.posterWidthPreset"
        static let showPosterLabels = "tvos.showPosterTitles"
        static let showLibraryTitles = "tvos.showLibraryTitles"
        static let posterCornerPreset = "tvos.posterCornerPreset"
        static let heroSourceKeys = "tvos.heroSourceKeys"
        static let showSearchDiscoverContent = "tvos.showSearchDiscoverContent"
        static let showCatalogAddonName = "tvos.showCatalogAddonName"
        static let showCatalogTypeSuffix = "tvos.showCatalogTypeSuffix"
        static let hideUnreleasedContent = "tvos.hideUnreleasedContent"
        static let focusedPosterExpandEnabled = "tvos.focusedPosterExpandEnabled"
        static let focusedPosterExpandDelaySeconds = "tvos.focusedPosterExpandDelaySeconds"
        static let focusedPosterTrailerEnabled = "tvos.focusedPosterTrailerEnabled"
        static let focusedPosterTrailerMuted = "tvos.focusedPosterTrailerMuted"
        static let focusedPosterTrailerTarget = "tvos.focusedPosterTrailerTarget"
        static let groupRecentlyAddedEpisodes = "tvos.groupRecentlyAddedEpisodes"
        static let blurUnwatchedEpisodes = "tvos.blurUnwatchedEpisodes"
        static let showTrailerButton = "tvos.showTrailerButton"
        static let preferExternalMetadata = "tvos.preferExternalMetadata"
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

        // Legacy settings retained for migration compatibility
        static let legacyHeroLayout = "tvos.heroLayout"
        static let legacyContinueWatchingLayout = "tvos.continueWatchingLayout"
        static let legacyRowLayout = "tvos.rowLayout"
        static let legacyPosterSize = "tvos.posterSize"
        static let legacyPosterCornerRadius = "tvos.posterCornerRadius"
        static let legacyDetailsScreenLayout = "tvos.detailsScreenLayout"
        static let legacyEpisodeLayout = "tvos.episodeLayout"
        static let legacySuggestedLayout = "tvos.suggestedLayout"
    }

    var discoveryDisabled: Bool { get { bool(forKey: TVKeys.discoveryDisabled) } set { set(newValue, forKey: TVKeys.discoveryDisabled) } }
    var showNewPopularTab: Bool { get { object(forKey: TVKeys.showNewPopularTab) as? Bool ?? true } set { set(newValue, forKey: TVKeys.showNewPopularTab) } }
    var includeTmdbInSearch: Bool { get { object(forKey: TVKeys.includeTmdbInSearch) as? Bool ?? true } set { set(newValue, forKey: TVKeys.includeTmdbInSearch) } }
    var voiceInputEnabled: Bool { get { object(forKey: TVKeys.voiceInputEnabled) as? Bool ?? true } set { set(newValue, forKey: TVKeys.voiceInputEnabled) } }
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
    var accentTheme: TVAccentTheme { get { TVAccentTheme(rawValue: string(forKey: TVKeys.accentTheme) ?? "") ?? .white } set { set(newValue.rawValue, forKey: TVKeys.accentTheme) } }
    var appFont: TVAppFont { get { TVAppFont(rawValue: string(forKey: TVKeys.appFont) ?? "") ?? .system } set { set(newValue.rawValue, forKey: TVKeys.appFont) } }
    var homeLayoutMode: TVHomeLayoutMode { get { TVHomeLayoutMode(rawValue: string(forKey: TVKeys.homeLayoutMode) ?? "") ?? .modern } set { set(newValue.rawValue, forKey: TVKeys.homeLayoutMode) } }
    var heroPresentationMode: TVHeroPresentationMode { get { TVHeroPresentationMode(rawValue: string(forKey: TVKeys.heroPresentationMode) ?? "") ?? .carousel } set { set(newValue.rawValue, forKey: TVKeys.heroPresentationMode) } }
    var modernLandscapePostersEnabled: Bool { get { object(forKey: TVKeys.modernLandscapePostersEnabled) as? Bool ?? false } set { set(newValue, forKey: TVKeys.modernLandscapePostersEnabled) } }
    var continueWatchingCardShape: TVRailCardShape { get { TVRailCardShape(rawValue: string(forKey: TVKeys.continueWatchingCardShape) ?? "") ?? .poster } set { set(newValue.rawValue, forKey: TVKeys.continueWatchingCardShape) } }
    var defaultRailCardShape: TVRailCardShape { get { TVRailCardShape(rawValue: string(forKey: TVKeys.defaultRailCardShape) ?? "") ?? .poster } set { set(newValue.rawValue, forKey: TVKeys.defaultRailCardShape) } }
    var posterWidthPreset: TVPosterWidthPreset { get { TVPosterWidthPreset(rawValue: string(forKey: TVKeys.posterWidthPreset) ?? "") ?? .balanced } set { set(newValue.rawValue, forKey: TVKeys.posterWidthPreset) } }
    var showPosterLabels: Bool { get { object(forKey: TVKeys.showPosterLabels) as? Bool ?? true } set { set(newValue, forKey: TVKeys.showPosterLabels) } }
    var showLibraryTitles: Bool { get { object(forKey: TVKeys.showLibraryTitles) as? Bool ?? true } set { set(newValue, forKey: TVKeys.showLibraryTitles) } }
    var posterCornerPreset: TVPosterCornerPreset { get { TVPosterCornerPreset(rawValue: string(forKey: TVKeys.posterCornerPreset) ?? "") ?? .rounded } set { set(newValue.rawValue, forKey: TVKeys.posterCornerPreset) } }
    var heroSourceKeys: [String] { get { stringArray(forKey: TVKeys.heroSourceKeys) ?? [] } set { set(newValue, forKey: TVKeys.heroSourceKeys) } }
    var showSearchDiscoverContent: Bool { get { object(forKey: TVKeys.showSearchDiscoverContent) as? Bool ?? true } set { set(newValue, forKey: TVKeys.showSearchDiscoverContent) } }
    var showCatalogAddonName: Bool { get { object(forKey: TVKeys.showCatalogAddonName) as? Bool ?? false } set { set(newValue, forKey: TVKeys.showCatalogAddonName) } }
    var showCatalogTypeSuffix: Bool { get { object(forKey: TVKeys.showCatalogTypeSuffix) as? Bool ?? false } set { set(newValue, forKey: TVKeys.showCatalogTypeSuffix) } }
    var hideUnreleasedContent: Bool { get { object(forKey: TVKeys.hideUnreleasedContent) as? Bool ?? false } set { set(newValue, forKey: TVKeys.hideUnreleasedContent) } }
    var focusedPosterExpandEnabled: Bool { get { object(forKey: TVKeys.focusedPosterExpandEnabled) as? Bool ?? false } set { set(newValue, forKey: TVKeys.focusedPosterExpandEnabled) } }
    var focusedPosterExpandDelaySeconds: Double { get { object(forKey: TVKeys.focusedPosterExpandDelaySeconds) as? Double ?? 3.0 } set { set(newValue, forKey: TVKeys.focusedPosterExpandDelaySeconds) } }
    var focusedPosterTrailerEnabled: Bool { get { object(forKey: TVKeys.focusedPosterTrailerEnabled) as? Bool ?? false } set { set(newValue, forKey: TVKeys.focusedPosterTrailerEnabled) } }
    var focusedPosterTrailerMuted: Bool { get { object(forKey: TVKeys.focusedPosterTrailerMuted) as? Bool ?? true } set { set(newValue, forKey: TVKeys.focusedPosterTrailerMuted) } }
    var focusedPosterTrailerTarget: TVFocusedPosterTrailerTarget { get { TVFocusedPosterTrailerTarget(rawValue: string(forKey: TVKeys.focusedPosterTrailerTarget) ?? "") ?? .heroMedia } set { set(newValue.rawValue, forKey: TVKeys.focusedPosterTrailerTarget) } }
    var groupRecentlyAddedEpisodes: Bool { get { object(forKey: TVKeys.groupRecentlyAddedEpisodes) as? Bool ?? true } set { set(newValue, forKey: TVKeys.groupRecentlyAddedEpisodes) } }
    var blurUnwatchedEpisodes: Bool { get { object(forKey: TVKeys.blurUnwatchedEpisodes) as? Bool ?? false } set { set(newValue, forKey: TVKeys.blurUnwatchedEpisodes) } }
    var showTrailerButton: Bool { get { object(forKey: TVKeys.showTrailerButton) as? Bool ?? true } set { set(newValue, forKey: TVKeys.showTrailerButton) } }
    var preferExternalMetadata: Bool { get { object(forKey: TVKeys.preferExternalMetadata) as? Bool ?? false } set { set(newValue, forKey: TVKeys.preferExternalMetadata) } }
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
        get { TVOverseerrAuthMethod(rawValue: string(forKey: TVKeys.overseerrAuthMethod) ?? "") ?? .plex }
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

    // Legacy raw values kept to support migration and a one-release compatibility window.
    var heroLayout: String { get { string(forKey: TVKeys.legacyHeroLayout) ?? "carousel" } set { set(newValue, forKey: TVKeys.legacyHeroLayout) } }
    var continueWatchingLayout: String { get { string(forKey: TVKeys.legacyContinueWatchingLayout) ?? "poster" } set { set(newValue, forKey: TVKeys.legacyContinueWatchingLayout) } }
    var rowLayout: String { get { string(forKey: TVKeys.legacyRowLayout) ?? "poster" } set { set(newValue, forKey: TVKeys.legacyRowLayout) } }
    var posterSize: String { get { string(forKey: TVKeys.legacyPosterSize) ?? "medium" } set { set(newValue, forKey: TVKeys.legacyPosterSize) } }
    var posterCornerRadius: String { get { string(forKey: TVKeys.legacyPosterCornerRadius) ?? "medium" } set { set(newValue, forKey: TVKeys.legacyPosterCornerRadius) } }
    var detailsScreenLayout: String { get { string(forKey: TVKeys.legacyDetailsScreenLayout) ?? "unified" } set { set(newValue, forKey: TVKeys.legacyDetailsScreenLayout) } }
    var episodeLayout: String { get { string(forKey: TVKeys.legacyEpisodeLayout) ?? "horizontal" } set { set(newValue, forKey: TVKeys.legacyEpisodeLayout) } }
    var suggestedLayout: String { get { string(forKey: TVKeys.legacySuggestedLayout) ?? "landscape" } set { set(newValue, forKey: TVKeys.legacySuggestedLayout) } }

    func clearOverseerrAuth() {
        overseerrApiKey = ""
        overseerrSessionCookie = ""
        overseerrPlexUsername = ""
    }
}
