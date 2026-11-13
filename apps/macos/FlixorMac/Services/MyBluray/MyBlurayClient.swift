//
//  MyBlurayClient.swift
//  FlixorMac
//
//  HTTP client for the MyBluray v2 API (catalog enrichment from Apple TV,
//  JustWatch, Letterboxd, IMDb and Blu-ray.com). The key goes in X-API-Key and
//  never into logs. Errors come back typed so features can degrade quietly:
//  a missing scope hides one feature, a missing Blu-ray.com login hides the
//  collection, and server trouble falls back to saved data.
//

import Foundation

enum MyBlurayError: LocalizedError, Equatable {
    /// No API key entered.
    case noKey
    /// The key is malformed, unknown, revoked or expired (API_KEY_* codes).
    case invalidKey(code: String)
    /// The key lacks the scope this route needs (SCOPE_NOT_ALLOWED).
    case scopeNotAllowed
    /// Account routes: no Blu-ray.com login is attached to the key, or it was rejected.
    case collectionNotConnected
    /// The Blu-ray.com session behind the key expired (UPSTREAM_SESSION_EXPIRED).
    /// The server signs in again on the next request, so it's worth one retry.
    case sessionExpired
    case notFound
    /// An exact title matched several productions (409).
    case ambiguous
    /// The route doesn't apply to this item, e.g. seasons for a film (422).
    case unsupported
    /// 429: quota used up or rate limited. `retryAfter` is in seconds when sent.
    case rateLimited(retryAfter: TimeInterval?, quotaExceeded: Bool)
    /// 5xx, including the edge's plain-text 502 pages.
    case server(status: Int)
    case http(status: Int, code: String?, message: String?)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .noKey: return String(localized: "Add your MyBluray API key in Settings.")
        case .invalidKey: return String(localized: "The MyBluray API key was not accepted.")
        case .scopeNotAllowed: return String(localized: "Your MyBluray key doesn't include this source.")
        case .collectionNotConnected: return String(localized: "Attach your Blu-ray.com login to this key in the MyBluray portal.")
        case .sessionExpired: return String(localized: "Blu-ray.com signed out. Try again in a moment.")
        case .notFound: return String(localized: "MyBluray has no match for this title.")
        case .ambiguous: return String(localized: "MyBluray matched more than one title.")
        case .unsupported: return String(localized: "MyBluray doesn't support this for this title.")
        case .rateLimited(_, let quotaExceeded):
            return quotaExceeded
                ? String(localized: "This month's MyBluray quota is used up.")
                : String(localized: "Too many MyBluray requests. Try again in a minute.")
        case .server: return String(localized: "MyBluray is having trouble right now.")
        case .http(let status, _, let message): return message ?? String(localized: "MyBluray returned an error (\(status)).")
        case .invalidResponse: return String(localized: "MyBluray sent an unexpected response.")
        }
    }

    /// Worth serving saved data instead: the failure says nothing about the data itself.
    var isTransient: Bool {
        switch self {
        case .rateLimited, .server, .invalidResponse, .sessionExpired: return true
        case .http(let status, _, _): return status >= 500
        default: return false
        }
    }
}

struct MyBlurayClient {
    static let defaultBaseURL = URL(string: "https://mybluray-api.devhomelab.app")!

    let apiKey: String
    var baseURL: URL = MyBlurayClient.defaultBaseURL
    var session: URLSession = .shared

    /// Long enough for the server's own 30 s upstream timeout to come back as its error.
    static let timeout: TimeInterval = 35

    // MARK: - Requests

    /// GET `path` (already escaped, e.g. `/v2/titles/imdb:tt0468569`) with `query`.
    /// Retries once on a 502/503/504 or a dropped connection.
    func get(_ path: String, query: [URLQueryItem] = []) async throws -> Data {
        do {
            return try await send("GET", path, query: query, body: nil)
        } catch let error as MyBlurayError {
            switch error {
            case .server(let status) where [502, 503, 504].contains(status):
                try await Task.sleep(nanoseconds: 600_000_000)
            case .sessionExpired:
                break   // the server signs in again on the next request
            default:
                throw error
            }
            return try await send("GET", path, query: query, body: nil)
        } catch let error as URLError where [.timedOut, .networkConnectionLost].contains(error.code) {
            try await Task.sleep(nanoseconds: 600_000_000)
            return try await send("GET", path, query: query, body: nil)
        }
    }

    /// Writes (POST/PATCH/PUT/DELETE) are never retried: a write may already
    /// have been applied when the response is lost.
    /// The one exception is an expired Blu-ray.com session: Blu-ray.com
    /// refused the change before making it, so it is sent once more.
    func write(_ method: String, _ path: String, body: Encodable?) async throws -> Data {
        let data = try body.map { try JSONEncoder().encode(AnyEncodable($0)) }
        let payload = data ?? (method == "DELETE" ? nil : Data("{}".utf8))
        do {
            return try await send(method, path, query: [], body: payload)
        } catch MyBlurayError.sessionExpired {
            return try await send(method, path, query: [], body: payload)
        }
    }

    private func send(_ method: String, _ path: String, query: [URLQueryItem], body: Data?) async throws -> Data {
        guard !apiKey.isEmpty else { throw MyBlurayError.noKey }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw MyBlurayError.invalidResponse
        }
        components.percentEncodedPath = path
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw MyBlurayError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = Self.timeout
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MyBlurayError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let error = Self.error(status: http.statusCode, data: data, response: http)
            AppLogger.shared.warn("[MyBluray] HTTP \(http.statusCode) for \(method) \(path)", data: ["error": "\(error)"])
            throw error
        }
        return data
    }

    // MARK: - Errors

    private struct ErrorBody: Decodable {
        struct Inner: Decodable {
            let code: String?
            let message: String?
        }
        let error: Inner?
    }

    static func error(status: Int, data: Data, response: HTTPURLResponse) -> MyBlurayError {
        let body = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
        let code = body?.code ?? ""
        switch status {
        case 401:
            if code.hasPrefix("API_KEY_") { return .invalidKey(code: code) }
            if code == "UPSTREAM_SESSION_EXPIRED" { return .sessionExpired }
            return .collectionNotConnected   // UNAUTHORIZED, KEY_CREDENTIALS_INVALID
        case 403:
            return code == "SCOPE_NOT_ALLOWED" ? .scopeNotAllowed : .http(status: status, code: code, message: body?.message)
        case 404: return .notFound
        case 409: return .ambiguous
        case 422: return .unsupported
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            return .rateLimited(retryAfter: retryAfter, quotaExceeded: code == "QUOTA_EXCEEDED")
        case 500...599: return .server(status: status)
        default: return .http(status: status, code: body?.code, message: body?.message)
        }
    }

    // MARK: - Paths

    /// Escapes one path segment, keeping `:` so ids like `imdb:tt0468569` stay readable.
    static func segment(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

/// Lets `write` take any Encodable body.
private struct AnyEncodable: Encodable {
    let value: Encodable
    init(_ value: Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}
