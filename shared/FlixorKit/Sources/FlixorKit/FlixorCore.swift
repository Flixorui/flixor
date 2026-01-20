//
//  FlixorCore.swift
//  FlixorKit
//
//  Main entry point for Flixor Core
//  Initializes and manages all services with platform-specific storage bindings
//  Reference: packages/core/src/FlixorCore.ts
//

import Foundation

// MARK: - Configuration

public struct FlixorCoreConfig {
    // Client identification
    public let clientId: String
    public var productName: String
    public var productVersion: String
    public var platform: String
    public var deviceName: String

    // API keys
    public let tmdbApiKey: String
    public let traktClientId: String
    public let traktClientSecret: String

    // Optional settings
    public var language: String

    public init(
        clientId: String,
        productName: String = "Flixor",
        productVersion: String = "1.0.0",
        platform: String = "macOS",
        deviceName: String = "Flixor",
        tmdbApiKey: String,
        traktClientId: String,
        traktClientSecret: String,
        language: String = "en-US"
    ) {
        self.clientId = clientId
        self.productName = productName
        self.productVersion = productVersion
        self.platform = platform
        self.deviceName = deviceName
        self.tmdbApiKey = tmdbApiKey
        self.traktClientId = traktClientId
        self.traktClientSecret = traktClientSecret
        self.language = language
    }
}

// MARK: - Stored Auth

private struct StoredPlexAuth: Codable {
    let token: String
    let server: PlexServerResource
    let connection: PlexConnectionResource
}

// MARK: - FlixorCore

@MainActor
public class FlixorCore: ObservableObject {
    // MARK: - Singleton

    public static let shared = FlixorCore()

    // MARK: - Configuration

    private var config: FlixorCoreConfig?

    // MARK: - Storage

    private let secureStorage = KeychainStorage()
    private let storage = UserDefaultsStorage()
    private let cache = CacheManager()

    // MARK: - Services

    private var _plexAuth: PlexAuthService?
    private var _plexServer: PlexServerService?
    private var _plexTv: PlexTvService?
    private var _tmdb: TMDBService?
    private var _trakt: TraktService?

    // MARK: - State

    @Published public private(set) var plexToken: String?
    @Published public private(set) var currentServer: PlexServerResource?
    @Published public private(set) var currentConnection: PlexConnectionResource?

    // MARK: - Initialization

    private init() {}

    /// Configure FlixorCore with required settings
    /// Must be called before using any services
    public func configure(
        clientId: String,
        tmdbApiKey: String,
        traktClientId: String,
        traktClientSecret: String,
        productName: String = "Flixor",
        productVersion: String = "1.0.0",
        platform: String = "macOS",
        deviceName: String = "Flixor",
        language: String = "en-US"
    ) {
        self.config = FlixorCoreConfig(
            clientId: clientId,
            productName: productName,
            productVersion: productVersion,
            platform: platform,
            deviceName: deviceName,
            tmdbApiKey: tmdbApiKey,
            traktClientId: traktClientId,
            traktClientSecret: traktClientSecret,
            language: language
        )

        // Initialize services
        _plexAuth = PlexAuthService(
            clientId: clientId,
            productName: productName,
            productVersion: productVersion,
            platform: platform,
            deviceName: deviceName
        )

        _tmdb = TMDBService(apiKey: tmdbApiKey, cache: cache, language: language)

        _trakt = TraktService(clientId: traktClientId, clientSecret: traktClientSecret)

        print("🚀 [FlixorCore] Configured")
    }

    /// Initialize FlixorCore - restore sessions from storage
    public func initialize() async -> Bool {
        guard config != nil else {
            print("❌ [FlixorCore] Not configured. Call configure() first.")
            return false
        }

        print("🚀 [FlixorCore] Initializing...")

        // Restore Plex session
        let plexRestored = await restorePlexSession()

        // Initialize Trakt (restore tokens)
        await initializeTrakt()

        print("✅ [FlixorCore] Initialization complete")
        return plexRestored
    }

    // MARK: - Service Accessors

