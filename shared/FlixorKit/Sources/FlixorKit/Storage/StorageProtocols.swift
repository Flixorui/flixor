//
//  StorageProtocols.swift
//  FlixorKit
//
//  Storage interfaces for FlixorKit
//  Reference: packages/core/src/storage/
//

import Foundation

// MARK: - Storage Protocol

/// Interface for general key-value storage (UserDefaults)
public protocol StorageProtocol {
    func get<T: Decodable>(_ key: String) async throws -> T?
    func set<T: Encodable>(_ key: String, value: T?) async throws
    func remove(_ key: String) async throws
    func clear() async throws
}

// MARK: - Secure Storage Protocol

/// Interface for secure/encrypted storage (Keychain)
public protocol SecureStorageProtocol {
    func get<T: Decodable>(_ key: String) async throws -> T?
    func set<T: Encodable>(_ key: String, value: T) async throws
    func remove(_ key: String) async throws
}

// MARK: - Cache Protocol

/// Interface for cached data with TTL support
public protocol CacheProtocol {
    func get<T: Decodable>(_ key: String) async -> T?
    func set<T: Encodable>(_ key: String, value: T, ttl: TimeInterval) async
    func remove(_ key: String) async
    func clear() async
    func invalidatePattern(_ pattern: String) async
}

// MARK: - Storage Keys

public enum StorageKeys {
    // Plex tokens and server
    public static let plexToken = "plex_auth_token"
    public static let plexUser = "plex_user"
    public static let selectedServer = "selected_server"
    public static let selectedConnection = "selected_connection"

    // Trakt tokens
    public static let traktTokens = "trakt_tokens"

    // Client identifier
    public static let clientId = "flixor_client_id"

    // User settings
    public static let watchlistProvider = "watchlist_provider"
    public static let preferredQuality = "preferred_quality"
    public static let preferredPlayerBackend = "preferred_player_backend"

    // API key overrides
    public static let tmdbApiKey = "tmdb_api_key_override"
    public static let traktClientId = "trakt_client_id_override"
    public static let traktClientSecret = "trakt_client_secret_override"
}
