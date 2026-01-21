//
//  SessionManager.swift
//  FlixorMac
//
//  Session management and authentication state
//  Now uses FlixorCore for standalone operation
//

import Foundation
import FlixorKit

@MainActor
class SessionManager: ObservableObject {
    static let shared = SessionManager()

    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var activeProfile: ActiveProfile?
    @Published var hasMultipleProfiles = false

    private init() {
        // Observe FlixorCore authentication state
        observeFlixorCore()
    }

    private func observeFlixorCore() {
        // FlixorCore is @MainActor so we can observe it safely
        Task { @MainActor in
            // Initial sync
            syncWithFlixorCore()
        }
    }

    private func syncWithFlixorCore() {
        let core = FlixorCore.shared
        isAuthenticated = core.isPlexAuthenticated && core.isPlexServerConnected
        activeProfile = core.currentProfile

        // Create a User from FlixorCore's server info or profile
        if let profile = core.currentProfile {
            currentUser = User(
                id: String(profile.userId),
                username: profile.title,
                email: nil,
                thumb: profile.thumb
            )
        } else if let server = core.server {
            currentUser = User(
                id: server.id,
                username: server.name,
                email: nil,
                thumb: nil
            )
        }
    }

    // MARK: - Session Restore

    func restoreSession() async {
        // FlixorCore handles session restoration in initialize()
        // Restore profile context from storage
        restoreProfileContext()
        // Then sync our state
        syncWithFlixorCore()
        // Check for multiple profiles
        await checkForMultipleProfiles()
    }

    // MARK: - Profile Management

    private let activeProfileIdKey = "flixor_active_profile_id"

    private func restoreProfileContext() {
        // Check if we have a stored active profile
        if let storedProfileId = UserDefaults.standard.string(forKey: activeProfileIdKey) {
            ProfileStorage.shared.setCurrentProfile(storedProfileId)
        }
    }

    private func checkForMultipleProfiles() async {
        do {
            let users = try await FlixorCore.shared.getHomeUsers()
            hasMultipleProfiles = users.count > 1
        } catch {
            hasMultipleProfiles = false
        }
    }

    /// Refresh profile state after switching
    func refreshProfile() {
        syncWithFlixorCore()
    }

    // MARK: - Login (now handled by FlixorCore's Plex PIN flow)

    func login(token: String) async throws {
        // This method is for legacy compatibility
        // New auth flow uses FlixorCore directly
        syncWithFlixorCore()
    }

    // MARK: - Logout

    func logout() async {
        await FlixorCore.shared.signOutPlex()
        currentUser = nil
        isAuthenticated = false
        activeProfile = nil
        hasMultipleProfiles = false

        // Clear profile context
        ProfileStorage.shared.setCurrentProfile(nil)

        // Reset all settings and show onboarding on next login
        UserDefaults.standard.resetAllSettings()
    }

    // MARK: - Sync with FlixorCore

    func updateFromFlixorCore() {
        syncWithFlixorCore()
    }
}
