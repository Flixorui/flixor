//
//  ProfileStorage.swift
//  FlixorKit
//
//  Profile-scoped storage key management
//  Enables data isolation between Plex Home profiles
//

import Foundation

// MARK: - ProfileStorage

/// Manages profile context for scoped storage keys
public class ProfileStorage {
    public static let shared = ProfileStorage()

    private var currentProfileId: String?
    private let lock = NSLock()

    private init() {}

    // MARK: - Profile Context

    /// Set the current profile ID for scoped storage
    public func setCurrentProfile(_ profileId: String?) {
        lock.lock()
        defer { lock.unlock() }
        currentProfileId = profileId
    }

    /// Get the current profile ID
    public func getCurrentProfile() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return currentProfileId
    }

    /// Check if currently using a profile (not main account)
    public var isUsingProfile: Bool {
        getCurrentProfile() != nil
    }

    // MARK: - Key Scoping

    /// Get a profile-scoped key
    /// - Parameter baseKey: The base storage key (e.g., "trakt_tokens")
    /// - Returns: Profile-scoped key if profile is active, otherwise base key
    public func getProfileKey(_ baseKey: String) -> String {
        guard let profileId = getCurrentProfile() else {
            return baseKey
        }
        return "profile:\(profileId):\(baseKey)"
    }

    /// Get a profile-scoped secure storage key
    /// - Parameter baseKey: The base storage key
    /// - Returns: Profile-scoped secure key
    public func getSecureProfileKey(_ baseKey: String) -> String {
        guard let profileId = getCurrentProfile() else {
            return "secure:\(baseKey)"
        }
        return "secure:profile:\(profileId):\(baseKey)"
    }

    // MARK: - Profile Data Management

    /// Clear all data for a specific profile
    /// - Parameter profileId: The profile UUID to clear
    public func clearProfileData(profileId: String) {
        // This would be implemented by the storage classes
        // to clear all keys with the profile prefix
    }
}

// MARK: - Profile-Scoped Keys

public extension StorageKeys {
    /// Keys that should be profile-scoped
    static let profileScopedKeys: Set<String> = [
        traktTokens,
        watchlistProvider,
        preferredQuality,
        preferredPlayerBackend
    ]

    /// Keys that should remain global (not profile-scoped)
    static let globalKeys: Set<String> = [
        plexToken,
        plexUser,
        selectedServer,
        selectedConnection,
        clientId,
        activeProfileId
    ]

    /// Check if a key should be profile-scoped
    static func isProfileScoped(_ key: String) -> Bool {
        // By default, keys are profile-scoped unless explicitly global
        return !globalKeys.contains(key)
    }
}
