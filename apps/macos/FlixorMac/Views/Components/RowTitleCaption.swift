//
//  RowTitleCaption.swift
//  FlixorMac
//
//  Secondary caption shown next to a row title, e.g. the addon name when two
//  Stremio catalogs would otherwise share the same title. Passed through the
//  environment so row views keep their initialisers unchanged:
//
//      PosterSectionRow(section: section, ...)
//          .environment(\.rowTitleCaption, "AIOMetadata")
//
//  Row headers read it and draw `RowTitleCaptionText` after the title.
//

import SwiftUI

private struct RowTitleCaptionKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

private struct RowTitleFontKey: EnvironmentKey {
    static let defaultValue: Font? = nil
}

extension EnvironmentValues {
    /// Overrides a carousel row's title font. nil = the standard row title.
    var rowTitleFont: Font? {
        get { self[RowTitleFontKey.self] }
        set { self[RowTitleFontKey.self] = newValue }
    }

    /// Subtle caption drawn next to a home row title. nil = no caption.
    var rowTitleCaption: String? {
        get { self[RowTitleCaptionKey.self] }
        set { self[RowTitleCaptionKey.self] = newValue }
    }
}

/// The caption as drawn next to a row title: small, tertiary, never part of the title.
struct RowTitleCaptionText: View {
    let caption: String
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        Text(caption)
            .flixorFont(.footnote, weight: .medium)
            .foregroundStyle(theme.textTertiary)
            .lineLimit(1)
            .accessibilityLabel(Text("from \(caption)"))
    }
}
