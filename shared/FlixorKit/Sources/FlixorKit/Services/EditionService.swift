//
//  EditionService.swift
//  FlixorKit
//
//  Edition title extraction (top-level or Media[0])
//

import Foundation

public enum EditionService {

    /// Prefer top-level editionTitle, then first media's editionTitle.
    public static func extractEditionTitle(
        topLevelEdition: String?,
        firstMediaEdition: String?
    ) -> String? {
        if let edition = topLevelEdition, !edition.isEmpty {
            return edition
        }
        if let edition = firstMediaEdition, !edition.isEmpty {
            return edition
        }
        return nil
    }

    public static func extractEditionTitle(
        topLevelEdition: String?,
        media: [PlexMedia]?
    ) -> String? {
        return extractEditionTitle(
            topLevelEdition: topLevelEdition,
            firstMediaEdition: media?.first?.editionTitle
        )
    }
}
