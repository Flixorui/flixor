//
//  PlexServerService.swift
//  FlixorKit
//
//  Handles Plex Media Server API calls
//  Reference: packages/core/src/services/PlexServerService.ts
//

import Foundation

// MARK: - PlexServerService

public class PlexServerService {
    private let baseUrl: String
    private let token: String
    private let clientId: String
    private let cache: CacheManager

    public init(baseUrl: String, token: String, clientId: String, cache: CacheManager) {
        self.baseUrl = baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.token = token
        self.clientId = clientId
        self.cache = cache
    }

    // MARK: - Headers

    private func getHeaders() -> [String: String] {
        return [
            "Accept": "application/json",
            "X-Plex-Token": token,
            "X-Plex-Client-Identifier": clientId,
            "X-Plex-Product": "Flixor",
            "X-Plex-Version": "1.0.0",
            "X-Plex-Platform": "macOS",
            "X-Plex-Device": "macOS",
            "X-Plex-Device-Name": "Flixor"
        ]
    }

    // MARK: - Generic Request

    private func get<T: Codable>(
        path: String,
        params: [String: String]? = nil,
        ttl: TimeInterval = CacheTTL.dynamic
    ) async throws -> T {
        var urlString = "\(baseUrl)\(path)"
        if let params = params, !params.isEmpty {
            let queryString = params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }.joined(separator: "&")
            urlString += "?\(queryString)"
        }

        let cacheKey = "plex:\(urlString)"

        // Check cache first
        if ttl > 0 {
            if let cached: T = await cache.get(cacheKey) {
                return cached
            }
        }

        guard let url = URL(string: urlString) else {
            throw PlexServerError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        for (key, value) in getHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexServerError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw PlexServerError.httpError(statusCode: httpResponse.statusCode)
        }

        // Debug: log raw JSON for metadata requests to trace Rating array
        if path.contains("/library/metadata/") && !path.contains("/children") {
            if let jsonString = String(data: data, encoding: .utf8) {
                // Check if Rating array exists in raw JSON
                let hasRatingArray = jsonString.contains("\"Rating\"")
                let hasRatingField = jsonString.contains("\"rating\"")
                print("🔍 [FlixorKit] Metadata response for \(path):")
                print("   - Has 'Rating' array: \(hasRatingArray)")
                print("   - Has 'rating' field: \(hasRatingField)")
                // Log a snippet around Rating if it exists
                if hasRatingArray, let range = jsonString.range(of: "\"Rating\"") {
                    let startIdx = jsonString.index(range.lowerBound, offsetBy: -20, limitedBy: jsonString.startIndex) ?? jsonString.startIndex
                    let endIdx = jsonString.index(range.upperBound, offsetBy: 200, limitedBy: jsonString.endIndex) ?? jsonString.endIndex
                    print("   - Rating snippet: ...\(jsonString[startIdx..<endIdx])...")
                }
            }
        }

        let result = try JSONDecoder().decode(T.self, from: data)

        // Cache the response
        if ttl > 0 {
            await cache.set(cacheKey, value: result, ttl: ttl)
        }

