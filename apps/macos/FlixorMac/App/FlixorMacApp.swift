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
        // Initialize AppLogger early to capture all logs
        _ = AppLogger.shared

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
/// Build-time keys injected from Config/Secrets.xcconfig via Info.plist.
/// They are not stored in source. Users can still override TMDB in Settings.
enum APIKeys {
    static let tmdbApiKey = infoValue("FlixorTMDBApiKey")
    static let traktClientId = infoValue("FlixorTraktClientId")
    static let traktClientSecret = infoValue("FlixorTraktClientSecret")

    private static func infoValue(_ key: String) -> String {
        let value = (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if value.isEmpty || value.hasPrefix("$(") {
            print("⚠️ [APIKeys] \(key) is not set. Create apps/macos/FlixorMac/Config/Secrets.xcconfig from Secrets.example.xcconfig.")
            return ""
        }
        return value
    }
}

extension Bundle {
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}

// MARK: - Playback Command State

/// Tracks whether a player is on screen so the Playback menu can enable its items.
@MainActor
final class PlaybackCommandState: ObservableObject {
    static let shared = PlaybackCommandState()
    @Published var isPlayerActive = false
    private init() {}
}

// MARK: - App Commands
struct AppCommands: Commands {
    @ObservedObject private var playback = PlaybackCommandState.shared

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            // Remove "New" menu items
        }

        // Space and the arrow keys are handled by the player's own key monitor
        // while it is on screen. They are deliberately NOT bound here: a menu
        // key equivalent without a modifier fires app-wide and would swallow
        // spaces/arrows typed into text fields such as Search.
        CommandMenu("Playback") {
            Button("Play/Pause") {
                NotificationCenter.default.post(name: .togglePlayPause, object: nil)
            }
            .disabled(!playback.isPlayerActive)

            Button("Skip Forward") {
                NotificationCenter.default.post(name: .skipForward, object: nil)
            }
            .disabled(!playback.isPlayerActive)

            Button("Skip Backward") {
                NotificationCenter.default.post(name: .skipBackward, object: nil)
            }
            .disabled(!playback.isPlayerActive)

            Divider()

            Button("Toggle Picture in Picture") {
                NotificationCenter.default.post(name: .togglePictureInPicture, object: nil)
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(!playback.isPlayerActive)
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let togglePlayPause = Notification.Name("togglePlayPause")
    static let skipForward = Notification.Name("skipForward")
    static let skipBackward = Notification.Name("skipBackward")
    static let togglePictureInPicture = Notification.Name("togglePictureInPicture")
}
