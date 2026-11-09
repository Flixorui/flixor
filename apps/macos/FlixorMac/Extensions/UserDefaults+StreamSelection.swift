//
//  UserDefaults+StreamSelection.swift
//  FlixorMac
//
//  Profile-scoped settings for what pressing Play on addon content does.
//
//  Keys (all go through `profileKey`, so each profile has its own values):
//    stremioPlayAction          "showSources" (default) | "playBest" | "matchRules" | "addonOrder"
//    stremioAutoPickTimeLimit   Int seconds to wait on addons, default 5
//    stremioRulesInclude        include words or regex, default ""
//    stremioRulesIncludeRegex   Bool, default false
//    stremioRulesExclude        exclude words, default ""
//    stremioRulesPreferredAddon addon installation id, default none
//    stremioRulesMaxResolution  2160 | 1080 | 720 | 480, default none
//

import Foundation

enum StremioPlayAction: String, CaseIterable, Identifiable {
    case showSources
    case playBest
    case matchRules
    case addonOrder

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .showSources: return String(localized: "Show sources")
        case .playBest: return String(localized: "Play best source")
        case .matchRules: return String(localized: "Match my rules")
        case .addonOrder: return String(localized: "Follow addon order")
        }
    }

    var isAutomatic: Bool { self != .showSources }
}

/// The "Match my rules" settings. Empty fields place no restriction.
struct StreamSelectionRules: Equatable {
    /// Include words (separated by `|` or `,`), or a regex when `includeIsRegex`.
    var include = ""
    var includeIsRegex = false
    /// Exclude words, separated by `|` or `,`.
    var exclude = ""
    /// Installation id of the addon to prefer.
    var preferredAddonId: String?
    /// Highest resolution allowed (2160/1080/720/480).
    var maxResolution: Int?
}

extension UserDefaults {
    private enum StreamSelectionKeys {
        static let playAction = "stremioPlayAction"
        static let timeLimit = "stremioAutoPickTimeLimit"
        static let include = "stremioRulesInclude"
        static let includeIsRegex = "stremioRulesIncludeRegex"
        static let exclude = "stremioRulesExclude"
        static let preferredAddon = "stremioRulesPreferredAddon"
        static let maxResolution = "stremioRulesMaxResolution"
    }

    /// Back to defaults: show sources, no rules, default time limit.
    func resetStreamSelectionSettings() {
        for key in [
            StreamSelectionKeys.playAction,
            StreamSelectionKeys.timeLimit,
            StreamSelectionKeys.include,
            StreamSelectionKeys.includeIsRegex,
            StreamSelectionKeys.exclude,
            StreamSelectionKeys.preferredAddon,
            StreamSelectionKeys.maxResolution,
        ] {
            removeObject(forKey: profileKey(key))
        }
    }

    /// What pressing Play on addon content does. Profiles that turned on the older
    /// "Auto-Play Best Source" toggle and never chose here keep auto-playing.
    var stremioPlayAction: StremioPlayAction {
        get {
            if let stored = string(forKey: profileKey(StreamSelectionKeys.playAction)),
               let action = StremioPlayAction(rawValue: stored) {
                return action
            }
            return stremioAutoPlayBestSource ? .playBest : .showSources
        }
        set { set(newValue.rawValue, forKey: profileKey(StreamSelectionKeys.playAction)) }
    }

    /// Seconds to wait on addons before deciding with what has arrived. Default: 5.
    var stremioAutoPickTimeLimit: Int {
        get {
            let stored = integer(forKey: profileKey(StreamSelectionKeys.timeLimit))
            return stored > 0 ? stored : 5
        }
        set { set(newValue, forKey: profileKey(StreamSelectionKeys.timeLimit)) }
    }

    var stremioStreamRules: StreamSelectionRules {
        get {
            StreamSelectionRules(
                include: string(forKey: profileKey(StreamSelectionKeys.include)) ?? "",
                includeIsRegex: bool(forKey: profileKey(StreamSelectionKeys.includeIsRegex)),
                exclude: string(forKey: profileKey(StreamSelectionKeys.exclude)) ?? "",
                preferredAddonId: string(forKey: profileKey(StreamSelectionKeys.preferredAddon)),
                maxResolution: {
                    let stored = integer(forKey: profileKey(StreamSelectionKeys.maxResolution))
                    return stored > 0 ? stored : nil
                }()
            )
        }
        set {
            set(newValue.include, forKey: profileKey(StreamSelectionKeys.include))
            set(newValue.includeIsRegex, forKey: profileKey(StreamSelectionKeys.includeIsRegex))
            set(newValue.exclude, forKey: profileKey(StreamSelectionKeys.exclude))
            set(newValue.preferredAddonId, forKey: profileKey(StreamSelectionKeys.preferredAddon))
            set(newValue.maxResolution ?? 0, forKey: profileKey(StreamSelectionKeys.maxResolution))
        }
    }
}
