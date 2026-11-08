//
//  UserDefaults+DetailsSections.swift
//  FlixorMac
//
//  Profile-scoped settings for the details screen sections: their order and
//  visibility, spoiler protection, the season picker style and episode ratings.
//  Read and write through `DetailsSectionsStore.shared` in UI code so views update.
//

import Foundation

/// A reorderable section below the details hero. The hero always stays first.
enum DetailsSectionKey: String, CaseIterable, Codable, Identifiable {
    case episodes
    case suggested
    case collection
    case cast
    case trailers
    case comments
    case about

    var id: String { rawValue }

    /// Tab id used by the tabbed layout. The first three match the ids
    /// DetailsView already uses for its initial tab ("EPISODES", "SUGGESTED", "DETAILS").
    var tabId: String {
        switch self {
        case .episodes: return "EPISODES"
        case .suggested: return "SUGGESTED"
        case .collection: return "COLLECTION"
        case .cast: return "CAST"
        case .trailers: return "TRAILERS"
        case .comments: return "COMMENTS"
        case .about: return "DETAILS"
        }
    }

    var title: String {
        switch self {
        case .episodes: return String(localized: "Episodes")
        case .suggested: return String(localized: "More Like This")
        case .collection: return String(localized: "Collection")
        case .cast: return String(localized: "Cast & Crew")
        case .trailers: return String(localized: "Trailers & Videos")
        case .comments: return String(localized: "Comments")
        case .about: return String(localized: "Details")
        }
    }

    /// Short label for the tabs bar.
    var tabLabel: String {
        switch self {
        case .suggested: return String(localized: "Suggested")
        case .trailers: return String(localized: "Videos")
        default: return title
        }
    }

    var subtitle: String {
        switch self {
        case .episodes: return String(localized: "Seasons and episodes (TV shows)")
        case .suggested: return String(localized: "Related and similar titles")
        case .collection: return String(localized: "Other movies in the franchise")
        case .cast: return String(localized: "Cast, crew and guest stars")
        case .trailers: return String(localized: "Trailers, teasers and featurettes")
        case .comments: return String(localized: "Trakt comments and reviews")
        case .about: return String(localized: "About, production, information and links")
        }
    }

    var icon: String {
        switch self {
        case .episodes: return "list.and.film"
        case .suggested: return "rectangle.stack.fill"
        case .collection: return "square.stack.3d.up.fill"
        case .cast: return "person.2.fill"
        case .trailers: return "play.rectangle.fill"
        case .comments: return "text.bubble.fill"
        case .about: return "info.circle.fill"
        }
    }

    /// Default order when nothing is saved (or after a reset).
    static let defaultOrder: [DetailsSectionKey] = [
        .episodes, .suggested, .collection, .cast, .trailers, .comments, .about
    ]
}

/// Saved order/visibility of one section.
struct DetailsSectionPreference: Codable, Hashable, Identifiable {
    let key: DetailsSectionKey
    var enabled: Bool

    var id: String { key.rawValue }

    static var defaults: [DetailsSectionPreference] {
        DetailsSectionKey.defaultOrder.map { DetailsSectionPreference(key: $0, enabled: true) }
    }

    /// Drops unknown/duplicate entries and appends sections added in later
    /// versions (enabled, at the end) so the saved list always covers every key.
    static func normalized(_ prefs: [DetailsSectionPreference]) -> [DetailsSectionPreference] {
        var seen = Set<DetailsSectionKey>()
        var result = prefs.filter { seen.insert($0.key).inserted }
        for key in DetailsSectionKey.defaultOrder where !seen.contains(key) {
            result.append(DetailsSectionPreference(key: key, enabled: true))
        }
        return result
    }
}

/// How seasons are picked on TV show details.
enum DetailsSeasonPickerStyle: String, CaseIterable, Identifiable {
    case chips
    case posters

    var id: String { rawValue }
}

extension UserDefaults {
    private enum DetailsSectionsKeys {
        static let sections = "detailsSectionOrder"
        static let spoilerProtection = "detailsHideEpisodeSpoilers"
        static let seasonPickerStyle = "detailsSeasonPickerStyle"
        static let showEpisodeRatings = "detailsShowEpisodeRatings"
    }

    /// Section order and visibility for the current profile.
    var detailsSectionPreferences: [DetailsSectionPreference] {
        get {
            guard let data = data(forKey: profileKey(DetailsSectionsKeys.sections)) else {
                return DetailsSectionPreference.defaults
            }
            // Decode leniently: entries with keys this build doesn't know are skipped.
            struct Raw: Decodable { let key: String; let enabled: Bool? }
            guard let raw = try? JSONDecoder().decode([Raw].self, from: data) else {
                return DetailsSectionPreference.defaults
            }
            let prefs = raw.compactMap { entry -> DetailsSectionPreference? in
                guard let key = DetailsSectionKey(rawValue: entry.key) else { return nil }
                return DetailsSectionPreference(key: key, enabled: entry.enabled ?? true)
            }
            return DetailsSectionPreference.normalized(prefs)
        }
        set {
            guard let data = try? JSONEncoder().encode(DetailsSectionPreference.normalized(newValue)) else { return }
            set(data, forKey: profileKey(DetailsSectionsKeys.sections))
        }
    }

    /// Blur thumbnails and hide descriptions of unwatched episodes. Default off.
    var detailsHideEpisodeSpoilers: Bool {
        get { object(forKey: profileKey(DetailsSectionsKeys.spoilerProtection)) as? Bool ?? false }
        set { set(newValue, forKey: profileKey(DetailsSectionsKeys.spoilerProtection)) }
    }

    /// Season picker style. Default chips.
    var detailsSeasonPickerStyle: DetailsSeasonPickerStyle {
        get {
            string(forKey: profileKey(DetailsSectionsKeys.seasonPickerStyle))
                .flatMap(DetailsSeasonPickerStyle.init(rawValue:)) ?? .chips
        }
        set { set(newValue.rawValue, forKey: profileKey(DetailsSectionsKeys.seasonPickerStyle)) }
    }

    /// Show a TMDB rating chip on each episode. Default on.
    var detailsShowEpisodeRatings: Bool {
        get { object(forKey: profileKey(DetailsSectionsKeys.showEpisodeRatings)) as? Bool ?? true }
        set { set(newValue, forKey: profileKey(DetailsSectionsKeys.showEpisodeRatings)) }
    }

    /// Removes the saved section settings for the current profile.
    func resetDetailsSectionSettings() {
        removeObject(forKey: profileKey(DetailsSectionsKeys.sections))
        removeObject(forKey: profileKey(DetailsSectionsKeys.spoilerProtection))
        removeObject(forKey: profileKey(DetailsSectionsKeys.seasonPickerStyle))
        removeObject(forKey: profileKey(DetailsSectionsKeys.showEpisodeRatings))
    }
}