        return result
    }

    // MARK: - Libraries

    /// Get all libraries
    public func getLibraries() async throws -> [PlexLibrary] {
        let response: PlexMediaContainerResponse<PlexLibrary> = try await get(
            path: "/library/sections",
            ttl: CacheTTL.trending
        )
        return response.MediaContainer.Directory ?? []
    }

    /// Get items in a library with pagination
    public func getLibraryItems(
        key: String,
        type: Int? = nil,
        sort: String? = nil,
        limit: Int? = nil,
        offset: Int? = nil,
        genre: String? = nil
    ) async throws -> [PlexMediaItem] {
        var params: [String: String] = [:]

        if let type = type { params["type"] = String(type) }
        if let sort = sort { params["sort"] = sort }
        if let genre = genre { params["genre"] = genre }
        if let limit = limit { params["X-Plex-Container-Size"] = String(limit) }
        if let offset = offset { params["X-Plex-Container-Start"] = String(offset) }

        let response: PlexMediaContainerResponse<PlexMediaItem> = try await get(
            path: "/library/sections/\(key)/all",
            params: params,
            ttl: CacheTTL.short
        )
        return response.MediaContainer.Metadata ?? []
    }

    /// Get items in a library with full pagination info
    public func getLibraryItemsWithPagination(
        key: String,
        type: Int? = nil,
        sort: String? = nil,
        limit: Int? = nil,
        offset: Int? = nil,
        genre: String? = nil
    ) async throws -> PlexLibraryItemsResult {
        var params: [String: String] = [:]

        if let type = type { params["type"] = String(type) }
        if let sort = sort { params["sort"] = sort }
        if let genre = genre { params["genre"] = genre }
        if let limit = limit { params["X-Plex-Container-Size"] = String(limit) }
        if let offset = offset { params["X-Plex-Container-Start"] = String(offset) }
        // Include extended media info for edition display
        params["includeGuids"] = "1"
        params["includeEditions"] = "1"

        let response: PlexMediaContainerResponse<PlexMediaItem> = try await get(
            path: "/library/sections/\(key)/all",
            params: params,
            ttl: CacheTTL.short
        )
        return PlexLibraryItemsResult(
            items: response.MediaContainer.Metadata ?? [],
            size: response.MediaContainer.size ?? 0,
            totalSize: response.MediaContainer.totalSize ?? response.MediaContainer.size ?? 0,
            offset: response.MediaContainer.offset ?? 0
        )
    }

    // MARK: - Metadata

    /// Get metadata for a specific item
    public func getMetadata(ratingKey: String) async throws -> PlexMediaItem {
        let response: PlexMediaContainerResponse<PlexMediaItem> = try await get(
            path: "/library/metadata/\(ratingKey)",
            ttl: CacheTTL.trending
        )
        guard let item = response.MediaContainer.Metadata?.first else {
            throw PlexServerError.notFound
        }
        // Debug: log decoded Rating array
        print("📊 [FlixorKit] Decoded item '\(item.title ?? "unknown")' - Rating count: \(item.ratings.count), rating: \(item.rating ?? 0), audienceRating: \(item.audienceRating ?? 0)")
        for r in item.ratings {
            print("   🎬 Rating: image='\(r.image ?? "nil")', value=\(r.value ?? 0)")
        }
        return item
    }

    /// Get children (seasons for show, episodes for season)
    public func getChildren(ratingKey: String) async throws -> [PlexMediaItem] {
        let response: PlexMediaContainerResponse<PlexMediaItem> = try await get(
            path: "/library/metadata/\(ratingKey)/children",
            ttl: CacheTTL.dynamic
        )
        // Plex returns episodes in Metadata and seasons in Directory
        // Filter out items without ratingKey (e.g., "All Episodes" pseudo-season)
        let items = (response.MediaContainer.Metadata ?? []) + (response.MediaContainer.Directory ?? [])
        return items.filter { $0.ratingKey != nil }
    }

    /// Get related items
    public func getRelated(ratingKey: String) async throws -> [PlexMediaItem] {
        let response: PlexMediaContainerResponse<PlexMediaItem> = try await get(
            path: "/library/metadata/\(ratingKey)/related",
            ttl: CacheTTL.trending
        )
        return response.MediaContainer.Metadata ?? []
    }

    // MARK: - Hubs (Continue Watching, On Deck, etc.)

    /// Get continue watching items (deduplicated by GUID)
    /// Returns items grouped by TMDB/IMDB GUID, keeping only the most recently watched version
    public func getContinueWatching() async throws -> ContinueWatchingResult {
        let response: PlexMediaContainerResponse<PlexMediaItem> = try await get(
            path: "/hubs/continueWatching/items",
            params: ["includeGuids": "1"],
            ttl: CacheTTL.short
        )
        let items = response.MediaContainer.Metadata ?? []
        return deduplicateContinueWatching(items)
    }

    /// Deduplicate continue watching items by GUID
    /// Groups items by their TMDB/IMDB GUID and keeps the most recently watched version
    private func deduplicateContinueWatching(_ items: [PlexMediaItem]) -> ContinueWatchingResult {
        var guidMap: [String: PlexMediaItem] = [:]
        var guidCount: [String: Int] = [:]

        for item in items {
            let guid = extractPrimaryGuid(item.guids)

            // If no GUID, use ratingKey as fallback (can't dedupe without GUID)
            guard let guid = guid else {
                if let rk = item.ratingKey {
                    guidMap[rk] = item
                }
                continue
            }

            // Count items per GUID to track duplicates
            guidCount[guid] = (guidCount[guid] ?? 0) + 1

            // Keep the most recently watched version (compare viewOffset or viewCount)
            if let existing = guidMap[guid] {
                let existingViewOffset = existing.viewOffset ?? 0
                let itemViewOffset = item.viewOffset ?? 0
                if itemViewOffset > existingViewOffset {
                    guidMap[guid] = item
                }
            } else {
                guidMap[guid] = item
            }
        }

        // Identify which final items had duplicates (multiple versions across libraries)
        var itemsWithMultipleVersions = Set<String>()
        for (guid, item) in guidMap {
            if (guidCount[guid] ?? 0) > 1, let rk = item.ratingKey {
                itemsWithMultipleVersions.insert(rk)
            }
        }

        return ContinueWatchingResult(
            items: Array(guidMap.values),
            itemsWithMultipleVersions: itemsWithMultipleVersions
        )
    }

    /// Extract primary GUID (TMDB or IMDB) from Guid array
    private func extractPrimaryGuid(_ guids: [String]) -> String? {
        // Prefer TMDB, then IMDB
        if let tmdb = guids.first(where: { $0.hasPrefix("tmdb://") }) {
            return tmdb
        }
        if let imdb = guids.first(where: { $0.hasPrefix("imdb://") }) {
            return imdb
        }
        return guids.first
    }

    /// Get on deck items
    public func getOnDeck() async throws -> [PlexMediaItem] {
        let response: PlexMediaContainerResponse<PlexMediaItem> = try await get(
            path: "/library/onDeck",
            ttl: CacheTTL.short
        )
        return response.MediaContainer.Metadata ?? []
    }

    /// Get recently added items
    public func getRecentlyAdded(libraryKey: String? = nil) async throws -> [PlexMediaItem] {
        let path = libraryKey != nil
            ? "/library/sections/\(libraryKey!)/recentlyAdded"
            : "/library/recentlyAdded"

        let response: PlexMediaContainerResponse<PlexMediaItem> = try await get(
            path: path,
            ttl: CacheTTL.dynamic
        )
        return response.MediaContainer.Metadata ?? []
    }

    // MARK: - Search

    /// Search the library
    public func search(query: String, type: Int? = nil) async throws -> [PlexMediaItem] {
        var results: [PlexMediaItem] = []

        // Get all libraries and search each one
        let libraries = try await getLibraries()

        // Filter libraries by type if specified
        let targetLibraries = libraries.filter { lib in
            guard let type = type else { return true }
            if type == 1 { return lib.type == "movie" }
            if type == 2 { return lib.type == "show" }
            return true
        }

        // Search each library section
        for lib in targetLibraries {
            do {
                var params: [String: String] = ["query": query]
                if let type = type { params["type"] = String(type) }
                // Include extended media info for edition display
                params["includeGuids"] = "1"
                params["includeEditions"] = "1"

                let response: PlexMediaContainerResponse<PlexMediaItem> = try await get(
                    path: "/library/sections/\(lib.key)/search",
                    params: params,
                    ttl: CacheTTL.short
                )
                results.append(contentsOf: response.MediaContainer.Metadata ?? [])
            } catch {
                // Try alternative: get all items and filter by title
                do {
                    var fallbackParams: [String: String] = ["title": query]
                    fallbackParams["includeGuids"] = "1"
                    fallbackParams["includeEditions"] = "1"
                    let response: PlexMediaContainerResponse<PlexMediaItem> = try await get(
                        path: "/library/sections/\(lib.key)/all",
                        params: fallbackParams,
                        ttl: CacheTTL.short
                    )
                    results.append(contentsOf: response.MediaContainer.Metadata ?? [])
                } catch {}
            }
        }

        return results
    }

    /// Find items by GUID (for TMDB/IMDB matching)
    public func findByGuid(guid: String, type: Int? = nil) async throws -> [PlexMediaItem] {
        var results: [PlexMediaItem] = []

        let libraries = try await getLibraries()

        let targetLibraries = libraries.filter { lib in
            guard let type = type else { return true }
            if type == 1 { return lib.type == "movie" }
            if type == 2 { return lib.type == "show" }
            return true
        }

        for lib in targetLibraries {
            do {
                let response: PlexMediaContainerResponse<PlexMediaItem> = try await get(
                    path: "/library/sections/\(lib.key)/all",
                    params: ["guid": guid],
                    ttl: CacheTTL.short
                )
                results.append(contentsOf: response.MediaContainer.Metadata ?? [])
            } catch {}
        }

        return results
    }

    // MARK: - Markers (Skip Intro/Credits)

    /// Get markers for an item (intro/credits skip points)
    public func getMarkers(ratingKey: String) async throws -> [PlexMarker] {
        let response: PlexMediaContainerResponse<PlexMediaItem> = try await get(
            path: "/library/metadata/\(ratingKey)",
            params: ["includeMarkers": "1"],
            ttl: CacheTTL.trending
        )
        return response.MediaContainer.Metadata?.first?.Marker ?? []
    }

    // MARK: - Playback

    /// Get direct stream URL for playback
    public func getStreamUrl(ratingKey: String) -> String {
        return "\(baseUrl)/library/metadata/\(ratingKey)?X-Plex-Token=\(token)"
    }

    /// Get transcode URL for HLS playback
    public func getTranscodeUrl(
        ratingKey: String,
        options: TranscodeOptions? = nil
    ) -> TranscodeResult {
        let opts = options ?? TranscodeOptions()
        let sessionId = opts.sessionId ?? UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(15).lowercased()

        var params: [String: String] = [
            "hasMDE": "1",
            "path": "/library/metadata/\(ratingKey)",
            "mediaIndex": "0",
            "partIndex": "0",
            "protocol": opts.protocol,
            "fastSeek": "1",
            "directPlay": "0",
            "directStream": opts.directStream ? "1" : "0",
            "directStreamAudio": "0",
            "videoQuality": "100",
            "videoResolution": opts.videoResolution,
            "maxVideoBitrate": String(opts.maxVideoBitrate),
            "subtitleSize": "100",
            "audioBoost": "100",
            "location": "lan",
            "addDebugOverlay": "0",
            "autoAdjustQuality": "0",
            "mediaBufferSize": "102400",
            "session": String(sessionId),
            "copyts": "1",
            "X-Plex-Token": token,
            "X-Plex-Client-Identifier": String(sessionId),
            "X-Plex-Product": "Flixor",
            "X-Plex-Platform": "macOS",
            "X-Plex-Device": "macOS"
        ]

        let queryString = params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }.joined(separator: "&")

        let startUrl = "\(baseUrl)/video/:/transcode/universal/start.m3u8?\(queryString)"
        let sessionUrl = "\(baseUrl)/video/:/transcode/universal/session/\(sessionId)/base/index.m3u8?X-Plex-Token=\(token)"

        return TranscodeResult(
            url: sessionUrl,
            startUrl: startUrl,
            sessionUrl: sessionUrl,
            sessionId: String(sessionId)
        )
    }

    /// Update playback timeline (progress tracking)
    public func updateTimeline(
        ratingKey: String,
        state: String,
        timeMs: Int,
        durationMs: Int
    ) async throws {
        let params: [String: String] = [
            "ratingKey": ratingKey,
            "key": "/library/metadata/\(ratingKey)",
            "state": state,
            "time": String(timeMs),
            "duration": String(durationMs),
            "X-Plex-Token": token,
            "X-Plex-Client-Identifier": clientId,
            "X-Plex-Product": "Flixor",
            "X-Plex-Device": "macOS"
        ]

        let queryString = params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }.joined(separator: "&")
        let urlString = "\(baseUrl)/:/timeline?\(queryString)"

        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        for (key, value) in getHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }

        _ = try? await URLSession.shared.data(for: request)
    }

    /// Stop transcode session
    public func stopTranscode(sessionId: String) async {
        let urlString = "\(baseUrl)/video/:/transcode/universal/stop?session=\(sessionId)&X-Plex-Token=\(token)"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: - Images

    /// Get image URL with token
    public func getImageUrl(path: String?, width: Int? = nil) -> String? {
        guard let path = path, !path.isEmpty else { return nil }

        // Handle absolute URLs (TMDB images)
        if path.hasPrefix("http") {
            return path
        }

        var urlString = "\(baseUrl)\(path)?X-Plex-Token=\(token)"
        if let width = width {
            urlString += "&width=\(width)"
        }

        return urlString
    }

    // MARK: - UltraBlur Colors

    /// Get UltraBlur colors from an image URL
    /// Returns gradient colors extracted from the image
    public func getUltraBlurColors(imageUrl: String) async throws -> PlexUltraBlurColors? {
        let cacheKey = "ultrablur:\(imageUrl)"

        // Check cache first
        if let cached: PlexUltraBlurColors = await cache.get(cacheKey) {
            return cached
        }

        let encodedUrl = imageUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? imageUrl
        let urlString = "\(baseUrl)/services/ultrablur/colors?url=\(encodedUrl)&X-Plex-Token=\(token)"

        guard let url = URL(string: urlString) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(clientId, forHTTPHeaderField: "X-Plex-Client-Identifier")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }

        let result = try JSONDecoder().decode(PlexUltraBlurResponse.self, from: data)
        let colors = result.MediaContainer.UltraBlurColors?.first

        // Cache the result (24 hours - colors don't change for a given image)
        if let colors = colors {
            await cache.set(cacheKey, value: colors, ttl: CacheTTL.`static`)
        }

        return colors
    }

    /// Get UltraBlur gradient image URL
    public func getUltraBlurImageUrl(colors: PlexUltraBlurColors, noise: Int = 1) -> String {
        return "\(baseUrl)/services/ultrablur/image?topLeft=\(colors.topLeft)&topRight=\(colors.topRight)&bottomRight=\(colors.bottomRight)&bottomLeft=\(colors.bottomLeft)&noise=\(noise)&X-Plex-Token=\(token)"
    }

    // MARK: - Library Filters

    /// Get genres for a library section
    public func getLibraryGenres(key: String) async throws -> [PlexFilterOption] {
        let response: PlexFilterResponse = try await get(
            path: "/library/sections/\(key)/genre",
            ttl: CacheTTL.`static`
        )
        return response.MediaContainer.Directory ?? []
    }

    /// Get years for a library section
    public func getLibraryYears(key: String) async throws -> [PlexFilterOption] {
        let response: PlexFilterResponse = try await get(
            path: "/library/sections/\(key)/year",
            ttl: CacheTTL.`static`
        )
        return response.MediaContainer.Directory ?? []
    }

    // MARK: - Playback Progress

    /// Report playback progress to Plex server
    public func reportProgress(ratingKey: String, time: Int, duration: Int, state: String) async throws {
        var params: [String: String] = [
            "ratingKey": ratingKey,
            "key": "/library/metadata/\(ratingKey)",
            "time": String(time),
            "duration": String(duration),
            "state": state
        ]

        // Map state to Plex timeline state
        let plexState: String
        switch state {
        case "playing": plexState = "playing"
        case "paused": plexState = "paused"
        case "stopped": plexState = "stopped"
        default: plexState = state
        }
        params["state"] = plexState

        // Use timeline endpoint for progress updates
        var urlString = "\(baseUrl)/:/timeline"
        let queryString = params.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        urlString += "?\(queryString)"

        guard let url = URL(string: urlString) else {
            throw PlexServerError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"  // Plex timeline uses GET with query params
        for (key, value) in getHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw PlexServerError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)
        }
    }

    /// Mark item as watched (scrobble)
    public func markWatched(ratingKey: String) async throws {
        let urlString = "\(baseUrl)/:/scrobble?identifier=com.plexapp.plugins.library&key=\(ratingKey)"
        guard let url = URL(string: urlString) else {
            throw PlexServerError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in getHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw PlexServerError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)
        }
    }

    // MARK: - Cache Management

    /// Invalidate cache for this server
    public func invalidateCache() async {
        await cache.invalidatePattern("plex:\(baseUrl):*")
    }
}

