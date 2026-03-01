//
//  StremioStorage.swift
//  FlixorMac
//
//  Profile-scoped persistence helpers for macOS Stremio state.
//

import Foundation

let STREMIO_DEFAULT_OPEN_SUBTITLES_URL = "https://opensubtitles-v3.strem.io/manifest.json"
let STREMIO_DEFAULT_OPEN_SUBTITLES_ID = "org.stremio.opensubtitlesv3"

func normalizeStremioManifestURL(_ url: String) -> String {
    let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }
    if trimmed.lowercased().hasSuffix("manifest.json") {
        return trimmed
    }
    return "\(trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/manifest.json"
}

actor StremioStorage {
    static let shared = StremioStorage()

    private let defaults = UserDefaults.standard

    func installedAddons() -> [StremioAddonManifest] {
        defaults.getStremioAddons()
    }

    func setInstalledAddons(_ addons: [StremioAddonManifest]) {
        defaults.setStremioAddons(addons)
    }

    func addonOrder() -> [String] {
        defaults.getStremioAddonOrder()
    }

    func setAddonOrder(_ order: [String]) {
        defaults.setStremioAddonOrder(order)
    }

    func removedDefaultAddons() -> [String] {
        defaults.getRemovedStremioDefaultAddons()
    }

    func setRemovedDefaultAddons(_ addonIds: [String]) {
        defaults.setRemovedStremioDefaultAddons(addonIds)
    }

    func streamCacheIndex() -> [String: CachedPlaybackSource] {
        defaults.getStremioStreamCache()
    }

    func setStreamCacheIndex(_ cache: [String: CachedPlaybackSource]) {
        defaults.setStremioStreamCache(cache)
    }

    func resumeStateIndex() -> [String: ResumeState] {
        defaults.getStremioResumeStates()
    }

    func setResumeStateIndex(_ states: [String: ResumeState]) {
        defaults.setStremioResumeStates(states)
    }
}
