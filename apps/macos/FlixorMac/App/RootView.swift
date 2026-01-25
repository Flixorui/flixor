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
    case downloads = "Downloads"
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
    @Published var downloadsPath = NavigationPath()

    func pathBinding(for tab: NavItem) -> Binding<NavigationPath> {
        Binding(
            get: {
                switch tab {
                case .home: return self.homePath
                case .search: return self.searchPath
                case .library: return self.libraryPath
                case .myList: return self.myListPath
                case .newPopular: return self.newPopularPath
                case .downloads: return self.downloadsPath
                }
            },
            set: { newValue in
                switch tab {
                case .home: self.homePath = newValue
                case .search: self.searchPath = newValue
                case .library: self.libraryPath = newValue
                case .myList: self.myListPath = newValue
                case .newPopular: self.newPopularPath = newValue
                case .downloads: self.downloadsPath = newValue
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
    @ObservedObject private var profileSettings = ProfileSettings.shared

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
            } else if !profileSettings.hasCompletedOnboarding {
                // Connected but not onboarded - show onboarding
                OnboardingView {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        profileSettings.hasCompletedOnboarding = true
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
        .animation(.easeInOut(duration: 0.3), value: profileSettings.hasCompletedOnboarding)
        .environmentObject(watchlistController)
        .task {
            // Wait for FlixorCore to initialize
            _ = await FlixorCore.shared.initialize()
            // Restore session (includes profile context and checking for multiple profiles)
            await sessionManager.restoreSession()
            isInitializing = false
        }
    }
}

struct MainView: View {
    @State private var showingSettings = false
    @State private var showingProfileSelect = false
    @State private var contentRefreshId = UUID()
    @EnvironmentObject var sessionManager: SessionManager
    @StateObject private var router = NavigationRouter()
    @StateObject private var mainViewState = MainViewState()
    @StateObject private var profileManager = ProfileManager.shared
    @ObservedObject private var profileSettings = ProfileSettings.shared

    /// Visible navigation items based on settings
    private var visibleNavItems: [NavItem] {
        NavItem.allCases.filter { item in
            if item == .newPopular && !profileSettings.showNewPopularTab {
                return false
            }
            return true
        }
    }

    // Profile avatar colors
    private let avatarColors: [Color] = [
        Color(red: 0.91, green: 0.3, blue: 0.24),
        Color(red: 0.16, green: 0.5, blue: 0.73),
        Color(red: 0.18, green: 0.8, blue: 0.44),
        Color(red: 0.61, green: 0.35, blue: 0.71),
        Color(red: 0.95, green: 0.77, blue: 0.06),
        Color(red: 0.9, green: 0.49, blue: 0.13),
        Color(red: 0.1, green: 0.74, blue: 0.61),
        Color(red: 0.93, green: 0.46, blue: 0.62),
    ]

    private var profileAvatarColor: Color {
        if let profile = sessionManager.activeProfile {
            let index = abs(profile.userId) % avatarColors.count
            return avatarColors[index]
        }
        return avatarColors[0]
    }

    private var profileInitials: String {
        if let profile = sessionManager.activeProfile {
            let name = profile.title
            let components = name.split(separator: " ")
            if components.count >= 2 {
                return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
            }
            return String(name.prefix(2)).uppercased()
        }
        return sessionManager.currentUser?.username.prefix(1).uppercased() ?? "U"
    }

    var body: some View {
        NavigationStack(path: router.pathBinding(for: mainViewState.selectedTab)) {
            destinationView(for: mainViewState.selectedTab)
                .id(contentRefreshId)
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
                .navigationDestination(for: OfflineMediaItem.self) { item in
                    PlayerView(offlineItem: item)
                        .toolbar(.hidden, for: .windowToolbar)
                        .ignoresSafeArea(.all, edges: .all)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    // Current profile/user info
                    if let profile = sessionManager.activeProfile {
                        Label(profile.title, systemImage: "person.circle.fill")
                            .font(.headline)
                    } else if let user = sessionManager.currentUser {
                        Label(user.username, systemImage: "person.circle")
                            .font(.headline)
                    }

                    Divider()

                    // Switch Profile (only if multiple profiles available)
                    if sessionManager.hasMultipleProfiles {
                        Button(action: {
                            showingProfileSelect = true
                        }) {
                            Label("Switch Profile", systemImage: "person.2")
                        }

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
                    Circle()
                        .fill(profileAvatarColor)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Text(profileInitials)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                        )
                        .padding(.horizontal, 20)
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
        .sheet(isPresented: $showingProfileSelect) {
            ProfileSelectView {
                // Refresh session after profile switch
                sessionManager.refreshProfile()
                // Force content refresh by changing the ID
                contentRefreshId = UUID()
                // Reset navigation to home
                mainViewState.selectedTab = .home
                router.homePath = NavigationPath()
            }
        }
        .onChange(of: profileSettings.showNewPopularTab) { newValue in
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
        case .downloads:
            if router.downloadsPath.count > 0 {
                router.downloadsPath.removeLast(router.downloadsPath.count)
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
        case .downloads:
            DownloadsView()
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
