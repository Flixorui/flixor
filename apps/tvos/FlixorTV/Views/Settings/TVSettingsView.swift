import SwiftUI
import FlixorKit

struct TVSettingsView: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var session: SessionManager
    @EnvironmentObject private var appState: AppState

    @State private var error: String?
    @State private var statusMessage: String?
    @State private var showTestPlayer = false
    @State private var servers: [PlexServer] = []
    @State private var loadingServers = false
    @State private var connectingServerId: String?

    private var activeServer: PlexServer? {
        servers.first(where: { $0.isActive == true })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Settings")
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(.white)

                plexServerSection
                authSection
                debugSection
            }
            .padding(40)
        }
        .background(Color.black)
        .task { await refreshServers(autoSelectIfMissing: true) }
#if DEBUG
        .fullScreenCover(isPresented: $showTestPlayer) {
            UniversalPlayerView()
        }
#endif
    }

    private var plexServerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Plex Server")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)

            if !session.isAuthenticated {
                Text("Sign in to Plex to select and connect a server.")
                    .foregroundStyle(.white.opacity(0.7))
            } else if loadingServers {
                ProgressView("Loading servers...")
                    .tint(.white)
                    .foregroundStyle(.white)
            } else if servers.isEmpty {
                Text("No Plex servers found for this account.")
                    .foregroundStyle(.orange)
            } else {
                if let active = activeServer {
                    Text("Connected to \(active.name)")
                        .foregroundStyle(.green)
                } else {
                    Text("No active server selected.")
                        .foregroundStyle(.orange)
                }

                HStack(spacing: 10) {
                    Button("Refresh") {
                        Task { await refreshServers(autoSelectIfMissing: false) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(loadingServers)

                    if activeServer == nil, let fallback = servers.first(where: { $0.owned == true }) ?? servers.first {
                        Button("Connect \(fallback.name)") {
                            Task { await connect(to: fallback) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(connectingServerId != nil)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(servers, id: \.id) { server in
                        HStack(spacing: 10) {
                            Text(server.name)
                                .foregroundStyle(.white)

                            if server.isActive == true {
                                Text("Active")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.25), in: Capsule())
                                    .foregroundStyle(.green)
                            }

                            Spacer()

                            if server.isActive != true {
                                Button(connectingServerId == server.id ? "Connecting..." : "Connect") {
                                    Task { await connect(to: server) }
                                }
                                .buttonStyle(.bordered)
                                .disabled(connectingServerId != nil)
                            }
                        }
                    }
                }
            }

            if let statusMessage {
                Text(statusMessage)
                    .foregroundStyle(.white.opacity(0.75))
            }

            if let error {
                Text(error)
                    .foregroundStyle(.orange)
            }
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
                Button("Sign Out") {
                    Task {
                        await session.logout()
                        await refreshServers(autoSelectIfMissing: false)
                    }
                }
                    .buttonStyle(.bordered)
            } else {
                Button("Sign in with Code") { appState.startLinking() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var debugSection: some View {
#if DEBUG
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
#else
        EmptyView()
#endif
    }

    private func refreshServers(autoSelectIfMissing: Bool) async {
        guard session.isAuthenticated else {
            servers = []
            statusMessage = nil
            return
        }

        loadingServers = true
        defer { loadingServers = false }

        do {
            error = nil
            var fetched = try await api.getPlexServers()

            if autoSelectIfMissing, fetched.first(where: { $0.isActive == true }) == nil,
               let preferred = fetched.first(where: { $0.owned == true }) ?? fetched.first {
                _ = try await api.setCurrentPlexServer(serverId: preferred.id)
                fetched = try await api.getPlexServers()
                statusMessage = "Connected to \(preferred.name)"
            }

            servers = fetched
        } catch {
            self.error = "Failed to load Plex servers: \(error.localizedDescription)"
        }
    }

    private func connect(to server: PlexServer) async {
        connectingServerId = server.id
        defer { connectingServerId = nil }

        do {
            _ = try await api.setCurrentPlexServer(serverId: server.id)
            statusMessage = "Connected to \(server.name)"
            error = nil
            await refreshServers(autoSelectIfMissing: false)
        } catch {
            self.error = "Unable to connect \(server.name): \(error.localizedDescription)"
        }
    }
}
