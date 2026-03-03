import SwiftUI

enum TVScreenID: String, CaseIterable {
    case home
    case details
    case library
    case myList
    case search
    case player
}

struct TVScrollAlignmentPolicy: Equatable {
    enum HorizontalRowAnchor: Equatable {
        case centeredFirst
        case leadingItems
    }

    enum VerticalSnapAnchor: Equatable {
        case top
        case center
    }

    let horizontalRowAnchor: HorizontalRowAnchor
    let verticalSnapAnchor: VerticalSnapAnchor
    let preferredViewportAnchor: UnitPoint

    static let home = TVScrollAlignmentPolicy(
        horizontalRowAnchor: .leadingItems,
        verticalSnapAnchor: .top,
        preferredViewportAnchor: .top
    )

    func horizontalAnchor(isFirstItem: Bool) -> UnitPoint {
        switch horizontalRowAnchor {
        case .centeredFirst:
            return isFirstItem ? .center : .leading
        case .leadingItems:
            return isFirstItem ? .center : .leading
        }
    }

    var verticalAnchor: UnitPoint {
        switch verticalSnapAnchor {
        case .top:
            return .top
        case .center:
            return .center
        }
    }
}
