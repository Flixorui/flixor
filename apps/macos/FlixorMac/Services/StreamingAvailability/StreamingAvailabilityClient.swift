//
//  StreamingAvailabilityClient.swift
//  FlixorMac
//
//  HTTP client for api.movieofthenight.com/v4. The key goes in X-API-Key and
//  never into logs. Every response's quota headers are reported back.
//

import Foundation
import CryptoKit

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

// MARK: - FlixPatrol

/// A FlixPatrol JSON API the user added: its base URL (e.g. ".../v2") and key.
struct FlixPatrolSource: Codable, Hashable, Identifiable {
    let url: String
    let key: String

    var id: String {
        SHA256.hash(data: Data((url + "|" + key).utf8)).map { String(format: "%02x", $0) }.joined().prefix(16).description
    }
    var host: String { URL(string: url)?.host ?? url }
    var maskedKey: String { String(repeating: "•", count: 8) + key.suffix(4) }

    /// The URL as typed, without spaces or a trailing slash, with https:// added when missing.
    static func normalizedURL(_ raw: String) -> String {
        var url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while url.hasSuffix("/") { url.removeLast() }
        if !url.isEmpty, !url.contains("://") { url = "https://" + url }
        return url
    }
}

enum FlixPatrolError: LocalizedError {
    case invalidURL
    case http(Int, String?)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL: return String(localized: "That isn't a valid URL.")
        case .http(let code, let detail):
            if code == 401 || code == 403 { return String(localized: "FlixPatrol didn't accept the API key.") }
            if code == 404 { return detail ?? String(localized: "FlixPatrol has no data for that (404).") }
            return detail ?? String(localized: "FlixPatrol returned an error (\(code)).")
        case .invalidResponse: return String(localized: "FlixPatrol sent an unexpected response.")
        }
    }
}

/// HTTP client for a FlixPatrol JSON API (v2). Same X-API-Key header as Movie
/// of the Night; no quota, so no budget. The key never goes into logs.
struct FlixPatrolClient {
    let source: FlixPatrolSource
    var session: URLSession = .shared

    func get(_ path: String, query: [URLQueryItem]) async throws -> Data {
        guard let base = URL(string: source.url), base.scheme?.hasPrefix("http") == true,
              var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        else { throw FlixPatrolError.invalidURL }
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw FlixPatrolError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue(source.key, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FlixPatrolError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            AppLogger.shared.warn("[FlixPatrol] HTTP \(http.statusCode) for \(path)")
            throw FlixPatrolError.http(http.statusCode, detail)
        }
        return data
    }
}
