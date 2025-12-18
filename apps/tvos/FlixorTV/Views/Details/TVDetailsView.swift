import SwiftUI
import FlixorKit

enum DetailsTab: String { case suggested = "SUGGESTED", details = "DETAILS", episodes = "EPISODES", extras = "EXTRAS" }

struct TVDetailsView: View {
    let item: MediaItem
    @StateObject private var vm = TVDetailsViewModel()
    @State private var activeTab: DetailsTab = .suggested
    @Namespace private var heroFocusNS
    @State private var scrollProxy: ScrollViewProxy?
    @State private var tabsHaveFocus = false
    @State private var contentAreaHasFocus = false
    @State private var heroFocusId: UUID = UUID()

    // Collapse state
    @State private var isCollapsed: Bool = false
    @State private var requestExpand: Bool = false

    // Hero button focus
    enum HeroButton: Hashable { case play, trailer, add }
    @FocusState private var focusedHeroButton: HeroButton?

    // Player state
    @State private var showPlayer = false
    @State private var playbackURL: String?

    // Focus namespaces per section
    @Namespace private var nsTabs
    @Namespace private var nsSuggested
    @Namespace private var nsDetails
    @Namespace private var nsEpisodes
    @Namespace private var nsExtras

    private var tabs: [DetailsTab] {
        var out: [DetailsTab] = []
        // TV or season → Episodes first
        if vm.mediaKind == "tv" || vm.isSeason { out.append(.episodes) }
        // Season-only hides Suggested/Extras
        if !vm.isSeason { out.append(.suggested) }
        out.append(.details)
        if !vm.isSeason { out.append(.extras) }
        return out
    }

    private var metaItems: [String] {
        var parts: [String] = []
        if let y = vm.year, !y.isEmpty { parts.append(y) }
        if let rt = vm.runtime, rt > 0 {
            if rt >= 60 { parts.append("\(rt/60)h \(rt%60)m") } else { parts.append("\(rt)m") }
        }
        if let cr = vm.rating, !cr.isEmpty { parts.append(cr) }
        return parts
    }

    var body: some View {
        ZStack {
            // Layer 1: Full-page backdrop image (edge-to-edge, corner-to-corner)
            AsyncImage(url: vm.backdropURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .empty, .failure:
                    Color.black.opacity(0.3)
                @unknown default:
                    Color.black.opacity(0.3)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(edges: .all)

            // Layer 2: Full-screen gradient overlay for text readability
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color.black.opacity(0.7), location: 0.0),
                    .init(color: Color.black.opacity(0.3), location: 0.35),
                    .init(color: .clear, location: 0.6)
                ]),
                startPoint: .leading, endPoint: .trailing
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(edges: .all)

            // Layer 3: Conditional frosted glass blur (only when collapsed)
            if isCollapsed, let colors = vm.ultraBlurColors {
                ZStack {
                    // Frosted glass material effect
                    Rectangle()
                        .fill(.ultraThinMaterial)

                    // Color overlay from extracted backdrop colors
                    UltraBlurGradientBackground(colors: colors, opacity: 0.6)
                }
                .ignoresSafeArea(edges: .all)
                .transition(.opacity)
            }

