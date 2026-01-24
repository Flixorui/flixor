//
//  ProfileSettings.swift
//  FlixorMac
//
//  Observable settings manager that uses profile-scoped storage
//  Use this instead of @AppStorage for settings that should be isolated per profile
//

import Foundation
import SwiftUI
import FlixorKit

@MainActor
class ProfileSettings: ObservableObject {
    static let shared = ProfileSettings()

    private let defaults = UserDefaults.standard

    // MARK: - Discovery Settings

    @Published var discoveryDisabled: Bool {
        didSet { defaults.discoveryDisabled = discoveryDisabled }
    }

    @Published var showNewPopularTab: Bool {
        didSet { defaults.showNewPopularTab = showNewPopularTab }
    }

    @Published var includeTmdbInSearch: Bool {
        didSet { defaults.includeTmdbInSearch = includeTmdbInSearch }
    }

    // MARK: - Home Screen Settings

    @Published var showTrendingRows: Bool {
        didSet { defaults.showTrendingRows = showTrendingRows }
    }

    @Published var showTraktRows: Bool {
        didSet { defaults.showTraktRows = showTraktRows }
    }

    @Published var showPlexPopular: Bool {
        didSet { defaults.showPlexPopular = showPlexPopular }
    }

    @Published var showWatchlist: Bool {
        didSet { defaults.showWatchlist = showWatchlist }
    }

    @Published var showCollectionRows: Bool {
        didSet { defaults.showCollectionRows = showCollectionRows }
    }

    @Published var hiddenCollectionKeys: [String] {
        didSet { defaults.hiddenCollectionKeys = hiddenCollectionKeys }
    }

    @Published var showHeroSection: Bool {
        didSet { defaults.showHeroSection = showHeroSection }
    }

    @Published var heroAutoRotate: Bool {
        didSet { defaults.heroAutoRotate = heroAutoRotate }
    }

    @Published var showContinueWatching: Bool {
        didSet { defaults.showContinueWatching = showContinueWatching }
    }

    @Published var heroLayout: String {
        didSet { defaults.heroLayout = heroLayout }
    }

    @Published var continueWatchingLayout: String {
        didSet { defaults.continueWatchingLayout = continueWatchingLayout }
    }

    @Published var rowLayout: String {
        didSet { defaults.rowLayout = rowLayout }
    }

    @Published var posterSize: String {
        didSet { defaults.posterSize = posterSize }
    }

    @Published var showPosterTitles: Bool {
        didSet { defaults.showPosterTitles = showPosterTitles }
    }

    @Published var showLibraryTitles: Bool {
        didSet { defaults.showLibraryTitles = showLibraryTitles }
    }

    @Published var posterCornerRadius: String {
        didSet { defaults.posterCornerRadius = posterCornerRadius }
    }

    // MARK: - Details Screen Settings

    @Published var detailsScreenLayout: String {
        didSet { defaults.detailsScreenLayout = detailsScreenLayout }
    }

    @Published var episodeLayout: String {
        didSet { defaults.episodeLayout = episodeLayout }
    }

    @Published var suggestedLayout: String {
        didSet { defaults.suggestedLayout = suggestedLayout }
    }

    @Published var showRelatedContent: Bool {
        didSet { defaults.showRelatedContent = showRelatedContent }
    }

    @Published var showCastCrew: Bool {
        didSet { defaults.showCastCrew = showCastCrew }
    }

    // MARK: - Ratings Settings

    @Published var showIMDbRating: Bool {
        didSet { defaults.showIMDbRating = showIMDbRating }
    }

    @Published var showRottenTomatoesCritic: Bool {
        didSet { defaults.showRottenTomatoesCritic = showRottenTomatoesCritic }
    }

    @Published var showRottenTomatoesAudience: Bool {
        didSet { defaults.showRottenTomatoesAudience = showRottenTomatoesAudience }
    }

    // MARK: - Continue Watching Settings

