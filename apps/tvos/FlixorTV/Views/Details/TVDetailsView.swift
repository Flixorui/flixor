import SwiftUI
import FlixorKit

enum DetailsTab: String { case suggested = "SUGGESTED", details = "DETAILS", episodes = "EPISODES", extras = "EXTRAS" }

struct TVDetailsView: View {
    let item: MediaItem
    @StateObject private var vm = TVDetailsViewModel()
    @State private var activeTab: DetailsTab = .suggested
    @Namespace private var heroFocusNS
    @State private var forceHeroFocus = false
    private enum SectionAnchor { case hero, tabs, contentSuggested, contentDetails, contentEpisodes, contentExtras }
    @State private var section: SectionAnchor = .hero
    @State private var scrollProxy: ScrollViewProxy?
    // Focus namespaces per section
    @Namespace private var nsTabs
    @Namespace private var nsSuggested
    @Namespace private var nsDetails
    @Namespace private var nsEpisodes
    @Namespace private var nsExtras
    // One-shot default focus flags when entering content sections and tabs
    @State private var dfTabs = false
    @State private var dfSuggested = false
    @State private var dfDetails = false
    @State private var dfEpisodes = false
    @State private var dfExtras = false

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

            ScrollViewReader { vProxy in
            ScrollView(.vertical, showsIndicators: false) {
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
                    TVDetailsTabsBar(tabs: tabs, active: $activeTab, focusNS: nsTabs, defaultFocus: dfTabs)
                }
                .id("tabs")
                .focusSection()

                // CONTENT
                VStack(spacing: 28) {
                    switch activeTab {
                    case .suggested:
                        Color.clear.frame(height: 1).id("content-suggested")
                        SuggestedSection(vm: vm, focusNS: nsSuggested, defaultFocus: dfSuggested)
                            .focusScope(nsSuggested)
                            .focusSection()
                    case .details:
                        Color.clear.frame(height: 1).id("content-details")
                        TVDetailsInfoGrid(vm: vm, focusNS: nsDetails, defaultFocus: dfDetails)
                            .focusScope(nsDetails)
                            .focusSection()
                    case .episodes:
                        VStack(alignment: .leading, spacing: 16) {
                            Color.clear.frame(height: 1).id("content-episodes")
                            TVSeasonsStrip(vm: vm, focusNS: nsEpisodes, defaultFocus: dfEpisodes)
                            TVEpisodesRail(vm: vm, focusNS: nsEpisodes, defaultFocus: false)
                        }
                        .focusScope(nsEpisodes)
                        .focusSection()
                    case .extras:
                        Color.clear.frame(height: 1).id("content-extras")
                        ExtrasSection(vm: vm, focusNS: nsExtras, defaultFocus: dfExtras)
                            .focusScope(nsExtras)
                            .focusSection()
                    }
                }
                .padding(.bottom, 80)
            }
        }
        .onMoveCommand { dir in
            switch dir {
            case .down:
                if section == .hero {
                    withAnimation(.easeOut(duration: 0.24)) { vProxy.scrollTo("tabs", anchor: .top) }
                    section = .tabs
                    dfTabs = true; DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { dfTabs = false }
                } else if section == .tabs {
                    let targetId: String = {
                        switch activeTab {
                        case .suggested: return "content-suggested"
                        case .details: return "content-details"
                        case .episodes: return "content-episodes"
                        case .extras: return "content-extras"
                        }
                    }()
                    withAnimation(.easeOut(duration: 0.24)) { vProxy.scrollTo(targetId, anchor: .top) }
                    section = {
                        switch activeTab {
                        case .suggested: return .contentSuggested
                        case .details: return .contentDetails
                        case .episodes: return .contentEpisodes
                        case .extras: return .contentExtras
                        }
                    }()
                    // Arm one-shot default focus for the target section
                    switch activeTab {
                    case .suggested:
                        dfSuggested = true; DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { dfSuggested = false }
                    case .details:
                        dfDetails = true; DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { dfDetails = false }
                    case .episodes:
                        dfEpisodes = true; DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { dfEpisodes = false }
                    case .extras:
                        dfExtras = true; DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { dfExtras = false }
                    }
                }
            case .up:
                if section == .contentSuggested || section == .contentDetails || section == .contentEpisodes || section == .contentExtras {
                    withAnimation(.easeOut(duration: 0.24)) { vProxy.scrollTo("tabs", anchor: .top) }
                    section = .tabs
                    dfTabs = true; DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { dfTabs = false }
                } else if section == .tabs {
                    withAnimation(.easeOut(duration: 0.24)) { vProxy.scrollTo("hero", anchor: .top) }
                    section = .hero
                    forceHeroFocus = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { forceHeroFocus = false }
                }
            default:
                break
            }
        }
        .onAppear { scrollProxy = vProxy }
        }
        .task {
            await vm.load(for: item)
            // Default tab depending on mediaKind
            if vm.mediaKind == "tv" || vm.isSeason { activeTab = .episodes } else { activeTab = .suggested }
            section = .hero
        }
        .onChange(of: vm.mediaKind) { _ in
            if vm.mediaKind == "tv" || vm.isSeason { activeTab = .episodes } else { activeTab = .suggested }
        }
        .onChange(of: activeTab) { _ in
            // When tab changes, stay at tabs and let Down move into content
            withAnimation(.easeOut(duration: 0.24)) { scrollProxy?.scrollTo("tabs", anchor: .top) }
            section = .tabs
        }
        .onChange(of: vm.ultraBlurColors) { colors in
            if let colors = colors {
                print("🎨 [TVDetails] UltraBlur colors updated: TL=\(colors.topLeft) TR=\(colors.topRight) BL=\(colors.bottomLeft) BR=\(colors.bottomRight)")
            } else {
                print("🎨 [TVDetails] UltraBlur colors cleared")
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
        DetailsCTA(title: vm.playableId != nil ? "Play" : "Play", systemName: "play.fill", primary: true)
            .prefersDefaultFocus(forceHeroFocus, in: heroFocusNS)
        DetailsCTA(title: "My List", systemName: "plus")
    }
}

// MARK: - Tabs
// Old inline tabs replaced by TVDetailsTabsBar component

// MARK: - Suggested
private struct SuggestedSection: View {
    @ObservedObject var vm: TVDetailsViewModel
    var focusNS: Namespace.ID
    var defaultFocus: Bool
    @State private var selected: MediaItem?
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if !vm.related.isEmpty {
                TVCarouselRow(title: "Because you watched", items: vm.related, kind: .poster, focusNS: focusNS, defaultFocus: defaultFocus, sectionId: "because-you-watched", onSelect: { selected = $0 })
            }
            if !vm.similar.isEmpty {
                TVCarouselRow(title: "More like this", items: vm.similar, kind: .poster, focusNS: focusNS, defaultFocus: !vm.related.isEmpty ? false : defaultFocus, sectionId: "more-like-this", onSelect: { selected = $0 })
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
    var defaultFocus: Bool
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
                            .prefersDefaultFocus(defaultFocus && index == 0, in: focusNS)
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
    @State private var focused: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemName)
            Text(title)
        }
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(primary ? Color.black : Color.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Capsule().fill(primary ? Color.white : Color.white.opacity(focused ? 0.18 : 0.10)))
        .overlay(Capsule().stroke(Color.white.opacity(!primary && focused ? 0.35 : 0.0), lineWidth: 1))
        .focusable(true) { f in focused = f }
        .scaleEffect(focused ? 1.06 : 1.0)
        .animation(.easeOut(duration: 0.18), value: focused)
    }
}
