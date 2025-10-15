import SwiftUI

enum UX {
    // Spacing
    static let gridH: CGFloat = 40
    static let railV: CGFloat = 40
    static let headerSpacing: CGFloat = 12
    static let itemSpacing: CGFloat = 18
    static let navHeight: CGFloat = 92
    static let navGradientHeight: CGFloat = 120
    static let rowFocusExtra: CGFloat = 36
    static let leftPeek: CGFloat = 40
    static let rowSnapInset: CGFloat = 8
    static let rowSnapTopPadding: CGFloat = 40 // snap padding
    static let tabHeight: CGFloat = 92

    // Radii
    static let posterRadius: CGFloat = 16
    static let landscapeRadius: CGFloat = 18
    static let billboardRadius: CGFloat = 18

    // Motion
    static let focusScale: CGFloat = 1.06
    static let focusDur: Double = 0.18
    static let neighborScale: CGFloat = 0.96
    static let dimNeighborOpacity: Double = 0.7

    // Colors
    static let surface = Color.black
    static let cardStroke = Color.white.opacity(0.12)
    static let cardFill = Color.white.opacity(0.06)
    static let pillFill = Color.white
    static let pillFillAlt = Color.white.opacity(0.18)

    // Billboard layout
    static let billboardSide: CGFloat = 8
    static let billboardTopPadding: CGFloat = 60

    // Sizes
    static let posterWidth: CGFloat = 320
    static let posterHeight: CGFloat = 480
    static let landscapeWidth: CGFloat = 560
    static let landscapeHeight: CGFloat = 315
}
