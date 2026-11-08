//
//  DetailsLayoutMetrics.swift
//  FlixorMac
//
//  Width-driven layout metrics shared by the details screen
//

import SwiftUI
import FlixorKit

struct DetailsLayoutMetrics {
    let width: CGFloat

    // Hero height based on 16:9 aspect ratio
    var heroHeight: CGFloat {
        width * 9 / 16
    }

    var heroHorizontalPadding: CGFloat {
        switch width {
        case ..<900: return 32
        case ..<1200: return 44
        case ..<1600: return 60
        default: return 72
        }
    }

    // Dynamic top padding - approximately 45% of hero height to push content to lower portion
    var heroTopPadding: CGFloat {
        heroHeight * 0.45
    }

    var heroBottomPadding: CGFloat {
        switch width {
        case ..<900: return 56
        case ..<1400: return 72
        default: return 88
        }
    }

    var heroTextMaxWidth: CGFloat {
        min(width * 0.52, 640)
    }

    var contentPadding: CGFloat { DetailsSectionStyle.inset }

    var tabsPadding: CGFloat {
        switch width {
        case ..<900: return 20
        case ..<1200: return 20
        default: return 20
        }
    }

    var contentMaxWidth: CGFloat {
        min(width - contentPadding * 2, 1320)
    }

    var infoGridColumns: Int {
        if width >= 1320 { return 3 }
        if width >= 960 { return 2 }
        return 1
    }

    var technicalGridMinimum: CGFloat {
        if width >= 1500 { return 240 }
        if width >= 1200 { return 220 }
        if width >= 960 { return 200 }
        return 180
    }

    var castGridMinimum: CGFloat {
        if width >= 1500 { return 180 }
        if width >= 1200 { return 170 }
        if width >= 960 { return 160 }
        return 150
    }

    var extraCardMinimum: CGFloat {
        if width >= 1400 { return 300 }
        if width >= 1100 { return 260 }
        if width >= 900 { return 220 }
        return 200
    }

    var episodeThumbnailWidth: CGFloat {
        if width >= 1500 { return 260 }
        if width >= 1250 { return 240 }
        if width >= 1000 { return 220 }
        if width >= 820 { return 200 }
        return 180
    }
}
