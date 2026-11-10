//
//  StreamingAvailabilityClient.swift
//  FlixorMac
//
//  HTTP client for api.movieofthenight.com/v4. The key goes in X-API-Key and
//  never into logs. Every response's quota headers are reported back.
//

import Foundation

enum StreamingAvailabilityError: LocalizedError {
    case noKey
    case overBudget
    case http(Int, String?)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .noKey: return String(localized: "Add your Streaming Availability API key in Settings.")
        case .overBudget: return String(localized: "Today's call limit is used up. Showing saved lists.")
        case .http(let code, let message):
            if code == 401 || code == 403 { return String(localized: "The API key was not accepted.") }
            if code == 429 { return String(localized: "The monthly call quota is used up.") }
            return message ?? String(localized: "The service returned an error (\(code)).")
        case .invalidResponse: return String(localized: "The service sent an unexpected response.")
        }
    }
}

struct StreamingAvailabilityClient {
    static let baseURL = URL(string: "https://api.movieofthenight.com/v4")!

    let apiKey: String
    var session: URLSession = .shared

    /// GET `path` with `query`; returns the body and the quota it reported.
    func get(_ path: String, query: [URLQueryItem]) async throws -> (Data, SAQuota?) {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw StreamingAvailabilityError.invalidResponse }
        let quota = Self.quota(from: http)
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            AppLogger.shared.warn("[StreamingAvailability] HTTP \(http.statusCode) for \(path)")
            throw StreamingAvailabilityError.http(http.statusCode, message)
        }
        return (data, quota)
    }

    static func quota(from response: HTTPURLResponse) -> SAQuota? {
        guard let used = (response.value(forHTTPHeaderField: "x-quota-used")).flatMap(Int.init),
              let granted = (response.value(forHTTPHeaderField: "x-quota-granted")).flatMap(Int.init) else { return nil }
        let reset = response.value(forHTTPHeaderField: "x-quota-reset").flatMap { ISO8601DateFormatter().date(from: $0) }
        return SAQuota(used: used, granted: granted, resetsAt: reset, observedAt: Date())
    }
}
