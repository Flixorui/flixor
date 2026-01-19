//
//  TrackPreferenceService.swift
//  FlixorMac
//
//  Service for persisting audio and subtitle track language preferences
//

import Foundation

/// Service for remembering user's preferred audio and subtitle track selections
class TrackPreferenceService {
    static let shared = TrackPreferenceService()

    private let audioPrefsKey = "audioTrackPreferences"
    private let subtitlePrefsKey = "subtitleTrackPreferences"

    private init() {}

    // MARK: - Audio Preferences

    /// Save the preferred audio language for a media item
    /// - Parameters:
    ///   - mediaId: The Plex rating key or unique identifier for the media
    ///   - languageCode: The ISO 639-1/2 language code (e.g., "eng", "jpn")
    func saveAudioPreference(for mediaId: String, languageCode: String) {
        guard UserDefaults.standard.rememberTrackSelections else { return }
        var prefs = getAudioPreferences()
        prefs[mediaId] = languageCode
        saveAudioPreferences(prefs)
    }

    /// Get the preferred audio language for a media item
    /// - Parameter mediaId: The Plex rating key or unique identifier
    /// - Returns: The saved language code, or nil if none
    func getAudioPreference(for mediaId: String) -> String? {
        guard UserDefaults.standard.rememberTrackSelections else { return nil }
        return getAudioPreferences()[mediaId]
    }

    /// Get global audio language preference (most frequently used)
    func getGlobalAudioPreference() -> String? {
        guard UserDefaults.standard.rememberTrackSelections else { return nil }
        let prefs = getAudioPreferences()
        return mostFrequentValue(in: prefs)
    }

    // MARK: - Subtitle Preferences

    /// Save the preferred subtitle language for a media item
    /// - Parameters:
    ///   - mediaId: The Plex rating key or unique identifier for the media
    ///   - languageCode: The ISO 639-1/2 language code, or "none" for disabled
    func saveSubtitlePreference(for mediaId: String, languageCode: String) {
        guard UserDefaults.standard.rememberTrackSelections else { return }
        var prefs = getSubtitlePreferences()
        prefs[mediaId] = languageCode
        saveSubtitlePreferences(prefs)
    }

    /// Get the preferred subtitle language for a media item
    /// - Parameter mediaId: The Plex rating key or unique identifier
    /// - Returns: The saved language code, "none" if subtitles disabled, or nil if no preference
    func getSubtitlePreference(for mediaId: String) -> String? {
        guard UserDefaults.standard.rememberTrackSelections else { return nil }
        return getSubtitlePreferences()[mediaId]
    }

    /// Get global subtitle language preference (most frequently used)
    func getGlobalSubtitlePreference() -> String? {
        guard UserDefaults.standard.rememberTrackSelections else { return nil }
        let prefs = getSubtitlePreferences()
        return mostFrequentValue(in: prefs)
    }

    // MARK: - Series-Level Preferences

    /// Save audio preference for an entire series (useful for anime, foreign shows)
    /// - Parameters:
    ///   - seriesId: The Plex rating key for the show/series
    ///   - languageCode: The ISO 639-1/2 language code
    func saveSeriesAudioPreference(for seriesId: String, languageCode: String) {
        guard UserDefaults.standard.rememberTrackSelections else { return }
        var prefs = getAudioPreferences()
        prefs["series:\(seriesId)"] = languageCode
        saveAudioPreferences(prefs)
    }

    /// Get audio preference for a series
    func getSeriesAudioPreference(for seriesId: String) -> String? {
        guard UserDefaults.standard.rememberTrackSelections else { return nil }
        return getAudioPreferences()["series:\(seriesId)"]
    }

    /// Save subtitle preference for an entire series
    func saveSeriesSubtitlePreference(for seriesId: String, languageCode: String) {
        guard UserDefaults.standard.rememberTrackSelections else { return }
        var prefs = getSubtitlePreferences()
        prefs["series:\(seriesId)"] = languageCode
        saveSubtitlePreferences(prefs)
    }

