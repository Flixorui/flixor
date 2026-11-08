//
//  SkipSegmentHTTP.swift
//  FlixorMac
//
//  Small HTTP helper shared by the community skip-segment clients:
//  short timeouts, an identifying User-Agent, and 429 handling.
//

import Foundation

enum SkipSegmentHTTPError: Error {
    /// HTTP 429. `retryAfter` is when the provider says we may ask again.
    case rateLimited(retryAfter: Date?)
    case status(Int)
    case invalidResponse
}

enum SkipSegmentHTTP {
    /// Ephemeral session: no cookies, no disk cache, short timeouts so a slow
    /// provider never holds up playback features.
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = [
            "User-Agent": userAgent,
            "Accept": "application/json",
        ]
        return URLSession(configuration: config)
    }()

    static let userAgent: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Flixor/\(version) (macOS)"
    }()

    /// GET a JSON document. Returns the decoded top-level object (dictionary,
    /// array or NSNull for `null`).
    static func getJSON(_ url: URL) async throws -> Any {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return try await send(request)
    }

    /// POST a JSON body and decode the JSON response.
    static func postJSON(_ url: URL, body: [String: Any], headers: [String: String] = [:]) async throws -> Any {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(request)
    }

    private static func send(_ request: URLRequest) async throws -> Any {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SkipSegmentHTTPError.invalidResponse }
        switch http.statusCode {
        case 200..<300:
            if data.isEmpty { return NSNull() }
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        case 404:
            // Most providers answer "unknown title" with 404.
            return NSNull()
        case 429:
            throw SkipSegmentHTTPError.rateLimited(retryAfter: retryAfterDate(http: http, data: data))
        default:
            throw SkipSegmentHTTPError.status(http.statusCode)
        }
    }

    /// Reads `Retry-After` (seconds) or an IntroDB-style `reset_at` body field.
    private static func retryAfterDate(http: HTTPURLResponse, data: Data) -> Date? {
        if let header = http.value(forHTTPHeaderField: "Retry-After"), let seconds = TimeInterval(header) {
            return Date().addingTimeInterval(seconds)
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let reset = json["reset_at"] {
            if let seconds = reset as? Double {
                // Either a Unix timestamp or a relative number of seconds.
                return seconds > 1_000_000_000 ? Date(timeIntervalSince1970: seconds) : Date().addingTimeInterval(seconds)
            }
            if let string = reset as? String {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: string) { return date }
                formatter.formatOptions = [.withInternetDateTime]
                return formatter.date(from: string)
            }
        }
        return nil
    }

    // MARK: - Value parsing

    /// Number from a JSON value: numbers, numeric strings, or clock strings (mm:ss, hh:mm:ss).
    static func seconds(_ raw: Any?) -> Double? {
        switch raw {
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespaces)
            if let value = Double(trimmed) { return value }
            let parts = trimmed.split(separator: ":").map { Double($0) }
            guard !parts.isEmpty, parts.count <= 3, parts.allSatisfy({ $0 != nil }) else { return nil }
            return parts.compactMap { $0 }.reduce(0) { $0 * 60 + $1 }
        default:
            return nil
        }
    }

    static func string(_ raw: Any?) -> String? {
        switch raw {
        case let string as String: return string.isEmpty ? nil : string
        case let number as NSNumber: return number.stringValue
        default: return nil
        }
    }

    static func int(_ raw: Any?) -> Int? {
        switch raw {
        case let number as NSNumber: return number.intValue
        case let string as String: return Int(string)
        default: return nil
        }
    }
}
