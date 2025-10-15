import SwiftUI
import FlixorKit

@main
struct FlixorTVApp: App {
    @StateObject private var apiClient = APIClient.shared
    @StateObject private var session = SessionManager.shared
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainTVView()
                .environmentObject(apiClient)
                .environmentObject(session)
                .environmentObject(appState)
                .task {
                    // Restore session on app launch
                    await session.restoreSession()
                }
        }
    }
}
