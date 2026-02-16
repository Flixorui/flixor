import SwiftUI
import FlixorKit
import Foundation

enum MainTVDestination: String, CaseIterable, Identifiable {
    case home
    case shows
    case movies
    case myList
    case search
    case newPopular
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .shows: return "Shows"
        case .movies: return "Movies"
        case .myList: return "My List"
        case .search: return "Search"
        case .newPopular: return "New & Popular"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .shows: return "tv.fill"
        case .movies: return "film.fill"
        case .myList: return "plus.circle.fill"
        case .search: return "magnifyingglass"
        case .newPopular: return "sparkles.tv.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

struct MainTVView: View {
    @State private var selected: MainTVDestination = .home
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var session: SessionManager
    @EnvironmentObject private var profileSettings: TVProfileSettings
    @EnvironmentObject private var watchlistController: TVWatchlistController
    @StateObject private var homeViewModel = TVHomeViewModel()
    @StateObject private var showsLibraryViewModel = TVLibraryViewModel()
    @StateObject private var moviesLibraryViewModel = TVLibraryViewModel()
    @StateObject private var myListViewModel = TVMyListViewModel()
    @StateObject private var searchViewModel = TVSearchViewModel()
    @StateObject private var newPopularViewModel = TVNewPopularViewModel()
    @State private var homeFocusHandoffToken: UUID?
    @State private var comingSoonMessage: String?
    @State private var comingSoonDismissTask: Task<Void, Never>?

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
                    TabView(selection: sidebarSelectionBinding) {
                        Tab(
                            MainTVDestination.home.title,
                            systemImage: MainTVDestination.home.systemImage,
                            value: MainTVDestination.home
                        ) {
                            TVHomeView(
                                viewModel: homeViewModel,
                                focusHandoffToken: homeFocusHandoffToken
                            )
                        }

                        Tab(
                            MainTVDestination.shows.title,
                            systemImage: MainTVDestination.shows.systemImage,
                            value: MainTVDestination.shows
                        ) {
                            TVLibraryView(preferredKind: .show, viewModel: showsLibraryViewModel)
                        }

                        Tab(
                            MainTVDestination.movies.title,
                            systemImage: MainTVDestination.movies.systemImage,
                            value: MainTVDestination.movies
                        ) {
                            TVLibraryView(preferredKind: .movie, viewModel: moviesLibraryViewModel)
                        }

                        Tab(
                            MainTVDestination.myList.title,
                            systemImage: MainTVDestination.myList.systemImage,
                            value: MainTVDestination.myList
                        ) {
                            TVMyListView(viewModel: myListViewModel)
                                .environmentObject(watchlistController)
                        }
                        .tabPlacement(.sidebarOnly)

                        Tab(
                            MainTVDestination.search.title,
                            systemImage: MainTVDestination.search.systemImage,
                            value: MainTVDestination.search,
                            role: .search
                        ) {
                            TVSearchView(viewModel: searchViewModel)
                        }
                        .tabPlacement(.sidebarOnly)

                        if shouldShowNewPopularDestination {
                            Tab(
                                MainTVDestination.newPopular.title,
                                systemImage: MainTVDestination.newPopular.systemImage,
                                value: MainTVDestination.newPopular
                            ) {
                                TVNewPopularView(viewModel: newPopularViewModel)
                                    .environmentObject(watchlistController)
                            }
                            .tabPlacement(.sidebarOnly)
                        }

                        Tab(
                            MainTVDestination.settings.title,
                            systemImage: MainTVDestination.settings.systemImage,
                            value: MainTVDestination.settings
                        ) {
                            TVSettingsView()
                        }
                        // Pin this destination in native sidebar placement for global actions.
                        .tabPlacement(.pinned)
                    }
                    .tabViewStyle(.sidebarAdaptable)
                    .overlay(alignment: .top) {
                        if let comingSoonMessage {
                            Text(comingSoonMessage)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(.top, 24)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
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
        .onChange(of: profileSettings.showNewPopularTab) { _ in
            enforceDestinationAvailability()
        }
        .onChange(of: profileSettings.discoveryDisabled) { _ in
            enforceDestinationAvailability()
        }
        .onDisappear {
            comingSoonDismissTask?.cancel()
            comingSoonDismissTask = nil
        }
    }

    private func updatePhaseFromSession() async {
        appState.phase = session.isAuthenticated ? .authenticated : .unauthenticated
        if session.isAuthenticated {
            selected = .home
            appState.selectedDestination = .home
            dispatchHomeFocusHandoff()
            // Ensure a current Plex server is selected
            await ensurePlexServerSelected()
        }
    }

    private var sidebarSelectionBinding: Binding<MainTVDestination> {
        Binding(
            get: { selected },
            set: { destination in
                if destination == .newPopular, !shouldShowNewPopularDestination {
                    showComingSoon(for: destination)
                    selected = .home
                    appState.selectedDestination = .home
                    dispatchHomeFocusHandoff()
                    return
                }

                selected = destination
                appState.selectedDestination = destination

                #if DEBUG
                print("🧭 [Sidebar] Selected destination: \(destination.rawValue)")
                #endif

                if destination == .home {
                    dispatchHomeFocusHandoff()
                }
            }
        )
    }

    private var shouldShowNewPopularDestination: Bool {
        profileSettings.showNewPopularTab && !profileSettings.discoveryDisabled
    }

    private func enforceDestinationAvailability() {
        if selected == .newPopular, !shouldShowNewPopularDestination {
            selected = .home
            appState.selectedDestination = .home
            dispatchHomeFocusHandoff()
        }
    }

    private func showComingSoon(for destination: MainTVDestination) {
        comingSoonDismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            comingSoonMessage = "\(destination.title) coming soon"
        }
        comingSoonDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                comingSoonMessage = nil
            }
        }
    }

    private func dispatchHomeFocusHandoff() {
        let token = UUID()
        homeFocusHandoffToken = token
        #if DEBUG
        print("🎯 [Sidebar] Home focus handoff token: \(token.uuidString)")
        #endif
    }

    private func ensurePlexServerSelected() async {
        do {
            let servers = try await APIClient.shared.getPlexServers()
            if let first = servers.first(where: { $0.owned == true }) ?? servers.first {
                _ = try? await APIClient.shared.setCurrentPlexServer(serverId: first.id)
            }
        } catch {
        }
    }
}