            // Layer 4: Content - VStack with collapsing hero
            VStack(spacing: 0) {
                // HERO - Collapsible section
                ZStack(alignment: .topLeading) {

                    // Content Overlay: Fixed-width column on left
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            // Logo (if available), otherwise show title
                            if let logo = vm.logoURL {
                                AsyncImage(url: logo) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image.resizable().aspectRatio(contentMode: .fit)
                                            .frame(
                                                maxWidth: isCollapsed ? 80 : 320,
                                                maxHeight: isCollapsed ? 40 : 100,
                                                alignment: .leading
                                            )
                                            .shadow(color: .black.opacity(0.6), radius: 8, y: 4)
                                    case .empty, .failure:
                                        // Fallback to title if logo fails to load
                                        Text(vm.title.isEmpty ? item.title : vm.title)
                                            .font(.system(size: isCollapsed ? 20 : 48, weight: .bold))
                                            .foregroundStyle(.white)
                                            .lineLimit(2)
                                    @unknown default:
                                        // Fallback to title
                                        Text(vm.title.isEmpty ? item.title : vm.title)
                                            .font(.system(size: isCollapsed ? 20 : 48, weight: .bold))
                                            .foregroundStyle(.white)
                                            .lineLimit(2)
                                    }
                                }
                                .padding(.bottom, isCollapsed ? 0 : 12)
                            } else {
                                // No logo available, show title
                                Text(vm.title.isEmpty ? item.title : vm.title)
                                    .font(.system(size: isCollapsed ? 20 : 48, weight: .bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                    .padding(.bottom, isCollapsed ? 0 : 16)
                            }

                            // Meta badges (TV-14, HD, 5.1, CC style) and meta text combined
                            if !isCollapsed {
                                HStack(spacing: 8) {
                                    // Technical badges
                                    if !vm.badges.isEmpty {
                                        ForEach(vm.badges, id: \.self) { badge in
                                            Text(badge)
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundStyle(.white.opacity(0.9))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                                        .stroke(Color.white.opacity(0.4), lineWidth: 1)
                                                )
                                        }
                                    }
                                }
                                .padding(.bottom, 12)
                                .opacity(isCollapsed ? 0 : 1)

                                // Rating badges (IMDB, Rotten Tomatoes)
                                if let ratings = vm.externalRatings {
                                    TVRatingsStrip(ratings: ratings)
                                        .padding(.bottom, 8)
                                        .opacity(isCollapsed ? 0 : 1)
                                }

                                // Meta text line (year, runtime, rating)
                                if !metaItems.isEmpty {
                                    Text(metaItems.joined(separator: " • "))
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.75))
                                        .padding(.bottom, 20)
                                        .opacity(isCollapsed ? 0 : 1)
                                }

                                // Overview
                                if !vm.overview.isEmpty {
                                    Text(vm.overview)
                                        .font(.system(size: 20, weight: .regular))
                                        .foregroundStyle(.white.opacity(0.85))
                                        .lineLimit(4)
                                        .lineSpacing(4)
                                        .padding(.bottom, 24)
                                        .opacity(isCollapsed ? 0 : 1)
                                }

