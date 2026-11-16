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

import FlixorKit
import Foundation
import CryptoKit

actor MyBlurayService {
    static let shared = MyBlurayService()

    /// How long each kind of result is used before asking again.
    enum TTL {
        static let title: TimeInterval = 24 * 3600
        static let artwork: TimeInterval = 7 * 24 * 3600
        static let offers: TimeInterval = 24 * 3600
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

    /// Apple TV artwork for a film or show (the textless wide backdrop and
    /// tall artwork). Artwork rarely changes, so it's kept for a week.
    func appleArtwork(imdbId: String) async throws -> MBAppleArtwork? {
        guard let id = Self.normalizedImdbId(imdbId) else { return nil }
        return try await cached("apple-artwork:\(id)", ttl: TTL.artwork) { client in
            let data = try await client.get(
                "/v2/titles/" + MyBlurayClient.segment("imdb:\(id)") + "/images",
                query: [URLQueryItem(name: "source", value: "apple-tv")]
            )
            let images = try Self.decode(MBEnvelope<LossyArray<MBImage>>.self, data).data.wrappedValue
            return MBAppleArtwork(images: images)
        }
    }

    /// The Apple TV backdrop when the option is on and Apple has one; nil otherwise.
    /// Never throws, so callers can fall back to TMDB or Plex.
    nonisolated static func appleBackdrop(imdbId: String?) async -> URL? {
        guard let imdbId, UserDefaults.standard.myblurayOptionActive(.appleArtwork) else { return nil }
        return try? await shared.appleArtwork(imdbId: imdbId)?.backdropURL
    }

    /// The same for a TMDB id: looks the IMDb id up first (cached).
    nonisolated static func appleBackdrop(tmdbId: String, isShow: Bool) async -> URL? {
        guard UserDefaults.standard.myblurayOptionActive(.appleArtwork), let id = Int(tmdbId) else { return nil }
        let imdbId = await MediaIdentityResolver.shared.imdbId(tmdbId: id, isShow: isShow)
        return await appleBackdrop(imdbId: imdbId)
    }

    // MARK: - Where to watch

    /// Store offers to stream, rent or buy a film or show (Apple TV and JustWatch, US).
    func offers(imdbId: String) async throws -> [MBOffer]? {
        guard let id = Self.normalizedImdbId(imdbId) else { return nil }
        return try await cached("offers:\(id)", ttl: TTL.offers) { client in
            let data = try await client.get(
                "/v2/titles/" + MyBlurayClient.segment("imdb:\(id)") + "/offers",
                query: [URLQueryItem(name: "source", value: "all")]
            )
            return try Self.decode(MBEnvelope<LossyArray<MBOffer>>.self, data).data.wrappedValue
        }
    }

    /// A Blu-ray.com film's releases in a digital category: `digital`, `itunes`,
    /// `prime-video` or `movies-anywhere`.
    func digitalEditions(movieId: String, category: String) async throws -> [MBEditionSummary]? {
        try await cached("digital-list:\(category):\(movieId)", ttl: TTL.editions) { client in
            let data = try await client.get(
                "/v2/movies/" + MyBlurayClient.segment(movieId) + "/editions",
                query: [URLQueryItem(name: "category", value: category), URLQueryItem(name: "pageSize", value: "100")]
            )
            return try Self.decode(MBEnvelope<LossyArray<MBEditionSummary>>.self, data).data.wrappedValue
        }
    }

    /// One digital release in full: its stores, prices and specs.
    func digitalEdition(id: String) async throws -> MBDigitalEdition? {
        try await cached("digital-edition:\(id)", ttl: TTL.edition) { client in
            let data = try await client.get("/v2/editions/" + MyBlurayClient.segment(id))
            return try Self.decode(MBEnvelope<MBDigitalEdition>.self, data).data
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

    /// A Blu-ray.com film by its id ("movie:18630"), e.g. an edition's film.
    func movie(id: String) async throws -> MBMovie? {
        try await cached("movie-id:\(id)", ttl: TTL.movie) { client in
            let data = try await client.get("/v2/movies/" + MyBlurayClient.segment(id))
            return try Self.decode(MBEnvelope<MBMovie>.self, data).data
        }
    }

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
        // v2: stored editions include the film's movieId.
        try await cached("edition-v2:\(id)", ttl: TTL.edition) { client in
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

// MARK: - Where to watch (merged)

extension MyBlurayService {
    /// Stream, rent and buy options for a title, or nil when MyBluray has none.
    /// Films also use Blu-ray.com's US digital release for its full store list
    /// (Google Play, Vudu, Microsoft...) and specs.
    nonisolated static func whereToWatch(imdbId: String, isMovie: Bool) async -> WhereToWatch? {
        guard UserDefaults.standard.myblurayOptionActive(.whereToWatch) else { return nil }
        let service = shared
        async let offers = try? await service.offers(imdbId: imdbId)
        async let digital = isMovie ? await digitalRelease(imdbId: imdbId) : nil
        var merged = WhereToWatchBuilder.build(offers: await offers ?? [], digital: await digital)
        guard !merged.isEmpty else { return nil }
        await StoreLogos.shared.apply(to: &merged)
        return merged
    }

    /// The film's US digital release on Blu-ray.com, and whether it's on Movies Anywhere.
    private nonisolated static func digitalRelease(imdbId: String) async -> WhereToWatchBuilder.Digital? {
        let service = shared
        guard let movie = try? await service.movie(imdbId: imdbId) else { return nil }
        async let list = try? await service.digitalEditions(movieId: movie.id, category: "digital")
        async let anywhere = try? await service.digitalEditions(movieId: movie.id, category: "movies-anywhere")
        let wanted = PlexDiscMatcher.normalized(movie.title ?? "")
        let candidates = (await list ?? []).filter {
            $0.country?.code == "US" && $0.bundle != true && !($0.title ?? "").contains("3D")
        }
        let pick = candidates.first { PlexDiscMatcher.normalized($0.title ?? "") == wanted } ?? candidates.first
        var edition: MBDigitalEdition?
        if let pick { edition = try? await service.digitalEdition(id: pick.id) }
        let onAnywhere = (await anywhere ?? []).contains { $0.country?.code == "US" && $0.bundle != true }
        guard edition != nil || onAnywhere else { return nil }
        return WhereToWatchBuilder.Digital(edition: edition, moviesAnywhere: onAnywhere)
    }
}

/// Merges store offers and Blu-ray.com stores into one entry per store and kind.
enum WhereToWatchBuilder {
    struct Digital {
        let edition: MBDigitalEdition?
        let moviesAnywhere: Bool
    }

    static func build(offers: [MBOffer], digital: Digital?) -> WhereToWatch {
        var stream: [String: WhereToWatch.Store] = [:]
        var rent: [String: WhereToWatch.Store] = [:]
        var buy: [String: WhereToWatch.Store] = [:]
        var logos: [String: URL] = [:]

        for offer in offers {
            guard let name = offer.provider?.name, !name.isEmpty else { continue }
            let quality = normalizedQuality(offer.quality)
            // Discs are covered by Physical Releases.
            if quality == nil, let raw = offer.quality?.uppercased(), ["BLURAY", "DVD", "4K_BLURAY"].contains(raw) { continue }
            if name.localizedCaseInsensitiveContains("DVD") || name.localizedCaseInsensitiveContains("Barnes") { continue }
            let (id, display) = canonical(name)
            let logo = offer.provider?.images.first(where: { $0.kind == "provider-logo" })?.url(width: 120, format: "png")
            if let logo, logos[id] == nil { logos[id] = logo }
            let providerId = offer.provenance?.provider == "justwatch" ? offer.provider?.id.flatMap(Int.init) : nil
            let store = WhereToWatch.Store(
                id: id, name: display, providerId: providerId, logo: logo, url: offer.url.flatMap(URL.init(string:)),
                price: offer.price?.amount.flatMap(Double.init), priceText: offer.priceText, quality: quality
            )
            switch offer.type?.lowercased() {
            case "rent": merge(store, into: &rent)
            case "buy": merge(store, into: &buy)
            case "subscription", "free", "ad-supported", "free-ad-supported-tv", "ads": merge(store, into: &stream)
            default: continue
            }
        }

        var specs: [WhereToWatch.Spec] = []
        if let edition = digital?.edition {
            for item in edition.stores {
                guard let rawId = item.id, rawId != "movies-anywhere", let name = item.name else { continue }
                let (id, display) = canonical(rawId == "itunes" ? "iTunes" : name)
                let prices = edition.prices.filter {
                    $0.offer?.lowercased() == "buy" && canonical($0.storeName ?? "").id == id
                }
                let cheapest = prices.compactMap { p in p.amount.flatMap(Double.init).map { ($0, p) } }.min { $0.0 < $1.0 }
                let store = WhereToWatch.Store(
                    id: id, name: display, logo: logos[id], url: item.url.flatMap(URL.init(string:)),
                    price: cheapest?.0, priceText: cheapest?.1.text, quality: normalizedQuality(cheapest?.1.quality)
                )
                merge(store, into: &buy)
            }
            if let video = edition.video {
                let resolution = (video.resolutions + [video.resolution].compactMap { $0 })
                    .contains { $0.localizedCaseInsensitiveContains("4K") || $0.contains("2160") } ? "Digital 4K" : nil
                let hdr = video.hdrFormats.joined(separator: " · ")
                if let resolution {
                    specs.append(.init(title: resolution, detail: hdr.isEmpty ? nil : hdr))
                } else if !hdr.isEmpty {
                    specs.append(.init(title: hdr, detail: nil))
                }
            }
            if edition.audio.contains(where: { $0.localizedCaseInsensitiveContains("Atmos") }) {
                specs.append(.init(title: "Dolby Atmos", detail: nil))
            }
        }
        if digital?.moviesAnywhere == true {
            specs.append(.init(title: "Movies Anywhere", detail: String(localized: "buy once, play in every linked store")))
        }

        // Fill missing logos from other kinds (Blu-ray.com stores carry none).
        func withLogos(_ stores: [String: WhereToWatch.Store]) -> [WhereToWatch.Store] {
            stores.values.map { store in
                var store = store
                if store.logo == nil { store.logo = logos[store.id] }
                return store
            }
        }
        return WhereToWatch(
            stream: sorted(dropChannels(withLogos(stream))),
            rent: sorted(withLogos(rent)),
            buy: sorted(withLogos(buy)),
            specs: specs
        )
    }

    /// Keeps the cheapest price per store, and the best quality at that price.
    private static func merge(_ store: WhereToWatch.Store, into stores: inout [String: WhereToWatch.Store]) {
        guard var existing = stores[store.id] else {
            stores[store.id] = store
            return
        }
        if existing.url == nil { existing.url = store.url }
        if existing.logo == nil { existing.logo = store.logo }
        if existing.providerId == nil { existing.providerId = store.providerId }
        switch (store.price, existing.price) {
        case let (new?, old?) where new < old:
            existing.price = new; existing.priceText = store.priceText; existing.quality = store.quality
        case let (new?, old?) where new == old && rank(store.quality) > rank(existing.quality):
            existing.quality = store.quality
        case (.some, nil):
            existing.price = store.price; existing.priceText = store.priceText; existing.quality = store.quality
        case (nil, nil) where rank(store.quality) > rank(existing.quality):
            existing.quality = store.quality
        default: break
        }
        stores[store.id] = existing
    }

    /// "HBO Max Amazon Channel" is dropped when HBO Max itself is listed.
    private static func dropChannels(_ stores: [WhereToWatch.Store]) -> [WhereToWatch.Store] {
        let names = Set(stores.map { $0.name.lowercased() })
        return stores.filter { store in
            for suffix in [" amazon channel", " apple tv channel", " roku premium channel"] {
                let lower = store.name.lowercased()
                if lower.hasSuffix(suffix), names.contains(String(lower.dropLast(suffix.count))) { return false }
            }
            return true
        }
    }

    /// Priced stores first (cheapest first), then the big stores, then the rest.
    private static func sorted(_ stores: [WhereToWatch.Store]) -> [WhereToWatch.Store] {
        let preferred = ["apple", "amazon", "google-play", "vudu", "microsoft", "youtube"]
        return stores.sorted { a, b in
            switch (a.price, b.price) {
            case let (x?, y?) where x != y: return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default:
                let ia = preferred.firstIndex(of: a.id) ?? preferred.count
                let ib = preferred.firstIndex(of: b.id) ?? preferred.count
                return ia != ib ? ia < ib : a.name < b.name
            }
        }
    }

    private static func rank(_ quality: String?) -> Int {
        switch quality { case "4K": return 3; case "HD": return 2; case "SD": return 1; default: return 0 }
    }

    static func normalizedQuality(_ raw: String?) -> String? {
        guard let raw = raw?.uppercased() else { return nil }
        if raw.contains("4K") || raw.contains("UHD") || raw.contains("2160") { return raw.contains("BLURAY") ? nil : "4K" }
        if raw == "HD" || raw.contains("1080") || raw.contains("720") { return "HD" }
        if raw == "SD" { return "SD" }
        return nil
    }

    /// One id and name per store across sources: the Apple TV app and iTunes are
    /// one store, as are Fandango at Home and Vudu.
    static func canonical(_ name: String) -> (id: String, name: String) {
        let lower = name.lowercased().trimmingCharacters(in: .whitespaces)
        if lower.contains("apple tv+") || lower.contains("apple tv plus") { return ("apple-tv-plus", "Apple TV+") }
        if lower == "itunes" || lower == "apple tv" || lower == "apple tv store" || lower == "apple itunes" { return ("apple", "Apple TV") }
        if lower.contains("fandango") || lower == "vudu" { return ("vudu", "Fandango at Home") }
        // "Prime Video" alone is the Amazon store (Movies Anywhere's name for it);
        // "Amazon Prime Video" is the subscription and stays separate.
        if lower == "amazon" || lower == "amazon video" || lower == "prime video" { return ("amazon", "Amazon") }
        if lower == "comcast" || lower.hasPrefix("xfinity") { return ("xfinity", "Xfinity") }
        if lower.hasPrefix("verizon") { return ("verizon-fios", "Verizon Fios") }
        if lower.contains("google play") || lower == "google-play" || lower == "google tv" { return ("google-play", "Google Play") }
        if lower.contains("microsoft") { return ("microsoft", "Microsoft Store") }
        if lower == "youtube" { return ("youtube", "YouTube") }
        let id = lower.replacingOccurrences(of: " ", with: "-")
        return (id, name)
    }
}

/// Official store logos from TMDB's watch-provider list (the same ids as
/// JustWatch), fetched once per launch for movies and TV.
actor StoreLogos {
    static let shared = StoreLogos()

    private var byId: [Int: URL] = [:]
    private var byName: [String: URL] = [:]
    private var loaded = false

    /// TMDB's names for stores that come from Blu-ray.com without an id.
    private static let aliases: [String: [String]] = [
        "apple": ["Apple TV Store", "Apple TV"],
        "amazon": ["Amazon Video"],
        "vudu": ["Fandango At Home"],
        "google-play": ["Google Play Movies"],
        "microsoft": ["Microsoft Store"],
        "youtube": ["YouTube"],
        "xfinity": ["Xfinity Stream"],
        "verizon-fios": ["Verizon On Demand", "Verizon Fios TV"],
        "kaleidescape": ["Kaleidescape"],
    ]

    func apply(to content: inout WhereToWatch) async {
        await load()
        content.stream = content.stream.map(resolve)
        content.rent = content.rent.map(resolve)
        content.buy = content.buy.map(resolve)
    }

    private func resolve(_ store: WhereToWatch.Store) -> WhereToWatch.Store {
        var store = store
        let names = (Self.aliases[store.id] ?? []) + [store.name]
        let official = store.providerId.flatMap { byId[$0] }
            ?? names.lazy.compactMap { self.byName[Self.key($0)] }.first
        if let official {
            store.logo = official
            store.logoIsIcon = true
        }
        return store
    }

    private func load() async {
        guard !loaded else { return }
        let tmdb = await FlixorCore.shared.tmdb
        async let movie = try? await tmdb.getWatchProviders(mediaType: "movie")
        async let tv = try? await tmdb.getWatchProviders(mediaType: "tv")
        for provider in (await movie?.results ?? []) + (await tv?.results ?? []) {
            guard let path = provider.logoPath,
                  let url = URL(string: "https://image.tmdb.org/t/p/w92\(path)") else { continue }
            if byId[provider.providerId] == nil { byId[provider.providerId] = url }
            if let name = provider.providerName, byName[Self.key(name)] == nil { byName[Self.key(name)] = url }
        }
        // Try again next time if TMDB was unreachable.
        loaded = !byId.isEmpty
    }

    private static func key(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