// MARK: - Continue Watching Result

public struct ContinueWatchingResult {
    public let items: [PlexMediaItem]
    public let itemsWithMultipleVersions: Set<String>  // ratingKeys that had duplicates across libraries
}

/// Get version string from media info (resolution/HDR/audio)
/// Used for Continue Watching to show which version user was watching
/// e.g., "4K · Dolby Vision · Atmos"
public func getVersionString(_ media: [PlexMedia]?) -> String? {
    guard let media = media, let m = media.first else { return nil }

    var parts: [String] = []

    // Resolution
    if let width = m.width {
        if width >= 3800 { parts.append("4K") }
        else if width >= 1900 { parts.append("1080p") }
        else if width >= 1200 { parts.append("720p") }
    }

    // HDR (from videoProfile)
    if let videoProfile = m.videoProfile?.lowercased() {
        if videoProfile.contains("dolby vision") || videoProfile.contains("dovi") {
            parts.append("Dolby Vision")
        } else if videoProfile.contains("hdr10+") {
            parts.append("HDR10+")
        } else if videoProfile.contains("hdr") {
            parts.append("HDR")
        }
    }

    // Audio
    if let audioChannels = m.audioChannels {
        if audioChannels >= 8 {
            parts.append("Atmos")
        } else if audioChannels >= 6 {
            parts.append("5.1")
        }
    }

    return parts.isEmpty ? nil : parts.joined(separator: " · ")
}

