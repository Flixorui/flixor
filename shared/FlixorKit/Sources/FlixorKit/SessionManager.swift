import Foundation

@MainActor
public final class SessionManager: ObservableObject {
    public static let shared = SessionManager()

    @Published public private(set) var isAuthenticated = false
    @Published public private(set) var currentUser: User?

    private let apiClient = APIClient.shared

    private init() {}

    public func restoreSession() async {
        print("🔐 [Session] Attempting to restore session...")
        do {
            let sessionInfo: SessionInfo = try await apiClient.get("/api/auth/session")
            if sessionInfo.authenticated, let user = sessionInfo.user {
                print("✅ [Session] Session restored for user: \(user.username)")
                currentUser = user
                isAuthenticated = true
            } else {
                print("⚠️ [Session] Session not authenticated, logging out")
                await logout()
            }
        } catch {
            print("❌ [Session] Restore failed: \(error)")
            await logout()
        }
    }

    public func login(token: String) async throws {
        print("🔐 [Session] Logging in with token...")
        apiClient.setToken(token)
        let sessionInfo: SessionInfo = try await apiClient.get("/api/auth/session")
        if sessionInfo.authenticated, let user = sessionInfo.user {
            print("✅ [Session] Login successful for user: \(user.username)")
            currentUser = user
            isAuthenticated = true
        } else {
            print("❌ [Session] Login failed: not authenticated")
            throw APIError.unauthorized
        }
    }

    public func logout() async {
        print("🔐 [Session] Logging out...")
        apiClient.setToken(nil)
        currentUser = nil
        isAuthenticated = false
    }
}
