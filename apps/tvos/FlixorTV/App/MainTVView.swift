import SwiftUI
import FlixorKit

struct MainTVView: View {
    enum Tab: String, CaseIterable { case home = "Home", shows = "Shows", movies = "Movies", myNetflix = "My Netflix", search = "Search", settings = "Settings" }
    @State private var selected: Tab = .home
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var session: SessionManager

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
                    VStack(spacing: 24) {
                        SimpleTopBar(selected: $selected)
                        Group {
                            switch selected {
                            case .home: TVHomeView()
                            case .shows: PlaceholderView(title: "Shows")
                            case .movies: PlaceholderView(title: "Movies")
                            case .myNetflix: PlaceholderView(title: "My Netflix")
                            case .search: PlaceholderView(title: "Search")
                            case .settings: TVSettingsView()
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onAppear {
            // Establish initial phase
            appState.phase = session.isAuthenticated ? .authenticated : .unauthenticated
            if appState.phase == .authenticated { selected = .home }
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
            appState.phase = authed ? .authenticated : .unauthenticated
            if authed { selected = .home }
        }
    }
}

struct SimpleTopBar: View {
    @Binding var selected: MainTVView.Tab

    var body: some View {
        TopNavBar(selected: $selected)
            .padding(.top, 24)
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