// MARK: - Supporting Models

public struct PlexMediaContainerResponse<T: Codable>: Codable {
    public let MediaContainer: PlexMediaContainer<T>
}

public struct PlexMediaContainer<T: Codable>: Codable {
    public let size: Int?
    public let totalSize: Int?
    public let offset: Int?
    public let Metadata: [T]?
    public let Directory: [T]?
}

public struct PlexLibrary: Codable, Identifiable {
    public let key: String
    public let title: String
    public let type: String
    public let uuid: String?
    public let agent: String?
    public let scanner: String?

    public var id: String { key }
}

public struct PlexFilterResponse: Codable {
    public let MediaContainer: PlexFilterContainer
}

public struct PlexFilterContainer: Codable {
    public let size: Int?
    public let Directory: [PlexFilterOption]?
}

public struct PlexFilterOption: Codable, Identifiable {
    public let key: String
    public let title: String
    public let fastKey: String?

    public var id: String { key }
}

public struct PlexLibraryItemsResult {
    public let items: [PlexMediaItem]
    public let size: Int
    public let totalSize: Int
    public let offset: Int
}

public struct PlexMediaItem: Codable, Identifiable {
    public let ratingKey: String?
    public let key: String?
    public let type: String?
    public let title: String?
    public let summary: String?
    public let year: Int?
    public let thumb: String?
    public let art: String?
    public let duration: Int?
    public let viewOffset: Int?
    public let viewCount: Int?
    public let contentRating: String?
    public let originallyAvailableAt: String?

