//
//  HomeScreenData.swift
//  FlixorMac
//
//  Models for home screen data
//

import Foundation
import FlixorKit

struct HomeScreenData {
    let billboard: [MediaItem]
    let continueWatching: [MediaItem]
    let onDeck: [MediaItem]
    let recentlyAdded: [MediaItem]
    let librarySections: [LibrarySection]
}

struct LibrarySection: Identifiable {
    let id: String
    let title: String
    let items: [MediaItem]
    let totalCount: Int
    let libraryKey: String?
    let browseContext: BrowseContext?
    let isCollection: Bool

    init(
        id: String,
        title: String,
        items: [MediaItem],
        totalCount: Int,
        libraryKey: String?,
        browseContext: BrowseContext? = nil,
        isCollection: Bool = false
    ) {
        self.id = id
        self.title = title
        self.items = items
        self.totalCount = totalCount
        self.libraryKey = libraryKey
        self.browseContext = browseContext
        self.isCollection = isCollection
    }
}

// Extended MediaItem with additional properties
extension MediaItem {
    var episodeLabel: String? {
        guard let grandparentTitle = grandparentTitle else { return nil }

        var label = grandparentTitle
        if let seasonIndex = parentIndex, let episodeIndex = index {
            label += " • S\(seasonIndex):E\(episodeIndex)"
        }
        return label
    }

    var displayTitle: String {
        if let grandparent = grandparentTitle {
            return "\(grandparent) • \(title)"
        }
        return title
    }

    var progressText: String? {
        guard let duration = duration, duration > 0,
              let viewOffset = viewOffset, viewOffset > 0 else {
            return nil
        }

        let remaining = duration - viewOffset
        let minutes = remaining / 60000

        if minutes < 60 {
            return "\(minutes) min left"
        } else {
            let hours = minutes / 60
            let mins = minutes % 60
            return "\(hours)h \(mins)m left"
        }
    }
}

// Complete MediaItem structure with all fields
struct MediaItemFull: Identifiable, Codable {
    struct GuidEntry: Codable {
        let id: String
    }

    struct MediaEntry: Codable {
        let editionTitle: String?
        let Part: [PartEntry]?
    }

    struct PartEntry: Codable {
        let file: String?
    }

    let id: String // ratingKey
    let title: String
    let type: String
    let thumb: String?
    let art: String?
    let year: Int?
    let rating: Double?
    let duration: Int?
    let viewOffset: Int?
    let summary: String?

    // TV Show specific
    let grandparentTitle: String?
    let grandparentThumb: String?
    let grandparentArt: String?
    let grandparentRatingKey: String?
    let parentIndex: Int?
    let index: Int?

    // Season specific
    let parentRatingKey: String?
    let parentTitle: String?
    let leafCount: Int?
    let viewedLeafCount: Int?

    // Additional metadata
    let addedAt: Int?
    let lastViewedAt: Int?
    let contentRating: String?
    let contentRatingAge: Int?
    let studio: String?
    let tagline: String?
    let key: String?
    let guid: String?
    let Guid: [GuidEntry]?
    let slug: String?
    let tmdbGuid: String? // TMDB guid enriched by backend for watchlist items

    // Media info
    let Media: [MediaEntry]?

    let editionTitle: String?

    // Library metadata
    let allowSync: Bool?
    let librarySectionID: Int?
    let librarySectionTitle: String?
    let librarySectionUUID: String?

