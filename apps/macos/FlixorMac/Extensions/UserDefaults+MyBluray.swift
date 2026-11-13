//
//  UserDefaults+MyBluray.swift
//  FlixorMac
//
//  Profile-scoped MyBluray settings. The API key lives in the Keychain; the
//  rest are plain defaults. MyBluraySettingsStore is the observable owner.
//

import Foundation

/// One on/off choice about what MyBluray adds to the app. Each is stored on
/// its own, so new options can be added without migrating anything.
enum MyBlurayOption: String, CaseIterable, Identifiable {
    // Trailers
    case appleTrailers
    case highQualityTrailers
    case bonusVideos
    // Ratings
    case ratings
    // Parents guide
    case ageRatings
    case commonSense
    case imdbGuide
    case guideDescriptions
    case revealSpoilers
    // Physical releases on Details
    case physicalReleases
    case blurayFormat
    case uhdFormat
    case boxSets
    case quickAdd
    // Edition page blocks
    case editionSpecs
    case editionScores
    case editionScreenshots
    case editionArtwork
    case editionDigitalCopy
    case editionPrice
    case editionLinks
    // Library
    case librarySection

    var id: String { rawValue }

    /// Off by default: bonus videos (a larger request per title) and spoilers.
    var defaultValue: Bool {
        switch self {
        case .bonusVideos, .revealSpoilers: return false
        default: return true
        }
    }

    /// The option this one depends on: it does nothing while that one is off.
    var requires: MyBlurayOption? {
        switch self {
        case .highQualityTrailers, .bonusVideos: return .appleTrailers
        case .guideDescriptions: return .imdbGuide
        case .revealSpoilers: return .guideDescriptions
        case .blurayFormat, .uhdFormat, .boxSets, .quickAdd: return .physicalReleases
        default: return nil
        }
    }

    static let editionBlocks: [MyBlurayOption] = [
        .editionSpecs, .editionScores, .editionScreenshots, .editionArtwork,
        .editionDigitalCopy, .editionPrice, .editionLinks,
    ]
}

extension UserDefaults {
    private enum MyBlurayKeys {
        static let apiKey = "myblurayApiKey"
        static let enabled = "myblurayEnabled"
        static let discCountry = "myblurayDiscCountry"
        static func option(_ option: MyBlurayOption) -> String { "mybluray.\(option.rawValue)" }
    }

    /// Each person's own key from the MyBluray portal (`mbr_…`).
    var myblurayApiKey: String {
        get { secret(forKey: profileKey(MyBlurayKeys.apiKey)) }
        set { setSecret(newValue, forKey: profileKey(MyBlurayKeys.apiKey)) }
    }

    /// Master switch. On by default, so adding a key is enough.
    var myblurayEnabled: Bool {
        get { object(forKey: profileKey(MyBlurayKeys.enabled)) as? Bool ?? true }
        set { set(newValue, forKey: profileKey(MyBlurayKeys.enabled)) }
    }

    /// Market for disc releases: an ISO country code, `auto` (this Mac's
    /// region) or `all`.
    var myblurayDiscCountry: String {
        get { string(forKey: profileKey(MyBlurayKeys.discCountry)) ?? "auto" }
        set { set(newValue, forKey: profileKey(MyBlurayKeys.discCountry)) }
    }

    func myblurayOption(_ option: MyBlurayOption) -> Bool {
        object(forKey: profileKey(MyBlurayKeys.option(option))) as? Bool ?? option.defaultValue
    }

    /// Whether MyBluray should supply this right now: a key is saved, the
    /// master switch is on, and so are the option and everything it depends
    /// on. For services off the main actor; views use MyBluraySettingsStore.
    func myblurayOptionActive(_ option: MyBlurayOption) -> Bool {
        guard myblurayEnabled,
              !myblurayApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        var current: MyBlurayOption? = option
        while let checked = current {
            if !myblurayOption(checked) { return false }
            current = checked.requires
        }
        return true
    }

    func setMyblurayOption(_ option: MyBlurayOption, _ value: Bool) {
        set(value, forKey: profileKey(MyBlurayKeys.option(option)))
    }

    /// Puts every display choice back to its default. Keeps the key.
    func resetMyblurayDisplaySettings() {
        removeObject(forKey: profileKey(MyBlurayKeys.discCountry))
        for option in MyBlurayOption.allCases {
            removeObject(forKey: profileKey(MyBlurayKeys.option(option)))
        }
    }
}