    /// Get Plex Auth service (for PIN auth flow)
    public var plexAuth: PlexAuthService {
        guard let service = _plexAuth else {
            fatalError("FlixorCore not configured. Call configure() first.")
        }
        return service
    }

    /// Get Plex Server service (requires active connection)
    public var plexServer: PlexServerService? {
        return _plexServer
    }

    /// Get Plex.tv service (requires authentication)
    public var plexTv: PlexTvService? {
        return _plexTv
    }

    /// Get TMDB service (always available)
    public var tmdb: TMDBService {
        guard let service = _tmdb else {
            fatalError("FlixorCore not configured. Call configure() first.")
        }
        return service
    }

    /// Get Trakt service (always available, but some features require auth)
    public var trakt: TraktService {
        guard let service = _trakt else {
            fatalError("FlixorCore not configured. Call configure() first.")
        }
        return service
    }

    // MARK: - Plex Authentication State

    /// Check if Plex is authenticated
    public var isPlexAuthenticated: Bool {
        return plexToken != nil && _plexTv != nil
    }

    /// Check if connected to a Plex server
    public var isPlexServerConnected: Bool {
        return _plexServer != nil
    }

    /// Get current Plex server info
    public var server: PlexServerResource? {
        return currentServer
    }

    /// Get current Plex connection info
    public var connection: PlexConnectionResource? {
        return currentConnection
    }

    /// Get the Plex auth token (for playback headers)
    public func getPlexToken() -> String? {
        return currentServer?.accessToken ?? plexToken
    }

    /// Get the client ID
    public func getClientId() -> String {
        return config?.clientId ?? ""
    }

    /// Client ID property accessor
    public var clientId: String {
        return config?.clientId ?? ""
    }

    /// Check PIN status (single poll)
    public func checkPlexPin(pinId: Int) async throws -> String? {
        return try await plexAuth.checkPin(id: pinId)
    }

    /// Complete Plex authentication after receiving token from PIN
    /// This stores the token and initializes PlexTvService
    public func completePlexAuth(token: String) async throws {
        guard let config = self.config else {
            throw FlixorCoreError.notConfigured
        }

        // Verify token is valid
        _ = try await plexAuth.getUser(token: token)

        // Store token and initialize PlexTvService
        self.plexToken = token
        _plexTv = PlexTvService(
            token: token,
            clientId: config.clientId,
            productName: config.productName,
            productVersion: config.productVersion,
            platform: config.platform
        )

        print("✅ [FlixorCore] Plex authentication completed")
    }

    // MARK: - Plex Session Restoration

    private func restorePlexSession() async -> Bool {
        do {
            guard let storedAuth: StoredPlexAuth = try await secureStorage.get(StorageKeys.plexToken) else {
                return false
            }

            // Verify token is still valid
            do {
                _ = try await plexAuth.getUser(token: storedAuth.token)
            } catch {
                // Token invalid, clear stored auth
                try? await secureStorage.remove(StorageKeys.plexToken)
                return false
            }

            // Restore state
            self.plexToken = storedAuth.token
            self.currentServer = storedAuth.server
            self.currentConnection = storedAuth.connection

            // Initialize services
            guard let config = self.config else { return false }

            _plexTv = PlexTvService(
                token: storedAuth.token,
                clientId: config.clientId,
                productName: config.productName,
                productVersion: config.productVersion,
                platform: config.platform
            )

            _plexServer = PlexServerService(
                baseUrl: storedAuth.connection.uri,
                token: storedAuth.server.accessToken,
                clientId: config.clientId,
                cache: cache
            )

            print("✅ [FlixorCore] Plex session restored")
            print("✅ [FlixorCore] Restored connection to \(storedAuth.server.name)")
            return true
        } catch {
            print("⚠️ [FlixorCore] Failed to restore Plex session: \(error)")
            return false
        }
    }

    // MARK: - Plex Authentication

    /// Authenticate with Plex using PIN code
    /// Returns the PIN info for user to enter at plex.tv/link
    public func createPlexPin() async throws -> PlexPin {
        return try await plexAuth.createPin()
    }

