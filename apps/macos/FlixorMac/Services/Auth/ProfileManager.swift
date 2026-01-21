//
//  ProfileManager.swift
//  FlixorMac
//
//  Profile management for Plex Home multi-profile support
//  Handles profile switching, state persistence, and data isolation
//

import Foundation
import FlixorKit
import SwiftUI

@MainActor
class ProfileManager: ObservableObject {
    static let shared = ProfileManager()

    // MARK: - Published State

    @Published var homeUsers: [PlexHomeUser] = []
    @Published var activeProfile: ActiveProfile?
    @Published var isLoading = false
    @Published var error: String?

    // MARK: - Computed Properties

    /// Whether user has multiple profiles available (Plex Home)
    var hasMultipleProfiles: Bool {
        homeUsers.count > 1
    }

    /// Whether currently using a profile (not main account)
    var isUsingProfile: Bool {
        activeProfile != nil
    }

    // MARK: - Storage Keys

    private let activeProfileIdKey = "flixor_active_profile_id"

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Load home users from Plex
    func loadHomeUsers() async {
        isLoading = true
        error = nil

        do {
            homeUsers = try await FlixorCore.shared.getHomeUsers()
            activeProfile = FlixorCore.shared.currentProfile
        } catch {
            self.error = error.localizedDescription
            homeUsers = []
        }

        isLoading = false
    }

    /// Switch to a specific profile
    /// - Parameters:
    ///   - user: The PlexHomeUser to switch to
    ///   - pin: PIN if required for protected profile
    func switchProfile(_ user: PlexHomeUser, pin: String? = nil) async throws {
        isLoading = true
        error = nil

        do {
            // Switch at the FlixorCore level
            try await FlixorCore.shared.switchToProfile(user, pin: pin)

            // Update local state
            activeProfile = FlixorCore.shared.currentProfile

            // Update profile storage context
            ProfileStorage.shared.setCurrentProfile(user.uuid)

            // Persist active profile ID
            UserDefaults.standard.set(user.uuid, forKey: activeProfileIdKey)

            // Reinitialize Trakt with profile-scoped tokens
            await FlixorCore.shared.reinitializeTrakt()

            // Clear ALL caches for fresh profile-specific data
            await FlixorCore.shared.clearAllCaches()

            // Reload profile-scoped settings
            ProfileSettings.shared.reloadFromStorage()

            isLoading = false
        } catch {
            isLoading = false
            self.error = error.localizedDescription
            throw error
        }
    }

    /// Switch back to main account
    func switchToMainAccount() async throws {
        isLoading = true
        error = nil

        do {
            try await FlixorCore.shared.switchToMainAccount()

            // Update local state
            activeProfile = nil

            // Clear profile storage context
            ProfileStorage.shared.setCurrentProfile(nil)

            // Clear persisted profile ID
            UserDefaults.standard.removeObject(forKey: activeProfileIdKey)

            // Reinitialize Trakt with main account tokens
            await FlixorCore.shared.reinitializeTrakt()

            // Clear ALL caches for fresh data
            await FlixorCore.shared.clearAllCaches()

            // Reload profile-scoped settings
            ProfileSettings.shared.reloadFromStorage()

            isLoading = false
        } catch {
            isLoading = false
            self.error = error.localizedDescription
            throw error
        }
    }

    /// Restore profile context on app launch
    func restoreProfileContext() {
        // Check if we have a stored active profile
        if let storedProfileId = UserDefaults.standard.string(forKey: activeProfileIdKey) {
            ProfileStorage.shared.setCurrentProfile(storedProfileId)
        }

        // Sync with FlixorCore state
        activeProfile = FlixorCore.shared.currentProfile
    }

    /// Refresh profile state from FlixorCore
    func refresh() {
        activeProfile = FlixorCore.shared.currentProfile
    }
}

// MARK: - Profile Display Helpers

extension PlexHomeUser {
    /// Display name for the profile
    var displayName: String {
        if !title.isEmpty {
            return title
        }
        if let username = username, !username.isEmpty {
            return username
        }
        return "User"
    }

    /// Initials for avatar placeholder
    var initials: String {
        let name = displayName
        let components = name.split(separator: " ")
        if components.count >= 2 {
            let first = components[0].prefix(1)
            let last = components[1].prefix(1)
            return "\(first)\(last)".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}