    // Ratings from Plex (IMDb, Rotten Tomatoes)
    public let Rating: [PlexRatingEntry]?
    public let rating: Double?           // IMDb rating (fallback)
    public let audienceRating: Double?   // RT Audience rating (fallback)

    // TV specific
    public let grandparentTitle: String?
    public let grandparentThumb: String?
    public let grandparentArt: String?
    public let grandparentRatingKey: String?
    public let parentTitle: String?
    public let parentRatingKey: String?
    public let parentIndex: Int?
    public let index: Int?
    public let leafCount: Int?
    public let viewedLeafCount: Int?

    // Media/Parts (for playback)
    public let Media: [PlexMedia]?
    public let Guid: [PlexGuid]?
    public let Genre: [PlexTag]?
    public let Role: [PlexRole]?
    public let Marker: [PlexMarker]?
    public let Collection: [PlexTag]?
    public let studio: String?

    public var id: String { ratingKey ?? key ?? UUID().uuidString }

    public var guids: [String] {
        (Guid ?? []).compactMap { $0.id }
    }

    public var genres: [PlexTag] {
        Genre ?? []
    }

    public var roles: [PlexRole] {
        Role ?? []
    }

    public var media: [PlexMedia] {
        Media ?? []
    }

    public var ratings: [PlexRatingEntry] {
        Rating ?? []
    }

