//
//  OverseerrModels.swift
//  FlixorMac
//
//  Overseerr API models for media requests
//

import Foundation

// MARK: - Status Enums

enum OverseerrStatus: String, Codable {
    case notRequested = "not_requested"
    case pending
    case approved
    case declined
    case processing
    case partiallyAvailable = "partially_available"
    case available
    case unknown

    var displayName: String {
        switch self {
        case .notRequested: return "Request"
        case .pending: return "Pending"
        case .approved: return "Approved"
        case .declined: return "Declined"
        case .processing: return "Processing"
        case .partiallyAvailable: return "Partial"
        case .available: return "Available"
        case .unknown: return "Unknown"
        }
    }

    var canRequest: Bool {
        switch self {
        case .notRequested, .declined, .partiallyAvailable, .unknown:
            return true
        default:
            return false
        }
    }
}

// MARK: - Media Status

struct OverseerrMediaStatus {
    let status: OverseerrStatus
    let requestId: Int?
    let canRequest: Bool
    let seasons: [OverseerrSeason]?  // Per-season info for TV shows

    init(status: OverseerrStatus, requestId: Int? = nil, canRequest: Bool? = nil, seasons: [OverseerrSeason]? = nil) {
        self.status = status
        self.requestId = requestId
        self.canRequest = canRequest ?? status.canRequest
        self.seasons = seasons
    }

    static let notConfigured = OverseerrMediaStatus(status: .unknown, canRequest: false)

    /// Get seasons that can be requested (not available, not processing, not partially available)
    var requestableSeasons: [OverseerrSeason] {
        (seasons ?? []).filter { $0.canRequest && $0.seasonNumber > 0 }
    }

    /// Get seasons that are not fully available (for display in picker)
    var unavailableSeasons: [OverseerrSeason] {
        (seasons ?? []).filter { !$0.isAvailable && $0.seasonNumber > 0 }
    }

    /// Check if this is a partially available TV show (has some unavailable seasons to potentially request)
    var isPartiallyAvailableTv: Bool {
        status == .partiallyAvailable && seasons != nil && !unavailableSeasons.isEmpty
    }

    /// Check if there are any partially available seasons (some episodes downloaded)
    var hasPartiallyAvailableSeasons: Bool {
        (seasons ?? []).contains { $0.isPartiallyAvailable }
    }
}

// MARK: - Request Result

struct OverseerrRequestResult {
    let success: Bool
    let requestId: Int?
    let status: OverseerrStatus?
    let error: String?
}

// MARK: - API Status Codes

enum MediaRequestStatusCode: Int {
    case pending = 1
    case approved = 2
    case declined = 3
}

enum MediaInfoStatusCode: Int {
    case unknown = 1
    case pending = 2
    case processing = 3
    case partiallyAvailable = 4
    case available = 5
}

// MARK: - API Response Models

struct OverseerrUser: Codable {
    let id: Int
    let email: String?
    let username: String?
    let plexUsername: String?
    let plexToken: String?
    let permissions: Int?
    let avatar: String?
}

struct OverseerrMediaRequest: Codable {
    let id: Int
    let status: Int
    let media: OverseerrMediaInfo?
}

struct OverseerrMediaInfo: Codable {
    let id: Int
    let tmdbId: Int
    let mediaType: String?
    let status: Int
    let requests: [OverseerrMediaRequest]?
    let seasons: [OverseerrSeason]?  // Per-season availability for TV shows
}

struct OverseerrMovieDetails: Codable {
    let id: Int
    let mediaInfo: OverseerrMediaInfo?
}

struct OverseerrTvDetails: Codable {
    let id: Int
    let mediaInfo: OverseerrMediaInfo?
    let seasons: [OverseerrSeason]?
}

struct OverseerrSeason: Codable {
    let seasonNumber: Int
    let status: Int?        // Per-season availability status
    let status4k: Int?      // Per-season 4K availability status

    /// Check if this season is available (status 5 = AVAILABLE)
    var isAvailable: Bool {
        status == MediaInfoStatusCode.available.rawValue
    }

    /// Check if this season is partially available
    var isPartiallyAvailable: Bool {
        status == MediaInfoStatusCode.partiallyAvailable.rawValue
    }

    /// Check if this season is processing
    var isProcessing: Bool {
        status == MediaInfoStatusCode.processing.rawValue
    }

    /// Check if this season is pending
    var isPending: Bool {
        status == MediaInfoStatusCode.pending.rawValue
    }

    /// Check if this season can be requested (not available, not processing, not pending, not partially available)
    /// Note: Overseerr doesn't support requesting seasons that already have some episodes available
    var canRequest: Bool {
        guard let status = status else { return true }
        return status != MediaInfoStatusCode.available.rawValue &&
               status != MediaInfoStatusCode.processing.rawValue &&
               status != MediaInfoStatusCode.pending.rawValue &&
               status != MediaInfoStatusCode.partiallyAvailable.rawValue
    }
}

// MARK: - Connection Validation

struct OverseerrConnectionResult {
    let valid: Bool
    let username: String?
    let error: String?
}
