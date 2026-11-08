//
//  PlayerBackend.swift
//  FlixorMac
//
//  Legacy player backend preference. Playback always uses MPV on macOS;
//  the AVPlayer backend was removed. This minimal definition remains only
//  so RootView can migrate an old stored "AVPlayer" value to MPV.
//

import Foundation

enum PlayerBackend: String {
    case avplayer = "AVPlayer"
    case mpv = "MPV"
}

// UserDefaults extension for player backend preference
extension UserDefaults {
    private enum Keys {
        static let playerBackend = "playerBackend"
    }

    var playerBackend: PlayerBackend {
        get {
            guard let rawValue = string(forKey: Keys.playerBackend),
                  let backend = PlayerBackend(rawValue: rawValue) else {
                return .mpv // Default to MPV
            }
            return backend
        }
        set {
            set(newValue.rawValue, forKey: Keys.playerBackend)
        }
    }
}
