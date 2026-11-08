//
//  UserDefaults+Cards.swift
//  FlixorMac
//
//  Profile-scoped settings for poster and landscape cards: corner style, titles,
//  rating badges and the hover preview. Poster size reuses the existing
//  `posterSize` home setting ("small" / "medium" / "large", plus "xlarge").
//
//  Keys (all go through `profileKey`, so each profile has its own values):
//    cardCornerStyle          "sharp" | "rounded" (default) | "extraRounded"
//    cardTitleMode            "always" | "hover" (default) | "never"
//    cardShowRatingBadges     Bool, default false
//    cardHoverPreviewEnabled  Bool, default true
//    cardHoverPreviewDelay    Double seconds, default 0.8 (0.3 ... 2.0)
//    cardHoverTrailerMode     "off" | "muted" (default) | "sound"
//

import Foundation

// MARK: - Option types

enum CardPosterSize: String, CaseIterable, Identifiable {
    case small
    case medium
    case large
    case xlarge

    var id: String { rawValue }

    /// Design-time width before window scaling (`WindowMetrics.posterWidth(base:)`).
    var baseWidth: CGFloat {
        switch self {
        case .small: return 130
        case .medium: return 160
        case .large: return 190
        case .xlarge: return 220
        }
    }

    var displayName: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .xlarge: return "Extra Large"
        }
    }

    /// Unknown stored values fall back to medium.
    init(stored: String) {
        self = CardPosterSize(rawValue: stored) ?? .medium
    }
}

enum CardCornerStyle: String, CaseIterable, Identifiable {
    case sharp
    case rounded
    case extraRounded

    static let `default`: CardCornerStyle = .rounded

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sharp: return "Sharp"
        case .rounded: return "Rounded"
        case .extraRounded: return "Extra Rounded"
        }
    }

    /// Corner radius for 2:3 poster cards.
    var posterRadius: CGFloat {
        switch self {
        case .sharp: return DS.Radius.r2
        case .rounded: return DS.Radius.poster
        case .extraRounded: return DS.Radius.r22
        }
    }

    /// Corner radius for landscape (backdrop) cards.
    var landscapeRadius: CGFloat {
        switch self {
        case .sharp: return DS.Radius.r2
        case .rounded: return DS.Radius.card
        case .extraRounded: return DS.Radius.r24
        }
    }
}

enum CardTitleMode: String, CaseIterable, Identifiable {
    /// Title (and year) always shown under posters.
    case always
    /// Each surface keeps its existing behaviour: Home poster rows reveal the
    /// title over the artwork on hover, grids keep their caption.
    case hover
    /// No visible titles (VoiceOver still reads them).
    case never

    static let `default`: CardTitleMode = .hover

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .always: return "Always"
        case .hover: return "On Hover"
        case .never: return "Never"
        }
    }
}

enum HoverTrailerMode: String, CaseIterable, Identifiable {
    case off
    case muted
    case sound

    static let `default`: HoverTrailerMode = .muted

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .muted: return "Muted"
        case .sound: return "With Sound"
        }
    }
}

// MARK: - Storage

extension UserDefaults {
    private enum CardKeys {
        static let cornerStyle = "cardCornerStyle"
        static let titleMode = "cardTitleMode"
        static let showRatingBadges = "cardShowRatingBadges"
        static let hoverPreviewEnabled = "cardHoverPreviewEnabled"
        static let hoverPreviewDelay = "cardHoverPreviewDelay"
        static let hoverTrailerMode = "cardHoverTrailerMode"
    }

    static let cardHoverPreviewDelayRange: ClosedRange<Double> = 0.3...2.0
    static let cardHoverPreviewDefaultDelay: Double = 0.8

    var cardCornerStyle: CardCornerStyle {
        get { string(forKey: profileKey(CardKeys.cornerStyle)).flatMap(CardCornerStyle.init(rawValue:)) ?? .default }
        set { set(newValue.rawValue, forKey: profileKey(CardKeys.cornerStyle)) }
    }

    var cardTitleMode: CardTitleMode {
        get { string(forKey: profileKey(CardKeys.titleMode)).flatMap(CardTitleMode.init(rawValue:)) ?? .default }
        set { set(newValue.rawValue, forKey: profileKey(CardKeys.titleMode)) }
    }

    var cardShowRatingBadges: Bool {
        get { object(forKey: profileKey(CardKeys.showRatingBadges)) as? Bool ?? false }
        set { set(newValue, forKey: profileKey(CardKeys.showRatingBadges)) }
    }

    var cardHoverPreviewEnabled: Bool {
        get { object(forKey: profileKey(CardKeys.hoverPreviewEnabled)) as? Bool ?? true }
        set { set(newValue, forKey: profileKey(CardKeys.hoverPreviewEnabled)) }
    }

    var cardHoverPreviewDelay: Double {
        get {
            let range = Self.cardHoverPreviewDelayRange
            guard let value = object(forKey: profileKey(CardKeys.hoverPreviewDelay)) as? Double else {
                return Self.cardHoverPreviewDefaultDelay
            }
            return min(max(value, range.lowerBound), range.upperBound)
        }
        set { set(newValue, forKey: profileKey(CardKeys.hoverPreviewDelay)) }
    }

    var cardHoverTrailerMode: HoverTrailerMode {
        get { string(forKey: profileKey(CardKeys.hoverTrailerMode)).flatMap(HoverTrailerMode.init(rawValue:)) ?? .default }
        set { set(newValue.rawValue, forKey: profileKey(CardKeys.hoverTrailerMode)) }
    }
}
