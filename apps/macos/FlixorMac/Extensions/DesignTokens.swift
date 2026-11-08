//
//  DesignTokens.swift
//  FlixorMac
//
//  Design-system foundation: spacing, radii, borders, opacity, motion,
//  shadows, icon sizes and the semantic type scale.
//
//  Colours that depend on the user's appearance settings (accent, pure black)
//  live in FlixorTheme.swift and are read with `@Environment(\.flixorTheme)`.
//  Window-size-aware layout helpers live in WindowMetrics.swift.
//
//  ---------------------------------------------------------------------------
//  MIGRATION TABLE (the token-migration wave follows this mechanically)
//  ---------------------------------------------------------------------------
//
//  Typography. Every token defaults to .regular weight, so a call keeps its
//  weight argument and only the size changes to a token:
//
//      .font(.system(size: 13, weight: .medium))
//          ->  .font(.flixor(.callout, weight: .medium))
//      .font(.system(size: 12, weight: .bold, design: .monospaced))
//          ->  .font(.flixor(.footnote, weight: .bold, design: .monospaced))
//
//  `.font(.flixor(...))` is pixel-identical to the old call when the size maps
//  exactly (marked "=" below). Rows marked "~" round to the nearest token.
//
//      old size (uses)        token               size
//      ---------------------  ------------------  ----
//      7 (1), 8 (3)        ~  .nano                  9
//      9 (12)              =  .nano                  9
//      10 (38)             =  .micro                10
//      11 (113)            =  .caption              11
//      12 (90)             =  .footnote             12
//      13 (96)             =  .callout              13
//      14 (79)             =  .body                 14
//      15 (30)             =  .bodyLarge            15
//      16 (44)             =  .headline             16
//      17 (3)              ~  .headline             16
//      18 (31)             =  .title3               18
//      20 (19)             =  .title2               20
//      22 (4)              ~  .title2               20   (Settings page header)
//      24 (18)             =  .title1               24
//      26 (1)              ~  .title1               24
//      28 (9)              =  .largeTitle           28
//      32 (8)              =  .display              32
//      34 (1), 36 (5)      ~  .display              32   (text only, see icons)
//      40-52 (23)          ~  .displayLarge         48   (text only, see icons)
//      60, 72, 80 (5)      ~  .hero                 64   (text only, see icons)
//
//  SF Symbol icons: when the `.font(.system(size:))` is on an
//  `Image(systemName:)`, map by size to an icon token instead and keep the
//  exact size where it matters visually:
//
//      <=12 -> DS.Icon.xs (12)     14 -> .sm (14)     16 -> .md (16)
//      18-20 -> .lg (20)           24 -> .xl (24)     28-32 -> .xxl (32)
//      36-52 -> .huge (48)         60+ -> .jumbo (64)
//      usage: .font(.flixorIcon(DS.Icon.lg, weight: .semibold))
//
//  Existing SwiftUI text styles (.headline, .caption, .title2...) are system
//  dynamic styles; leave them as they are unless a screen is being redesigned.
//
//  Spacing / padding (numeric scale, use the semantic alias when it fits):
//      2 -> DS.Space.s2    4 -> .s4    6 -> .s6    8 -> .s8    10 -> .s10
//      12 -> .s12          14 -> .s14  16 -> .s16  18 -> .s18  20 -> .s20
//      24 -> .s24          28 -> .s28  32 -> .s32  40 -> .s40  48 -> .s48
//      60 -> .s60          64 -> .s64  80 -> .s80
//      3 and 5 -> keep literal (optical nudges, not part of the scale)
//
//  Corner radius:
//      2 -> DS.Radius.r2   4 -> .r4 (.badge)    6 -> .r6 (.control)
//      8 -> .r8 (.button, .thumbnail)           10 -> .r10 (.compactCard, .group)
//      12 -> .r12 (.poster)                     14 -> .r14 (.card)
//      16 -> .r16 (.sheet)  18 -> .r18          20 -> .r20 (.dialog)
//      22 -> .r22           24 -> .r24          capsule -> .chip (Capsule())
//
//  Animations:
//      .easeOut(duration: 0.15) / .easeInOut(duration: 0.15) -> DS.Motion.quick
//      .easeInOut(duration: 0.2) / .easeOut(duration: 0.2)   -> DS.Motion.standard
//      .easeOut(duration: 0.24) / .easeInOut(duration: 0.3)  -> DS.Motion.emphasized
//      .easeInOut(duration: 0.5)                             -> DS.Motion.slow
//      .easeInOut(duration: 0.8)                             -> DS.Motion.cinematic
//      .spring(response: 0.3, dampingFraction: 0.7)          -> DS.Motion.spring
//      .spring(response: 0.6, dampingFraction: 0.8)          -> DS.Motion.gentleSpring
//
//  Shadows (.shadow(color: .black.opacity(x), radius: r, y: y)):
//      opacity 0.15-0.3, radius <= 6   -> .flixorShadow(.raised)
//      opacity 0.3-0.5,  radius 8-12   -> .flixorShadow(.card)
//      opacity 0.5-0.6,  radius 16-24  -> .flixorShadow(.floating)
//      opacity 0.6-0.7,  radius >= 24  -> .flixorShadow(.modal)
//
//  Everything here is available on macOS 13.
//  ---------------------------------------------------------------------------