    public var collections: [PlexTag] {
        Collection ?? []
    }
}

public struct PlexRatingEntry: Codable {
    public let image: String?
    public let value: Double?
    public let type: String?
}

public struct PlexMedia: Codable {
    public let id: String?  // Can be Int or String from different Plex APIs
    public let duration: Int?
    public let bitrate: Int?
    public let width: Int?
    public let height: Int?
    public let aspectRatio: Double?
    public let videoCodec: String?
    public let videoProfile: String?
    public let audioCodec: String?
    public let audioProfile: String?
    public let audioChannels: Int?
    public let container: String?
    public let editionTitle: String?  // e.g., "Theatrical Cut", "Director's Cut"
    public let Part: [PlexPart]?

    // Custom decoder to handle both Int and String for id
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let stringId = try? container.decode(String.self, forKey: .id) {
            id = stringId
        } else if let intId = try? container.decode(Int.self, forKey: .id) {
            id = String(intId)
        } else {
            id = nil
        }

        duration = try container.decodeIfPresent(Int.self, forKey: .duration)
        bitrate = try container.decodeIfPresent(Int.self, forKey: .bitrate)
        width = try container.decodeIfPresent(Int.self, forKey: .width)
        height = try container.decodeIfPresent(Int.self, forKey: .height)
        aspectRatio = try container.decodeIfPresent(Double.self, forKey: .aspectRatio)
        videoCodec = try container.decodeIfPresent(String.self, forKey: .videoCodec)
        videoProfile = try container.decodeIfPresent(String.self, forKey: .videoProfile)
        audioCodec = try container.decodeIfPresent(String.self, forKey: .audioCodec)
        audioProfile = try container.decodeIfPresent(String.self, forKey: .audioProfile)
        audioChannels = try container.decodeIfPresent(Int.self, forKey: .audioChannels)
        self.container = try container.decodeIfPresent(String.self, forKey: .container)
        editionTitle = try container.decodeIfPresent(String.self, forKey: .editionTitle)
        Part = try container.decodeIfPresent([PlexPart].self, forKey: .Part)
    }

    enum CodingKeys: String, CodingKey {
        case id, duration, bitrate, width, height, aspectRatio
        case videoCodec, videoProfile, audioCodec, audioProfile, audioChannels
        case container, editionTitle, Part
    }

    public var parts: [PlexPart] {
        Part ?? []
    }
}

