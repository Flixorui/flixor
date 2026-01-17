//
//  FlixorMacApp.swift
//  FlixorMac
//
//  Created by Claude Code
//  Copyright © 2025 Flixor. All rights reserved.
//

import SwiftUI
import FlixorKit

@main
struct FlixorMacApp: App {
    @StateObject private var sessionManager = SessionManager.shared
    @StateObject private var apiClient = APIClient.shared

    init() {
        // Configure FlixorCore
        let clientId = getOrCreateClientId()

        FlixorCore.shared.configure(
            clientId: clientId,
            tmdbApiKey: APIKeys.tmdbApiKey,
            traktClientId: APIKeys.traktClientId,
            traktClientSecret: APIKeys.traktClientSecret,
            productName: "Flixor",
            productVersion: Bundle.main.appVersion,
            platform: "macOS",
            deviceName: Host.current().localizedName ?? "Flixor Mac"
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(sessionManager)
                .environmentObject(apiClient)
                .environmentObject(FlixorCore.shared)
                .frame(minWidth: 1024, minHeight: 768)
                .preferredColorScheme(.dark) // Force dark mode
                .task {
                    // Initialize FlixorCore (restore sessions)
                    _ = await FlixorCore.shared.initialize()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            AppCommands()
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(sessionManager)
                .environmentObject(apiClient)
                .environmentObject(FlixorCore.shared)
                .preferredColorScheme(.dark) // Force dark mode
        }
        #endif
    }

    private func getOrCreateClientId() -> String {
        let key = "flixor_client_id"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }
}

// MARK: - API Keys Configuration
enum APIKeys {
    // TMDB API Key
    static let tmdbApiKey = "db55323b8d3e4154498498a75642b381"

    // Trakt Client ID & Secret
    static let traktClientId = "4ab0ead6d5510bf39180a5e1dd7b452f5ad700b7794564befdd6bca56e0f7ce4"
    static let traktClientSecret = "64d24f12e4628dcf0dda74a61f2235c086daaf8146384016b6a86c196e419c26"
}

extension Bundle {
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}

// MARK: - App Commands
struct AppCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            // Remove "New" menu items
        }

        CommandMenu("Playback") {
            Button("Play/Pause") {
                NotificationCenter.default.post(name: .togglePlayPause, object: nil)
            }
            .keyboardShortcut(.space, modifiers: [])

            Button("Skip Forward") {
                NotificationCenter.default.post(name: .skipForward, object: nil)
            }
            .keyboardShortcut(.rightArrow, modifiers: [])

            Button("Skip Backward") {
                NotificationCenter.default.post(name: .skipBackward, object: nil)
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let togglePlayPause = Notification.Name("togglePlayPause")
    static let skipForward = Notification.Name("skipForward")
    static let skipBackward = Notification.Name("skipBackward")
}
