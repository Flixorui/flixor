//
//  XtreamClient.swift
//  FlixorMac
//
//  Personal build only (FLIXOR_LIVE_TV). Direct Xtream Codes `player_api.php`
//  client, the same calls xtream-web's provider.ts makes. Every URL here
//  carries the account's username and password, so nothing in this file logs
//  a URL; errors go through `LiveTVRedactor`.
//

#if FLIXOR_LIVE_TV
import Foundation

enum LiveTVError: LocalizedError {
    case notConfigured
    case invalidServer
    case unauthorized
    case provider(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Set up your Xtream account in Settings > Live TV."
        case .invalidServer: return "The server URL is not valid. Use http:// or https:// with the host and port."
        case .unauthorized: return "The provider rejected the username or password."
        case .provider(let message): return message
        }
    }
}

/// Removes the account's secrets from any text before it is logged or shown.
enum LiveTVRedactor {
    static func redact(_ text: String, account: LiveTVAccount?) -> String {
        guard let account else { return text }
        var out = text
        let secrets = [account.password, account.username, account.serverURL, account.baseURL?.host ?? ""]
            .filter { $0.count >= 3 }
            .sorted { $0.count > $1.count }
        for secret in secrets {
            out = out.replacingOccurrences(of: secret, with: "‹redacted›")
            let encoded = XtreamClient.encode(secret)
            if encoded != secret { out = out.replacingOccurrences(of: encoded, with: "‹redacted›") }
        }
        return out
    }
}

struct XtreamClient {
    let account: LiveTVAccount

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 180
        config.httpCookieStorage = nil
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    private func apiURL(action: String?, extra: [String: String] = [:]) throws -> URL {
        guard let base = account.baseURL else { throw LiveTVError.invalidServer }
        guard var components = URLComponents(url: base.appendingPathComponent("player_api.php"), resolvingAgainstBaseURL: false) else {
            throw LiveTVError.invalidServer
        }
        // URLSearchParams-style encoding: a "+" in a password must reach PHP as %2B, not a space.
        var pairs = [("username", account.username), ("password", account.password)]
        if let action { pairs.append(("action", action)) }
        pairs += extra.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        components.percentEncodedQuery = pairs.map { "\(Self.encode($0.0))=\(Self.encode($0.1))" }.joined(separator: "&")
        guard let url = components.url else { throw LiveTVError.invalidServer }
        return url
    }

    private func get(_ url: URL, timeout: TimeInterval = 30) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("Flixor", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await Self.session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw LiveTVError.provider("No response from the provider.") }
            if http.statusCode == 401 || http.statusCode == 403 { throw LiveTVError.unauthorized }
            guard (200..<300).contains(http.statusCode) else {
                throw LiveTVError.provider("The Xtream provider returned HTTP \(http.statusCode). Try again shortly.")
            }
            return data
        } catch let error as LiveTVError {
            throw error
        } catch {
            // URLError descriptions can include the failing URL; never pass them through.
            let code = (error as? URLError)?.code.rawValue ?? 0
            throw LiveTVError.provider("The Xtream provider is unavailable (\(code)). Try again shortly.")
        }
    }

    private func json(_ data: Data) throws -> Any {
        do { return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) }
        catch { throw LiveTVError.provider("The provider sent data Flixor could not read.") }
    }

    // MARK: Calls

    /// `player_api.php` without an action: account status.
    func authenticate() async throws -> LiveTVAccountStatus {
        let object = try json(await get(apiURL(action: nil)))
        guard let root = object as? [String: Any], let info = root["user_info"] as? [String: Any] else {
            throw LiveTVError.provider("The server did not answer like an Xtream Codes provider.")
        }
        if let auth = LiveTVJSON.number(info["auth"]), auth == 0 { throw LiveTVError.unauthorized }
        let expiry = LiveTVJSON.number(info["exp_date"]).flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
        return LiveTVAccountStatus(
            status: info["status"] as? String ?? "Unknown",
            expiresAt: expiry,
            maxConnections: LiveTVJSON.number(info["max_connections"]).map { Int($0) },
            activeConnections: LiveTVJSON.number(info["active_cons"]).map { Int($0) }
        )
    }

    func liveCategoriesData() async throws -> Data {
        try await get(apiURL(action: "get_live_categories"), timeout: 60)
    }

    func liveStreamsData() async throws -> Data {
        try await get(apiURL(action: "get_live_streams"), timeout: 180)
    }

    /// `get_short_epg` with `limit=12`, parsed like curation.ts `parsePrograms`.
    func shortEPG(streamId: String) async throws -> [LiveProgram] {
        let object = try json(await get(apiURL(action: "get_short_epg", extra: ["stream_id": streamId, "limit": "12"])))
        let rows = ((object as? [String: Any])?["epg_listings"] as? [[String: Any]]) ?? []
        return Self.parsePrograms(rows)
    }

    /// `/live/{user}/{pass}/{id}.m3u8`, as provider.ts `streamUrl`.
    func streamURL(sourceId: String) -> URL? {
        guard let base = account.baseURL,
              JSRegex("^\\d+$").test(sourceId) else { return nil }
        let user = Self.encode(account.username), pass = Self.encode(account.password)
        return URL(string: "live/\(user)/\(pass)/\(sourceId).m3u8", relativeTo: base)?.absoluteURL
    }

    /// `encodeURIComponent`: everything but A-Z a-z 0-9 - _ . ! ~ * ' ( ) is escaped.
    private static let componentAllowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
    static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: componentAllowed) ?? value
    }

    // MARK: Parsing (curation.ts)

    static func decodeText(_ value: Any?) -> String {
        guard let raw = value as? String else { return "" }
        let text = JSString.trim(raw)
        if text.count % 4 == 0, JSRegex("^[A-Za-z0-9+/]+={0,2}$").test(text),
           let data = Data(base64Encoded: text), let decoded = String(data: data, encoding: .utf8),
           !decoded.contains("\u{FFFD}"), !JSRegex("[\\x00-\\x08]").test(decoded) {
            return decoded
        }
        return text
    }

    static func parsePrograms(_ rows: [[String: Any]]) -> [LiveProgram] {
        rows.compactMap { r -> LiveProgram? in
            guard let start = LiveTVJSON.number(r["start_timestamp"]), let end = LiveTVJSON.number(r["stop_timestamp"]),
                  start.isFinite, end.isFinite, end > start else { return nil }
            let title = decodeText(r["title"])
            return LiveProgram(
                id: LiveTVJSON.string(r["id"]) ?? "\(start)",
                title: title.isEmpty ? "Untitled program" : title,
                description: decodeText(r["description"]),
                start: Date(timeIntervalSince1970: start),
                end: Date(timeIntervalSince1970: end)
            )
        }.jsStableSorted { a, b in a.start < b.start ? -1 : a.start > b.start ? 1 : 0 }
    }
}
#endif