    /// Get subtitle preference for a series
    func getSeriesSubtitlePreference(for seriesId: String) -> String? {
        guard UserDefaults.standard.rememberTrackSelections else { return nil }
        return getSubtitlePreferences()["series:\(seriesId)"]
    }

    // MARK: - Best Match Selection

    /// Find the best audio track index based on preferences
    /// - Parameters:
    ///   - tracks: Array of available audio tracks with language codes
    ///   - mediaId: Current media item ID
    ///   - seriesId: Optional series ID for TV shows
    /// - Returns: The recommended track index, or nil for default
    func recommendedAudioTrackIndex(
        tracks: [(index: Int, languageCode: String)],
        mediaId: String,
        seriesId: String? = nil
    ) -> Int? {
        guard UserDefaults.standard.rememberTrackSelections else { return nil }

        // Priority order: specific episode > series > global
        let preferredLanguages: [String?] = [
            getAudioPreference(for: mediaId),
            seriesId.flatMap { getSeriesAudioPreference(for: $0) },
            getGlobalAudioPreference()
        ]

        for preferredLang in preferredLanguages.compactMap({ $0 }) {
            if let match = tracks.first(where: { $0.languageCode.lowercased() == preferredLang.lowercased() }) {
                return match.index
            }
        }

        return nil
    }

    /// Find the best subtitle track index based on preferences
    /// - Parameters:
    ///   - tracks: Array of available subtitle tracks with language codes
    ///   - mediaId: Current media item ID
    ///   - seriesId: Optional series ID for TV shows
    /// - Returns: The recommended track index, nil for default, or -1 to disable subtitles
    func recommendedSubtitleTrackIndex(
        tracks: [(index: Int, languageCode: String)],
        mediaId: String,
        seriesId: String? = nil
    ) -> Int? {
        guard UserDefaults.standard.rememberTrackSelections else { return nil }

        // Priority order: specific episode > series > global
        let preferredLanguages: [String?] = [
            getSubtitlePreference(for: mediaId),
            seriesId.flatMap { getSeriesSubtitlePreference(for: $0) },
            getGlobalSubtitlePreference()
        ]

        for preferredLang in preferredLanguages.compactMap({ $0 }) {
            if preferredLang == "none" {
                return -1 // Special value indicating subtitles should be disabled
            }
            if let match = tracks.first(where: { $0.languageCode.lowercased() == preferredLang.lowercased() }) {
                return match.index
            }
        }

        return nil
    }

    // MARK: - Clear Preferences

    /// Clear all track preferences
    func clearAllPreferences() {
        UserDefaults.standard.removeObject(forKey: audioPrefsKey)
        UserDefaults.standard.removeObject(forKey: subtitlePrefsKey)
    }

    /// Clear preferences for a specific media item
    func clearPreferences(for mediaId: String) {
        var audioPrefs = getAudioPreferences()
        audioPrefs.removeValue(forKey: mediaId)
        saveAudioPreferences(audioPrefs)

        var subtitlePrefs = getSubtitlePreferences()
        subtitlePrefs.removeValue(forKey: mediaId)
        saveSubtitlePreferences(subtitlePrefs)
    }

    // MARK: - Private Helpers

    private func getAudioPreferences() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: audioPrefsKey) as? [String: String] ?? [:]
    }

    private func saveAudioPreferences(_ prefs: [String: String]) {
        UserDefaults.standard.set(prefs, forKey: audioPrefsKey)
    }

    private func getSubtitlePreferences() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: subtitlePrefsKey) as? [String: String] ?? [:]
    }

    private func saveSubtitlePreferences(_ prefs: [String: String]) {
        UserDefaults.standard.set(prefs, forKey: subtitlePrefsKey)
    }

    private func mostFrequentValue(in dict: [String: String]) -> String? {
        var frequency: [String: Int] = [:]
        for value in dict.values {
            frequency[value, default: 0] += 1
        }
        return frequency.max(by: { $0.value < $1.value })?.key
    }
}
