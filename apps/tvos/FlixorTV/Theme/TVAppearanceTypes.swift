import SwiftUI

enum TVAccentTheme: String, CaseIterable, Identifiable {
    case white
    case crimson
    case ocean
    case violet
    case emerald
    case amber
    case rose

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .white: return "White"
        case .crimson: return "Crimson"
        case .ocean: return "Ocean"
        case .violet: return "Violet"
        case .emerald: return "Emerald"
        case .amber: return "Amber"
        case .rose: return "Rose"
        }
    }
}

enum TVAppFont: String, CaseIterable, Identifiable {
    case system
    case inter
    case dmSans = "dm_sans"
    case openSans = "open_sans"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .inter: return "Inter"
        case .dmSans: return "DM Sans"
        case .openSans: return "Open Sans"
        }
    }
}

enum TVHomeLayoutMode: String, CaseIterable, Identifiable {
    case modern
    case classic
    case grid

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .modern: return "Modern"
        case .classic: return "Classic"
        case .grid: return "Grid"
        }
    }
}

enum TVHeroPresentationMode: String, CaseIterable, Identifiable {
    case carousel
    case billboard

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .carousel: return "Carousel"
        case .billboard: return "Billboard"
        }
    }
}

enum TVRailCardShape: String, CaseIterable, Identifiable {
    case poster
    case landscape

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .poster: return "Poster"
        case .landscape: return "Landscape"
        }
    }
}

enum TVFocusedPosterTrailerTarget: String, CaseIterable, Identifiable {
    case heroMedia
    case expandedCard

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .heroMedia: return "Hero Media"
        case .expandedCard: return "Expanded Card"
        }
    }
}

enum TVPosterWidthPreset: String, CaseIterable, Identifiable {
    case compact
    case dense
    case standard
    case balanced
    case comfort
    case large

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .compact: return "Compact"
        case .dense: return "Dense"
        case .standard: return "Standard"
        case .balanced: return "Balanced"
        case .comfort: return "Comfort"
        case .large: return "Large"
        }
    }

    var widthMultiplier: CGFloat {
        switch self {
        case .compact: return 0.825
        case .dense: return 0.889
        case .standard: return 0.952
        case .balanced: return 1.0
        case .comfort: return 1.063
        case .large: return 1.111
        }
    }

    var libraryGridColumnCount: Int {
        switch self {
        case .compact, .dense:
            return 6
        case .large:
            return 4
        default:
            return 5
        }
    }
}

enum TVPosterCornerPreset: String, CaseIterable, Identifiable {
    case sharp
    case subtle
    case classic
    case rounded
    case pill

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sharp: return "Sharp"
        case .subtle: return "Subtle"
        case .classic: return "Classic"
        case .rounded: return "Rounded"
        case .pill: return "Pill"
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .sharp: return 0
        case .subtle: return 8
        case .classic: return 12
        case .rounded: return 16
        case .pill: return 20
        }
    }
}

struct TVCardVisualTokens: Equatable {
    let posterRadius: CGFloat
    let landscapeRadius: CGFloat
    let focusedStrokeWidth: CGFloat
    let focusedScale: CGFloat
    let neighborScale: CGFloat
    let neighborDimOpacity: Double
    let focusedShadowRadius: CGFloat
    let focusedShadowYOffset: CGFloat
    let unfocusedShadowRadius: CGFloat
    let unfocusedShadowYOffset: CGFloat

    init(posterCornerPreset: TVPosterCornerPreset) {
        posterRadius = posterCornerPreset.cornerRadius
        landscapeRadius = UX.landscapeRadius
        focusedStrokeWidth = 3
        focusedScale = UX.focusScale
        neighborScale = UX.neighborScale
        neighborDimOpacity = UX.dimNeighborOpacity
        focusedShadowRadius = 18
        focusedShadowYOffset = 8
        unfocusedShadowRadius = 8
        unfocusedShadowYOffset = 4
    }
}
