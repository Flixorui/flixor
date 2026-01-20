//
//  PlexAuthViewModel.swift
//  FlixorMac
//
//  View model for Plex authentication using FlixorCore
//

import Foundation
import AppKit
import FlixorKit

@MainActor
class PlexAuthViewModel: ObservableObject {
    @Published var isAuthenticating = false
    @Published var error: String?
    @Published var authToken: String?

    private var pollingTask: Task<Void, Never>?

    // MARK: - Plex Authentication

    func startAuthentication() async {
        guard !isAuthenticating else {
            print("⚠️ [Auth] Already authenticating, skipping")
            return
        }

        print("🔐 [Auth] Starting authentication flow...")
        isAuthenticating = true
        error = nil

        do {
            // 1. Create PIN via FlixorCore
            print("📍 [Auth] Creating Plex PIN...")
            let pin = try await FlixorCore.shared.createPlexPin()
            print("✅ [Auth] Received PIN - ID: \(pin.id), Code: \(pin.code)")

            // 2. Open browser to Plex auth URL
            let authUrl = "https://app.plex.tv/auth#?clientID=\(FlixorCore.shared.clientId)&code=\(pin.code)&context%5Bdevice%5D%5Bproduct%5D=Flixor"
            if let url = URL(string: authUrl) {
                print("🔗 [Auth] Opening browser for authentication...")
                NSWorkspace.shared.open(url)
            }

            // 3. Start polling for authentication
            print("⏳ [Auth] Starting polling for PIN \(pin.id)...")
            await pollForAuth(pinId: pin.id)

        } catch {
            print("❌ [Auth] Authentication failed: \(error)")
            self.error = error.localizedDescription
            isAuthenticating = false
        }
    }

    private func pollForAuth(pinId: Int) async {
        pollingTask?.cancel()

        pollingTask = Task {
            var attempts = 0
            let maxAttempts = 60 // 2 minutes at 2 seconds per attempt

            print("🔄 [Auth] Polling started")

            while attempts < maxAttempts && !Task.isCancelled {
                attempts += 1

                do {
                    // Check PIN status via FlixorCore
                    print("🔍 [Auth] Poll attempt \(attempts)/\(maxAttempts) - Checking PIN \(pinId)...")

                    if let token = try await FlixorCore.shared.checkPlexPin(pinId: pinId) {
                        // PIN authorized! Now complete the authentication flow
                        print("✅ [Auth] PIN authorized! Token received")

                        // Complete authentication (stores token and initializes PlexTvService)
                        try await FlixorCore.shared.completePlexAuth(token: token)
                        print("✅ [Auth] Authentication completed")

                        // Success! RootView will show ServerSelectView next
                        await MainActor.run {
                            self.authToken = token
                            self.isAuthenticating = false
                        }
                        print("✅ [Auth] Authentication complete! User will select server next.")
                        return
                    } else {
                        print("⏸️ [Auth] Not authenticated yet, waiting...")
                    }

                } catch {
                    print("⚠️ [Auth] Poll attempt \(attempts) failed: \(error)")
                }

                // Wait 2 seconds before next attempt
                if attempts < maxAttempts && !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }

            // Timeout
            if !Task.isCancelled {
                print("⏱️ [Auth] Polling timeout after \(attempts) attempts")
                error = "Authentication timeout. Please try again."
                isAuthenticating = false
            } else {
                print("🛑 [Auth] Polling cancelled")
            }
        }
    }

    func cancelAuthentication() {
        pollingTask?.cancel()
        isAuthenticating = false
    }
}
