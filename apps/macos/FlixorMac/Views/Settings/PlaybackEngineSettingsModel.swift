//
//  PlaybackEngineSettingsModel.swift
//  FlixorMac
//
//  Observable bridge between PlayerSettingsView and the profile-scoped playback
//  engine settings. Every change is saved and announced so an open player applies it live.
//

import Foundation
import SwiftUI

@MainActor
final class PlaybackEngineSettingsModel: ObservableObject {
    @Published var aspectMode: PlayerAspectMode = .fit { didSet { save { $0.playerAspectMode = aspectMode } } }
    @Published var filterSDH = false { didSet { save { $0.subtitleFilterSDH = filterSDH } } }
    @Published var fontName = "" { didSet { save { $0.subtitleFontName = fontName } } }
    @Published var bold = false { didSet { save { $0.subtitleBold = bold } } }
    @Published var position = 100 { didSet { save { $0.subtitlePosition = position } } }

    private var isReloading = false

    init() {
        reload()
    }

    /// Re-reads the current profile's values (no save, no notification).
    func reload() {
        isReloading = true
        defer { isReloading = false }
        let defaults = UserDefaults.standard
        aspectMode = defaults.playerAspectMode
        filterSDH = defaults.subtitleFilterSDH
        fontName = defaults.subtitleFontName
        bold = defaults.subtitleBold
        position = defaults.subtitlePosition
    }

    /// Tells an open player to re-read and apply the engine settings.
    static func notifyPlayer() {
        NotificationCenter.default.post(name: .playbackEngineSettingsDidChange, object: nil)
    }

    private func save(_ write: (UserDefaults) -> Void) {
        guard !isReloading else { return }
        write(.standard)
        Self.notifyPlayer()
    }
}

/// One language choice in the preferred-language pickers.
struct PlaybackLanguageOption: Hashable, Identifiable {
    let code: String
    let name: String
    var id: String { code }

    private static let common: [PlaybackLanguageOption] = [
        .init(code: "en", name: String(localized: "English")),
        .init(code: "es", name: String(localized: "Spanish")),
        .init(code: "es-419", name: String(localized: "Spanish (Latin America)")),
        .init(code: "pt", name: String(localized: "Portuguese")),
        .init(code: "pt-BR", name: String(localized: "Portuguese (Brazil)")),
        .init(code: "fr", name: String(localized: "French")),
        .init(code: "fr-CA", name: String(localized: "French (Canada)")),
        .init(code: "de", name: String(localized: "German")),
        .init(code: "it", name: String(localized: "Italian")),
        .init(code: "ja", name: String(localized: "Japanese")),
        .init(code: "ko", name: String(localized: "Korean")),
        .init(code: "zh-Hans", name: String(localized: "Chinese (Simplified)")),
        .init(code: "zh-Hant", name: String(localized: "Chinese (Traditional)")),
        .init(code: "ru", name: String(localized: "Russian")),
        .init(code: "ar", name: String(localized: "Arabic")),
        .init(code: "hi", name: String(localized: "Hindi")),
        .init(code: "nl", name: String(localized: "Dutch")),
        .init(code: "sv", name: String(localized: "Swedish")),
        .init(code: "no", name: String(localized: "Norwegian")),
        .init(code: "da", name: String(localized: "Danish")),
        .init(code: "fi", name: String(localized: "Finnish")),
        .init(code: "pl", name: String(localized: "Polish")),
        .init(code: "tr", name: String(localized: "Turkish")),
        .init(code: "he", name: String(localized: "Hebrew")),
        .init(code: "th", name: String(localized: "Thai")),
        .init(code: "vi", name: String(localized: "Vietnamese")),
        .init(code: "id", name: String(localized: "Indonesian")),
        .init(code: "cs", name: String(localized: "Czech")),
        .init(code: "el", name: String(localized: "Greek")),
        .init(code: "hu", name: String(localized: "Hungarian")),
        .init(code: "ro", name: String(localized: "Romanian")),
        .init(code: "uk", name: String(localized: "Ukrainian")),
    ]

    /// Audio choices; a code typed in an earlier version stays selectable.
    static func audioOptions(including current: String) -> [PlaybackLanguageOption] {
        withCurrent(current, leading: [
            .init(code: "", name: String(localized: "Default")),
            .init(code: PlaybackLanguagePreference.original, name: String(localized: "Original Language")),
        ])
    }

    /// Subtitle choices; "" means the first available track.
    static func subtitleOptions(including current: String) -> [PlaybackLanguageOption] {
        withCurrent(current, leading: [.init(code: "", name: String(localized: "Any"))])
    }

    private static func withCurrent(_ current: String, leading: [PlaybackLanguageOption]) -> [PlaybackLanguageOption] {
        var options = leading + common
        if !options.contains(where: { $0.code == current }) {
            options.insert(.init(code: current, name: LanguageMatcher.displayName(for: current)), at: leading.count)
        }
        return options
    }
}
