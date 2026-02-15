import SwiftUI
import FlixorKit

@main
struct FlixorTVApp: App {
    @StateObject private var apiClient = APIClient.shared
    @StateObject private var session = SessionManager.shared
    @StateObject private var appState = AppState()

    init() {
        let clientId = getOrCreateClientId()

        FlixorCore.shared.configure(
            clientId: clientId,
            tmdbApiKey: APIKeys.tmdbApiKey,
            traktClientId: APIKeys.traktClientId,
            traktClientSecret: APIKeys.traktClientSecret,
            productName: "Flixor",
            productVersion: Bundle.main.appVersion,
            platform: "tvOS",
            deviceName: "Flixor TV"
        )
    }

    var body: some Scene {
        WindowGroup {
            MainTVView()
                .environmentObject(apiClient)
                .environmentObject(session)
                .environmentObject(appState)
                .task {
                    // Initialize FlixorCore first (restore tokens/services)
                    _ = await FlixorCore.shared.initialize()
                    // Restore session on app launch
                    await session.restoreSession()
                }
        }
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

private enum APIKeys {
    static let tmdbApiKey = "db55323b8d3e4154498498a75642b381"
    static let traktClientId = "4ab0ead6d5510bf39180a5e1dd7b452f5ad700b7794564befdd6bca56e0f7ce4"
    static let traktClientSecret = "64d24f12e4628dcf0dda74a61f2235c086daaf8146384016b6a86c196e419c26"
}

private extension Bundle {
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}