    /// Wait for PIN authorization and complete auth
    public func waitForPlexPin(
        pinId: Int,
        intervalMs: Int = 2000,
        timeoutMs: Int = 300000,
        onPoll: (() -> Void)? = nil
    ) async throws -> String {
        let token = try await plexAuth.waitForPin(
            id: pinId,
            intervalMs: intervalMs,
            timeoutMs: timeoutMs,
            onPoll: onPoll
        )

        guard let config = self.config else {
            throw FlixorCoreError.notConfigured
        }

        // Store token and initialize PlexTvService
        self.plexToken = token
        _plexTv = PlexTvService(
            token: token,
            clientId: config.clientId,
            productName: config.productName,
            productVersion: config.productVersion,
            platform: config.platform
        )

        return token
    }

    /// Get available Plex servers for authenticated user
    public func getPlexServers() async throws -> [PlexServerResource] {
        guard let token = plexToken else {
            throw FlixorCoreError.plexNotAuthenticated
        }
        return try await plexAuth.getServers(token: token)
    }

    /// Connect to a specific Plex server
    public func connectToPlexServer(_ server: PlexServerResource) async throws -> PlexConnectionResource {
        guard let token = plexToken, let config = self.config else {
            throw FlixorCoreError.plexNotAuthenticated
        }

        // Find the best connection
        var bestConnection: PlexConnectionResource?

        // Try connections in order: local first, then non-relay, then relay
        let sortedConnections = server.connections.sorted { conn1, conn2 in
            if conn1.local != conn2.local { return conn1.local }
            if conn1.relay != conn2.relay { return !conn1.relay }
            return false
        }

        for connection in sortedConnections {
            if try await plexAuth.testConnection(connection, token: server.accessToken) {
                bestConnection = connection
                break
            }
        }

        guard let connection = bestConnection else {
            throw FlixorCoreError.serverConnectionFailed(serverName: server.name)
        }

        // Store state
        self.currentServer = server
        self.currentConnection = connection

        // Initialize server service
        _plexServer = PlexServerService(
            baseUrl: connection.uri,
            token: server.accessToken,
            clientId: config.clientId,
            cache: cache
        )

        // Persist to secure storage
        try await secureStorage.set(StorageKeys.plexToken, value: StoredPlexAuth(
            token: token,
            server: server,
            connection: connection
        ))

        print("✅ [FlixorCore] Connected to server: \(server.name)")
        return connection
    }

    /// Connect to a specific Plex server with a specific URI
    public func connectToPlexServerWithUri(_ server: PlexServerResource, uri: String) async throws -> PlexConnectionResource {
        guard let token = plexToken, let config = self.config else {
            throw FlixorCoreError.plexNotAuthenticated
        }

        // Find connection matching the URI, or create a synthetic one
        let connection: PlexConnectionResource
        if let existingConnection = server.connections.first(where: { $0.uri == uri }) {
            connection = existingConnection
        } else {
            // Create a synthetic connection for custom endpoints
            connection = PlexConnectionResource(
                uri: uri,
                protocol: uri.hasPrefix("https") ? "https" : "http",
                local: false,
                relay: false,
                IPv6: false
            )
        }

        // Test the connection
        guard try await plexAuth.testConnection(connection, token: server.accessToken) else {
            throw FlixorCoreError.serverConnectionFailed(serverName: server.name)
        }

        // Store state
        self.currentServer = server
        self.currentConnection = connection

        // Initialize server service
        _plexServer = PlexServerService(
            baseUrl: connection.uri,
            token: server.accessToken,
            clientId: config.clientId,
            cache: cache
        )

        // Persist to secure storage
        try await secureStorage.set(StorageKeys.plexToken, value: StoredPlexAuth(
            token: token,
            server: server,
            connection: connection
        ))

        print("✅ [FlixorCore] Connected to server: \(server.name) via \(uri)")
        return connection
    }

    /// Sign out from Plex
    public func signOutPlex() async {
        if let token = plexToken {
            await plexAuth.signOut(token: token)
        }

        // Clear state
        plexToken = nil
        currentServer = nil
        currentConnection = nil
        _plexTv = nil
        _plexServer = nil

        // Clear storage
        try? await secureStorage.remove(StorageKeys.plexToken)
        await cache.invalidatePattern("plex:*")
        await cache.invalidatePattern("plextv:*")

        print("✅ [FlixorCore] Signed out from Plex")
    }

