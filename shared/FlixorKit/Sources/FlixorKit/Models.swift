import Foundation

public struct User: Codable, Identifiable {
    public let id: String
    public let username: String
    public let email: String?
    public let thumb: String?
}

public struct SessionInfo: Codable {
    public let authenticated: Bool
    public let user: User?
}

public struct AuthResponse: Codable {
    public let token: String
    public let user: User
}

// Core media item used across views
public struct MediaItem: Identifiable, Codable, Hashable {
    public let id: String // ratingKey
    public let title: String
    public let type: String // movie, show, episode, season
    public let thumb: String?
    public let art: String?
    public let logo: String? // TMDB clear logo (when available)
    public let year: Int?
    public let rating: Double?
    public let duration: Int?
    public let viewOffset: Int?
    public let summary: String?

    // TV Show specific
    public let grandparentTitle: String?
    public let grandparentThumb: String?
    public let grandparentArt: String?
    public let parentIndex: Int?
    public let index: Int?

    // Season specific
    public let parentRatingKey: String?
    public let parentTitle: String?
    public let leafCount: Int?
    public let viewedLeafCount: Int?

    public init(
        id: String,
        title: String,
        type: String,
        thumb: String?,
        art: String?,
        logo: String? = nil,
        year: Int?,
        rating: Double?,
        duration: Int?,
        viewOffset: Int?,
        summary: String?,
        grandparentTitle: String?,
        grandparentThumb: String?,
        grandparentArt: String?,
        parentIndex: Int?,
        index: Int?,
        parentRatingKey: String? = nil,
        parentTitle: String? = nil,
        leafCount: Int? = nil,
        viewedLeafCount: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.thumb = thumb
        self.art = art
        self.logo = logo
        self.year = year
        self.rating = rating
        self.duration = duration
        self.viewOffset = viewOffset
        self.summary = summary
        self.grandparentTitle = grandparentTitle
        self.grandparentThumb = grandparentThumb
        self.grandparentArt = grandparentArt
        self.parentIndex = parentIndex
        self.index = index
        self.parentRatingKey = parentRatingKey
        self.parentTitle = parentTitle
        self.leafCount = leafCount
        self.viewedLeafCount = viewedLeafCount
    }

    public enum CodingKeys: String, CodingKey {
        case id = "ratingKey"
        case title
        case type
        case thumb
        case art
        case logo
        case year
        case rating
        case duration
        case viewOffset
        case summary
        case grandparentTitle
        case grandparentThumb
        case grandparentArt
        case parentIndex
        case index
        case parentRatingKey
        case parentTitle
        case leafCount
        case viewedLeafCount
    }
}

public struct PlexServer: Codable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let host: String?
    public let port: Int?
    public let protocolName: String?
    public let preferredUri: String?
    public let publicAddress: String?
    public let localAddresses: [String]?
    public let machineIdentifier: String?
    public let isActive: Bool?
    public let owned: Bool?
    public let presence: Bool?

    public enum CodingKeys: String, CodingKey {
        case id, name, host, port, preferredUri, publicAddress, localAddresses, machineIdentifier, isActive, owned, presence
        case protocolName = "protocol"
    }
}

public struct PlexConnection: Codable, Identifiable, Hashable {
    public let uri: String
    public let protocolName: String?
    public let local: Bool?
    public let relay: Bool?
    public let IPv6: Bool?
    public let isCurrent: Bool?
    public let isPreferred: Bool?
    public var id: String { uri }

    public enum CodingKeys: String, CodingKey {
        case uri
        case protocolName = "protocol"
        case local, relay, IPv6, isCurrent, isPreferred
    }
}

public struct PlexConnectionsResponse: Codable {
    public let serverId: String?
    public let connections: [PlexConnection]
}

public struct PlexAuthServer: Codable { public let clientIdentifier: String; public let token: String; public let name: String? }

public struct SimpleMessageResponse: Decodable { public let message: String?; public let serverId: String? }

// MARK: - Plex library responses used for Home

public struct PlexLibraryResponse: Decodable {
    public let size: Int?
    public let totalSize: Int?
    public let offset: Int?
    public let Metadata: [MediaItemFull]?
}

public struct MediaItemFull: Codable {
    public let id: String
    public let title: String
    public let type: String
    public let thumb: String?
    public let art: String?
    public let year: Int?
    public let rating: Double?
    public let duration: Int?
    public let viewOffset: Int?
    public let summary: String?
    public let grandparentTitle: String?
    public let grandparentThumb: String?
    public let grandparentArt: String?
    public let grandparentRatingKey: String?
    public let parentIndex: Int?
    public let index: Int?
    public let parentRatingKey: String?
    public let parentTitle: String?
    public let leafCount: Int?
    public let viewedLeafCount: Int?

    // Library metadata (optional)
    public let allowSync: Bool?
    public let librarySectionID: Int?
    public let librarySectionTitle: String?
    public let librarySectionUUID: String?

    public struct GuidEntry: Codable { public let id: String }
    public let Guid: [GuidEntry]?
    public let guid: String?
    public let slug: String?
    public let tmdbGuid: String?

    public enum CodingKeys: String, CodingKey {
        case id = "ratingKey"
        case title, type, thumb, art, year, rating, duration, viewOffset, summary
        case grandparentTitle, grandparentThumb, grandparentArt, grandparentRatingKey
        case parentIndex, index, parentRatingKey, parentTitle, leafCount, viewedLeafCount
        case allowSync, librarySectionID, librarySectionTitle, librarySectionUUID
        case Guid, guid, slug, tmdbGuid
    }

    public func toMediaItem() -> MediaItem {
        let effectiveArt: String?
        if type == "season" && (art == nil || art?.isEmpty == true) { effectiveArt = grandparentArt } else { effectiveArt = art }
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
            parentIndex: parentIndex,
            index: index,
            parentRatingKey: parentRatingKey,
            parentTitle: parentTitle,
            leafCount: leafCount,
            viewedLeafCount: viewedLeafCount
        )
    }
}

public struct ContinueWatchingResponse: Codable { public let size: Int; public let items: [MediaItemFull]; public enum CodingKeys: String, CodingKey { case size; case items = "Metadata" } }
public struct OnDeckResponse: Codable { public let size: Int; public let items: [MediaItemFull]; public enum CodingKeys: String, CodingKey { case size; case items = "Metadata" } }
public struct RecentlyAddedResponse: Codable { public let size: Int; public let items: [MediaItemFull]; public enum CodingKeys: String, CodingKey { case size; case items = "Metadata" } }