public struct PlexPart: Codable {
    public let id: String?  // Can be Int or String from different Plex APIs
    public let key: String?
    public let duration: Int?
    public let file: String?
    public let size: Int?
    public let container: String?
    public let Stream: [PlexStream]?

    // Custom decoder to handle both Int and String for id
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Try String first, then Int
        if let stringId = try? container.decode(String.self, forKey: .id) {
            id = stringId
        } else if let intId = try? container.decode(Int.self, forKey: .id) {
            id = String(intId)
        } else {
            id = nil
        }

        key = try container.decodeIfPresent(String.self, forKey: .key)
        duration = try container.decodeIfPresent(Int.self, forKey: .duration)
        file = try container.decodeIfPresent(String.self, forKey: .file)
        size = try container.decodeIfPresent(Int.self, forKey: .size)
        self.container = try container.decodeIfPresent(String.self, forKey: .container)
        Stream = try container.decodeIfPresent([PlexStream].self, forKey: .Stream)
    }

    enum CodingKeys: String, CodingKey {
        case id, key, duration, file, size, container, Stream
    }
}

public struct PlexStream: Codable {
    public let id: String?  // Can be Int or String from different Plex APIs
    public let streamType: Int?
    public let displayTitle: String?
    public let language: String?
    public let languageTag: String?
    public let codec: String?

