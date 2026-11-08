//
//  UserDefaults+PlaybackEngine.swift
//  FlixorMac
//
//  Profile-scoped settings for the playback engine: aspect mode, subtitle
//  appearance (font, bold, position), SDH filtering.
//  Language preferences live in UserDefaults+Extensions (preferredAudioLanguage /
//  preferredSubtitleLanguage); `PlaybackLanguagePreference.original` is stored there.
//

import Foundation

extension Notification.Name {
    /// Posted (on the main thread) when a playback-engine setting changes in Settings,
    /// so a running player can apply it live.
    static let playbackEngineSettingsDidChange = Notification.Name("playbackEngineSettingsDidChange")
}

/// Special values for the preferred-language settings.
enum PlaybackLanguagePreference {
    /// Stored in `preferredAudioLanguage`: pick the title's original language.
    static let original = "original"
}

extension UserDefaults {
    private enum PlaybackEngineKeys {
        static let aspectMode = "playerAspectMode"
        static let zoomStep = "playerZoomStep"
        static let subtitleFilterSDH = "subtitleFilterSDH"
        static let subtitleFontName = "subtitleFontName"
        static let subtitleBold = "subtitleBold"
        static let subtitlePosition = "subtitlePosition"
    }

    // MARK: Aspect (Profile-Scoped)

    /// Video aspect mode (fit / fill / zoom / stretch). Default: fit.
    var playerAspectMode: PlayerAspectMode {
        get { string(forKey: profileKey(PlaybackEngineKeys.aspectMode)).flatMap(PlayerAspectMode.init(rawValue:)) ?? .fit }
        set { set(newValue.rawValue, forKey: profileKey(PlaybackEngineKeys.aspectMode)) }
    }

    /// Zoom step used by `.zoom` (index into `PlayerAspectMode.zoomFactors`). Default: 0 (first step).
    var playerZoomStep: Int {
        get { object(forKey: profileKey(PlaybackEngineKeys.zoomStep)) as? Int ?? 0 }
        set { set(newValue, forKey: profileKey(PlaybackEngineKeys.zoomStep)) }
    }

    // MARK: Subtitles (Profile-Scoped)

    /// Strip hearing-impaired annotations ([MUSIC], (laughs), SPEAKER:) via mpv `sub-filter-sdh`.
    var subtitleFilterSDH: Bool {
        get { object(forKey: profileKey(PlaybackEngineKeys.subtitleFilterSDH)) as? Bool ?? false }
        set { set(newValue, forKey: profileKey(PlaybackEngineKeys.subtitleFilterSDH)) }
    }

    /// Subtitle font family; "" uses mpv's default (sans-serif).
    var subtitleFontName: String {
        get { string(forKey: profileKey(PlaybackEngineKeys.subtitleFontName)) ?? "" }
        set { set(newValue, forKey: profileKey(PlaybackEngineKeys.subtitleFontName)) }
    }

    /// Bold subtitle text.
    var subtitleBold: Bool {
        get { object(forKey: profileKey(PlaybackEngineKeys.subtitleBold)) as? Bool ?? false }
        set { set(newValue, forKey: profileKey(PlaybackEngineKeys.subtitleBold)) }
    }

    /// Vertical subtitle position, mpv `sub-pos` (0 = top, 100 = bottom). Default: 100.
    var subtitlePosition: Int {
        get { object(forKey: profileKey(PlaybackEngineKeys.subtitlePosition)) as? Int ?? 100 }
        set { set(min(150, max(0, newValue)), forKey: profileKey(PlaybackEngineKeys.subtitlePosition)) }
    }

    /// Resets the engine settings from this file (called with the player settings reset).
    func resetPlaybackEngineSettings() {
        playerAspectMode = .fit
        playerZoomStep = 0
        subtitleFilterSDH = false
        subtitleFontName = ""
        subtitleBold = false
        subtitlePosition = 100
    }
}
