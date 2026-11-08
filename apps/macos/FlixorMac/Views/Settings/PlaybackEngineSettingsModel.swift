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
        .init(code: "en", name: "English"),
        .init(code: "es", name: "Spanish"),
        .init(code: "es-419", name: "Spanish (Latin America)"),
        .init(code: "pt", name: "Portuguese"),
        .init(code: "pt-BR", name: "Portuguese (Brazil)"),
        .init(code: "fr", name: "French"),
        .init(code: "fr-CA", name: "French (Canada)"),
        .init(code: "de", name: "German"),
        .init(code: "it", name: "Italian"),
        .init(code: "ja", name: "Japanese"),
        .init(code: "ko", name: "Korean"),
        .init(code: "zh-Hans", name: "Chinese (Simplified)"),
        .init(code: "zh-Hant", name: "Chinese (Traditional)"),
        .init(code: "ru", name: "Russian"),
        .init(code: "ar", name: "Arabic"),
        .init(code: "hi", name: "Hindi"),
        .init(code: "nl", name: "Dutch"),
        .init(code: "sv", name: "Swedish"),
        .init(code: "no", name: "Norwegian"),
        .init(code: "da", name: "Danish"),
        .init(code: "fi", name: "Finnish"),
        .init(code: "pl", name: "Polish"),
        .init(code: "tr", name: "Turkish"),
        .init(code: "he", name: "Hebrew"),
        .init(code: "th", name: "Thai"),
        .init(code: "vi", name: "Vietnamese"),
        .init(code: "id", name: "Indonesian"),
        .init(code: "cs", name: "Czech"),
        .init(code: "el", name: "Greek"),
        .init(code: "hu", name: "Hungarian"),
        .init(code: "ro", name: "Romanian"),
        .init(code: "uk", name: "Ukrainian"),
    ]

    /// Audio choices; a code typed in an earlier version stays selectable.
    static func audioOptions(including current: String) -> [PlaybackLanguageOption] {
        withCurrent(current, leading: [
            .init(code: "", name: "Default"),
            .init(code: PlaybackLanguagePreference.original, name: "Original Language"),
        ])
    }

    /// Subtitle choices; "" means the first available track.
    static func subtitleOptions(including current: String) -> [PlaybackLanguageOption] {
        withCurrent(current, leading: [.init(code: "", name: "Any")])
    }

    private static func withCurrent(_ current: String, leading: [PlaybackLanguageOption]) -> [PlaybackLanguageOption] {
        var options = leading + common
        if !options.contains(where: { $0.code == current }) {
            options.insert(.init(code: current, name: LanguageMatcher.displayName(for: current)), at: leading.count)
        }
        return options
    }
}