    @Published var useCachedStreams: Bool {
        didSet { defaults.useCachedStreams = useCachedStreams }
    }

    @Published var streamCacheTTL: Int {
        didSet { defaults.streamCacheTTL = streamCacheTTL }
    }

    // MARK: - Playback Preferences

    @Published var defaultQuality: Int {
        didSet { defaults.defaultQuality = defaultQuality }
    }

    @Published var autoPlayNext: Bool {
        didSet { defaults.autoPlayNext = autoPlayNext }
    }

    @Published var skipIntroAutomatically: Bool {
        didSet { defaults.skipIntroAutomatically = skipIntroAutomatically }
    }

    @Published var skipCreditsAutomatically: Bool {
        didSet { defaults.skipCreditsAutomatically = skipCreditsAutomatically }
    }

    // MARK: - Player Settings (Profile-Scoped Preferences)

    @Published var seekTimeSmall: Int {
        didSet { defaults.seekTimeSmall = seekTimeSmall }
    }

    @Published var seekTimeLarge: Int {
        didSet { defaults.seekTimeLarge = seekTimeLarge }
    }

    @Published var playerVolume: Double {
        didSet { defaults.playerVolume = playerVolume }
    }

    @Published var defaultPlaybackSpeed: Double {
        didSet { defaults.defaultPlaybackSpeed = defaultPlaybackSpeed }
    }

    @Published var autoSkipDelay: Int {
        didSet { defaults.autoSkipDelay = autoSkipDelay }
    }

    @Published var creditsCountdownFallback: Int {
        didSet { defaults.creditsCountdownFallback = creditsCountdownFallback }
    }

    @Published var rememberTrackSelections: Bool {
        didSet { defaults.rememberTrackSelections = rememberTrackSelections }
    }

    @Published var subtitleFontSize: Int {
        didSet { defaults.subtitleFontSize = subtitleFontSize }
    }

    @Published var subtitleBorderSize: Double {
        didSet { defaults.subtitleBorderSize = subtitleBorderSize }
    }

    @Published var subtitleBackgroundOpacity: Double {
        didSet { defaults.subtitleBackgroundOpacity = subtitleBackgroundOpacity }
    }

    // MARK: - TMDB Settings (Profile-Scoped Preferences)

    @Published var tmdbLanguage: String {
        didSet { defaults.tmdbLanguage = tmdbLanguage }
    }

    @Published var tmdbEnrichMetadata: Bool {
        didSet { defaults.tmdbEnrichMetadata = tmdbEnrichMetadata }
    }

    @Published var tmdbLocalizedMetadata: Bool {
        didSet { defaults.tmdbLocalizedMetadata = tmdbLocalizedMetadata }
    }

    // MARK: - Catalog Settings

    @Published var enabledLibraryKeys: [String] {
        didSet { defaults.enabledLibraryKeys = enabledLibraryKeys }
    }

    // MARK: - Trakt Settings

    @Published var traktAutoSyncWatched: Bool {
        didSet { defaults.traktAutoSyncWatched = traktAutoSyncWatched }
    }

    @Published var traktSyncRatings: Bool {
        didSet { defaults.traktSyncRatings = traktSyncRatings }
    }

    @Published var traktSyncWatchlist: Bool {
        didSet { defaults.traktSyncWatchlist = traktSyncWatchlist }
    }

    @Published var traktScrobbleEnabled: Bool {
        didSet { defaults.traktScrobbleEnabled = traktScrobbleEnabled }
    }

    // MARK: - MDBList Settings

    @Published var mdblistEnabled: Bool {
        didSet { defaults.mdblistEnabled = mdblistEnabled }
    }

    @Published var mdblistApiKey: String {
        didSet { defaults.mdblistApiKey = mdblistApiKey }
    }

    // MARK: - Overseerr Settings

    @Published var overseerrEnabled: Bool {
        didSet { defaults.overseerrEnabled = overseerrEnabled }
    }

    @Published var overseerrUrl: String {
        didSet { defaults.overseerrUrl = overseerrUrl }
    }