import SwiftUI

/// Design-system namespace. Static constants only, no state.
enum DS {

    // MARK: - Spacing

    enum Space {
        static let none: CGFloat = 0
        static let s2: CGFloat = 2
        static let s4: CGFloat = 4
        static let s6: CGFloat = 6
        static let s8: CGFloat = 8
        static let s10: CGFloat = 10
        static let s12: CGFloat = 12
        static let s14: CGFloat = 14
        static let s16: CGFloat = 16
        static let s18: CGFloat = 18
        static let s20: CGFloat = 20
        static let s24: CGFloat = 24
        static let s28: CGFloat = 28
        static let s32: CGFloat = 32
        static let s40: CGFloat = 40
        static let s48: CGFloat = 48
        static let s60: CGFloat = 60
        static let s64: CGFloat = 64
        static let s80: CGFloat = 80

        // Semantic aliases
        /// Gap between an icon and its label, or between small controls.
        static let controlGap: CGFloat = s8
        /// Gap between items in a row or list (posters, cards, settings rows).
        static let itemGap: CGFloat = s12
        /// Inner padding of a card or grouped settings box.
        static let cardPadding: CGFloat = s16
        /// Gap between two sections / rows on a page.
        static let sectionGap: CGFloat = s32
        /// Default horizontal page inset. Prefer `WindowMetrics.pageGutter`,
        /// which grows on wide windows.
        static let pageGutter: CGFloat = s40
        /// Padding inside sheets and dialogs.
        static let sheetPadding: CGFloat = s24
    }

    // MARK: - Corner radius

    enum Radius {
        static let none: CGFloat = 0
        static let r2: CGFloat = 2
        static let r4: CGFloat = 4
        static let r6: CGFloat = 6
        static let r8: CGFloat = 8
        static let r10: CGFloat = 10
        static let r12: CGFloat = 12
        static let r14: CGFloat = 14
        static let r16: CGFloat = 16
        static let r18: CGFloat = 18
        static let r20: CGFloat = 20
        static let r22: CGFloat = 22
        static let r24: CGFloat = 24
        /// Large enough to render as a capsule for any control height.
        static let full: CGFloat = 999

        // Semantic aliases
        /// Rating pills, quality badges, small tags.
        static let badge: CGFloat = r4
        /// Text fields, small segmented controls.
        static let control: CGFloat = r6
        /// Rectangular buttons.
        static let button: CGFloat = r8
        /// Episode thumbnails, small artwork.
        static let thumbnail: CGFloat = r8
        /// Grouped settings boxes, compact cards.
        static let compactCard: CGFloat = r10
        static let group: CGFloat = r10
        /// Portrait posters (PosterCard).
        static let poster: CGFloat = r12
        /// Landscape cards (LandscapeCard, Continue Watching).
        static let card: CGFloat = r14
        /// Sheets and large panels.
        static let sheet: CGFloat = r16
        /// Dialogs and modal overlays.
        static let dialog: CGFloat = r20
        /// Chips are capsules; use `Capsule()` or this radius.
        static let chip: CGFloat = full
    }

