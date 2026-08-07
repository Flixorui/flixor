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
        // In Stremio-only mode there is no Plex session to be authenticated against;
        // the app is usable regardless.
        isAuthenticated = AppModeStore.shared.isStremioOnly
            || (core.isPlexAuthenticated && core.isPlexServerConnected)
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
        } else if AppModeStore.shared.isStremioOnly {
            currentUser = User(id: "stremio", username: "Stremio", email: nil, thumb: nil)
        } else {
            currentUser = nil
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
        // Plex Home profiles don't exist without Plex - skip the call rather than
        // letting it throw on every launch.
        guard !AppModeStore.shared.isStremioOnly, FlixorCore.shared.isPlexAuthenticated else {
            hasMultipleProfiles = false
            return
        }
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

    /// Full sign-out: clears Plex and returns the user to the mode chooser.
    func logout() async {
        await clearPlexSession()

        // Reset settings and show onboarding on next login. Stremio config is left
        // alone so it survives a Plex sign-out.
        UserDefaults.standard.resetNonStremioSettings()

        // Back to the mode chooser.
        AppModeStore.shared.clear()
    }

    /// Disconnects Plex but keeps the app usable as a standalone Stremio client.
    /// All settings, addons and local history are preserved.
    func disconnectPlex() async {
        await clearPlexSession()
        AppModeStore.shared.select(.stremio)
    }

    private func clearPlexSession() async {
        await FlixorCore.shared.signOutPlex()
        currentUser = nil
        isAuthenticated = false
        activeProfile = nil
        hasMultipleProfiles = false

        // Clear profile context
        ProfileStorage.shared.setCurrentProfile(nil)
    }

    // MARK: - Sync with FlixorCore

    func updateFromFlixorCore() {
        syncWithFlixorCore()
    }
}
