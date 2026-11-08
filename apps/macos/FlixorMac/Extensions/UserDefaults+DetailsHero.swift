//
//  UserDefaults+DetailsHero.swift
//  FlixorMac
//
//  Profile-scoped settings for the details hero's inline trailer.
//

import Foundation

extension UserDefaults {
    private enum DetailsHeroKeys {
        static let inlineTrailer = "detailsHeroInlineTrailerEnabled"
        static let startMuted = "detailsHeroTrailerStartsMuted"
    }

    /// Play the title's trailer in the hero background after a short idle delay. Default on.
    var detailsHeroInlineTrailerEnabled: Bool {
        get { object(forKey: profileKey(DetailsHeroKeys.inlineTrailer)) as? Bool ?? true }
        set { set(newValue, forKey: profileKey(DetailsHeroKeys.inlineTrailer)) }
    }

    /// Start the inline trailer muted. Default on.
    var detailsHeroTrailerStartsMuted: Bool {
        get { object(forKey: profileKey(DetailsHeroKeys.startMuted)) as? Bool ?? true }
        set { set(newValue, forKey: profileKey(DetailsHeroKeys.startMuted)) }
    }
}
