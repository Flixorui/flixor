//
//  MyBlurayService.swift
//  FlixorMac
//
//  The one place the app reads MyBluray data from. Each read is cached on disk
//  with its own time limit, concurrent reads of the same thing share one
//  request, a "no match" answer is remembered for a day, and when the service
//  is down or the quota is used up a saved copy is returned even if it's old.
//
//  Lookups return nil when MyBluray has no match. Errors are `MyBlurayError`
//  (or URLError when offline with nothing saved); callers hide the feature.
//

import Foundation
import CryptoKit

actor MyBlurayService {
    static let shared = MyBlurayService()

    /// How long each kind of result is used before asking again.
    enum TTL {
        static let title: TimeInterval = 24 * 3600
        static let parentsGuide: TimeInterval = 7 * 24 * 3600
        static let movie: TimeInterval = 30 * 24 * 3600
        static let editions: TimeInterval = 7 * 24 * 3600
        static let edition: TimeInterval = 7 * 24 * 3600
        static let collection: TimeInterval = 5 * 60
        static let notFound: TimeInterval = 24 * 3600
    }

    /// Edition lists can run to hundreds of rows worldwide; stop after this many pages of 100.
    private static let maxEditionPages = 5

    private let cache = MyBlurayCache.shared
    private var inFlight: [String: Task<Data, Error>] = [:]
    /// Keys whose collection routes said "no Blu-ray.com login", until when.
    /// Details pages skip the collection meanwhile instead of asking each time.
    private var collectionUnavailableUntil: [String: Date] = [:]
    private static let collectionRecheck: TimeInterval = 10 * 60

    /// Requests sent this session (not cache hits). For logs and verification.
    private(set) var networkRequestCount = 0

    // MARK: - Configuration

    nonisolated var apiKey: String {
        UserDefaults.standard.myblurayApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated var isConfigured: Bool { !apiKey.isEmpty }

    /// A key is saved and the master switch in Settings is on.
    nonisolated var isEnabled: Bool { isConfigured && UserDefaults.standard.myblurayEnabled }

    private func makeClient() throws -> MyBlurayClient {
        let key = apiKey
        guard !key.isEmpty else { throw MyBlurayError.noKey }
        return MyBlurayClient(apiKey: key)
    }

    /// Cache entries are kept per key id (the part after `mbr_`), so two
    /// profiles with different keys or Blu-ray.com accounts never share
    /// collection data, and rotating a key's secret keeps its cache.
    private static func keyScope(_ key: String) -> String {
        let parts = key.split(separator: "_", maxSplits: 2)
        if parts.count == 3, parts[0] == "mbr" { return String(parts[1]) }
        return SHA256.hash(data: Data(key.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Titles

    /// Ratings, Common Sense guidance, certifications and playable videos for a
    /// film or show. One request covers all of them.
    ///
    /// The server returns a short "recommended" video list by default. With
    /// bonus videos turned on in Settings the full list is asked for instead
    /// (a larger response, cached separately), so one call still covers everything.
    func title(imdbId: String, allVideos: Bool? = nil) async throws -> MBTitle? {
        guard let id = Self.normalizedImdbId(imdbId) else { return nil }
        let all = allVideos ?? UserDefaults.standard.myblurayOptionActive(.bonusVideos)
        // v2: stored titles include each source's page link.
        return try await cached(all ? "title-all-v2:\(id)" : "title-v2:\(id)", ttl: TTL.title) { client in
            let data = try await client.get(
                "/v2/titles/" + MyBlurayClient.segment("imdb:\(id)"),
                query: all ? [URLQueryItem(name: "videoSelection", value: "all")] : []
            )
            return try Self.decode(MBEnvelope<MBTitle>.self, data).data.trimmedForStorage()
        }
    }

    /// IMDb's parents guide. Spoilers are included and marked so the UI can hide them.
    func parentsGuide(imdbId: String) async throws -> MBParentsGuide? {
        guard let id = Self.normalizedImdbId(imdbId) else { return nil }
        return try await cached("parents-guide:\(id)", ttl: TTL.parentsGuide) { client in
            let data = try await client.get(
                "/v2/titles/" + MyBlurayClient.segment("imdb:\(id)") + "/parents-guide",
                query: [URLQueryItem(name: "spoilers", value: "include")]
            )
            return try Self.decode(MBEnvelope<MBParentsGuide>.self, data).data
        }
    }

    // MARK: - Blu-ray.com

    /// The Blu-ray.com film for an IMDb id (needed before listing its editions).
    func movie(imdbId: String) async throws -> MBMovie? {
        guard let id = Self.normalizedImdbId(imdbId) else { return nil }
        return try await cached("movie:\(id)", ttl: TTL.movie) { client in
            let data = try await client.get("/v2/movies/resolve", query: [URLQueryItem(name: "imdbId", value: id)])
            return try Self.decode(MBEnvelope<MBMovie>.self, data).data
        }
    }

    /// A film's Blu-ray and 4K editions, optionally for one market (`US`, `GB`, `IN`...).
    func editions(movieId: String, country: String?, formats: [String] = ["bluray", "4k"]) async throws -> [MBEditionSummary] {
        let formatList = formats.joined(separator: ",")
        let key = "editions:\(movieId):\(country ?? "all"):\(formatList)"
        let result: [MBEditionSummary]? = try await cached(key, ttl: TTL.editions) { client in
            var query = [
                URLQueryItem(name: "category", value: "bluray"),
                URLQueryItem(name: "formats", value: formatList),
                URLQueryItem(name: "pageSize", value: "100"),
            ]
            if let country { query.append(URLQueryItem(name: "country", value: country)) }
            var data = try await client.get("/v2/movies/" + MyBlurayClient.segment(movieId) + "/editions", query: query)
            var page = try Self.decode(MBEnvelope<LossyArray<MBEditionSummary>>.self, data)
            var all = page.data.wrappedValue
            var pages = 1
            while let next = page.links?.next, pages < Self.maxEditionPages,
                  let components = URLComponents(string: next) {
                data = try await client.get(components.percentEncodedPath, query: components.queryItems ?? [])
                page = try Self.decode(MBEnvelope<LossyArray<MBEditionSummary>>.self, data)
                all += page.data.wrappedValue
                pages += 1
            }
            return all
        }
        return result ?? []
    }

    /// Full details for one edition: specs, review scores, screenshots, artwork, price.
    func edition(id: String) async throws -> MBEdition? {
        try await cached("edition:\(id)", ttl: TTL.edition) { client in
            let data = try await client.get("/v2/editions/" + MyBlurayClient.segment(id))
            return try Self.decode(MBEnvelope<MBEdition>.self, data).data
        }
    }

    // MARK: - Collection (Blu-ray.com login attached to the key)

    /// Whether account routes work: true when a Blu-ray.com login is attached to
    /// the key, false when it isn't. Not cached.
    func isCollectionConnected() async throws -> Bool {
        let client = try makeClient()
        networkRequestCount += 1
        do {
            _ = try await client.get("/v2/account")
            return true
        } catch MyBlurayError.collectionNotConnected {
            return false
        }
    }

    func collectionLists(category: String = "bluray") async throws -> [MBCollectionList] {
        try checkCollectionAvailable()
        do {
            let result: [MBCollectionList]? = try await cached("collection-lists:\(category)", ttl: TTL.collection) { client in
                let data = try await client.get("/v2/collection/lists", query: [URLQueryItem(name: "category", value: category)])
                return try Self.decode(MBEnvelope<LossyArray<MBCollectionList>>.self, data).data.wrappedValue
            }
            return result ?? []
        } catch MyBlurayError.collectionNotConnected {
            noteCollectionUnavailable()
            throw MyBlurayError.collectionNotConnected
        }
    }

    func collection(category: String = "bluray") async throws -> [MBCollectionEntry] {
        try checkCollectionAvailable()
        do {
            let result: [MBCollectionEntry]? = try await cached("collection:\(category)", ttl: TTL.collection) { client in
                let data = try await client.get("/v2/collection", query: [URLQueryItem(name: "category", value: category)])
                return try Self.decode(MBEnvelope<LossyArray<MBCollectionEntry>>.self, data).data.wrappedValue
            }
            return result ?? []
        } catch MyBlurayError.collectionNotConnected {
            noteCollectionUnavailable()
            throw MyBlurayError.collectionNotConnected
        }
    }

    private func checkCollectionAvailable() throws {
        let scope = Self.keyScope(apiKey)
        if let until = collectionUnavailableUntil[scope], until > Date() {
            throw MyBlurayError.collectionNotConnected
        }
    }

    private func noteCollectionUnavailable() {
        collectionUnavailableUntil[Self.keyScope(apiKey)] = Date().addingTimeInterval(Self.collectionRecheck)
    }

    /// Forget a remembered "not connected", e.g. after Settings saw the login.
    func resetCollectionStatus() {
        collectionUnavailableUntil.removeAll()
    }

    /// Adds an edition to a list, e.g. `MBCollectionChange(productId: "bluray:187101", list: "owned")`.
    func addToCollection(_ change: MBCollectionChange, category: String = "bluray") async throws {
        let client = try makeClient()
        networkRequestCount += 1
        defer { invalidateCollection(category: category, client: client) }
        _ = try await client.write("POST", "/v2/collection/items", body: change)
    }

    func updateCollectionEntry(productId: String, _ change: MBCollectionChange, category: String = "bluray") async throws {
        let client = try makeClient()
        networkRequestCount += 1
        defer { invalidateCollection(category: category, client: client) }
        var body = change
        body.productId = nil
        _ = try await client.write("PATCH", "/v2/collection/items/" + MyBlurayClient.segment(productId), body: body)
    }

    func removeFromCollection(productId: String, category: String = "bluray") async throws {
        let client = try makeClient()
        networkRequestCount += 1
        defer { invalidateCollection(category: category, client: client) }
        _ = try await client.write("DELETE", "/v2/collection/items/" + MyBlurayClient.segment(productId), body: nil)
    }

    private func invalidateCollection(category: String, client: MyBlurayClient) {
        let scope = Self.keyScope(client.apiKey)
        cache.remove("\(scope)|collection:\(category)")
    }

    // MARK: - Key check

    /// Sources the server offers. Works with any valid key, so Settings uses it
    /// to check a key. Not cached.
    func providers() async throws -> [MBProvider] {
        let client = try makeClient()
        networkRequestCount += 1
        let data = try await client.get("/v2/titles/providers")
        return try Self.decode(MBEnvelope<LossyArray<MBProvider>>.self, data).data.wrappedValue
    }

    /// Checks a key, saved or not, and what it can reach. The server has no
    /// route that lists a key's scopes, so this asks for The Dark Knight from
    /// each source: 5 requests, none cached, so the answer is always current.
    /// Throws when the key itself is refused (`invalidKey`, `rateLimited`...).
    func checkKey(_ key: String) async throws -> MyBlurayAccess {
        let client = MyBlurayClient(apiKey: key.trimmingCharacters(in: .whitespacesAndNewlines))
        networkRequestCount += 1
        _ = try await client.get("/v2/titles/providers")

        networkRequestCount += 4
        let probeId = MyBlurayClient.segment("imdb:\(Self.probeImdbId)")
        async let title = Self.probe { try await client.get("/v2/titles/" + probeId) }
        async let guide = Self.probe { try await client.get("/v2/titles/" + probeId + "/parents-guide") }
        async let movie = Self.probe {
            try await client.get("/v2/movies/resolve", query: [URLQueryItem(name: "imdbId", value: Self.probeImdbId)])
        }
        async let account = Self.probe { try await client.get("/v2/account") }

        var access = MyBlurayAccess()
        switch await title {
        case .success(let data):
            let sources = Set(((try? Self.decode(MBEnvelope<MBTitle>.self, data))?.data.sources ?? []).map(\.provider))
            for id in MyBlurayAccess.titleSources {
                access.states[id] = sources.contains(id) ? .yes : .no
            }
        case .failure(let error):
            for id in MyBlurayAccess.titleSources {
                access.states[id] = Self.accessState(for: error)
            }
        }
        access.states[MyBlurayAccess.imdb] = Self.accessState(await guide)
        access.states[MyBlurayAccess.bluray] = Self.accessState(await movie)
        access.states[MyBlurayAccess.collection] = Self.accessState(await account)
        AppLogger.shared.debug("[MyBluray] key check", data: access.states.mapValues { "\($0)" })
        return access
    }

    /// A film every source has.
    private static let probeImdbId = "tt0468569"

    private static func probe(_ call: @escaping () async throws -> Data) async -> Result<Data, Error> {
        do { return .success(try await call()) } catch { return .failure(error) }
    }

    private static func accessState(_ result: Result<Data, Error>) -> MyBlurayAccess.State {
        switch result {
        case .success: return .yes
        case .failure(let error): return accessState(for: error)
        }
    }

    /// A refused scope or a missing Blu-ray.com login is a clear no; "no match"
    /// still means the route is open; anything else can't be told.
    private static func accessState(for error: Error) -> MyBlurayAccess.State {
        switch error as? MyBlurayError {
        case .scopeNotAllowed?, .collectionNotConnected?: return .no
        case .notFound?, .ambiguous?, .unsupported?: return .yes
        default: return .unknown
        }
    }

    /// Forgets every saved result (Settings, or after changing the key).
    func clearCache() {
        cache.clear()
    }

    nonisolated var cacheSizeOnDisk: Int64 { MyBlurayCache.shared.sizeOnDisk }

    // MARK: - Caching

    /// What's stored per key: the value, or nil for "MyBluray has no match".
    private struct Stored<T: Codable>: Codable {
        let value: T?
    }

    private func cached<T: Codable>(
        _ key: String,
        ttl: TimeInterval,
        fetch: @escaping (MyBlurayClient) async throws -> T
    ) async throws -> T? {
        let client = try makeClient()
        let fullKey = "\(Self.keyScope(client.apiKey))|\(key)"
        let saved = cache.read(fullKey)
        let savedValue = saved.flatMap { try? JSONDecoder().decode(Stored<T>.self, from: $0.data) }

        if let saved, let savedValue {
            let limit = savedValue.value == nil ? TTL.notFound : ttl
            if Date().timeIntervalSince(saved.fetchedAt) < limit {
                return savedValue.value
            }
        }

        let task: Task<Data, Error>
        let ownsTask: Bool
        if let existing = inFlight[fullKey] {
            task = existing
            ownsTask = false
        } else {
            networkRequestCount += 1
            AppLogger.shared.debug("[MyBluray] fetch \(key)")
            task = Task {
                do {
                    return try JSONEncoder().encode(Stored(value: try await fetch(client)))
                } catch MyBlurayError.notFound {
                    return try JSONEncoder().encode(Stored<T>(value: nil))
                }
            }
            inFlight[fullKey] = task
            ownsTask = true
        }

        do {
            let data = try await task.value
            if ownsTask {
                inFlight[fullKey] = nil
                cache.write(data, for: fullKey)
            }
            return try JSONDecoder().decode(Stored<T>.self, from: data).value
        } catch {
            if ownsTask { inFlight[fullKey] = nil }
            let transient = (error as? MyBlurayError)?.isTransient ?? (error is URLError)
            if transient, let savedValue {
                AppLogger.shared.debug("[MyBluray] serving saved \(key) after error")
                return savedValue.value
            }
            throw error
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            AppLogger.shared.warn("[MyBluray] decode failed for \(T.self)", data: ["error": "\(error)"])
            throw MyBlurayError.invalidResponse
        }
    }

    /// "tt0468569", "imdb:tt0468569" and "imdb://tt0468569" all become "tt0468569".
    static func normalizedImdbId(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: #"tt\d{7,10}"#, options: .regularExpression) else { return nil }
        return String(trimmed[range])
    }
}
