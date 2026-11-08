//
//  DetailsSectionHeading.swift
//  FlixorMac
//
//  One heading style and one left edge for every section of the details page.
//

import SwiftUI

enum DetailsSectionStyle {
    /// Left edge of every heading and row.
    static let inset: CGFloat = DS.Space.s20
    static let headingGap: CGFloat = DS.Space.s16
    static var headingFont: Font { .flixor(.title2, weight: .bold) }
}

struct DetailsSectionHeading: View {
    let title: LocalizedStringKey

    @Environment(\.flixorTheme) private var theme

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(DetailsSectionStyle.headingFont)
            .foregroundStyle(theme.textPrimary)
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Horizontal row that starts on the section's left edge and scrolls out to the
/// window's edges. Use it inside the page's horizontal content padding.
struct DetailsHorizontalRow<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            content()
                .padding(.horizontal, DetailsSectionStyle.inset)
        }
        .padding(.horizontal, -DetailsSectionStyle.inset)
    }
}
