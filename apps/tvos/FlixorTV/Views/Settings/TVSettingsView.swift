import SwiftUI
import FlixorKit

struct TVSettingsView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionManager
    @EnvironmentObject private var appState: AppState

    @State private var baseURL: String = ""
    @State private var showingCode = false
    @State private var error: String?
    @State private var showTestPlayer = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Settings")
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(.white)

                backendSection
                authSection
                debugSection
            }
            .padding(40)
        }
        .background(Color.black)
        .onAppear { baseURL = api.baseURL.absoluteString }
        .fullScreenCover(isPresented: $showTestPlayer) {
            UniversalPlayerView()
        }
    }

    private var backendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Backend URL")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)

            HStack(spacing: 12) {
                TextField("http://server:3001", text: $baseURL)
                    .font(.title3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.12)))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.2), lineWidth: 1))
                    .frame(width: 820)
                    .onSubmit { api.setBaseURL(baseURL) }
                Button("Save") { api.setBaseURL(baseURL) }
                    .buttonStyle(.borderedProminent)
                Button(action: { Task { await testBackend() } }) {
                    if testing { ProgressView().tint(.white) } else { Text(statusOK ? "Connected" : "Test") }
                }
                .buttonStyle(.bordered)
                .tint(statusOK ? .green : .blue)
            }

            if let error { Text(error).foregroundStyle(.orange) }
        }
    }

    private var authSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                Text("Plex Account")
                    .font(.title2.weight(.semibold))
                if session.isAuthenticated {
                    Text("Signed in").foregroundStyle(.green)
                } else {
                    Text("Signed out").foregroundStyle(.secondary)
                }
            }

            if session.isAuthenticated {
                Button("Sign Out") { Task { await session.logout() } }
                    .buttonStyle(.bordered)
            } else {
                Button("Sign in with Code") { appState.startLinking() }
                    .buttonStyle(.borderedProminent)
                .disabled(!statusOK)
            }
        }
    }

    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Developer & Testing")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 10) {
                Text("Test MPV video rendering pipeline with public test videos")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))

                Button {
                    showTestPlayer = true
                } label: {
                    HStack {
                        Image(systemName: "play.rectangle.fill")
                        Text("MPV Test Player")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            }
        }
    }

    // MARK: - backend status
    @State private var statusOK: Bool = false
    @State private var testing = false

    private func testBackend() async {
        testing = true
        defer { testing = false }
        do {
            _ = try await api.healthCheck()
            statusOK = true
        } catch {
            statusOK = false
            self.error = "Backend not reachable: \(error.localizedDescription)"
        }
    }
}