                                // Action Buttons
                                HStack(spacing: 16) { heroActionButtons }
                                    .focusSection()
                                    .opacity(isCollapsed ? 0 : 1)
                            }
                        }
                        .onPreferenceChange(HeroActionButtonFocusIdKey.self) { newId in
                            if let newId = newId {
                                heroFocusId = newId
                            }
                        }
                        .frame(width: isCollapsed ? 200 : 550)
                        .padding(.leading, isCollapsed ? 60 : 80)
                        .padding(.top, isCollapsed ? 40 : (UX.billboardTopPadding + 100))
                        .padding(.bottom, isCollapsed ? 0 : 100)

                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: isCollapsed ? 120 : (900 + UX.billboardTopPadding))
                .clipped()
                .id("hero")
                .focusSection()
                .animation(.spring(response: 0.5, dampingFraction: 0.75), value: isCollapsed)

                // TAB BAR - Fixed position below hero
                TVDetailsTabsBar(tabs: tabs, active: $activeTab, reportFocus: $tabsHaveFocus, requestExpand: $requestExpand)
                    .frame(height: 60)
                    .padding(.horizontal, 80)
                    .id("tabs")
                    .focusSection()

                // CONTENT - Scrollable area
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 28) {
                            switch activeTab {
                            case .suggested:
                                Color.clear.frame(height: 1).id("content-suggested")
                                SuggestedSection(vm: vm, focusNS: nsSuggested)
                                    .focusScope(nsSuggested)
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                                        removal: .opacity.combined(with: .move(edge: .leading))
                                    ))
                            case .details:
                                Color.clear.frame(height: 1).id("content-details")
                                TVDetailsInfoGrid(vm: vm, focusNS: nsDetails)
                                    .focusScope(nsDetails)
                                    .preference(key: ContentAreaFocusKey.self, value: true)
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                                        removal: .opacity.combined(with: .move(edge: .leading))
                                    ))
                            case .episodes:
                                VStack(alignment: .leading, spacing: 24) {
                                    Color.clear.frame(height: 1).id("content-episodes")
                                    TVEpisodesRail(vm: vm, focusNS: nsEpisodes)
                                }
                                .focusScope(nsEpisodes)
                                .preference(key: ContentAreaFocusKey.self, value: true)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .trailing)),
                                    removal: .opacity.combined(with: .move(edge: .leading))
                                ))
                            case .extras:
                                Color.clear.frame(height: 1).id("content-extras")
                                ExtrasSection(vm: vm, focusNS: nsExtras)
                                    .focusScope(nsExtras)
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                                        removal: .opacity.combined(with: .move(edge: .leading))
                                    ))
                            }
                        }
                        .padding(.bottom, 80)
                        .frame(minHeight: 800)
                        .onPreferenceChange(ContentAreaFocusKey.self) { hasFocus in
                            contentAreaHasFocus = hasFocus
                        }
                    }
                    .disabled(!isCollapsed)
                    .onAppear { scrollProxy = proxy }
                }
            }  // End main VStack
        }  // End ZStack
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: .all)
        .fullScreenCover(isPresented: $showPlayer) {
            if let url = playbackURL {
                PlayerView(playbackURL: url)
            }
        }
        .task {
            await vm.load(for: item)
            // Default tab depending on mediaKind
            if vm.mediaKind == "tv" || vm.isSeason { activeTab = .episodes } else { activeTab = .suggested }
        }
        .onChange(of: vm.mediaKind) { _ in
            if vm.mediaKind == "tv" || vm.isSeason { activeTab = .episodes } else { activeTab = .suggested }
        }
        .onChange(of: vm.ultraBlurColors) { colors in
            if let colors = colors {
                print("🎨 [TVDetails] UltraBlur colors updated: TL=\(colors.topLeft) TR=\(colors.topRight) BL=\(colors.bottomLeft) BR=\(colors.bottomRight)")
            } else {
                print("🎨 [TVDetails] UltraBlur colors cleared")
            }
        }
        .onChange(of: tabsHaveFocus) { hasFocus in
            if hasFocus && !isCollapsed && focusedHeroButton == nil {
                print("🎯 [TVDetails] Tabs gained focus - collapsing hero")
                withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                    isCollapsed = true
                }
            }
        }
        .onChange(of: focusedHeroButton) { button in
            if button != nil && isCollapsed {
                // If hero button gains focus while collapsed, expand automatically
                print("🎯 [TVDetails] Hero button focused while collapsed - expanding")
                withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                    isCollapsed = false
                }
            }
        }
        .onChange(of: requestExpand) { shouldExpand in
            if shouldExpand && isCollapsed {
                print("🎯 [TVDetails] Expand requested - expanding hero")
                // Cancel any ongoing animations by immediately setting state
                withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                    isCollapsed = false
                }
                // Auto-focus first hero button after expansion animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    focusedHeroButton = .play
                }
                // Reset scroll position
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    scrollProxy?.scrollTo("content-\(activeTab.rawValue.lowercased())", anchor: .top)
                }
                // Reset request flag
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    requestExpand = false
                }
            } else if shouldExpand && !isCollapsed {
                // Already expanded, just reset flag
                requestExpand = false
            }
        }
        .onChange(of: isCollapsed) { collapsed in
            print("🎯 [TVDetails] Hero collapse state changed: \(collapsed ? "COLLAPSED" : "EXPANDED")")
        }
        .onChange(of: activeTab) { newTab in
            if isCollapsed {
                // Animate tab content transitions when collapsed
                withAnimation(.easeInOut(duration: 0.3)) {
                    // Animation context for transition
                }
                // Reset scroll position for new tab
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    scrollProxy?.scrollTo("content-\(newTab.rawValue.lowercased())", anchor: .top)
                }
            }
        }
    }

    @ViewBuilder private var metaRow: some View {
        if !metaItems.isEmpty {
            Text(metaItems.joined(separator: " • "))
                .font(.system(size: 22, weight: .medium))
                .opacity(0.9)
        }
        ForEach(vm.badges, id: \.self) { b in
            TVMetaPill(text: b)
        }
        if let ratings = vm.externalRatings { TVRatingsStrip(ratings: ratings) }
    }

    @ViewBuilder private var actionButtons: some View {
        DetailsCTA(title: vm.playableId != nil ? "Play" : "Play", systemName: "play.fill", primary: false, isDefaultFocusTarget: true, focusNS: heroFocusNS)
        DetailsCTA(title: "My List", systemName: "plus")
    }

    @ViewBuilder private var heroActionButtons: some View {
        HeroPlayButton(isDefaultFocusTarget: true, focusNS: heroFocusNS, action: playContent)
            .focused($focusedHeroButton, equals: .play)
        HeroTrailerButton(focusNS: heroFocusNS)
            .focused($focusedHeroButton, equals: .trailer)
        HeroAddButton(focusNS: heroFocusNS)
            .focused($focusedHeroButton, equals: .add)
    }

    // MARK: - Playback

    private func playContent() {
        print("🎬 [TVDetails] Play button tapped")

        // Build playback URL from Plex ratingKey
        guard let ratingKey = vm.plexRatingKey else {
            print("❌ [TVDetails] No playable content available")
            return
        }

        // Get Plex server info from APIClient
        let api = APIClient.shared
        let baseURL = api.baseURL.absoluteString.replacingOccurrences(of: "/api", with: "")

        // TODO: Get actual Plex token from session
        // For now, this will need to be wired up with proper auth
        guard let plexURL = URL(string: "\(baseURL)/plex/library/metadata/\(ratingKey)") else {
            print("❌ [TVDetails] Failed to construct Plex URL")
            return
        }

        print("✅ [TVDetails] Playing: \(plexURL.absoluteString)")
        playbackURL = plexURL.absoluteString
        showPlayer = true
    }
}

