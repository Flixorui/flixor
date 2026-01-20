//
//  RootView.swift
//  FlixorMac
//
//  Root container that switches between login and main app
//

import SwiftUI
import FlixorKit

enum NavItem: String, CaseIterable, Identifiable {
    case home = "Home"
    case library = "Library"
    case myList = "My List"
    case newPopular = "New & Popular"
    case search = "Search"

    var id: String { rawValue }
}

// Wrapper type for DetailsView navigation to avoid conflicts with MediaItem
struct DetailsNavigationItem: Hashable {
    let item: MediaItem
}


// Observable object to track current tab selection
final class MainViewState: ObservableObject {
    @Published var selectedTab: NavItem = .home
}

// Navigation router with per-tab navigation paths
final class NavigationRouter: ObservableObject {
    @Published var homePath = NavigationPath()
    @Published var searchPath = NavigationPath()
    @Published var libraryPath = NavigationPath()
    @Published var myListPath = NavigationPath()
    @Published var newPopularPath = NavigationPath()

    func pathBinding(for tab: NavItem) -> Binding<NavigationPath> {
        Binding(
            get: {
                switch tab {
                case .home: return self.homePath
                case .search: return self.searchPath
                case .library: return self.libraryPath
                case .myList: return self.myListPath
                case .newPopular: return self.newPopularPath
                }
            },
            set: { newValue in
                switch tab {
                case .home: self.homePath = newValue
                case .search: self.searchPath = newValue
                case .library: self.libraryPath = newValue
                case .myList: self.myListPath = newValue
                case .newPopular: self.newPopularPath = newValue
                }
            }
        )
    }

    // For backwards compatibility with existing code
    var path: NavigationPath {
        get { homePath }
        set { homePath = newValue }
    }
}

struct RootView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var flixorCore: FlixorCore
    @StateObject private var watchlistController = WatchlistController()
    @State private var isInitializing = true
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    var body: some View {
        Group {
            if isInitializing {
                // Loading state while FlixorCore initializes
                VStack {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading...")
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            } else if !flixorCore.isPlexAuthenticated {
                // Not authenticated - show login
                PlexAuthView()
                    .transition(.opacity)
            } else if !flixorCore.isPlexServerConnected {
                // Authenticated but no server connected - show server/endpoint selection
                ServerEndpointFlowView()
                    .transition(.opacity)
            } else if !hasCompletedOnboarding {
                // Connected but not onboarded - show onboarding
                OnboardingView {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        hasCompletedOnboarding = true
                    }
                }
                .transition(.opacity)
            } else {
                // Fully ready - show main app
                MainView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: flixorCore.isPlexAuthenticated)
        .animation(.easeInOut(duration: 0.3), value: flixorCore.isPlexServerConnected)
        .animation(.easeInOut(duration: 0.3), value: hasCompletedOnboarding)
        .environmentObject(watchlistController)
        .task {
            // Wait for FlixorCore to initialize
            _ = await FlixorCore.shared.initialize()
            // Sync SessionManager with FlixorCore
            sessionManager.updateFromFlixorCore()
            isInitializing = false
        }
    }
}

struct MainView: View {
    @State private var showingSettings = false
    @EnvironmentObject var sessionManager: SessionManager
    @StateObject private var router = NavigationRouter()
    @StateObject private var mainViewState = MainViewState()
    @AppStorage("showNewPopularTab") private var showNewPopularTab: Bool = true

    /// Visible navigation items based on settings
    private var visibleNavItems: [NavItem] {
        NavItem.allCases.filter { item in
            if item == .newPopular && !showNewPopularTab {
                return false
            }
            return true
        }
    }

    var body: some View {
        NavigationStack(path: router.pathBinding(for: mainViewState.selectedTab)) {
            destinationView(for: mainViewState.selectedTab)
                // Centralize PlayerView presentation here to avoid inheriting padding
                .navigationDestination(for: MediaItem.self) { item in
                    PlayerView(item: item)
                        .toolbar(.hidden, for: .windowToolbar)
                        .ignoresSafeArea(.all, edges: .all)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .navigationDestination(for: DetailsNavigationItem.self) { navItem in
                    DetailsView(item: navItem.item)
                }
        }
        .environmentObject(router)
        .environmentObject(mainViewState)
        .toolbar {
            // Logo on left
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 8) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accent)

                    Text("FLIXOR")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                }.padding(.horizontal, 10)
            }

            // Navigation links in center
            ToolbarItemGroup(placement: .principal) {
                HStack(spacing: 32) {
                    ForEach(visibleNavItems) { item in
                        ToolbarNavButton(
                            item: item,
                            isActive: mainViewState.selectedTab == item,
                            onTap: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    // If clicking the current tab, pop to root
                                    if mainViewState.selectedTab == item {
                                        popToRoot(for: item)
                                    } else {
                                        mainViewState.selectedTab = item
                                    }
                                }
                            }
                        )
                    }
                }.padding(.horizontal, 15)
            }

            // User profile menu on right
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if let user = sessionManager.currentUser {
                        Text(user.username)
                            .font(.headline)

                        Divider()
                    }

                    Button(action: {
                        showingSettings = true
                    }) {
                        Label("Settings", systemImage: "gear")
                    }

                    Button(action: {
                        Task {
                            await sessionManager.logout()
                        }
                    }) {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(sessionManager.currentUser?.username.uppercased() ?? "U")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }.padding(.horizontal, 20)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .padding(.horizontal, 15)
            }
        }
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbarBackground(.ultraThinMaterial, for: .windowToolbar)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .onChange(of: showNewPopularTab) { newValue in
            // If New & Popular tab is hidden while on that tab, switch to Home
            if !newValue && mainViewState.selectedTab == .newPopular {
                mainViewState.selectedTab = .home
            }
        }
    }

    private func popToRoot(for tab: NavItem) {
        switch tab {
        case .home:
            if router.homePath.count > 0 {
                router.homePath.removeLast(router.homePath.count)
            }
        case .search:
            if router.searchPath.count > 0 {
                router.searchPath.removeLast(router.searchPath.count)
            }
        case .library:
            if router.libraryPath.count > 0 {
                router.libraryPath.removeLast(router.libraryPath.count)
            }
        case .myList:
            if router.myListPath.count > 0 {
                router.myListPath.removeLast(router.myListPath.count)
            }
        case .newPopular:
            if router.newPopularPath.count > 0 {
                router.newPopularPath.removeLast(router.newPopularPath.count)
            }
        }
    }

    @ViewBuilder
    private func destinationView(for item: NavItem) -> some View {
        switch item {
        case .home:
            HomeView()
        case .search:
            SearchView()
        case .library:
            LibraryView()
        case .myList:
            MyListView()
        case .newPopular:
            NewPopularView()
        }
    }
}

// MARK: - Toolbar Navigation Button
struct ToolbarNavButton: View {
    let item: NavItem
    let isActive: Bool
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            Text(item.rawValue)
                .font(.system(size: 14, weight: isActive ? .semibold : .medium))
                .foregroundStyle(textColor)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var textColor: Color {
        if isActive {
            return .white
        } else if isHovered {
            return .white.opacity(0.8)
        } else {
            return .white.opacity(0.65)
        }
    }
}
#if DEBUG && canImport(PreviewsMacros)
#Preview {
    RootView()
        .environmentObject(SessionManager.shared)
        .environmentObject(APIClient.shared)
}
#endif
