//
//  UserDefaults+SkipSegments.swift
//  FlixorMac
//
//  Profile-scoped settings for community skip segments (IntroDB / AniSkip /
//  Anime-Skip) and recap auto-skip. UI for these lives in the player settings.
//

import Foundation

extension UserDefaults {
    enum SkipSegmentKeys {
        static let skipRecapAutomatically = "skipRecapAutomatically"
        static let communitySkipSegmentsEnabled = "communitySkipSegmentsEnabled"
        static let animeSkipClientId = "animeSkipClientId"
    }

    /// Auto-skip recaps (countdown like intro/credits). Default: enabled, matching intro/credits.
    var skipRecapAutomatically: Bool {
        get { object(forKey: profileKey(SkipSegmentKeys.skipRecapAutomatically)) as? Bool ?? true }
        set { set(newValue, forKey: profileKey(SkipSegmentKeys.skipRecapAutomatically)) }
    }

    /// Look up intro/recap/credits timings from community databases for items
    /// without Plex markers (addon streams, Plex items lacking markers). Default: enabled.
    var communitySkipSegmentsEnabled: Bool {
        get { object(forKey: profileKey(SkipSegmentKeys.communitySkipSegmentsEnabled)) as? Bool ?? true }
        set { set(newValue, forKey: profileKey(SkipSegmentKeys.communitySkipSegmentsEnabled)) }
    }

    /// The user's own Anime-Skip client id (the API needs one; see anime-skip.com/api).
    /// Empty = Anime-Skip is not queried.
    var animeSkipClientId: String {
        get { string(forKey: profileKey(SkipSegmentKeys.animeSkipClientId)) ?? "" }
        set { set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: profileKey(SkipSegmentKeys.animeSkipClientId)) }
    }
}
