import SwiftUI
import FlixorKit

struct MainTVView: View {
    enum Tab: String, CaseIterable { case home = "Home", shows = "Shows", movies = "Movies", myNetflix = "My List", search = "Search" }
    @State private var selected: Tab = .home
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var session: SessionManager
    @State private var showSettings = false

    var body: some View {
        ZStack {
            // Main content varies by app phase
            Group {
                switch appState.phase {
                case .linking:
                    Color.black.ignoresSafeArea() // block background
                case .unauthenticated:
                    // Show settings by default when not signed in
                    TVSettingsView()
                case .authenticated:
                    // Move NavigationStack to outer level to share focus scope
                    NavigationStack {
                        ZStack(alignment: .top) {
                            // Content behind nav bar
                            Group {
                                switch selected {
                                case .home: TVHomeView()
                                case .shows: PlaceholderView(title: "Shows")
                                case .movies: PlaceholderView(title: "Movies")
                                case .myNetflix: PlaceholderView(title: "My List")
                                case .search: PlaceholderView(title: "Search")
                                }
                            }

                            // Floating transparent nav bar (now inside NavigationStack)
                            VStack(spacing: 0) {
                                SimpleTopBar(
                                    selected: $selected,
                                    onProfileTapped: { showSettings = true },
                                    onSearchTapped: { selected = .search }
                                )
                                Spacer()
                            }
                        }
                        .navigationDestination(for: MediaItem.self) { item in
                            TVDetailsView(item: item)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        // Settings presented from the profile button per UI spec
        .sheet(isPresented: $showSettings) {
            TVSettingsView()
        }
        .task {
            // Establish initial phase after session restore
            await updatePhaseFromSession()
        }
        .fullScreenCover(isPresented: Binding(
            get: { appState.phase == .linking },
            set: { _ in }
        )) {
            TVAuthLinkView(isPresented: Binding(
                get: { appState.phase == .linking },
                set: { _ in }
            ))
            .environmentObject(appState)
        }
        .onChange(of: session.isAuthenticated) { authed in
            Task { await updatePhaseFromSession() }
        }
    }

    private func updatePhaseFromSession() async {
        appState.phase = session.isAuthenticated ? .authenticated : .unauthenticated
        if session.isAuthenticated {
            selected = .home
            // Ensure a current Plex server is selected
            await ensurePlexServerSelected()
        }
    }

    private func ensurePlexServerSelected() async {
        do {
            let servers = try await APIClient.shared.getPlexServers()
            if let first = servers.first(where: { $0.owned == true }) ?? servers.first {
                print("📡 [MainTVView] Setting current server: \(first.name)")
                _ = try? await APIClient.shared.setCurrentPlexServer(serverId: first.id)
            }
        } catch {
            print("⚠️ [MainTVView] Failed to set server: \(error)")
        }
    }
}

struct SimpleTopBar: View {
    @Binding var selected: MainTVView.Tab
    var onProfileTapped: () -> Void
    var onSearchTapped: () -> Void

    var body: some View {
        TopNavBar(selected: $selected, onProfileTapped: onProfileTapped, onSearchTapped: onSearchTapped)
            .padding(.top, -50)
    }
}

struct TVHomePlaceholder: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("FlixorTV")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
            Text("Home screen placeholder — Milestone 2 will implement billboard + rows.")
                .foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

struct PlaceholderView: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.title)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
    }
}
