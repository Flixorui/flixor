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

        // Create a User from FlixorCore's server info if available
        if let server = core.server {
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
        // Just sync our state
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
    }

    // MARK: - Sync with FlixorCore

    func updateFromFlixorCore() {
        syncWithFlixorCore()
    }
}
