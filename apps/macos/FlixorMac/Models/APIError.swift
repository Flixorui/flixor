//
//  APIError.swift
//  FlixorMac
//
//  API error types
//

import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case decodingError(Error)
    case httpError(statusCode: Int, message: String?)
    case unauthorized
    case serverError(String)
    case noData

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return String(localized: "Invalid URL")
        case .networkError(let error):
            return String(localized: "Network error: \(error.localizedDescription)")
        case .decodingError(let error):
            return String(localized: "Failed to decode response: \(error.localizedDescription)")
        case .httpError(let statusCode, let message):
            return message ?? String(localized: "HTTP error: \(statusCode)")
        case .unauthorized:
            return String(localized: "Unauthorized. Please sign in again.")
        case .serverError(let message):
            return String(localized: "Server error: \(message)")
        case .noData:
            return String(localized: "No data received from server")
        }
    }
}