    // MARK: - Trakt Authentication

    private func initializeTrakt() async {
        print("🔄 [FlixorCore] Initializing Trakt...")
        do {
            if let storedTokens: TraktTokens = try await secureStorage.get(StorageKeys.traktTokens) {
                print("✅ [FlixorCore] Found stored Trakt tokens")
                _trakt?.setTokens(storedTokens)

                // Check if tokens are expired
                if _trakt?.areTokensExpired() == true {
                    print("⏰ [FlixorCore] Trakt tokens expired, refreshing...")
                    do {
                        try await _trakt?.refreshTokens()
                        // Save refreshed tokens
                        if let newTokens = _trakt?.getTokens() {
                            try await secureStorage.set(StorageKeys.traktTokens, value: newTokens)
                        }
                        print("✅ [FlixorCore] Trakt tokens refreshed")
                    } catch {
                        // Clear invalid tokens
                        _trakt?.setTokens(nil)
                        try? await secureStorage.remove(StorageKeys.traktTokens)
                        print("⚠️ [FlixorCore] Failed to refresh Trakt tokens: \(error)")
                    }
                } else {
                    print("✅ [FlixorCore] Trakt session restored (tokens valid)")
                }
            } else {
                print("ℹ️ [FlixorCore] No stored Trakt tokens found")
            }
        } catch {
            print("⚠️ [FlixorCore] Failed to restore Trakt session: \(error)")
        }
    }

    /// Check if Trakt is authenticated
    public var isTraktAuthenticated: Bool {
        return _trakt?.isAuthenticated ?? false
    }

    /// Generate Trakt device code for authentication
    public func createTraktDeviceCode() async throws -> TraktDeviceCode {
        return try await trakt.generateDeviceCode()
    }

    /// Wait for Trakt device code authorization
    public func waitForTraktDeviceCode(
        _ deviceCode: TraktDeviceCode,
        onPoll: (() -> Void)? = nil
    ) async throws -> TraktTokens {
        let tokens = try await trakt.waitForDeviceCode(deviceCode, onPoll: onPoll)

        // Save tokens to secure storage
        try await secureStorage.set(StorageKeys.traktTokens, value: tokens)

        print("✅ [FlixorCore] Trakt authenticated")
        return tokens
    }

    /// Save Trakt tokens to storage (used when authenticating via APIClient)
    public func saveTraktTokens(_ tokens: TraktTokens) async throws {
        try await secureStorage.set(StorageKeys.traktTokens, value: tokens)
        print("✅ [FlixorCore] Trakt tokens saved to storage")
    }

    /// Sign out from Trakt
    public func signOutTrakt() async {
        await trakt.signOut()
        try? await secureStorage.remove(StorageKeys.traktTokens)
        await cache.invalidatePattern("trakt:*")
        print("✅ [FlixorCore] Signed out from Trakt")
    }

    // MARK: - Cache Management

    /// Clear all caches
    public func clearAllCaches() async {
        await cache.clear()
        print("✅ [FlixorCore] All caches cleared")
    }

    /// Clear Plex caches
    public func clearPlexCache() async {
        await cache.invalidatePattern("plex:*")
        await cache.invalidatePattern("plextv:*")
    }

    /// Clear TMDB cache
    public func clearTmdbCache() async {
        await cache.invalidatePattern("tmdb:*")
    }

    /// Clear Trakt cache
    public func clearTraktCache() async {
        await cache.invalidatePattern("trakt:*")
    }
}

// MARK: - Errors

public enum FlixorCoreError: Error, LocalizedError {
    case notConfigured
    case plexNotAuthenticated
    case serverConnectionFailed(serverName: String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "FlixorCore not configured. Call configure() first."
        case .plexNotAuthenticated:
            return "Plex not authenticated"
        case .serverConnectionFailed(let serverName):
            return "Could not connect to server: \(serverName)"
        }
    }
}
