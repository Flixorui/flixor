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

    init(status: OverseerrStatus, requestId: Int? = nil, canRequest: Bool? = nil) {
        self.status = status
        self.requestId = requestId
        self.canRequest = canRequest ?? status.canRequest
    }

    static let notConfigured = OverseerrMediaStatus(status: .unknown, canRequest: false)
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
    let permissions: Int?
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
}

// MARK: - Connection Validation

struct OverseerrConnectionResult {
    let valid: Bool
    let username: String?
    let error: String?
}
