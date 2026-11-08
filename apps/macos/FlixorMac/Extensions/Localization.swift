//
//  Localization.swift
//  FlixorMac
//
//  Helpers for showing text from Localizable.xcstrings.
//

import SwiftUI

extension LocalizedStringKey {
    /// Shows `text` exactly as given, for components whose label is a `LocalizedStringKey`.
    /// Use for dynamic content (server titles, addon names, error text from a
    /// service, already-localized strings); the catalog is never consulted, and
    /// `text` is not parsed as Markdown.
    static func verbatim(_ text: String) -> LocalizedStringKey {
        "\(text)"
    }
}

extension RawRepresentable where RawValue == String {
    /// The raw value looked up in the catalog, for enums whose raw values double
    /// as English labels (the raw value stays the persisted/compared identity).
    var localizedRawValue: String {
        String(localized: String.LocalizationValue(rawValue))
    }
}