// MARK: - Tabs
// Old inline tabs replaced by TVDetailsTabsBar component

// MARK: - Suggested
private struct SuggestedSection: View {
    @ObservedObject var vm: TVDetailsViewModel
    var focusNS: Namespace.ID
    @State private var selected: MediaItem?
    @State private var focusedRowId: String?
    @State private var rowLastFocusedItem: [String: String] = [:]
    @State private var nextRowToReceiveFocus: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if !vm.related.isEmpty {
                TVCarouselRow(
                    title: "Because you watched",
                    items: vm.related,
                    kind: .poster,
                    focusNS: focusNS,
                    defaultFocus: focusedRowId == "because-you-watched" || nextRowToReceiveFocus == "because-you-watched" || focusedRowId == nil,
                    preferredFocusItemId: rowLastFocusedItem["because-you-watched"],
                    sectionId: "because-you-watched",
                    onSelect: { selected = $0 }
                )
            }
            if !vm.similar.isEmpty {
                TVCarouselRow(
                    title: "More like this",
                    items: vm.similar,
                    kind: .poster,
                    focusNS: focusNS,
                    defaultFocus: focusedRowId == "more-like-this" || nextRowToReceiveFocus == "more-like-this" || (vm.related.isEmpty && focusedRowId == nil),
                    preferredFocusItemId: rowLastFocusedItem["more-like-this"],
                    sectionId: "more-like-this",
                    onSelect: { selected = $0 }
                )
            }
        }
        .onPreferenceChange(RowFocusKey.self) { newId in
            let previousId = focusedRowId
            if previousId != newId {
                nextRowToReceiveFocus = newId
                focusedRowId = newId
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    nextRowToReceiveFocus = nil
                }
            }
        }
        .onPreferenceChange(RowItemFocusKey.self) { value in
            if let rowId = value.rowId, let itemId = value.itemId {
                rowLastFocusedItem[rowId] = itemId
            }
        }
        .preference(key: ContentAreaFocusKey.self, value: focusedRowId != nil)
        .fullScreenCover(item: $selected) { item in TVDetailsView(item: item) }
    }
}

