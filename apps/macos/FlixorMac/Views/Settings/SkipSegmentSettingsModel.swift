//
//  SkipSegmentSettingsModel.swift
//  FlixorMac
//
//  Observable bridge between PlayerSettingsView and the profile-scoped skip
//  segment settings (UserDefaults+SkipSegments). They are read when playback
//  starts, so no live notification is needed.
//

import Foundation
import SwiftUI

@MainActor
final class SkipSegmentSettingsModel: ObservableObject {
    @Published var skipRecapAutomatically = true {
        didSet { save { $0.skipRecapAutomatically = skipRecapAutomatically } }
    }
    @Published var communitySkipSegmentsEnabled = true {
        didSet { save { $0.communitySkipSegmentsEnabled = communitySkipSegmentsEnabled } }
    }
    @Published var animeSkipClientId = "" {
        didSet { save { $0.animeSkipClientId = animeSkipClientId } }
    }

    private var isReloading = false

    init() {
        reload()
    }

    /// Re-reads the current profile's values without saving.
    func reload() {
        isReloading = true
        defer { isReloading = false }
        let defaults = UserDefaults.standard
        skipRecapAutomatically = defaults.skipRecapAutomatically
        communitySkipSegmentsEnabled = defaults.communitySkipSegmentsEnabled
        animeSkipClientId = defaults.animeSkipClientId
    }

    func resetToDefaults() {
        skipRecapAutomatically = true
        communitySkipSegmentsEnabled = true
        animeSkipClientId = ""
    }

    private func save(_ write: (UserDefaults) -> Void) {
        guard !isReloading else { return }
        write(.standard)
    }
}