    enum CodingKeys: String, CodingKey {
        case id = "ratingKey"
        case title
        case type
        case thumb
        case art
        case year
        case rating
        case duration
        case viewOffset
        case summary
        case grandparentTitle
        case grandparentThumb
        case grandparentArt
        case grandparentRatingKey
        case parentIndex
        case index
        case parentRatingKey
        case parentTitle
        case leafCount
        case viewedLeafCount
        case addedAt
        case lastViewedAt
        case contentRating
        case contentRatingAge
        case studio
        case tagline
        case key
        case guid
        case Guid
        case slug
        case tmdbGuid
        case Media
        case editionTitle
        case allowSync
        case librarySectionID
        case librarySectionTitle
        case librarySectionUUID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        type = try container.decode(String.self, forKey: .type)
        thumb = try container.decodeIfPresent(String.self, forKey: .thumb)
        art = try container.decodeIfPresent(String.self, forKey: .art)
        year = try container.decodeIfPresent(Int.self, forKey: .year)
        rating = try container.decodeIfPresent(Double.self, forKey: .rating)
        duration = try container.decodeIfPresent(Int.self, forKey: .duration)
        viewOffset = try container.decodeIfPresent(Int.self, forKey: .viewOffset)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        grandparentTitle = try container.decodeIfPresent(String.self, forKey: .grandparentTitle)
        grandparentThumb = try container.decodeIfPresent(String.self, forKey: .grandparentThumb)
        grandparentArt = try container.decodeIfPresent(String.self, forKey: .grandparentArt)
        grandparentRatingKey = try container.decodeIfPresent(String.self, forKey: .grandparentRatingKey)
        parentIndex = try container.decodeIfPresent(Int.self, forKey: .parentIndex)
        index = try container.decodeIfPresent(Int.self, forKey: .index)
        parentRatingKey = try container.decodeIfPresent(String.self, forKey: .parentRatingKey)
        parentTitle = try container.decodeIfPresent(String.self, forKey: .parentTitle)
        leafCount = try container.decodeIfPresent(Int.self, forKey: .leafCount)
        viewedLeafCount = try container.decodeIfPresent(Int.self, forKey: .viewedLeafCount)
        addedAt = try container.decodeIfPresent(Int.self, forKey: .addedAt)
        lastViewedAt = try container.decodeIfPresent(Int.self, forKey: .lastViewedAt)
        contentRating = try container.decodeIfPresent(String.self, forKey: .contentRating)
        contentRatingAge = try container.decodeIfPresent(Int.self, forKey: .contentRatingAge)
        studio = try container.decodeIfPresent(String.self, forKey: .studio)
        tagline = try container.decodeIfPresent(String.self, forKey: .tagline)
        key = try container.decodeIfPresent(String.self, forKey: .key)
        guid = try container.decodeIfPresent(String.self, forKey: .guid)
        Guid = try container.decodeIfPresent([GuidEntry].self, forKey: .Guid)
        slug = try container.decodeIfPresent(String.self, forKey: .slug)
        tmdbGuid = try container.decodeIfPresent(String.self, forKey: .tmdbGuid)
        // Safely decode Media - if it fails, just set to nil
        Media = try? container.decodeIfPresent([MediaEntry].self, forKey: .Media)
        editionTitle = try container.decodeIfPresent(String.self, forKey: .editionTitle)
        allowSync = try container.decodeIfPresent(Bool.self, forKey: .allowSync)
        librarySectionID = try container.decodeIfPresent(Int.self, forKey: .librarySectionID)
        librarySectionTitle = try container.decodeIfPresent(String.self, forKey: .librarySectionTitle)
        librarySectionUUID = try container.decodeIfPresent(String.self, forKey: .librarySectionUUID)
    }

    private func extractEditionTitle() -> String? {
        return EditionService.extractEditionTitle(
            topLevelEdition: editionTitle,
            firstMediaEdition: Media?.first?.editionTitle
        )
    }

    // Convert to MediaItem
    func toMediaItem() -> MediaItem {
        // For seasons, if art is missing, try to use grandparentArt (show's backdrop)
        let effectiveArt: String?
        if type == "season" && (art == nil || art?.isEmpty == true) {
            effectiveArt = grandparentArt
        } else {
            effectiveArt = art
        }

        return MediaItem(
            id: id,
            title: title,
            type: type,
            thumb: thumb,
            art: effectiveArt,
            year: year,
            rating: rating,
            duration: duration,
            viewOffset: viewOffset,
            summary: summary,
            grandparentTitle: grandparentTitle,
            grandparentThumb: grandparentThumb,
            grandparentArt: grandparentArt,
            grandparentRatingKey: grandparentRatingKey,
            parentIndex: parentIndex,
            index: index,
            parentRatingKey: parentRatingKey,
            parentTitle: parentTitle,
            leafCount: leafCount,
            viewedLeafCount: viewedLeafCount,
            editionTitle: extractEditionTitle()
        )
    }
}

// API Response structures
struct OnDeckResponse: Codable {
    let size: Int
    let items: [MediaItemFull]

    enum CodingKeys: String, CodingKey {
        case size
        case items = "Metadata"
    }
}

struct ContinueWatchingResponse: Codable {
    let size: Int
    let items: [MediaItemFull]

    enum CodingKeys: String, CodingKey {
        case size
        case items = "Metadata"
    }
}

struct RecentlyAddedResponse: Codable {
    let size: Int
    let items: [MediaItemFull]

    enum CodingKeys: String, CodingKey {
        case size
        case items = "Metadata"
    }
}

struct LibraryResponse: Codable {
    let size: Int
    let items: [MediaItemFull]

    enum CodingKeys: String, CodingKey {
        case size
        case items = "Metadata"
    }
}

struct LibrariesResponse: Codable {
    let libraries: [Library]

    struct Library: Codable, Identifiable {
        let key: String
        let type: String
        let title: String
        let agent: String?
        let scanner: String?
        let language: String?
        let uuid: String?

        var id: String { key }

        enum CodingKeys: String, CodingKey {
            case key
            case type
            case title
            case agent
            case scanner
            case language
            case uuid
        }
    }

    enum CodingKeys: String, CodingKey {
        case libraries = "Directory"
    }
}