// MARK: - Details Info
// InfoSection replaced by TVDetailsInfoGrid component

// MARK: - Episodes
// Episodes section handled by redesigned TVEpisodesRail (with integrated season sidebar)

// MARK: - Extras placeholder
private struct ExtrasSection: View {
    @ObservedObject var vm: TVDetailsViewModel
    var focusNS: Namespace.ID
    @State private var hasFocus = false

    var body: some View {
        if vm.extras.isEmpty {
            Text("No extras available").foregroundStyle(.white.opacity(0.8)).padding(.horizontal, 48)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(Array(vm.extras.enumerated()), id: \.element.id) { index, ex in
                        TVImage(url: ex.image, corner: 16, aspect: 16/9)
                            .frame(width: 960 * 0.6, height: 540 * 0.6)
                            .focusable(true) { focused in
                                if focused { hasFocus = true }
                            }
                            .prefersDefaultFocus(index == 0, in: focusNS)
                    }
                }.padding(.horizontal, 48)
            }
            .preference(key: ContentAreaFocusKey.self, value: hasFocus)
        }
    }
}

// Local CTA button replicating Home hero style
private struct DetailsCTA: View {
    let title: String
    let systemName: String
    var primary: Bool = false
    var isDefaultFocusTarget: Bool = false
    var focusNS: Namespace.ID? = nil
    @State private var focused: Bool = false
    @State private var focusId: UUID? = nil

    // Computed property for background color
    private var backgroundColor: Color {
        if focused {
            return Color.white  // Full white when focused
        } else if primary {
            return Color.white.opacity(0.55)  // 55% white when primary but not focused
        } else {
            return Color.white.opacity(focused ? 0.18 : 0.10)  // 10-18% white for secondary
        }
    }

    // Computed property for text color
    private var textColor: Color {
        if focused {
            return Color.black  // Black when focused (any button)
        } else if primary {
            return Color.black  // Black for primary when not focused
        } else {
            return Color.white.opacity(0.85)  // Dimmed white for secondary when not focused
        }
    }

    // Show stroke only when focused
    private var strokeOpacity: Double {
        focused ? 0.4 : 0.0
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemName)
            Text(title)
        }
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(textColor)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Capsule().fill(backgroundColor))
        .overlay(Capsule().stroke(Color.white.opacity(strokeOpacity), lineWidth: 2))
        .focusable(true) { f in
            focused = f
            if f {
                focusId = UUID()
            } else {
                focusId = nil
            }
        }
        .preference(key: HeroActionButtonFocusIdKey.self, value: focusId)
        .modifier(PreferredDefaultDetailsFocusModifier(enabled: isDefaultFocusTarget, ns: focusNS))
        .scaleEffect(focused ? 1.06 : 1.0)
        .shadow(color: .black.opacity(focused ? 0.35 : 0.0), radius: 12, y: 4)
        .animation(.easeOut(duration: 0.18), value: focused)
    }
}

private struct PreferredDefaultDetailsFocusModifier: ViewModifier {
    let enabled: Bool
    let ns: Namespace.ID?
    func body(content: Content) -> some View {
        if let ns, enabled {
            content.prefersDefaultFocus(true, in: ns)
        } else {
            content
        }
    }
}

// MARK: - Hero Action Buttons

