//
//  PlayerBackend.swift
//  FlixorMac
//
//  Player backend selection
//

import Foundation

enum PlayerBackend: String, CaseIterable, Identifiable {
    case avplayer = "AVPlayer"
    case mpv = "MPV"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .avplayer:
            return "AVPlayer (Native)"
        case .mpv:
            return "MPV (Advanced)"
        }
    }

    var description: String {
        switch self {
        case .avplayer:
            return "Apple's native player. Best for standard formats."
        case .mpv:
            return "Advanced player with broader codec support."
        }
    }
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