    // MARK: - Onboarding Settings

    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.hasCompletedOnboarding = hasCompletedOnboarding }
    }

    // MARK: - Initialization

    private init() {
        // Load initial values from UserDefaults (profile-scoped)
        // Discovery
        self.discoveryDisabled = defaults.discoveryDisabled
        self.showNewPopularTab = defaults.showNewPopularTab
        self.includeTmdbInSearch = defaults.includeTmdbInSearch

        // Home Screen
        self.showTrendingRows = defaults.showTrendingRows
        self.showTraktRows = defaults.showTraktRows
        self.showPlexPopular = defaults.showPlexPopular
        self.showWatchlist = defaults.showWatchlist
        self.showCollectionRows = defaults.showCollectionRows
        self.hiddenCollectionKeys = defaults.hiddenCollectionKeys
        self.showHeroSection = defaults.showHeroSection
        self.heroAutoRotate = defaults.heroAutoRotate
        self.showContinueWatching = defaults.showContinueWatching
        self.heroLayout = defaults.heroLayout
        self.continueWatchingLayout = defaults.continueWatchingLayout
        self.rowLayout = defaults.rowLayout
        self.posterSize = defaults.posterSize
        self.showPosterTitles = defaults.showPosterTitles
        self.showLibraryTitles = defaults.showLibraryTitles
        self.posterCornerRadius = defaults.posterCornerRadius

        // Details Screen
        self.detailsScreenLayout = defaults.detailsScreenLayout
        self.episodeLayout = defaults.episodeLayout
        self.suggestedLayout = defaults.suggestedLayout
        self.showRelatedContent = defaults.showRelatedContent
        self.showCastCrew = defaults.showCastCrew

        // Ratings
        self.showIMDbRating = defaults.showIMDbRating
        self.showRottenTomatoesCritic = defaults.showRottenTomatoesCritic
        self.showRottenTomatoesAudience = defaults.showRottenTomatoesAudience

        // Continue Watching
        self.useCachedStreams = defaults.useCachedStreams
        self.streamCacheTTL = defaults.streamCacheTTL

        // Playback Preferences
        self.defaultQuality = defaults.defaultQuality
        self.autoPlayNext = defaults.autoPlayNext
        self.skipIntroAutomatically = defaults.skipIntroAutomatically
        self.skipCreditsAutomatically = defaults.skipCreditsAutomatically

        // Player Settings
        self.seekTimeSmall = defaults.seekTimeSmall
        self.seekTimeLarge = defaults.seekTimeLarge
        self.playerVolume = defaults.playerVolume
        self.defaultPlaybackSpeed = defaults.defaultPlaybackSpeed
        self.autoSkipDelay = defaults.autoSkipDelay
        self.creditsCountdownFallback = defaults.creditsCountdownFallback
        self.rememberTrackSelections = defaults.rememberTrackSelections
        self.subtitleFontSize = defaults.subtitleFontSize
        self.subtitleBorderSize = defaults.subtitleBorderSize
        self.subtitleBackgroundOpacity = defaults.subtitleBackgroundOpacity

        // TMDB
        self.tmdbLanguage = defaults.tmdbLanguage
        self.tmdbEnrichMetadata = defaults.tmdbEnrichMetadata
        self.tmdbLocalizedMetadata = defaults.tmdbLocalizedMetadata

        // Catalog
        self.enabledLibraryKeys = defaults.enabledLibraryKeys

        // Trakt
        self.traktAutoSyncWatched = defaults.traktAutoSyncWatched
        self.traktSyncRatings = defaults.traktSyncRatings
        self.traktSyncWatchlist = defaults.traktSyncWatchlist
        self.traktScrobbleEnabled = defaults.traktScrobbleEnabled

        // MDBList
        self.mdblistEnabled = defaults.mdblistEnabled
        self.mdblistApiKey = defaults.mdblistApiKey

        // Overseerr
        self.overseerrEnabled = defaults.overseerrEnabled
        self.overseerrUrl = defaults.overseerrUrl

        // Onboarding
        self.hasCompletedOnboarding = defaults.hasCompletedOnboarding
    }

    // MARK: - Reload Settings (call after profile switch)

    func reloadFromStorage() {
        // Discovery
        discoveryDisabled = defaults.discoveryDisabled
        showNewPopularTab = defaults.showNewPopularTab
        includeTmdbInSearch = defaults.includeTmdbInSearch

        // Home Screen
        showTrendingRows = defaults.showTrendingRows
        showTraktRows = defaults.showTraktRows
        showPlexPopular = defaults.showPlexPopular
        showWatchlist = defaults.showWatchlist
        showCollectionRows = defaults.showCollectionRows
        hiddenCollectionKeys = defaults.hiddenCollectionKeys
        showHeroSection = defaults.showHeroSection
        heroAutoRotate = defaults.heroAutoRotate
        showContinueWatching = defaults.showContinueWatching
        heroLayout = defaults.heroLayout
        continueWatchingLayout = defaults.continueWatchingLayout
        rowLayout = defaults.rowLayout
        posterSize = defaults.posterSize
        showPosterTitles = defaults.showPosterTitles
        showLibraryTitles = defaults.showLibraryTitles
        posterCornerRadius = defaults.posterCornerRadius

        // Details Screen
        detailsScreenLayout = defaults.detailsScreenLayout
        episodeLayout = defaults.episodeLayout
        suggestedLayout = defaults.suggestedLayout
        showRelatedContent = defaults.showRelatedContent
        showCastCrew = defaults.showCastCrew

        // Ratings
        showIMDbRating = defaults.showIMDbRating
        showRottenTomatoesCritic = defaults.showRottenTomatoesCritic
        showRottenTomatoesAudience = defaults.showRottenTomatoesAudience

        // Continue Watching
        useCachedStreams = defaults.useCachedStreams
        streamCacheTTL = defaults.streamCacheTTL

        // Playback Preferences
        defaultQuality = defaults.defaultQuality
        autoPlayNext = defaults.autoPlayNext
        skipIntroAutomatically = defaults.skipIntroAutomatically
        skipCreditsAutomatically = defaults.skipCreditsAutomatically

        // Player Settings
        seekTimeSmall = defaults.seekTimeSmall
        seekTimeLarge = defaults.seekTimeLarge
        playerVolume = defaults.playerVolume
        defaultPlaybackSpeed = defaults.defaultPlaybackSpeed
        autoSkipDelay = defaults.autoSkipDelay
        creditsCountdownFallback = defaults.creditsCountdownFallback
        rememberTrackSelections = defaults.rememberTrackSelections
        subtitleFontSize = defaults.subtitleFontSize
        subtitleBorderSize = defaults.subtitleBorderSize
        subtitleBackgroundOpacity = defaults.subtitleBackgroundOpacity

        // TMDB
        tmdbLanguage = defaults.tmdbLanguage
        tmdbEnrichMetadata = defaults.tmdbEnrichMetadata
        tmdbLocalizedMetadata = defaults.tmdbLocalizedMetadata

        // Catalog
        enabledLibraryKeys = defaults.enabledLibraryKeys

        // Trakt
        traktAutoSyncWatched = defaults.traktAutoSyncWatched
        traktSyncRatings = defaults.traktSyncRatings
        traktSyncWatchlist = defaults.traktSyncWatchlist
        traktScrobbleEnabled = defaults.traktScrobbleEnabled

        // MDBList
        mdblistEnabled = defaults.mdblistEnabled
        mdblistApiKey = defaults.mdblistApiKey

        // Overseerr
        overseerrEnabled = defaults.overseerrEnabled
        overseerrUrl = defaults.overseerrUrl

        // Onboarding
        hasCompletedOnboarding = defaults.hasCompletedOnboarding
    }

    // MARK: - Discovery Mode Helper

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
