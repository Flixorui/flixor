//
//  StremioService.swift
//  FlixorMac
//
//  Native Stremio addon, streams, and subtitles service for macOS.
//

import AppKit
import Foundation

struct StremioError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

actor StremioService {
    static let shared = StremioService()

    private let storage = StremioStorage.shared
    private let logger = AppLogger.shared
    private var initialized = false
    private var addons: [String: StremioAddonManifest] = [:]
    private var order: [String] = []

    private struct RequestConfig {
        let timeout: TimeInterval
        let accept: String
    }

    private struct ManifestPayload {
        let id: String
        let name: String
        let version: String
        let description: String?
        let resources: [StremioResourceObject]
        let types: [String]?
        let idPrefixes: [String]?
        let behaviorHints: StremioAddonBehaviorHints?
        let config: [StremioAddonConfigOption]?
        let catalogs: [StremioCatalogDefinition]
    }

    /// A catalog paired with the addon that serves it.
    struct InstalledCatalog: Identifiable {
        let addonId: String
        let addonName: String
        let installationId: String
        let catalog: StremioCatalogDefinition

        var id: String { "\(installationId):\(catalog.id)" }
    }

    func ensureInitialized(installDefaults: Bool = false) async {
        if !initialized {
            let persistedAddons = await storage.installedAddons()
            let persistedOrder = await storage.addonOrder()
            addons = Dictionary(uniqueKeysWithValues: persistedAddons.map { ($0.installationId, $0) })
            order = persistedOrder.filter { addons[$0] != nil }
            let missingOrder = persistedAddons.map(\.installationId).filter { !order.contains($0) }
            order.append(contentsOf: missingOrder)
            initialized = true
        }

        if installDefaults {
            await ensureDefaultAddons()
        } else {
            await persist()
        }
    }

    func getInstalledAddons() async -> [StremioAddonManifest] {
        await ensureInitialized()
        return order.compactMap { addons[$0] }
    }

    func getAddonSummary() async -> [StremioAddonSummary] {
        let installed = await getInstalledAddons()
        return installed.map { addon in
            StremioAddonSummary(
                addonId: addon.id,
                installationId: addon.installationId,
                name: addon.name,
                manifestURL: addon.originalURL,
                configureURL: getAddonConfigureURL(for: addon)?.absoluteString,
                streamCapable: addonProvidesStreams(addon),
                subtitleCapable: addonProvidesSubtitles(addon),
                catalogCapable: !(addon.catalogs ?? []).isEmpty,
                configurationRequired: addon.behaviorHints?.configurationRequired ?? false
            )
        }
    }

    // MARK: - Catalogs

    /// Catalogs from installed addons that can be listed without user input.
    /// Ordered by addon priority, matching the stream-provider ordering.
    func getBrowsableCatalogs() async -> [InstalledCatalog] {
        let installed = await getInstalledAddons()
        return installed.flatMap { addon in
            (addon.catalogs ?? [])
                .filter { $0.isBrowsable && addonSupportsResource(addon, resourceName: "catalog", catalogType: $0.type) }
                .map {
                    InstalledCatalog(
                        addonId: addon.id,
                        addonName: addon.name,
                        installationId: addon.installationId,
                        catalog: $0
                    )
                }
        }
    }

    func hasCatalogProviders() async -> Bool {
        !(await getBrowsableCatalogs()).isEmpty
    }

    /// Fetches one catalog page. `extras` become the `/key=value` path segments the
    /// addon protocol uses (e.g. `skip=100`, `genre=Comedy`, `search=dune`).
    func getCatalog(
        installationId: String,
        type: String,
        catalogId: String,
        extras: [String: String] = [:],
        limit: Int = 30
    ) async -> [StremioMetaPreview] {
        (try? await fetchCatalog(installationId: installationId, type: type, catalogId: catalogId, extras: extras, limit: limit)) ?? []
    }

    /// Same as `getCatalog`, but throws when the addon request fails, so callers
    /// can tell a failing addon from an empty catalog.
    func fetchCatalog(
        installationId: String,
        type: String,
        catalogId: String,
        extras: [String: String] = [:],
        limit: Int = 30
    ) async throws -> [StremioMetaPreview] {
        await ensureInitialized()
        guard let addon = addons[installationId], let baseURL = addon.url else { return [] }

        var resourcePath = "/catalog/\(type)/\(encodePathSegment(catalogId))"
        // Sorted so the same request always produces the same URL (cache-friendly).
        for key in extras.keys.sorted() {
            guard let value = extras[key] else { continue }
            resourcePath += "/\(encodePathSegment(key))=\(encodePathSegment(value))"
        }
        resourcePath += ".json"

        guard let requestURL = URL(string: buildResourceURL(baseURL: baseURL, resourcePath: resourcePath)) else {
            return []
        }

        do {
            let data = try await requestData(from: requestURL, config: RequestConfig(timeout: 20, accept: "application/json"))
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let metas = json?["metas"] as? [[String: Any]] ?? []
            return metas.prefix(limit).compactMap(parseMetaPreview)
        } catch {
            logger.warn("[Stremio] Catalog request failed", data: [
                "addonId": addon.id,
                "catalog": "\(type):\(catalogId)",
                "error": error.localizedDescription,
            ])
            throw error
        }
    }

    /// Runs the query against every search-capable catalog, de-duplicating by meta id.
    func searchCatalogs(query: String, limit: Int = 20) async -> [StremioMetaPreview] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        await ensureInitialized()
        let installed = await getInstalledAddons()
        let searchable: [InstalledCatalog] = installed.flatMap { addon in
            (addon.catalogs ?? [])
                .filter { $0.supportsSearch && addonSupportsResource(addon, resourceName: "catalog", catalogType: $0.type) }
                .map {
                    InstalledCatalog(
                        addonId: addon.id,
                        addonName: addon.name,
                        installationId: addon.installationId,
                        catalog: $0
                    )
                }
        }
        guard !searchable.isEmpty else { return [] }

        var results: [[StremioMetaPreview]] = []
        await withTaskGroup(of: [StremioMetaPreview].self) { group in
            for entry in searchable {
                group.addTask {
                    await self.getCatalog(
                        installationId: entry.installationId,
                        type: entry.catalog.type,
                        catalogId: entry.catalog.catalogId,
                        extras: ["search": trimmed],
                        limit: limit
                    )
                }
            }
            for await page in group {
                results.append(page)
            }
        }

        var seen = Set<String>()
        return results.flatMap { $0 }.filter { seen.insert($0.id).inserted }
    }

    // MARK: - Meta

    /// Full metadata for one title, including the episode list for series.
    /// Tries each meta-capable addon in priority order and returns the first hit.
    func getMeta(type: String, id: String) async -> StremioMetaDetail? {
        await ensureInitialized()
        let installed = await getInstalledAddons()

        for addon in installed {
            guard addonSupportsResource(addon, resourceName: "meta", catalogType: type, contentId: id),
                  let baseURL = addon.url else { continue }

            let resourcePath = "/meta/\(type)/\(encodePathSegment(id)).json"
            guard let requestURL = URL(string: buildResourceURL(baseURL: baseURL, resourcePath: resourcePath)) else {
                continue
            }

            do {
                let data = try await requestData(from: requestURL, config: RequestConfig(timeout: 20, accept: "application/json"))
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                if let raw = json?["meta"] as? [String: Any], let detail = parseMetaDetail(raw) {
                    return detail
                }
            } catch {
                logger.warn("[Stremio] Meta request failed", data: [
                    "addonId": addon.id,
                    "type": type,
                    "id": id,
                    "error": error.localizedDescription,
                ])
            }
        }
        return nil
    }

    func hasStreamProviders(requestType: StremioRequestType? = nil) async -> Bool {
        let installed = await getInstalledAddons()
        return installed.contains { addon in
            if let requestType {
                return addonSupportsResource(addon, resourceName: "stream", requestType: requestType, contentId: nil)
            }
            return addonProvidesStreams(addon)
        }
    }

    func installAddon(from url: String, suppressRemovedDefaultCleanup: Bool = false) async throws -> StremioAddonManifest {
        await ensureInitialized()

        let manifestURL = normalizeStremioManifestURL(url)
        guard !manifestURL.isEmpty else {
            throw StremioError(message: "Manifest URL is required")
        }

        logger.info("[Stremio] Installing addon", data: ["manifestUrl": manifestURL])

        do {
            let manifest = try await getManifest(from: manifestURL)
            let existing = addons.values.filter { $0.id == manifest.id }
            if !existing.isEmpty && !addonProvidesStreams(manifest) {
                throw StremioError(message: "This addon is already installed. Multiple installs are only allowed for stream providers.")
            }

            addons[manifest.installationId] = manifest
            if !order.contains(manifest.installationId) {
                order.append(manifest.installationId)
            }

            if !suppressRemovedDefaultCleanup {
                var removed = await storage.removedDefaultAddons()
                if removed.contains(manifest.id) {
                    removed.removeAll { $0 == manifest.id }
                    await storage.setRemovedDefaultAddons(removed)
                }
            }

            await persist()
            logger.info("[Stremio] Installed addon", data: [
                "id": manifest.id,
                "installationId": manifest.installationId,
                "name": manifest.name,
                "manifestUrl": manifest.originalURL ?? manifestURL,
            ])
            return manifest
        } catch {
            let message = error.localizedDescription
            logger.error("[Stremio] Failed to install addon", data: [
                "manifestUrl": manifestURL,
                "error": message,
            ])
            throw StremioError(message: message)
        }
    }

    func removeAddon(installationId: String) async {
        await ensureInitialized()
        guard let addon = addons[installationId] else { return }

        addons.removeValue(forKey: installationId)
        order.removeAll { $0 == installationId }

        let hasSameAddonRemaining = addons.values.contains { $0.id == addon.id }
        if !hasSameAddonRemaining && addon.id == STREMIO_DEFAULT_OPEN_SUBTITLES_ID {
            var removed = await storage.removedDefaultAddons()
            if !removed.contains(addon.id) {
                removed.append(addon.id)
                await storage.setRemovedDefaultAddons(removed)
            }
        }

        await persist()
        logger.info("[Stremio] Removed addon", data: [
            "id": addon.id,
            "installationId": installationId,
            "name": addon.name,
        ])
    }

    func moveAddons(fromOffsets: IndexSet, toOffset: Int) async {
        await ensureInitialized()
        let moving = fromOffsets.sorted().map { order[$0] }
        order.remove(atOffsets: fromOffsets)
        let insertionIndex = min(max(0, toOffset), order.count)
        order.insert(contentsOf: moving, at: insertionIndex)
        await persist()
    }

    func getAddonConfigureURL(for addon: StremioAddonManifest) -> URL? {
        if let explicit = addon.behaviorHints?.configurationURL, let url = URL(string: explicit) {
            return url
        }

        guard let sourceURL = addon.transportURL ?? addon.originalURL ?? addon.url else {
            return nil
        }
        let normalized = normalizeStremioManifestURL(sourceURL)
        guard !normalized.isEmpty else { return nil }
        return URL(string: normalized.replacingOccurrences(of: "manifest.json", with: "configure"))
    }

    func openAddonConfigureURL(for addon: StremioAddonManifest) {
        guard let url = getAddonConfigureURL(for: addon) else { return }
        NSWorkspace.shared.open(url)
    }

    func canResolveId(requestType: StremioRequestType, contentId: String) async -> Bool {
        let installed = await getInstalledAddons()
        let strictMatches = installed.filter {
            addonSupportsResource($0, resourceName: "stream", requestType: requestType, contentId: contentId)
        }
        if !strictMatches.isEmpty {
            return true
        }

        return installed.contains { addon in
            guard addonSupportsResource(addon, resourceName: "stream", requestType: requestType, contentId: nil) else {
                return false
            }
            let resources = addon.resources ?? []
            let streamResources = resources.filter { $0.name == "stream" }
            return streamResources.contains { ($0.idPrefixes ?? addon.idPrefixes ?? []).isEmpty }
        }
    }

    func getStreams(identity: StremioContentIdentity) async -> [StremioAddonStreamResult] {
        await ensureInitialized()
        let requestType = StremioRequestType(rawValue: identity.requestType) ?? .movie
        let installed = await getInstalledAddons()
        let streamAddons = installed.filter {
            addonSupportsResource($0, resourceName: "stream", requestType: requestType, contentId: identity.requestId)
        }

        if streamAddons.isEmpty {
            return []
        }

        return await withTaskGroup(of: StremioAddonStreamResult.self) { group in
            for addon in streamAddons {
                group.addTask {
                    await self.fetchStreams(for: addon, identity: identity)
                }
            }

            var results: [StremioAddonStreamResult] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { lhs, rhs in
                self.order.firstIndex(of: lhs.installationId) ?? .max < self.order.firstIndex(of: rhs.installationId) ?? .max
            }
        }
    }

    func getSubtitles(identity: StremioContentIdentity) async -> [StremioSubtitleCandidate] {
        await ensureInitialized()
        let requestType = StremioRequestType(rawValue: identity.requestType) ?? .movie
        let installed = await getInstalledAddons()
        let subtitleAddons = installed.filter {
            addonSupportsResource($0, resourceName: "subtitles", requestType: requestType, contentId: identity.requestId)
        }
        if subtitleAddons.isEmpty {
            return []
        }

        let requestId: String
        if requestType == .series, let season = identity.seasonNumber, let episode = identity.episodeNumber {
            requestId = "\(identity.baseId):\(season):\(episode)"
        } else {
            requestId = identity.requestId
        }

        var deduped: [String: StremioSubtitleCandidate] = [:]
        await withTaskGroup(of: [StremioSubtitleCandidate].self) { group in
            for addon in subtitleAddons {
                group.addTask {
                    await self.fetchSubtitles(for: addon, requestType: requestType, requestId: requestId)
                }
            }

            for await subtitles in group {
                for subtitle in subtitles where deduped[subtitle.url] == nil {
                    deduped[subtitle.url] = subtitle
                }
            }
        }
        return Array(deduped.values)
    }

    // MARK: - Private

    private func ensureDefaultAddons() async {
        let removedDefaults = await storage.removedDefaultAddons()
        if removedDefaults.contains(STREMIO_DEFAULT_OPEN_SUBTITLES_ID) {
            await persist()
            return
        }

        if addons.values.contains(where: { $0.id == STREMIO_DEFAULT_OPEN_SUBTITLES_ID }) {
            await persist()
            return
        }

        do {
            _ = try await installAddon(from: STREMIO_DEFAULT_OPEN_SUBTITLES_URL, suppressRemovedDefaultCleanup: true)
        } catch {
            logger.warn("[Stremio] Failed to install default OpenSubtitles addon", data: [
                "manifestUrl": STREMIO_DEFAULT_OPEN_SUBTITLES_URL,
                "error": error.localizedDescription,
            ])
        }
    }

    private func persist() async {
        let ordered = order.compactMap { addons[$0] }
        let trailing = addons.values.filter { !order.contains($0.installationId) }
        let nextAddons = ordered + trailing.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let nextOrder = nextAddons.map(\.installationId)
        order = nextOrder
        await storage.setInstalledAddons(nextAddons)
        await storage.setAddonOrder(nextOrder)
    }

    private func getManifest(from url: String) async throws -> StremioAddonManifest {
        let normalizedURL = normalizeStremioManifestURL(url)
        guard let requestURL = URL(string: normalizedURL) else {
            throw StremioError(message: "Invalid manifest URL")
        }

        let data = try await requestData(from: requestURL, config: RequestConfig(timeout: 60, accept: "application/json"))
        let payload = try parseManifestPayload(data: data)

        return StremioAddonManifest(
            id: payload.id,
            installationId: generateInstallationId(addonId: payload.id),
            name: payload.name,
            version: payload.version,
            description: payload.description,
            url: normalizedURL.replacingOccurrences(of: "/manifest.json", with: ""),
            originalURL: normalizedURL,
            transportURL: normalizedURL,
            resources: payload.resources,
            types: payload.types,
            idPrefixes: payload.idPrefixes,
            behaviorHints: payload.behaviorHints,
            config: payload.config,
            catalogs: payload.catalogs.isEmpty ? nil : payload.catalogs
        )
    }

    private func fetchStreams(for addon: StremioAddonManifest, identity: StremioContentIdentity) async -> StremioAddonStreamResult {
        guard let baseURL = addon.url else {
            return StremioAddonStreamResult(addonId: addon.id, addonName: addon.name, installationId: addon.installationId, streams: [], error: "Addon has no transport URL")
        }

        do {
            logger.info("[Stremio] Fetching streams", data: [
                "addonId": addon.id,
                "installationId": addon.installationId,
                "requestType": identity.requestType,
                "requestId": identity.requestId,
            ])

            let requestType = identity.requestType
            let resourcePath = "/stream/\(requestType)/\(identity.requestId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? identity.requestId).json"
            guard let requestURL = URL(string: buildResourceURL(baseURL: baseURL, resourcePath: resourcePath)) else {
                return StremioAddonStreamResult(addonId: addon.id, addonName: addon.name, installationId: addon.installationId, streams: [], error: "Invalid stream request URL")
            }

            let data = try await requestData(from: requestURL, config: RequestConfig(timeout: 60, accept: "application/json"))
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let rawStreams = json?["streams"] as? [[String: Any]] ?? []
            let normalized = rawStreams.enumerated().compactMap { index, raw in
                normalizeStream(addon: addon, stream: raw, streamIndex: index)
            }

            return StremioAddonStreamResult(
                addonId: addon.id,
                addonName: addon.name,
                installationId: addon.installationId,
                streams: normalized,
                error: nil
            )
        } catch {
            logger.warn("[Stremio] Stream request failed", data: [
                "addonId": addon.id,
                "installationId": addon.installationId,
                "error": error.localizedDescription,
            ])
            return StremioAddonStreamResult(
                addonId: addon.id,
                addonName: addon.name,
                installationId: addon.installationId,
                streams: [],
                error: error.localizedDescription
            )
        }
    }

    private func fetchSubtitles(for addon: StremioAddonManifest, requestType: StremioRequestType, requestId: String) async -> [StremioSubtitleCandidate] {
        guard let baseURL = addon.url else { return [] }

        do {
            let resourcePath = "/subtitles/\(requestType.rawValue)/\(requestId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? requestId).json"
            guard let requestURL = URL(string: buildResourceURL(baseURL: baseURL, resourcePath: resourcePath)) else {
                return []
            }
            let data = try await requestData(from: requestURL, config: RequestConfig(timeout: 10, accept: "application/json"))
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let rawSubtitles = json?["subtitles"] as? [[String: Any]] ?? []
            return rawSubtitles.enumerated().compactMap { index, raw in
                guard let url = raw["url"] as? String else { return nil }
                let id = (raw["id"] as? String) ?? "\(addon.id)-\(index)"
                let lang = (raw["lang"] as? String) ?? (raw["language"] as? String) ?? "unknown"
                return StremioSubtitleCandidate(
                    id: id,
                    url: url,
                    lang: lang,
                    format: raw["format"] as? String,
                    addonId: addon.id,
                    addonName: addon.name
                )
            }
        } catch {
            logger.warn("[Stremio] Subtitle request failed", data: [
                "addonId": addon.id,
                "installationId": addon.installationId,
                "error": error.localizedDescription,
            ])
            return []
        }
    }

    private func requestData(from url: URL, config: RequestConfig) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = config.timeout
        request.setValue(config.accept, forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return data
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                let responseText = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let summary = String(responseText.prefix(240))
                if summary.isEmpty {
                    throw StremioError(message: "HTTP \(httpResponse.statusCode) from \(url.absoluteString)")
                }
                throw StremioError(message: "HTTP \(httpResponse.statusCode) from \(url.absoluteString): \(summary)")
            }
            return data
        } catch let error as StremioError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw StremioError(message: "Request timed out while fetching \(url.absoluteString)")
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost:
                throw StremioError(message: "Network error while fetching \(url.absoluteString)")
            default:
                throw StremioError(message: error.localizedDescription)
            }
        } catch {
            throw StremioError(message: error.localizedDescription)
        }
    }

    private func parseManifestPayload(data: Data) throws -> ManifestPayload {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StremioError(message: "Invalid addon manifest response")
        }

        let id = (json["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (json["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = (json["version"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let finalId = id, !finalId.isEmpty else {
            throw StremioError(message: "Addon manifest is missing an id")
        }
        guard let finalName = name, !finalName.isEmpty else {
            throw StremioError(message: "Addon manifest is missing a name")
        }
        guard let finalVersion = version, !finalVersion.isEmpty else {
            throw StremioError(message: "Addon manifest is missing a version")
        }

        let normalizedResources = normalizeResources(json["resources"])
        let behaviorHints = parseBehaviorHints(json["behaviorHints"] as? [String: Any])
        let config = parseConfig(json["config"] as? [[String: Any]])
        let catalogs = parseCatalogs(json["catalogs"] as? [[String: Any]])

        return ManifestPayload(
            id: finalId,
            name: finalName,
            version: finalVersion,
            description: json["description"] as? String,
            resources: normalizedResources,
            types: json["types"] as? [String],
            idPrefixes: json["idPrefixes"] as? [String],
            behaviorHints: behaviorHints,
            config: config,
            catalogs: catalogs
        )
    }

    private func parseCatalogs(_ rawValue: [[String: Any]]?) -> [StremioCatalogDefinition] {
        guard let rawValue else { return [] }
        return rawValue.compactMap { item in
            guard let type = item["type"] as? String,
                  let catalogId = item["id"] as? String else {
                return nil
            }
            return StremioCatalogDefinition(
                type: type,
                catalogId: catalogId,
                name: item["name"] as? String,
                extra: parseCatalogExtras(item)
            )
        }
    }

    /// Handles both the modern `extra` array and the legacy
    /// `extraRequired`/`extraSupported` string arrays.
    private func parseCatalogExtras(_ item: [String: Any]) -> [StremioCatalogExtra]? {
        if let extras = item["extra"] as? [[String: Any]] {
            let parsed = extras.compactMap { raw -> StremioCatalogExtra? in
                guard let name = raw["name"] as? String else { return nil }
                return StremioCatalogExtra(
                    name: name,
                    isRequired: (raw["isRequired"] as? Bool) ?? false,
                    options: raw["options"] as? [String],
                    optionsLimit: raw["optionsLimit"] as? Int
                )
            }
            return parsed.isEmpty ? nil : parsed
        }

        let required = Set(item["extraRequired"] as? [String] ?? [])
        let supported = item["extraSupported"] as? [String] ?? []
        let names = supported.isEmpty ? Array(required) : supported
        guard !names.isEmpty else { return nil }

        return names.map {
            StremioCatalogExtra(
                name: $0,
                isRequired: required.contains($0),
                options: nil,
                optionsLimit: nil
            )
        }
    }

    private func normalizeResources(_ rawValue: Any?) -> [StremioResourceObject] {
        guard let resources = rawValue as? [Any] else { return [] }
        return resources.compactMap { resource in
            if let name = resource as? String {
                return StremioResourceObject(name: name, types: nil, idPrefixes: nil)
            }
            guard let object = resource as? [String: Any], let name = object["name"] as? String else {
                return nil
            }
            let types = object["types"] as? [String]
            let idPrefixes = (object["idPrefixes"] as? [String]) ?? (object["idPrefix"] as? [String])
            return StremioResourceObject(name: name, types: types, idPrefixes: idPrefixes)
        }
    }

    private func parseBehaviorHints(_ rawValue: [String: Any]?) -> StremioAddonBehaviorHints? {
        guard let rawValue else { return nil }
        return StremioAddonBehaviorHints(
            configurable: rawValue["configurable"] as? Bool,
            configurationRequired: rawValue["configurationRequired"] as? Bool,
            configurationURL: rawValue["configurationURL"] as? String,
            adult: rawValue["adult"] as? Bool,
            p2p: rawValue["p2p"] as? Bool
        )
    }

    private func parseConfig(_ rawValue: [[String: Any]]?) -> [StremioAddonConfigOption]? {
        guard let rawValue else { return nil }
        return rawValue.compactMap { item in
            guard let key = item["key"] as? String,
                  let type = item["type"] as? String else {
                return nil
            }
            return StremioAddonConfigOption(
                key: key,
                type: type,
                defaultValue: item["default"] as? String,
                title: item["title"] as? String,
                options: item["options"] as? [String],
                required: item["required"] as? Bool
            )
        }
    }

    private func buildResourceURL(baseURL: String, resourcePath: String) -> String {
        let parts = baseURL.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let sanitizedBase = parts[0].replacingOccurrences(of: "manifest.json", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if parts.count > 1 {
            return "\(sanitizedBase)\(resourcePath)?\(parts[1])"
        }
        return "\(sanitizedBase)\(resourcePath)"
    }

    private func addonProvidesStreams(_ addon: StremioAddonManifest) -> Bool {
        addonSupportsResource(addon, resourceName: "stream", requestType: .movie, contentId: nil)
            || addonSupportsResource(addon, resourceName: "stream", requestType: .series, contentId: nil)
    }

    private func addonProvidesSubtitles(_ addon: StremioAddonManifest) -> Bool {
        addonSupportsResource(addon, resourceName: "subtitles", requestType: .movie, contentId: nil)
            || addonSupportsResource(addon, resourceName: "subtitles", requestType: .series, contentId: nil)
    }

    private func addonSupportsResource(
        _ addon: StremioAddonManifest,
        resourceName: String,
        requestType: StremioRequestType,
        contentId: String?
    ) -> Bool {
        addonSupportsResource(
            addon,
            resourceName: resourceName,
            catalogType: requestType.rawValue,
            contentId: contentId
        )
    }

    /// Same check keyed by a raw Stremio type string, since catalogs and meta use
    /// types beyond movie/series.
    private func addonSupportsResource(
        _ addon: StremioAddonManifest,
        resourceName: String,
        catalogType: String,
        contentId: String? = nil
    ) -> Bool {
        let resources = addon.resources ?? []
        guard let resource = resources.first(where: { $0.name == resourceName }) else {
            return false
        }

        let supportedTypes = resource.types ?? addon.types ?? []
        if !supportedTypes.isEmpty && !supportedTypes.contains(catalogType) {
            return false
        }

        let idPrefixes = resource.idPrefixes ?? addon.idPrefixes ?? []
        if idPrefixes.isEmpty || contentId == nil {
            return true
        }

        return idPrefixes.contains { contentId?.hasPrefix($0) == true }
    }

    private func encodePathSegment(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private func parseMetaPreview(_ raw: [String: Any]) -> StremioMetaPreview? {
        guard let id = raw["id"] as? String,
              let type = raw["type"] as? String,
              let name = raw["name"] as? String else {
            return nil
        }
        return StremioMetaPreview(
            id: id,
            type: type,
            name: name,
            poster: raw["poster"] as? String,
            background: raw["background"] as? String,
            description: raw["description"] as? String,
            releaseInfo: stringValue(raw["releaseInfo"]),
            imdbRating: stringValue(raw["imdbRating"])
        )
    }

    private func parseMetaDetail(_ raw: [String: Any]) -> StremioMetaDetail? {
        guard let id = raw["id"] as? String,
              let type = raw["type"] as? String,
              let name = raw["name"] as? String else {
            return nil
        }

        let videos = (raw["videos"] as? [[String: Any]])?.compactMap { video -> StremioMetaVideo? in
            guard let videoId = video["id"] as? String else { return nil }
            return StremioMetaVideo(
                id: videoId,
                title: (video["title"] as? String) ?? (video["name"] as? String),
                season: video["season"] as? Int,
                episode: (video["episode"] as? Int) ?? (video["number"] as? Int),
                released: stringValue(video["released"]),
                thumbnail: video["thumbnail"] as? String,
                overview: (video["overview"] as? String) ?? (video["description"] as? String)
            )
        }

        return StremioMetaDetail(
            id: id,
            type: type,
            name: name,
            poster: raw["poster"] as? String,
            background: raw["background"] as? String,
            description: raw["description"] as? String,
            releaseInfo: stringValue(raw["releaseInfo"]),
            imdbRating: stringValue(raw["imdbRating"]),
            genres: (raw["genres"] as? [String]) ?? (raw["genre"] as? [String]),
            videos: videos
        )
    }

    /// Addons are inconsistent about whether these fields are strings or numbers.
    private func stringValue(_ raw: Any?) -> String? {
        switch raw {
        case let value as String: return value
        case let value as Int: return String(value)
        case let value as Double: return String(value)
        default: return nil
        }
    }

    private func generateInstallationId(addonId: String) -> String {
        "\(addonId)-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(6))"
    }

    private func normalizeStream(addon: StremioAddonManifest, stream: [String: Any], streamIndex: Int) -> StremioPlayableStream? {
        let sourceType = detectSourceType(stream)
        if sourceType == .unknown {
            return nil
        }

        let playableURL = stream["url"] as? String
        let isPlayableURL = sourceType == .url && (playableURL?.lowercased().hasPrefix("http://") == true || playableURL?.lowercased().hasPrefix("https://") == true)
        let disabledReason: String?
        if sourceType == .url, playableURL != nil, !isPlayableURL {
            disabledReason = "Only HTTP(S) direct streams are supported in-app"
        } else if isPlayableURL {
            disabledReason = nil
        } else {
            disabledReason = unsupportedReason(for: sourceType)
        }

        let rawSubtitles = stream["subtitles"] as? [[String: Any]] ?? []
        let subtitles = rawSubtitles.enumerated().compactMap { subtitleIndex, rawSubtitle -> StremioSubtitleCandidate? in
            guard let url = rawSubtitle["url"] as? String else { return nil }
            return StremioSubtitleCandidate(
                id: (rawSubtitle["id"] as? String) ?? "\(addon.id)-\(subtitleIndex)",
                url: url,
                lang: (rawSubtitle["lang"] as? String) ?? (rawSubtitle["language"] as? String) ?? "unknown",
                format: rawSubtitle["format"] as? String,
                addonId: addon.id,
                addonName: addon.name
            )
        }

        let behaviorHints = parseStreamBehaviorHints(stream["behaviorHints"] as? [String: Any])
        let videoSize = behaviorHints?.videoSize ?? (stream["size"] as? Int)

        return StremioPlayableStream(
            id: "\(addon.installationId)-\(streamIndex)",
            url: playableURL,
            externalUrl: stream["externalUrl"] as? String,
            ytId: stream["ytId"] as? String,
            infoHash: stream["infoHash"] as? String,
            nzbUrl: stream["nzbUrl"] as? String,
            rarUrls: parseArchiveSources(stream["rarUrls"]),
            zipUrls: parseArchiveSources(stream["zipUrls"]),
            sevenZipUrls: parseArchiveSources(stream["7zipUrls"]),
            tgzUrls: parseArchiveSources(stream["tgzUrls"]),
            tarUrls: parseArchiveSources(stream["tarUrls"]),
            fileIdx: stream["fileIdx"] as? Int,
            fileMustInclude: stream["fileMustInclude"] as? String,
            servers: stream["servers"] as? [String],
            name: stream["name"] as? String,
            title: (stream["title"] as? String) ?? (stream["description"] as? String) ?? (stream["name"] as? String),
            description: stream["description"] as? String,
            addonId: addon.id,
            addonName: addon.name,
            addonInstallationId: addon.installationId,
            size: videoSize,
            isFree: stream["isFree"] as? Bool,
            isDebrid: behaviorHints?.cached,
            quality: stream["quality"] as? String,
            headers: stream["headers"] as? [String: String],
            subtitles: subtitles,
            sources: stream["sources"] as? [String],
            behaviorHints: behaviorHints,
            streamIndex: streamIndex,
            sourceType: sourceType,
            playable: isPlayableURL,
            disabledReason: disabledReason
        )
    }

    private func parseArchiveSources(_ rawValue: Any?) -> [StremioArchiveSource]? {
        guard let values = rawValue as? [[String: Any]], !values.isEmpty else { return nil }
        return values.compactMap { value in
            guard let url = value["url"] as? String else { return nil }
            return StremioArchiveSource(url: url, bytes: value["bytes"] as? Int)
        }
    }

    private func parseStreamBehaviorHints(_ rawValue: [String: Any]?) -> StremioStreamBehaviorHints? {
        guard let rawValue else { return nil }
        let proxyRaw = rawValue["proxyHeaders"] as? [String: Any]
        let proxyHeaders = StremioStreamProxyHeaders(
            request: proxyRaw?["request"] as? [String: String],
            response: proxyRaw?["response"] as? [String: String]
        )
        return StremioStreamBehaviorHints(
            bingeGroup: rawValue["bingeGroup"] as? String,
            notWebReady: rawValue["notWebReady"] as? Bool,
            countryWhitelist: rawValue["countryWhitelist"] as? [String],
            cached: rawValue["cached"] as? Bool,
            proxyHeaders: proxyHeaders,
            videoHash: rawValue["videoHash"] as? String,
            videoSize: rawValue["videoSize"] as? Int,
            filename: rawValue["filename"] as? String
        )
    }

    private func detectSourceType(_ stream: [String: Any]) -> StremioSourceType {
        if stream["url"] is String { return .url }
        if stream["externalUrl"] is String { return .externalUrl }
        if stream["ytId"] is String { return .ytId }
        if stream["infoHash"] is String { return .infoHash }
        if stream["nzbUrl"] is String { return .nzbUrl }
        if stream["rarUrls"] is [[String: Any]] || stream["zipUrls"] is [[String: Any]] || stream["7zipUrls"] is [[String: Any]] || stream["tgzUrls"] is [[String: Any]] || stream["tarUrls"] is [[String: Any]] {
            return .archive
        }
        return .unknown
    }

    private func unsupportedReason(for sourceType: StremioSourceType) -> String {
        switch sourceType {
        case .externalUrl:
            return "Opens externally"
        case .ytId:
            return "YouTube playback is not supported in-app"
        case .infoHash:
            return "Torrent playback is not supported in-app"
        case .nzbUrl:
            return "NZB playback is not supported in-app"
        case .archive:
            return "Archive streams are not supported in-app"
        case .unknown:
            return "Unsupported stream type"
        case .url:
            return "Only HTTP(S) direct streams are supported in-app"
        }
    }
}

private extension Array {
    mutating func remove(atOffsets offsets: IndexSet) {
        for offset in offsets.sorted(by: >) {
            remove(at: offset)
        }
    }
}
