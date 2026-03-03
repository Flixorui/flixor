import Foundation

enum TVSettingsMigration {
    private static let settingsV2AppliedKey = "tvos.settingsMigration.v2.applied"
    private static let settingsV3AppliedKey = "tvos.settingsMigration.v3.applied"

    static func apply(to defaults: UserDefaults) {
        if defaults.object(forKey: settingsV2AppliedKey) as? Bool != true {
            if defaults.object(forKey: "tvos.skipIntroAutomatically") == nil {
                defaults.set(true, forKey: "tvos.skipIntroAutomatically")
            }
            if defaults.object(forKey: "tvos.skipCreditsAutomatically") == nil {
                defaults.set(true, forKey: "tvos.skipCreditsAutomatically")
            }
            defaults.set(true, forKey: settingsV2AppliedKey)
        }

        guard defaults.object(forKey: settingsV3AppliedKey) as? Bool != true else { return }

        migrateString(defaults, from: "tvos.heroLayout", to: "tvos.heroPresentationMode") { raw in
            raw == "billboard" ? TVHeroPresentationMode.billboard.rawValue : TVHeroPresentationMode.carousel.rawValue
        }
        migrateString(defaults, from: "tvos.continueWatchingLayout", to: "tvos.continueWatchingCardShape") { raw in
            raw == "landscape" ? TVRailCardShape.landscape.rawValue : TVRailCardShape.poster.rawValue
        }
        migrateString(defaults, from: "tvos.rowLayout", to: "tvos.defaultRailCardShape") { raw in
            raw == "landscape" ? TVRailCardShape.landscape.rawValue : TVRailCardShape.poster.rawValue
        }
        migrateString(defaults, from: "tvos.posterSize", to: "tvos.posterWidthPreset") { raw in
            switch raw {
            case "small": return TVPosterWidthPreset.dense.rawValue
            case "large": return TVPosterWidthPreset.large.rawValue
            default: return TVPosterWidthPreset.balanced.rawValue
            }
        }
        migrateString(defaults, from: "tvos.posterCornerRadius", to: "tvos.posterCornerPreset") { raw in
            switch raw {
            case "none": return TVPosterCornerPreset.sharp.rawValue
            case "small": return TVPosterCornerPreset.classic.rawValue
            case "large": return TVPosterCornerPreset.pill.rawValue
            default: return TVPosterCornerPreset.rounded.rawValue
            }
        }

        // Deprecated keys are intentionally kept readable for one release.
        _ = defaults.string(forKey: "tvos.detailsScreenLayout")
        _ = defaults.string(forKey: "tvos.episodeLayout")
        _ = defaults.string(forKey: "tvos.suggestedLayout")

        seed(defaults, key: "tvos.accentTheme", value: TVAccentTheme.white.rawValue)
        seed(defaults, key: "tvos.appFont", value: TVAppFont.system.rawValue)
        seed(defaults, key: "tvos.homeLayoutMode", value: TVHomeLayoutMode.modern.rawValue)
        seed(defaults, key: "tvos.heroPresentationMode", value: TVHeroPresentationMode.carousel.rawValue)
        seed(defaults, key: "tvos.modernLandscapePostersEnabled", value: false)
        seed(defaults, key: "tvos.continueWatchingCardShape", value: TVRailCardShape.poster.rawValue)
        seed(defaults, key: "tvos.defaultRailCardShape", value: TVRailCardShape.poster.rawValue)
        seed(defaults, key: "tvos.heroSourceKeys", value: [String]())
        seed(defaults, key: "tvos.showSearchDiscoverContent", value: true)
        seed(defaults, key: "tvos.showCatalogAddonName", value: false)
        seed(defaults, key: "tvos.showCatalogTypeSuffix", value: false)
        seed(defaults, key: "tvos.hideUnreleasedContent", value: false)
        seed(defaults, key: "tvos.blurUnwatchedEpisodes", value: false)
        seed(defaults, key: "tvos.showTrailerButton", value: true)
        seed(defaults, key: "tvos.preferExternalMetadata", value: false)
        seed(defaults, key: "tvos.focusedPosterExpandEnabled", value: false)
        seed(defaults, key: "tvos.focusedPosterExpandDelaySeconds", value: 3.0)
        seed(defaults, key: "tvos.focusedPosterTrailerEnabled", value: false)
        seed(defaults, key: "tvos.focusedPosterTrailerMuted", value: true)
        seed(defaults, key: "tvos.focusedPosterTrailerTarget", value: TVFocusedPosterTrailerTarget.heroMedia.rawValue)
        seed(defaults, key: "tvos.posterWidthPreset", value: TVPosterWidthPreset.balanced.rawValue)
        seed(defaults, key: "tvos.posterCornerPreset", value: TVPosterCornerPreset.rounded.rawValue)
        seed(defaults, key: "tvos.voiceInputEnabled", value: true)

        defaults.set(true, forKey: settingsV3AppliedKey)
    }

    private static func migrateString(
        _ defaults: UserDefaults,
        from legacyKey: String,
        to newKey: String,
        transform: (String) -> String
    ) {
        guard defaults.object(forKey: newKey) == nil else { return }
        let migrated = transform(defaults.string(forKey: legacyKey) ?? "")
        defaults.set(migrated, forKey: newKey)
    }

    private static func seed(_ defaults: UserDefaults, key: String, value: Any) {
        guard defaults.object(forKey: key) == nil else { return }
        defaults.set(value, forKey: key)
    }
}
