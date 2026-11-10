//
//  XtreamWebGuideClient.swift
//  FlixorMac
//
//  Personal build only (FLIXOR_LIVE_TV). Reads the merged guide from the
//  deployed xtream-web server (`/api/guide?ids=…`), which already combines its
//  India schedule worker, YouTube TV reference guide, dated premium schedules
//  and the provider's short EPG. Signs in with the server's existing password
//  form (`/api/auth/login`) and keeps the 30-day session cookie in the Keychain.
//

#if FLIXOR_LIVE_TV
import Foundation

final class XtreamWebGuideClient {
    static let maxIdsPerRequest = 24
    private static let cookieName = "__Host-tuned-session"

    private let server: LiveTVGuideServer
    private let session: URLSession
    private let redirectBlocker = RedirectBlocker()

    init(server: LiveTVGuideServer) {
        self.server = server
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        session = URLSession(configuration: config, delegate: redirectBlocker, delegateQueue: nil)
    }

    deinit { session.finishTasksAndInvalidate() }

    /// Signs in and stores the session cookie. Throws on a wrong password.
    @discardableResult
    func signIn() async throws -> String {
        guard let origin = server.origin else { throw LiveTVError.provider("The guide server address is not valid.") }
        var request = URLRequest(url: origin.appendingPathComponent("api/auth/login"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(origin.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")), forHTTPHeaderField: "Origin")
        request.httpBody = "password=\(XtreamClient.encode(server.password))".data(using: .utf8)
        let (_, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else { throw LiveTVError.provider("No answer from the guide server.") }
        if http.statusCode == 429 { throw LiveTVError.provider("The guide server asked to wait a minute before signing in again.") }
        let location = http.value(forHTTPHeaderField: "Location") ?? ""
        let cookie = Self.sessionCookie(from: http)
        guard (300..<400).contains(http.statusCode), !location.contains("error"), let cookie else {
            throw LiveTVError.provider(http.statusCode == 503 ? "Sign-in is not enabled on the guide server." : "The guide server rejected the password.")
        }
        AppLogger.shared.registerSensitiveValue(cookie)
        LiveTVSecrets.guideSessionCookie = cookie
        return cookie
    }

    /// Guide entries for up to 24 provider stream ids.
    func guide(ids: [String]) async throws -> [String: LiveGuideEntry] {
        let valid = ids.filter { JSRegex("^\\d+$").test($0) }
        guard !valid.isEmpty else { return [:] }
        guard valid.count <= Self.maxIdsPerRequest else { throw LiveTVError.provider("At most 24 channels per guide request.") }
        var cookie = LiveTVSecrets.guideSessionCookie
        if cookie == nil { cookie = try await signIn() }
        var (data, status) = try await requestGuide(ids: valid, cookie: cookie!)
        if status == 401 {
            cookie = try await signIn()
            (data, status) = try await requestGuide(ids: valid, cookie: cookie!)
        }
        guard (200..<300).contains(status) else { throw LiveTVError.provider("The guide server returned HTTP \(status).") }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LiveTVError.provider("The guide server sent data Flixor could not read.")
        }
        var result: [String: LiveGuideEntry] = [:]
        for (id, value) in root {
            guard let entry = value as? [String: Any] else { continue }
            let programs = (entry["programs"] as? [[String: Any]] ?? []).compactMap { p -> LiveProgram? in
                guard let start = LiveTVJSON.number(p["start"]), let end = LiveTVJSON.number(p["end"]), end > start else { return nil }
                return LiveProgram(
                    id: LiveTVJSON.string(p["id"]) ?? "\(id)-\(start)",
                    title: (p["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled program",
                    description: p["description"] as? String ?? "",
                    metadata: p["metadata"] as? String,
                    start: Date(timeIntervalSince1970: start / 1000),
                    end: Date(timeIntervalSince1970: end / 1000)
                )
            }
            result[id] = LiveGuideEntry(programs: programs, unavailable: entry["unavailable"] as? Bool ?? false, source: entry["source"] as? String)
        }
        return result
    }

    private func requestGuide(ids: [String], cookie: String) async throws -> (Data, Int) {
        guard let origin = server.origin,
              var components = URLComponents(url: origin.appendingPathComponent("api/guide"), resolvingAgainstBaseURL: false) else {
            throw LiveTVError.provider("The guide server address is not valid.")
        }
        components.queryItems = [URLQueryItem(name: "ids", value: ids.joined(separator: ","))]
        guard let url = components.url else { throw LiveTVError.provider("The guide server address is not valid.") }
        var request = URLRequest(url: url)
        request.setValue("\(Self.cookieName)=\(cookie)", forHTTPHeaderField: "Cookie")
        let (data, response) = try await perform(request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do { return try await session.data(for: request) }
        catch {
            let code = (error as? URLError)?.code.rawValue ?? 0
            throw LiveTVError.provider("The guide server is unavailable (\(code)).")
        }
    }

    private static func sessionCookie(from response: HTTPURLResponse) -> String? {
        guard let url = response.url else { return nil }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String { result[key] = value }
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
        return cookies.first { $0.name == cookieName }?.value
    }

    /// Keeps the 303 from /api/auth/login so its Set-Cookie can be read.
    private final class RedirectBlocker: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? { nil }
    }
}
#endif