    // MARK: - Borders

    enum Border {
        static let hairline: CGFloat = 0.5
        static let thin: CGFloat = 1
        static let medium: CGFloat = 2
        /// Focus / selection ring.
        static let focus: CGFloat = 2
    }

    // MARK: - Opacity

    /// Opacity levels for white-on-dark content and overlays.
    enum Opacity {
        static let invisible: Double = 0
        /// Barely-there fills (card backgrounds on dark).
        static let subtle: Double = 0.06
        static let hover: Double = 0.08
        static let pressed: Double = 0.12
        static let selected: Double = 0.15
        static let disabled: Double = 0.38
        static let tertiary: Double = 0.5
        static let muted: Double = 0.6
        /// Inactive navigation text, secondary labels.
        static let secondary: Double = 0.7
        static let strong: Double = 0.85
        static let visible: Double = 1

        // Scrims (black overlays on artwork)
        static let scrimLight: Double = 0.35
        static let scrimMedium: Double = 0.55
        static let scrimHeavy: Double = 0.8
    }

    // MARK: - Motion

    enum Motion {
        // Durations (seconds)
        static let instantDuration: Double = 0
        static let quickDuration: Double = 0.15
        static let standardDuration: Double = 0.2
        static let emphasizedDuration: Double = 0.3
        static let slowDuration: Double = 0.5
        static let cinematicDuration: Double = 0.8

        /// Hover states, small toggles.
        static let quick: Animation = .easeOut(duration: quickDuration)
        /// Default UI transition.
        static let standard: Animation = .easeInOut(duration: standardDuration)
        /// Screen / state changes that should feel deliberate.
        static let emphasized: Animation = .easeInOut(duration: emphasizedDuration)
        /// Large content swaps (hero crossfades).
        static let slow: Animation = .easeInOut(duration: slowDuration)
        /// Backdrop colour washes and other ambient changes.
        static let cinematic: Animation = .easeInOut(duration: cinematicDuration)
        /// Material-style "standard" curve: fast start, soft landing.
        static let decelerate: Animation = .timingCurve(0.2, 0, 0, 1, duration: emphasizedDuration)
        /// Snappy spring for presses and selection.
        static let spring: Animation = .spring(response: 0.3, dampingFraction: 0.7)
        /// Softer spring for panels and cards moving into place.
        static let gentleSpring: Animation = .spring(response: 0.6, dampingFraction: 0.8)
    }

    // MARK: - Icon sizes (SF Symbols point sizes)

    enum Icon {
        static let xs: CGFloat = 12
        static let sm: CGFloat = 14
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        /// Empty-state and onboarding illustrations.
        static let huge: CGFloat = 48
        static let jumbo: CGFloat = 64
    }

    // MARK: - Elevation / shadows

    struct Shadow: Equatable {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat

        static let none = Shadow(color: .clear, radius: 0, x: 0, y: 0)
        /// Small lift: badges, buttons over artwork.
        static let raised = Shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        /// Posters and cards at rest.
        static let card = Shadow(color: .black.opacity(0.4), radius: 10, x: 0, y: 5)
        /// Hovered cards, popovers, floating controls.
        static let floating = Shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
        /// Sheets, dialogs, player panels.
        static let modal = Shadow(color: .black.opacity(0.6), radius: 30, x: 0, y: 14)

        /// Soft coloured glow, e.g. around a focused accent control.
        static func glow(_ color: Color, radius: CGFloat = 12) -> Shadow {
            Shadow(color: color.opacity(0.45), radius: radius, x: 0, y: 0)
        }
    }

    // MARK: - Layout constants

