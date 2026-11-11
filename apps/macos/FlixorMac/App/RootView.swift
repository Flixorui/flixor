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
    @ObservedObject private var appMode = AppModeStore.shared
    #if FLIXOR_LIVE_TV
    @ObservedObject private var liveTV = LiveTVStore.shared
    #endif
    @Environment(\.flixorTheme) private var theme

    /// In Stremio-only mode there is no Plex step at all. A nil mode (existing
    /// installs, upgraded in place) behaves exactly like the old Plex-only flow.
    private var needsPlexAuth: Bool {
        !appMode.isStremioOnly && !flixorCore.isPlexAuthenticated
    }

    private var needsPlexServer: Bool {
        !appMode.isStremioOnly && !flixorCore.isPlexServerConnected
    }

    var body: some View {
        Group {
            if isInitializing {
                // Loading state while FlixorCore initializes
                VStack {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading...")
                        .foregroundColor(.secondary)
                        .padding(.top, DS.Space.s8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            } else if needsPlexAuth {
                // No mode chosen yet, or Plex mode without a token - PlexAuthView
                // doubles as the mode chooser.
                PlexAuthView()
                    .transition(.opacity)
            } else if needsPlexServer {
                // Authenticated but no server connected - show server/endpoint selection
                ServerEndpointFlowView()
                    .transition(.opacity)
            } else if !profileSettings.hasCompletedOnboarding {
                // Connected but not onboarded - show onboarding
                OnboardingView {
                    withAnimation(DS.Motion.emphasized) {
                        profileSettings.hasCompletedOnboarding = true
                    }
                }
                .transition(.opacity)
            } else {
                // Fully ready - show main app
                #if FLIXOR_LIVE_TV
                // Live TV covers the window; MainView stays alive underneath so
                // leaving returns to the same tab and page.
                ZStack {
                    MainView()
                        .toast() // single app-wide toast host
                        .opacity(liveTV.isActive ? 0 : 1)
                        .allowsHitTesting(!liveTV.isActive)
                        .accessibilityHidden(liveTV.isActive)
                    if liveTV.isActive {
                        LiveTVRootView()
                            .transition(.opacity)
                            .zIndex(10)
                    }
                }
                .transition(.opacity)
                .onAppear { if liveTV.openOnLaunch && liveTV.featureEnabled { liveTV.enter() } }
                #else
                MainView()
                    .toast() // single app-wide toast host
                    .transition(.opacity)
                #endif
            }
        }
        .animation(DS.Motion.emphasized, value: needsPlexAuth)
        .animation(DS.Motion.emphasized, value: needsPlexServer)
        .animation(DS.Motion.emphasized, value: profileSettings.hasCompletedOnboarding)
        // Pure black: paint the window black behind screens that leave areas
        // transparent. Off by default so the default look is unchanged.
        .background(theme.pureBlack ? Color.black.ignoresSafeArea() : nil)
        .environmentObject(watchlistController)
        .environment(\.cardWatchlistController, watchlistController)
        .task {
            if UserDefaults.standard.playerBackend == .avplayer {
                UserDefaults.standard.playerBackend = .mpv
                AppLogger.shared.info("[Player] Migrated stored backend preference to MPV for macOS")
            }
            // Wait for FlixorCore to initialize
            let plexRestored = await FlixorCore.shared.initialize()
            // Existing installs have no stored mode; a live Plex session means Plex mode.
            if appMode.mode == nil && plexRestored {
                appMode.select(.plex)
            }
            // Restore session (includes profile context and checking for multiple profiles)
            await sessionManager.restoreSession()
            // The active profile is known now; load its accent/background.
            AppearanceStore.shared.reload()
            isInitializing = false
        }
    }
}

struct MainView: View {
    @State private var showingSettings = false
    @State private var showingProfileSelect = false
    @State private var showingSignOutConfirmation = false
    @State private var contentRefreshId = UUID()
    /// Tabs whose stacks exist. Home and My List start built (My List's load
    /// fills the WatchlistController); others are built when first selected or
    /// warmed after launch, then stay alive.
    @State private var builtTabs: Set<NavItem> = [.home, .myList]
    @EnvironmentObject var sessionManager: SessionManager
    @StateObject private var router = NavigationRouter()
    @StateObject private var mainViewState = MainViewState()
    @StateObject private var profileManager = ProfileManager.shared
    @ObservedObject private var profileSettings = ProfileSettings.shared
    @ObservedObject private var appMode = AppModeStore.shared
    @ObservedObject private var navigationStyle = NavigationStyleStore.shared
    @ObservedObject private var playback = PlaybackCommandState.shared

    /// Sidebar layout chosen and no player covering the window (the
    /// fullscreen player hides the toolbar and the rail).
    private var showsSidebar: Bool {
        navigationStyle.usesSidebar && !playback.isPlayerActive
    }

    /// Top-bar layout on a tab's first page. Pushed pages and the player use the
    /// whole window, and go back with the floating back button.
    private var showsFloatingBar: Bool {
        guard !navigationStyle.usesSidebar, !playback.isPlayerActive else { return false }
        return router.pathBinding(for: mainViewState.selectedTab).wrappedValue.isEmpty
    }

    /// Room the content leaves for the sidebar. A hover-expanded rail floats
    /// over the content; a pinned one pushes it aside.
    private var contentLeadingInset: CGFloat {
        guard showsSidebar else { return 0 }
        return navigationStyle.sidebarPinned ? SidebarMetrics.expandedWidth : SidebarMetrics.collapsedWidth
    }

    /// Profile identity and actions for the sidebar (mirrors the toolbar menu).
    private var sidebarProfileMenu: SidebarProfileMenu {
        SidebarProfileMenu(
            name: sessionManager.activeProfile?.title ?? sessionManager.currentUser?.username ?? String(localized: "Profile"),
            initials: profileInitials,
            avatarColor: profileAvatarColor,
            canSwitchProfile: sessionManager.hasMultipleProfiles,
            isStremioOnly: appMode.isStremioOnly,
            onSwitchProfile: { showingProfileSelect = true },
            onOpenSettings: { showingSettings = true },
            onConnectPlex: { showingSettings = true },
            onSignOut: { showingSignOutConfirmation = true }
        )
    }

    /// Visible navigation items based on settings and the active mode.
    private var visibleNavItems: [NavItem] {
        NavItem.allCases.filter { item in
            if item == .newPopular && !profileSettings.showNewPopularTab {
                return false
            }
            // Downloads fetches Plex parts with an X-Plex-Token, so it has nothing
            // to show without a server. Library stays: it shows the user's collections.
            if appMode.isStremioOnly && item == .downloads {
                return false
            }
            return true
        }
    }

    private func isBuilt(_ tab: NavItem) -> Bool {
        builtTabs.contains(tab) || mainViewState.selectedTab == tab
    }

    /// Delay before warming hidden tabs, and the gap between them, so Home's
    /// first load gets the network and main thread first.
    private static let warmUpDelay: UInt64 = 4_000_000_000
    private static let warmUpGap: UInt64 = 1_500_000_000

    /// Order hidden tabs are warmed in.
    private static let warmUpOrder: [NavItem] = [.library, .newPopular, .search, .downloads]

    /// Builds the remaining tabs one at a time in the background.
    @MainActor
    private func warmUpTabs() async {
        try? await Task.sleep(nanoseconds: Self.warmUpDelay)
        for tab in Self.warmUpOrder {
            guard !Task.isCancelled else { return }
            // Hidden tabs are skipped; they build when shown and selected.
            guard visibleNavItems.contains(tab), !builtTabs.contains(tab) else { continue }
            builtTabs.insert(tab)
            try? await Task.sleep(nanoseconds: Self.warmUpGap)
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
        // Use ZStack with separate NavigationStacks per tab for smooth tab switching
        // Each tab maintains its own navigation state and is shown/hidden via opacity
        // Same outer structure in both layouts so switching never rebuilds
        // the tabs. In top-bar mode the inset is 0 and there is no rail.
        ZStack(alignment: .topLeading) {
            ZStack {
                // Home Tab
                NavigationStack(path: $router.homePath) {
                    HomeView()
                        .navigationDestinations()
                }
                .pushAppearance(depth: router.homePath.count)
                .id(contentRefreshId) // Only changes on profile switch, not tab switch
                .opacity(mainViewState.selectedTab == .home ? 1 : 0)
                .zIndex(mainViewState.selectedTab == .home ? 1 : 0)

                // Search Tab
                if isBuilt(.search) {
                    NavigationStack(path: $router.searchPath) {
                        SearchView()
                            .floatingNavContentInset(!navigationStyle.usesSidebar)
                            .navigationDestinations()
                    }
                    .pushAppearance(depth: router.searchPath.count)
                    .opacity(mainViewState.selectedTab == .search ? 1 : 0)
                    .zIndex(mainViewState.selectedTab == .search ? 1 : 0)
                }

                // Library Tab - not instantiated without Plex, otherwise its .task would
                // still fire /api/plex/libraries while hidden.
                if visibleNavItems.contains(.library) && isBuilt(.library) {
                    NavigationStack(path: $router.libraryPath) {
                        LibraryView()
                            .floatingNavContentInset(!navigationStyle.usesSidebar)
                            .navigationDestinations()
                    }
                    .pushAppearance(depth: router.libraryPath.count)
                    .opacity(mainViewState.selectedTab == .library ? 1 : 0)
                    .zIndex(mainViewState.selectedTab == .library ? 1 : 0)
                }

                // My List Tab
                if isBuilt(.myList) {
                    NavigationStack(path: $router.myListPath) {
                        MyListView()
                            .floatingNavContentInset(!navigationStyle.usesSidebar)
                            .navigationDestinations()
                    }
                    .pushAppearance(depth: router.myListPath.count)
                    .opacity(mainViewState.selectedTab == .myList ? 1 : 0)
                    .zIndex(mainViewState.selectedTab == .myList ? 1 : 0)
                }

                // New & Popular Tab
                if profileSettings.showNewPopularTab && isBuilt(.newPopular) {
                    NavigationStack(path: $router.newPopularPath) {
                        NewPopularView()
                            .floatingNavContentInset(!navigationStyle.usesSidebar)
                            .navigationDestinations()
                    }
                    .pushAppearance(depth: router.newPopularPath.count)
                    .opacity(mainViewState.selectedTab == .newPopular ? 1 : 0)
                    .zIndex(mainViewState.selectedTab == .newPopular ? 1 : 0)
                }

                // Downloads Tab
                if visibleNavItems.contains(.downloads) && isBuilt(.downloads) {
                    NavigationStack(path: $router.downloadsPath) {
                        DownloadsView()
                            .floatingNavContentInset(!navigationStyle.usesSidebar)
                            .navigationDestinations()
                    }
                    .pushAppearance(depth: router.downloadsPath.count)
                    .opacity(mainViewState.selectedTab == .downloads ? 1 : 0)
                    .zIndex(mainViewState.selectedTab == .downloads ? 1 : 0)
                }
            }
            .padding(.leading, contentLeadingInset)

            if showsSidebar {
                SidebarNavigationRail(
                    items: visibleNavItems,
                    selectedTab: mainViewState.selectedTab,
                    onSelect: { selectTab($0) },
                    profile: sidebarProfileMenu
                )
                .zIndex(2)
            }

            if showsFloatingBar {
                FloatingNavigationBar(
                    items: visibleNavItems,
                    selectedTab: mainViewState.selectedTab,
                    onSelect: { selectTab($0) },
                    profile: sidebarProfileMenu
                )
                .ignoresSafeArea(edges: .top)
                .zIndex(3)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if !playback.isPlayerActive {
                FloatingBackButton()
                    .padding(.leading, contentLeadingInset + DetailsSectionStyle.inset)
                    .padding(.top, FloatingBackButton.topPadding)
                    .ignoresSafeArea(edges: .top)
                    .zIndex(4)
            }
        }
        .animation(DS.Motion.standard, value: showsFloatingBar)
        .environmentObject(router)
        .environmentObject(mainViewState)
        .environment(\.cardNavigationContext, CardNavigationContext(router: router, mainViewState: mainViewState))
        .sheet(isPresented: $showingSettings) {
            SettingsView(showsCloseButton: true)
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
        .confirmationDialog(
            "Sign Out",
            isPresented: $showingSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                Task {
                    await sessionManager.logout()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .onChange(of: profileSettings.showNewPopularTab) { newValue in
            // If New & Popular tab is hidden while on that tab, switch to Home
            if !newValue && mainViewState.selectedTab == .newPopular {
                mainViewState.selectedTab = .home
            }
        }
        .onChange(of: appMode.mode) { _ in
            // Connecting or disconnecting Plex changes which tabs exist.
            if !visibleNavItems.contains(mainViewState.selectedTab) {
                mainViewState.selectedTab = .home
            }
        }
        // Mouse back/forward buttons, Esc and Go > Back pop the current tab.
        .background(HostingWindowReader { BackNavigationController.shared.registerWindow($0) })
        .onAppear {
            BackNavigationController.shared.register(router: router, mainViewState: mainViewState)
        }
        // Whatever selects a tab, keep it built once shown.
        .onChange(of: mainViewState.selectedTab) { tab in
            builtTabs.insert(tab)
        }
        .task { await warmUpTabs() }
    }

    /// Tab bar / sidebar tap: switch tabs, or pop to root when the tab is
    /// already selected.
    private func selectTab(_ item: NavItem) {
        if mainViewState.selectedTab == item {
            popToRoot(for: item)
        } else {
            // Instant tab switch - no animation needed
            builtTabs.insert(item)
            mainViewState.selectedTab = item
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

}

// MARK: - Navigation Destinations Extension
extension View {
    /// Common navigation destinations for all tabs.
    ///
    /// All tabs stay alive at opacity 0 and share the window toolbar, so a hidden
    /// tab's stack would still put its system back button there. Every pushed page
    /// hides it; `FloatingBackButton` is the one arrow, for the visible tab.
    func navigationDestinations() -> some View {
        self
            .navigationDestination(for: PlayerDestination.self) { destination in
                PlayerView(destination: destination)
                    .navigationBarBackButtonHidden(true)
                    .toolbar(.hidden, for: .windowToolbar)
                    .ignoresSafeArea(.all, edges: .all)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationDestination(for: DetailsNavigationItem.self) { navItem in
                DetailsView(item: navItem.item)
                    .navigationBarBackButtonHidden(true)
            }
            .navigationDestination(for: StremioSourcesDestination.self) { destination in
                StremioSourcesView(destination: destination)
                    .backButtonContentInset()
                    .navigationBarBackButtonHidden(true)
            }
            .navigationDestination(for: PersonRoute.self) { route in
                PersonDetailView(route: route)
                    .backButtonContentInset()
                    .navigationBarBackButtonHidden(true)
            }
            .navigationDestination(for: BrowseRoute.self) { route in
                BrowsePageView(route: route)
                    .navigationBarBackButtonHidden(true)
            }
            .navigationDestination(for: EntityBrowseRoute.self) { route in
                EntityBrowseView(route: route)
                    .backButtonContentInset()
                    .navigationBarBackButtonHidden(true)
            }
            .navigationDestination(for: UserCollectionRoute.self) { route in
                UserCollectionDetailView(route: route)
                    .backButtonContentInset()
            }
    }
}

// MARK: - Toolbar Back Button

/// Back arrow for the visible tab; shown only when that tab has a page to pop.

// MARK: - Back Button

extension View {
    /// Keeps a pushed page's content clear of the floating back button.
    func backButtonContentInset() -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: FloatingBackButton.contentInset)
        }
    }
}

/// Below the window controls, on every page that has somewhere to go back to.
struct FloatingBackButton: View {
    static let topPadding: CGFloat = 36
    static let size: CGFloat = 40
    /// Space a pushed page leaves below the window's title bar safe area.
    static let contentInset: CGFloat = 56

    @ObservedObject private var navigation = BackNavigationController.shared

    var body: some View {
        if navigation.canGoBack {
            Button {
                navigation.goBack()
            } label: {
                Image(systemName: "arrow.left")
                    .font(.flixorIcon(DS.Icon.md, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: Self.size, height: Self.size)
                    .background(.ultraThinMaterial, in: Circle())
                    .background(Color.black.opacity(0.25), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Back")
            .accessibilityLabel("Back")
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