    // Custom decoder to handle both Int and String for id
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let stringId = try? container.decode(String.self, forKey: .id) {
            id = stringId
        } else if let intId = try? container.decode(Int.self, forKey: .id) {
            id = String(intId)
        } else {
            id = nil
        }

        streamType = try container.decodeIfPresent(Int.self, forKey: .streamType)
        displayTitle = try container.decodeIfPresent(String.self, forKey: .displayTitle)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        languageTag = try container.decodeIfPresent(String.self, forKey: .languageTag)
        codec = try container.decodeIfPresent(String.self, forKey: .codec)
    }

    enum CodingKeys: String, CodingKey {
        case id, streamType, displayTitle, language, languageTag, codec
    }
}

public struct PlexGuid: Codable {
    public let id: String?
}

public struct PlexTag: Codable {
    public let tag: String
}

public struct PlexRole: Codable {
    public let tag: String
    public let thumb: String?
}

public struct PlexMarker: Codable {
    public let id: String?
    public let type: String?
    public let startTimeOffset: Int?
    public let endTimeOffset: Int?
}

public struct TranscodeOptions {
    public let maxVideoBitrate: Int
    public let videoResolution: String
    public let `protocol`: String
    public let sessionId: String?
    public let directStream: Bool

    public init(
        maxVideoBitrate: Int = 20000,
        videoResolution: String = "1920x1080",
        protocol: String = "hls",
        sessionId: String? = nil,
        directStream: Bool = false
    ) {
        self.maxVideoBitrate = maxVideoBitrate
        self.videoResolution = videoResolution
        self.protocol = `protocol`
        self.sessionId = sessionId
        self.directStream = directStream
    }
}

public struct TranscodeResult {
    public let url: String
    public let startUrl: String
    public let sessionUrl: String
    public let sessionId: String
}

// MARK: - UltraBlur Models

public struct PlexUltraBlurColors: Codable {
    public let topLeft: String
    public let topRight: String
    public let bottomRight: String
    public let bottomLeft: String
}

public struct PlexUltraBlurResponse: Codable {
    public let MediaContainer: PlexUltraBlurMediaContainer
}

public struct PlexUltraBlurMediaContainer: Codable {
    public let UltraBlurColors: [PlexUltraBlurColors]?
}

// MARK: - Errors

public enum PlexServerError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case notFound

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .notFound:
            return "Item not found"
        }
    }
}