    enum Layout {
        /// Poster aspect ratio (height / width), 2:3.
        static let posterAspect: CGFloat = 1.5
        /// Landscape artwork aspect ratio (height / width), 16:9.
        static let landscapeAspect: CGFloat = 9.0 / 16.0
        /// Reference window size the fixed sizes in the app were designed at.
        static let referenceWindow = CGSize(width: 1440, height: 900)
        /// Minimum main-window size (FlixorMacApp).
        static let minimumWindow = CGSize(width: 1024, height: 768)
    }
}

// MARK: - Typography

/// Semantic type scale. Sizes match the point sizes the app already uses most,
/// so `.system(size:)` calls migrate 1:1 (see the table at the top of the file).
enum FlixorType: String, CaseIterable, Identifiable {
    case nano
    case micro
    case caption
    case footnote
    case callout
    case body
    case bodyLarge
    case headline
    case title3
    case title2
    case title1
    case largeTitle
    case display
    case displayLarge
    case hero

    var id: String { rawValue }

    /// Point size.
    var size: CGFloat {
        switch self {
        case .nano: return 9
        case .micro: return 10
        case .caption: return 11
        case .footnote: return 12
        case .callout: return 13
        case .body: return 14
        case .bodyLarge: return 15
        case .headline: return 16
        case .title3: return 18
        case .title2: return 20
        case .title1: return 24
        case .largeTitle: return 28
        case .display: return 32
        case .displayLarge: return 48
        case .hero: return 64
        }
    }

    /// Weight used by `.flixorFont(_:)` when none is given. `Font.flixor(_:)`
    /// always defaults to `.regular` so mechanical migration is exact.
    var designedWeight: Font.Weight {
        switch self {
        case .nano, .micro: return .semibold
        case .caption, .footnote, .callout, .body, .bodyLarge: return .regular
        case .headline, .title3, .title2: return .semibold
        case .title1, .largeTitle, .display, .displayLarge, .hero: return .bold
        }
    }

    /// Letter spacing applied by `.flixorFont(_:)`. Tight for display sizes,
    /// slightly open for the tiny label sizes.
    var tracking: CGFloat {
        switch self {
        case .nano, .micro: return 0.3
        case .caption, .footnote, .callout, .body, .bodyLarge, .headline, .title3, .title2: return 0
        case .title1: return -0.2
        case .largeTitle: return -0.4
        case .display: return -0.6
        case .displayLarge: return -1.0
        case .hero: return -1.4
        }
    }

    /// Extra space between lines for multi-line copy (`.flixorParagraph`).
    var paragraphLineSpacing: CGFloat {
        switch self {
        case .nano, .micro, .caption: return 2
        case .footnote, .callout, .body, .bodyLarge: return 4
        case .headline, .title3, .title2: return 3
        case .title1, .largeTitle, .display, .displayLarge, .hero: return 2
        }
    }
}

extension Font {
    /// Font for a type token. Defaults to regular weight so that
    /// `.system(size: 13, weight: .medium)` becomes `.flixor(.callout, weight: .medium)`.
    static func flixor(_ style: FlixorType, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: style.size, weight: weight, design: design)
    }

    /// Font for an SF Symbol at an icon token size (`DS.Icon.*`).
    static func flixorIcon(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

extension View {
    /// Applies a type token with its designed weight and tracking. Use for new
    /// UI; use `.font(.flixor(...))` when migrating an existing call 1:1.
    func flixorFont(_ style: FlixorType, weight: Font.Weight? = nil, design: Font.Design = .default) -> some View {
        self
            .font(.flixor(style, weight: weight ?? style.designedWeight, design: design))
            .tracking(style.tracking)
    }

    /// Type token plus comfortable line spacing, for overviews and other
    /// multi-line copy.
    func flixorParagraph(_ style: FlixorType = .body, weight: Font.Weight = .regular) -> some View {
        self
            .font(.flixor(style, weight: weight))
            .lineSpacing(style.paragraphLineSpacing)
    }

    /// Applies a shadow preset.
    func flixorShadow(_ shadow: DS.Shadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}