// Primary PLAY button - solid white background, black text
private struct HeroPlayButton: View {
    var isDefaultFocusTarget: Bool = false
    var focusNS: Namespace.ID? = nil
    var action: (() -> Void)? = nil
    @FocusState private var isFocused: Bool
    @State private var focusId: UUID? = nil

    var body: some View {
        Button(action: {
            print("🎬 [HeroPlayButton] Button tapped!")
            action?()
        }) {
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                    .font(.system(size: 20, weight: .bold))
                Text("PLAY")
                    .font(.system(size: 24, weight: .semibold))
            }
            .foregroundStyle(isFocused ? Color.white : Color.black)
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .frame(width: 180, height: 56)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isFocused ? Color.black : Color.white)
            )
        }
        .buttonStyle(.card)
        .scaleEffect(isFocused ? 1.08 : 1.0)
        .shadow(color: .black.opacity(isFocused ? 0.4 : 0.2), radius: isFocused ? 16 : 8, y: isFocused ? 8 : 4)
        .focused($isFocused)
        .onChange(of: isFocused) { focused in
            if focused {
                focusId = UUID()
            } else {
                focusId = nil
            }
        }
        .preference(key: HeroActionButtonFocusIdKey.self, value: focusId)
        .modifier(PreferredDefaultDetailsFocusModifier(enabled: isDefaultFocusTarget, ns: focusNS))
        .animation(.easeOut(duration: 0.18), value: isFocused)
    }
}

// Secondary TRAILER button - dark gray background, white text
private struct HeroTrailerButton: View {
    var focusNS: Namespace.ID? = nil
    @State private var focused: Bool = false
    @State private var focusId: UUID? = nil

    var body: some View {
        HStack(spacing: 10) {
            Text("TRAILER")
                .font(.system(size: 24, weight: .semibold))
        }
        .foregroundStyle(.white.opacity(focused ? 1.0 : 0.9))
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
        .frame(width: 200, height: 56)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(focused ? 0.35 : 0.25))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(focused ? 0.5 : 0.2), lineWidth: focused ? 2 : 1)
        )
        .scaleEffect(focused ? 1.08 : 1.0)
        .shadow(color: .black.opacity(focused ? 0.4 : 0.0), radius: focused ? 16 : 0, y: focused ? 8 : 0)
        .focusable(true) { f in
            focused = f
            if f {
                focusId = UUID()
            } else {
                focusId = nil
            }
        }
        .preference(key: HeroActionButtonFocusIdKey.self, value: focusId)
        .animation(.easeOut(duration: 0.18), value: focused)
    }
}

// Circular ADD button - dark background, plus icon only
private struct HeroAddButton: View {
    var focusNS: Namespace.ID? = nil
    @State private var focused: Bool = false
    @State private var focusId: UUID? = nil

    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(.white.opacity(focused ? 1.0 : 0.9))
            .frame(width: 56, height: 56)
            .background(
                Circle()
                    .fill(Color.white.opacity(focused ? 0.35 : 0.25))
            )
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(focused ? 0.5 : 0.2), lineWidth: focused ? 2 : 1)
            )
            .scaleEffect(focused ? 1.12 : 1.0)
            .shadow(color: .black.opacity(focused ? 0.4 : 0.0), radius: focused ? 16 : 0, y: focused ? 8 : 0)
            .focusable(true) { f in
                focused = f
                if f {
                    focusId = UUID()
                } else {
                    focusId = nil
                }
            }
            .preference(key: HeroActionButtonFocusIdKey.self, value: focusId)
            .animation(.easeOut(duration: 0.18), value: focused)
    }
}

// Preference key for hero action button focus (carries UUID to detect any focus change)
struct HeroActionButtonFocusIdKey: PreferenceKey {
    static var defaultValue: UUID? = nil
    static func reduce(value: inout UUID?, nextValue: () -> UUID?) {
        value = nextValue() ?? value
    }
}

// Preference key for tracking content area focus
struct ContentAreaFocusKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}
