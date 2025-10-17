import Foundation

public enum APIError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case decodingError(Error)
    case httpError(statusCode: Int, message: String?)
    case unauthorized
    case serverError(String)
    case noData

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .httpError(let statusCode, let message):
            return message ?? "HTTP error: \(statusCode)"
        case .unauthorized:
            return "Unauthorized. Please sign in again."
        case .serverError(let message):
            return "Server error: \(message)"
        case .noData:
            return "No data received from server"
        }
    }
}

