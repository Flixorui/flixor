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
    @State private var heroFocusId: UUID = UUID()
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
            // Background
            Color.black.ignoresSafeArea()

            // UltraBlur gradient background
            if let colors = vm.ultraBlurColors {
                UltraBlurGradientBackground(colors: colors, opacity: 0.85)
            } else {
                Color.clear.onAppear {
                    print("🎨 [TVDetails] UltraBlur colors not available yet")
                }
            }

            ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                // Absolute top marker for scroll anchoring
                Color.clear.frame(height: 1).id("scroll-top")

                VStack(spacing: 24) {
                // Top spacer below transparent nav bar
                Color.clear.frame(height: UX.billboardTopPadding)

                // HERO
                ZStack(alignment: .bottomLeading) {
                    TVImage(url: vm.backdropURL, corner: UX.billboardRadius, height: 800)
                        .overlay(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Color.black.opacity(0.65), location: 0.0),
                                    .init(color: Color.black.opacity(0.18), location: 0.55),
                                    .init(color: .clear, location: 1.0)
                                ]),
                                startPoint: .bottom, endPoint: .top
                            )
                            .clipShape(RoundedRectangle(cornerRadius: UX.billboardRadius, style: .continuous))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: UX.billboardRadius, style: .continuous)
                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)

                    VStack(alignment: .leading, spacing: 14) {
                        // Clear logo preferred
                        if let logo = vm.logoURL {
                            AsyncImage(url: logo) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().aspectRatio(contentMode: .fit)
                                        .frame(maxWidth: 520, maxHeight: 150, alignment: .leading)
                                        .shadow(color: .black.opacity(0.8), radius: 12, y: 4)
                                case .empty, .failure:
                                    Text(vm.title.isEmpty ? item.title : vm.title)
                                        .font(.system(size: 56, weight: .bold))
                                @unknown default:
                                    Text(vm.title.isEmpty ? item.title : vm.title)
                                        .font(.system(size: 56, weight: .bold))
                                }
                            }
                        } else {
                            Text(vm.title.isEmpty ? item.title : vm.title)
                                .font(.system(size: 56, weight: .bold))
                        }

                        // Meta line + pills + ratings
                        if !(metaItems.isEmpty && (vm.badges.isEmpty) && vm.externalRatings == nil) {
                            ViewThatFits {
                                HStack(spacing: 10) { metaRow }
                                VStack(alignment: .leading, spacing: 10) { metaRow }
                            }
                        }

                        // Overview
                        if !vm.overview.isEmpty {
                            Text(vm.overview)
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(3)
                                .frame(maxWidth: 1000, alignment: .leading)
                        }

                        // Actions
                        ViewThatFits {
                            HStack(spacing: 16) { actionButtons }
                            VStack(alignment: .leading, spacing: 12) { actionButtons }
                        }
                        .focusSection()
                    }
                    .onPreferenceChange(HeroActionButtonFocusIdKey.self) { newId in
                        if let newId = newId {
                            heroFocusId = newId
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.top, 28)
                    .padding(.bottom, 20)
                }
                .padding(.horizontal, UX.billboardSide)
                .frame(height: 820)
                .id("hero")
                .focusSection()

                // TABS
                VStack(spacing: 0) {
                    TVDetailsTabsBar(tabs: tabs, active: $activeTab, focusNS: nsTabs, reportFocus: $tabsHaveFocus)
                }
                .id("tabs")
                .focusSection()

                // CONTENT
                VStack(spacing: 28) {
                    switch activeTab {
                    case .suggested:
                        Color.clear.frame(height: 1).id("content-suggested")
                        SuggestedSection(vm: vm, focusNS: nsSuggested)
                            .focusScope(nsSuggested)
                    case .details:
                        Color.clear.frame(height: 1).id("content-details")
                        TVDetailsInfoGrid(vm: vm, focusNS: nsDetails)
                            .focusScope(nsDetails)
                    case .episodes:
                        VStack(alignment: .leading, spacing: 16) {
                            Color.clear.frame(height: 1).id("content-episodes")
                            TVSeasonsStrip(vm: vm, focusNS: nsEpisodes)
                            TVEpisodesRail(vm: vm, focusNS: nsEpisodes)
                        }
                        .focusScope(nsEpisodes)
                    case .extras:
                        Color.clear.frame(height: 1).id("content-extras")
                        ExtrasSection(vm: vm, focusNS: nsExtras)
                            .focusScope(nsExtras)
                    }
                }
                .padding(.bottom, 80)
                }
            }
        }
        .onAppear { scrollProxy = proxy }
        .onChange(of: heroFocusId) { newId in
            print("🎯 [TVDetails] Hero button focus changed (\(newId)) - scrolling to top")
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.3)) {
                    scrollProxy?.scrollTo("scroll-top")
                }
            }
        }
        .onChange(of: tabsHaveFocus) { hasFocus in
            if hasFocus {
                print("🎯 [TVDetails] Tabs gained focus - scrolling to tabs")
                withAnimation(.easeOut(duration: 0.24)) {
                    scrollProxy?.scrollTo("tabs", anchor: .top)
                }
            }
        }
        }
        }
        .background(Color.black)
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
        .fullScreenCover(item: $selected) { item in TVDetailsView(item: item) }
    }
}

// MARK: - Details Info
// InfoSection replaced by TVDetailsInfoGrid component

// MARK: - Episodes
// Episodes section now split into TVSeasonsStrip + TVEpisodesRail components

// MARK: - Extras placeholder
private struct ExtrasSection: View {
    @ObservedObject var vm: TVDetailsViewModel
    var focusNS: Namespace.ID
    var body: some View {
        if vm.extras.isEmpty {
            Text("No extras available").foregroundStyle(.white.opacity(0.8)).padding(.horizontal, 48)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(Array(vm.extras.enumerated()), id: \.element.id) { index, ex in
                        TVImage(url: ex.image, corner: 16, aspect: 16/9)
                            .frame(width: 960 * 0.6, height: 540 * 0.6)
                            .focusable(true)
                            .prefersDefaultFocus(index == 0, in: focusNS)
                    }
                }.padding(.horizontal, 48)
            }
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

// Preference key for hero action button focus (carries UUID to detect any focus change)
struct HeroActionButtonFocusIdKey: PreferenceKey {
    static var defaultValue: UUID? = nil
    static func reduce(value: inout UUID?, nextValue: () -> UUID?) {
        value = nextValue() ?? value
    }
}
