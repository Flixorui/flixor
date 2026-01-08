//
//  DetailsView.swift
//  FlixorMac
//
//  Minimal details page to enable navigation from Home
//

import SwiftUI

private struct DetailsLayoutMetrics {
    let width: CGFloat

    var heroHeight: CGFloat {
        switch width {
        case ..<900: return 900
        case ..<1200: return 1200
        case ..<1500: return 1520
        default: return 2000
        }
    }

    var heroHorizontalPadding: CGFloat {
        switch width {
        case ..<900: return 32
        case ..<1200: return 44
        case ..<1600: return 60
        default: return 72
        }
    }

    var heroTopPadding: CGFloat {
        switch width {
        case ..<900: return 108
        case ..<1200: return 128
        default: return 416
        }
    }

    var heroBottomPadding: CGFloat {
        switch width {
        case ..<900: return 56
        case ..<1400: return 72
        default: return 88
        }
    }

    var heroTextMaxWidth: CGFloat {
        min(width * 0.52, 640)
    }

    var contentPadding: CGFloat {
        switch width {
        case ..<900: return 20
        case ..<1200: return 20
        default: return 20
        }
    }

    var tabsPadding: CGFloat {
        switch width {
        case ..<900: return 20
        case ..<1200: return 20
        default: return 20
        }
    }

    var contentMaxWidth: CGFloat {
        min(width - contentPadding * 2, 1320)
    }

    var infoGridColumns: Int {
        if width >= 1320 { return 3 }
        if width >= 960 { return 2 }
        return 1
    }

    var technicalGridMinimum: CGFloat {
        if width >= 1500 { return 240 }
        if width >= 1200 { return 220 }
        if width >= 960 { return 200 }
        return 180
    }

    var castGridMinimum: CGFloat {
        if width >= 1500 { return 180 }
        if width >= 1200 { return 170 }
        if width >= 960 { return 160 }
        return 150
    }

    var extraCardMinimum: CGFloat {
        if width >= 1400 { return 300 }
        if width >= 1100 { return 260 }
        if width >= 900 { return 220 }
        return 200
    }

    var episodeThumbnailWidth: CGFloat {
        if width >= 1500 { return 260 }
        if width >= 1250 { return 240 }
        if width >= 1000 { return 220 }
        if width >= 820 { return 200 }
        return 180
    }
}

struct DetailsView: View {
    let item: MediaItem
    @StateObject private var vm = DetailsViewModel()
    @State private var activeTab: String = "SUGGESTED"
    @StateObject private var browseViewModel = BrowseModalViewModel()
    @State private var showBrowseModal = false
    @State private var activeBrowseContext: BrowseContext?
    @StateObject private var personViewModel = PersonModalViewModel()
    @State private var showPersonModal = false
    @State private var activePerson: PersonReference?
    @EnvironmentObject private var router: NavigationRouter
    @EnvironmentObject private var mainView: MainViewState

    private var hasPlexSource: Bool {
        vm.playableId != nil || vm.plexRatingKey != nil
    }

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                let width = max(proxy.size.width, 640)
                let layout = DetailsLayoutMetrics(width: width)

                ScrollView {
                    VStack(spacing: 20) {
                        VStack(spacing: 0) {
                            DetailsHeroSection(
                                vm: vm,
                                trailers: vm.trailers,
                                onPlay: playContent,
                                layout: layout
                            )

                            DetailsTabsBar(tabs: tabsData, activeTab: $activeTab)
                        }

                        VStack(spacing: 32) {
                            switch activeTab {
                            case "SUGGESTED":
                                SuggestedSections(vm: vm, layout: layout, onBrowse: { context in
                                    presentBrowse(context)
                                })
                            case "DETAILS":
                                DetailsTabContent(vm: vm, layout: layout, onPersonTap: { person in
                                    presentPerson(person)
                                })
                            case "EPISODES":
                                EpisodesTabContent(vm: vm, layout: layout, onPlayEpisode: playEpisode, hasPlexSource: hasPlexSource)
                            default:
                                SuggestedSections(vm: vm, layout: layout, onBrowse: { context in
                                    presentBrowse(context)
                                })
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, layout.contentPadding)
                        .padding(.bottom, 32)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)

            if showBrowseModal {
                BrowseModalView(
                    isPresented: $showBrowseModal,
                    viewModel: browseViewModel,
                    onSelect: { media in
                        showBrowseModal = false
                        Task {
                            await vm.load(for: media)
                            await MainActor.run {
                                activeTab = (vm.mediaKind == "tv") ? "EPISODES" : "SUGGESTED"
                            }
                        }
                    }
                )
                .padding(.top, 80)
                .transition(.opacity)
                .zIndex(2)
            }

            if showPersonModal {
                PersonModalView(
                    isPresented: $showPersonModal,
                    person: activePerson,
                    viewModel: personViewModel,
                    onSelect: { media in
                        showPersonModal = false
                        Task {
                            await vm.load(for: media)
                            await MainActor.run {
                                activeTab = (vm.mediaKind == "tv") ? "EPISODES" : "SUGGESTED"
                            }
                        }
                    }
                )
                .padding(.top, 80)
                .transition(.opacity)
                .zIndex(3)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(HomeBackground())
        .navigationTitle("")
        .task {
            await vm.load(for: item)
            if vm.mediaKind == "tv" || vm.isSeason { activeTab = "EPISODES" }
        }
        .onChange(of: showBrowseModal) { value in
            if !value {
                activeBrowseContext = nil
                browseViewModel.reset()
            }
        }
        .onChange(of: showPersonModal) { value in
            if !value {
                activePerson = nil
                personViewModel.reset()
            }
        }
        // Destination for PlayerView is handled at root via NavigationStack(path:)
    }

    private func playContent() {
        // If we have a playableId from the ViewModel, use it
        if let playableId = vm.playableId {
            // CRITICAL: Preserve episode type from original item
            // vm.mediaKind only stores "movie" or "tv", but episodes need type="episode"
            let mediaType: String = {
                if item.type == "episode" {
                    return "episode"
                }
                return vm.mediaKind ?? item.type
            }()

            let playerItem = MediaItem(
                id: playableId,
                title: vm.title.isEmpty ? item.title : vm.title,
                type: mediaType,
                thumb: item.thumb,
                art: item.art,
                year: vm.year.flatMap { Int($0) },
                rating: nil,
                duration: vm.runtime.map { $0 * 60000 },
                viewOffset: nil,
                summary: vm.overview.isEmpty ? nil : vm.overview,
                grandparentTitle: item.grandparentTitle,
                grandparentThumb: item.grandparentThumb,
                grandparentArt: item.grandparentArt,
                grandparentRatingKey: item.grandparentRatingKey,
                parentIndex: item.parentIndex,
                index: item.index,
                parentRatingKey: item.parentRatingKey,
                parentTitle: item.parentTitle,
                leafCount: item.leafCount,
                viewedLeafCount: item.viewedLeafCount
            )
            appendToCurrentTabPath(playerItem)
        } else {
            appendToCurrentTabPath(item)
        }
    }

    private func appendToCurrentTabPath(_ item: MediaItem) {
        switch mainView.selectedTab {
        case .home: router.homePath.append(item)
        case .search: router.searchPath.append(item)
        case .library: router.libraryPath.append(item)
        case .myList: router.myListPath.append(item)
        case .newPopular: router.newPopularPath.append(item)
        }
    }

    private func presentBrowse(_ context: BrowseContext) {
        activeBrowseContext = context
        showBrowseModal = true
        Task {
            await browseViewModel.load(context: context)
        }
    }

    private func presentPerson(_ person: CastCrewCard.Person) {
        guard !person.id.isEmpty, Int(person.id) != nil else { return }
        let reference = PersonReference(id: person.id, name: person.name, role: person.role, image: person.image)
        activePerson = reference
        showPersonModal = true
        Task {
            await personViewModel.load(personId: reference.id, name: reference.name, profilePath: reference.image)
        }
    }

    private func playEpisode(_ episode: DetailsViewModel.Episode) {
        let playerItem = MediaItem(
            id: episode.id,
            title: episode.title,
            type: "episode",
            thumb: episode.image?.absoluteString,
            art: nil,
            year: nil,
            rating: nil,
            duration: episode.durationMin.map { $0 * 60000 },
            viewOffset: episode.viewOffset,
            summary: episode.overview,
            grandparentTitle: vm.title.isEmpty ? nil : vm.title,
            grandparentThumb: nil,
            grandparentArt: nil,
            grandparentRatingKey: vm.plexRatingKey,
            parentIndex: nil,
            index: nil,
            parentRatingKey: nil,
            parentTitle: nil,
            leafCount: nil,
            viewedLeafCount: nil
        )
        appendToCurrentTabPath(playerItem)
    }
}

// MARK: - Hero Section

private struct DetailsHeroSection: View {
    @ObservedObject var vm: DetailsViewModel
    let trailers: [Trailer]
    let onPlay: () -> Void
    let layout: DetailsLayoutMetrics

    @State private var isOverviewExpanded = false
    @State private var selectedTrailer: Trailer?

    private var hasTrailers: Bool { !trailers.isEmpty }

    private var metaItems: [String] {
        var parts: [String] = []
        if let y = vm.year, !y.isEmpty { parts.append(y) }
        if let runtime = formattedRuntime(vm.runtime) { parts.append(runtime) }
        return parts
    }

    // Audio channels badge label
    private var audioBadgeLabel: String? {
        guard let channels = vm.activeVersionDetail?.technical.audioChannels else { return nil }
        let codec = (vm.activeVersionDetail?.technical.audioCodec ?? "").lowercased()
        if codec.contains("atmos") || codec.contains("truehd") {
            return "Atmos"
        }
        switch channels {
        case 8: return "7.1"
        case 6: return "5.1"
        case 2: return "Stereo"
        default: return channels > 2 ? "\(channels)CH" : nil
        }
    }

    // Check if has Plex source
    private var hasPlexSource: Bool {
        vm.playableId != nil || vm.plexRatingKey != nil
    }

    // HDR/DV badge from technical info
    private var hdrBadge: String? {
        let profile = (vm.activeVersionDetail?.technical.videoProfile ?? "").lowercased()
        if profile.contains("dv") || profile.contains("dolby vision") {
            return "DV"
        }
        if profile.contains("hdr10+") {
            return "HDR10+"
        }
        if profile.contains("hdr") || profile.contains("pq") || profile.contains("smpte2084") {
            return "HDR"
        }
        if profile.contains("hlg") {
            return "HLG"
        }
        return nil
    }

    // Resolution badge (4K, 1080p, etc)
    private var resolutionBadge: String? {
        guard let resolution = vm.activeVersionDetail?.technical.resolution else { return nil }
        let parts = resolution.split(separator: "x")
        guard parts.count == 2,
              let width = Int(parts[0]),
              let height = Int(parts[1]) else { return nil }
        if width >= 3800 || height >= 2100 { return "4K" }
        if width >= 1900 || height >= 1000 { return "1080p" }
        if width >= 1260 || height >= 700 { return "720p" }
        return nil
    }

    private func formattedRuntime(_ minutes: Int?) -> String? {
        guard let minutes = minutes, minutes > 0 else { return nil }
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            if mins == 0 { return "\(hours)h" }
            return "\(hours)h \(mins)m"
        }
        return "\(minutes)m"
    }

    private func hasRatings(_ ratings: DetailsViewModel.ExternalRatings) -> Bool {
        if let score = ratings.imdb?.score, score > 0 { return true }
        if let critic = ratings.rottenTomatoes?.critic, critic > 0 { return true }
        if let audience = ratings.rottenTomatoes?.audience, audience > 0 { return true }
        return false
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Backdrop - matches content height
            GeometryReader { geo in
                ZStack {
                    CachedAsyncImage(url: vm.backdropURL)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                    LinearGradient(
                        colors: [Color.black.opacity(0.55), Color.black.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    LinearGradient(
                        colors: [Color.black.opacity(0.78), Color.black.opacity(0.35), Color.black.opacity(0.08)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    RadialGradient(
                        gradient: Gradient(colors: [Color.black.opacity(0.6), .clear]),
                        center: .init(x: -0.1, y: 0.4),
                        startRadius: 10,
                        endRadius: 900
                    )
                }
            }
            .clipped()

            // Content - determines the overall height
            VStack(alignment: .leading, spacing: heroSpacing) {
                if let logo = vm.logoURL {
                    CachedAsyncImage(url: logo, contentMode: .fit)
                        .frame(maxWidth: logoWidth)
                        .shadow(color: .black.opacity(0.7), radius: 16, y: 6)
                } else {
                    Text(vm.title)
                        .font(.system(size: titleFontSize, weight: .heavy))
                        .kerning(0.4)
                        .shadow(color: .black.opacity(0.6), radius: 12)
                }

                // Badges row (pills + ratings) - like mobile app
                if !(vm.badges.isEmpty && vm.rating == nil && !(vm.externalRatings.map(hasRatings) ?? false)) {
                    ViewThatFits {
                        HStack(spacing: 10) { badgesRow }
                        VStack(alignment: .leading, spacing: 8) { badgesRow }
                    }
                }

                // Meta line (year • runtime • genres) - below badges, like mobile app
                metaLine

                if !vm.overview.isEmpty {
                    CollapsibleOverview(
                        text: vm.overview,
                        maxWidth: layout.heroTextMaxWidth,
                        isExpanded: $isOverviewExpanded
                    )
                }

                ViewThatFits {
                    HStack(alignment: .top, spacing: heroFactSpacing) { heroFacts }
                    VStack(alignment: .leading, spacing: 16) { heroFacts }
                }

                ViewThatFits {
                    HStack(spacing: actionSpacing) { actionButtons }
                    VStack(alignment: .leading, spacing: 12) { actionButtons }
                }

                // Trailers section
                if hasTrailers {
                    VStack(alignment: .leading, spacing: 12) {
                        // Header - styled like DetailsSectionHeader
                        Text("Trailer & Videos".uppercased())
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(.white.opacity(0.72))

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 10) {
                                ForEach(trailers) { trailer in
                                    HeroTrailerCard(
                                        trailer: trailer,
                                        width: 180,
                                        onPlay: {
                                            selectedTrailer = trailer
                                        }
                                    )
                                }
                            }
                            .padding(.leading, 4)
                            .padding(.trailing, 60)
                        }
                    }
                }
            }
            .padding(.leading, layout.heroHorizontalPadding)
            .padding(.trailing, heroTrailingPadding)
            .padding(.top, layout.heroTopPadding)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .sheet(item: $selectedTrailer) { trailer in
            TrailerModal(
                trailer: trailer,
                onClose: { selectedTrailer = nil }
            )
        }
    }

    private var canonicalWatchlistId: String? {
        if let playable = vm.playableId { return playable }
        if let tmdb = vm.tmdbId {
            let prefix = (vm.mediaKind == "tv") ? "tmdb:tv:" : "tmdb:movie:"
            return prefix + tmdb
        }
        return nil
    }

    private var watchlistMediaType: MyListViewModel.MediaType? {
        if vm.mediaKind == "tv" { return .show }
        if vm.mediaKind == "movie" { return .movie }
        return .movie
    }

    private var castSummary: String {
        if vm.cast.isEmpty { return "—" }
        let names = vm.castShort.map { $0.name }
        let summary = names.joined(separator: ", ")
        if vm.castMoreCount > 0 {
            return summary + " +\(vm.castMoreCount) more"
        }
        return summary
    }

    @ViewBuilder
    private func heroFactBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.72))
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(2)
        }
    }

    private var width: CGFloat { layout.width }

    private var heroSpacing: CGFloat {
        width < 1100 ? 20 : 26
    }

    private var heroFactSpacing: CGFloat {
        width < 1100 ? 20 : 26
    }

    private var actionSpacing: CGFloat {
        width < 820 ? 12 : 16
    }

    private var titleFontSize: CGFloat {
        if width < 820 { return 36 }
        if width < 1100 { return 42 }
        return 48
    }

    private var logoWidth: CGFloat {
        if width < 900 { return 340 }
        if width < 1300 { return 420 }
        return 480
    }

    private var heroTrailingPadding: CGFloat {
        width < 1100 ? layout.heroHorizontalPadding : 48
    }

    // Badges row - pills and ratings (like mobile app)
    @ViewBuilder private var badgesRow: some View {
        // Age Rating pill (content rating like PG-13, R, TV-MA)
        if let contentRating = vm.rating, !contentRating.isEmpty {
            HeroMetaPill(text: contentRating)
        }

        // Technical badges from ViewModel (4K, HDR, Dolby Vision, Atmos)
        ForEach(vm.badges.filter { $0.lowercased() != "plex" }, id: \.self) { badge in
            let style: HeroMetaPill.Style = {
                let lower = badge.lowercased()
                if lower.contains("hdr") || lower.contains("dolby") || lower == "dv" || lower.contains("hlg") {
                    return .highlighted
                }
                return .default
            }()
            HeroMetaPill(text: badge, style: style)
        }

        // Audio pill (5.1, 7.1, Atmos, Stereo) - if not already in badges
        if let audio = audioBadgeLabel, !vm.badges.contains(where: { $0.lowercased().contains(audio.lowercased()) }) {
            HeroMetaPill(text: audio)
        }

        // Plex SOURCE pill - only show once
        if hasPlexSource {
            HeroMetaPill(text: "Plex", style: .source)
        } else if vm.tmdbId != nil {
            HeroMetaPill(text: "No local source", style: .warning)
        }

        // External ratings (IMDb, Rotten Tomatoes)
        if let ratings = vm.externalRatings, hasRatings(ratings) {
            RatingsStrip(ratings: ratings)
        }

        // MDBList ratings (additional sources)
        if let mdbRatings = vm.mdblistRatings, mdbRatings.hasAnyRating {
            RatingsDisplay(ratings: mdbRatings)
        }
    }

    // Meta line - year, runtime, genres as text (below badges, like mobile app)
    @ViewBuilder private var metaLine: some View {
        if !metaItems.isEmpty || !vm.genres.isEmpty {
            HStack(spacing: 0) {
                // Year and runtime
                if !metaItems.isEmpty {
                    Text(metaItems.joined(separator: " • "))
                }
                // Genres
                if !vm.genres.isEmpty {
                    if !metaItems.isEmpty {
                        Text(" • ")
                    }
                    Text(vm.genres.prefix(3).joined(separator: ", "))
                }
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white.opacity(0.7))
        }
    }

    // Legacy metaRow for compatibility - now combines badges and meta
    @ViewBuilder private var metaRow: some View {
        badgesRow
    }

    @ViewBuilder private var heroFacts: some View {
        // Show episodes count for seasons instead of cast
        if vm.isSeason {
            if let episodeCount = vm.episodeCount {
                let watchedCount = vm.watchedCount ?? 0
                heroFactBlock(title: "Episodes", value: "\(episodeCount) episodes • \(watchedCount) watched")
            }
        } else {
            heroFactBlock(title: "Cast", value: castSummary)
        }

        if !vm.genres.isEmpty {
            heroFactBlock(title: "Genres", value: vm.genres.joined(separator: ", "))
        }

        if !vm.moodTags.isEmpty {
            let title = vm.isSeason ? "This Season Is" : (vm.mediaKind == "tv" ? "This Show Is" : "This Movie Is")
            heroFactBlock(title: title, value: vm.moodTags.joined(separator: ", "))
        }
    }

    @ViewBuilder private var actionButtons: some View {
        // For seasons, show "View Show" button instead of "Play"
        if vm.isSeason {
            if let parentKey = vm.parentShowKey {
                Button(action: {
                    let showItem = MediaItem(
                        id: "plex:\(parentKey)",
                        title: vm.title,
                        type: "show",
                        thumb: nil,
                        art: nil,
                        year: nil,
                        rating: nil,
                        duration: nil,
                        viewOffset: nil,
                        summary: nil,
                        grandparentTitle: nil,
                        grandparentThumb: nil,
                        grandparentArt: nil,
                        grandparentRatingKey: nil,
                        parentIndex: nil,
                        index: nil,
                        parentRatingKey: nil,
                        parentTitle: nil,
                        leafCount: nil,
                        viewedLeafCount: nil
                    )
                    // Navigate to show details using parent key
                    Task {
                        await vm.load(for: showItem)
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "tv.fill")
                        Text("View Show").fontWeight(.semibold)
                    }
                    .font(.system(size: 16))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        } else {
            Button(action: onPlay) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("Play").fontWeight(.semibold)
                }
                .font(.system(size: 16))
                .foregroundStyle(hasPlexSource ? .black : .gray)
                .padding(.horizontal, 26)
                .padding(.vertical, 12)
                .background(hasPlexSource ? Color.white : Color.white.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!hasPlexSource)

            if let watchlistId = canonicalWatchlistId,
               let mediaType = watchlistMediaType {
                WatchlistButton(
                    canonicalId: watchlistId,
                    mediaType: mediaType,
                    plexRatingKey: vm.plexRatingKey,
                    plexGuid: vm.plexGuid,
                    tmdbId: vm.tmdbId,
                    imdbId: nil,
                    title: vm.title,
                    year: vm.year.flatMap { Int($0) },
                    style: .pill
                )
            }

            // Overseerr request button
            if let tmdbIdStr = vm.tmdbId, let tmdbIdInt = Int(tmdbIdStr) {
                let overseerrMediaType = vm.mediaKind == "tv" ? "tv" : "movie"
                RequestButton(
                    tmdbId: tmdbIdInt,
                    mediaType: overseerrMediaType,
                    title: vm.title,
                    style: .pill
                )
            }
        }
    }
}

// MARK: - Tab Content Helpers

private struct SuggestedSections: View {
    @ObservedObject var vm: DetailsViewModel
    let layout: DetailsLayoutMetrics
    var onBrowse: ((BrowseContext) -> Void)?

    @AppStorage("showRelatedContent") private var showRelatedContent: Bool = true
    @AppStorage("suggestedLayout") private var suggestedLayout: String = "landscape"

    var body: some View {
        VStack(alignment: .leading, spacing: layout.width < 1100 ? 24 : 28) {
            if showRelatedContent && !vm.related.isEmpty {
                suggestedRow(
                    section: LibrarySection(
                        id: "rel",
                        title: "Related",
                        items: vm.related,
                        totalCount: vm.related.count,
                        libraryKey: nil,
                        browseContext: vm.relatedBrowseContext
                    )
                )
            }
            if showRelatedContent && !vm.similar.isEmpty {
                suggestedRow(
                    section: LibrarySection(
                        id: "sim",
                        title: "Similar",
                        items: vm.similar,
                        totalCount: vm.similar.count,
                        libraryKey: nil,
                        browseContext: vm.similarBrowseContext
                    )
                )
            }
        }
    }

    @ViewBuilder
    private func suggestedRow(section: LibrarySection) -> some View {
        if suggestedLayout == "poster" {
            PosterSectionRow(
                section: section,
                onTap: { media in
                    Task { await vm.load(for: media) }
                },
                onBrowse: { context in
                    onBrowse?(context)
                }
            )
            .padding(.trailing, 60)
        } else {
            LandscapeSectionView(
                section: section,
                onTap: { media in
                    Task { await vm.load(for: media) }
                },
                onBrowse: { context in
                    onBrowse?(context)
                }
            )
            .padding(.trailing, 60)
        }
    }
}

private struct DetailsTabContent: View {
    @ObservedObject var vm: DetailsViewModel
    let layout: DetailsLayoutMetrics
    var onPersonTap: (CastCrewCard.Person) -> Void

    @AppStorage("showCastCrew") private var showCastCrew: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            // About Section (Apple TV+ style cards) - moved above Cast & Crew
            VStack(alignment: .leading, spacing: 16) {
                Text("About")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)

                // Tagline (if available)
                if let tagline = vm.tagline, !tagline.isEmpty {
                    Text("\"\(tagline)\"")
                        .font(.system(size: 15, weight: .regular))
                        .italic()
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.bottom, 4)
                }

                HStack(alignment: .top, spacing: 16) {
                    // Main info card
                    VStack(alignment: .leading, spacing: 12) {
                        Text(vm.title)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)

                        if !vm.genres.isEmpty {
                            Text(vm.genres.joined(separator: ", ").uppercased())
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))
                        }

                        if !vm.overview.isEmpty {
                            Text(vm.overview)
                                .font(.system(size: 14))
                                .lineSpacing(4)
                                .foregroundStyle(.white.opacity(0.85))
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )

                    // Content rating card - height matches description card
                    if let rating = vm.rating {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                                    .font(.system(size: 18))
                                Text(rating)
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            Text("CONTENT RATING")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                            Spacer(minLength: 0)
                        }
                        .padding(20)
                        .frame(width: 200)
                        .frame(maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            // Cast & Crew Section (Apple TV+ style)
            if showCastCrew && (!vm.cast.isEmpty || !vm.crew.isEmpty) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Cast & Crew")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 20) {
                            ForEach(allCastCrew) { person in
                                CastCrewCircleCard(person: person, onTap: { onPersonTap(person) })
                            }
                        }
                    }
                }
            }
            
            // Production Section (Movies) - with logos
            if vm.mediaKind == "movie" && !vm.productionCompanies.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Production")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(vm.productionCompanies.prefix(6)) { company in
                                if let logoURL = company.logoURL {
                                    CachedAsyncImage(url: logoURL, aspectRatio: nil, contentMode: .fit)
                                        .frame(width: 80, height: 32)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(Color.white)
                                        )
                                } else {
                                    Text(company.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(Color.white)
                                        )
                                }
                            }
                        }
                    }
                }
            }

            // Networks Section (TV) - with logos
            if vm.mediaKind == "tv" && !vm.networks.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Networks")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(vm.networks.prefix(6)) { network in
                                if let logoURL = network.logoURL {
                                    CachedAsyncImage(url: logoURL, aspectRatio: nil, contentMode: .fit)
                                        .frame(width: 80, height: 32)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(Color.white)
                                        )
                                } else {
                                    Text(network.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(Color.white)
                                        )
                                }
                            }
                        }
                    }
                }
            }

            // Three-column info section (Apple TV+ style)
            HStack(alignment: .top, spacing: 40) {
                // Information column
                VStack(alignment: .leading, spacing: 20) {
                    Text("Information")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)

                    VStack(alignment: .leading, spacing: 16) {
                        if let year = vm.year {
                            InfoRow(label: "Released", value: year)
                        }

                        if let runtime = vm.runtime {
                            InfoRow(label: "Run Time", value: formattedRuntime(runtime))
                        }

                        if let rating = vm.rating {
                            InfoRow(label: "Rated", value: rating)
                        }

                        if let status = vm.status {
                            InfoRow(label: "Status", value: status)
                        }

                        if vm.mediaKind == "tv" {
                            if let seasons = vm.numberOfSeasons {
                                InfoRow(label: "Seasons", value: "\(seasons)")
                            }
                            if let episodes = vm.numberOfEpisodes {
                                InfoRow(label: "Episodes", value: "\(episodes)")
                            }
                        }

                        if vm.mediaKind == "movie" {
                            if let budget = vm.budget {
                                InfoRow(label: "Budget", value: formatCurrency(budget))
                            }
                            if let revenue = vm.revenue {
                                InfoRow(label: "Box Office", value: formatCurrency(revenue))
                            }
                        }

                        if let lang = vm.originalLanguage {
                            InfoRow(label: "Original Language", value: languageName(for: lang))
                        }

                        if let studio = vm.studio {
                            InfoRow(label: "Studio", value: studio)
                        }

                        if vm.mediaKind == "tv" && !vm.creators.isEmpty {
                            InfoRow(label: "Created By", value: vm.creators.joined(separator: ", "))
                        }

                        // Directors
                        if !vm.directors.isEmpty {
                            InfoRow(label: "Directed By", value: vm.directors.joined(separator: ", "))
                        }

                        // Writers
                        if !vm.writers.isEmpty {
                            InfoRow(label: "Written By", value: vm.writers.joined(separator: ", "))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Languages column
                VStack(alignment: .leading, spacing: 20) {
                    Text("Languages")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)

                    VStack(alignment: .leading, spacing: 16) {
                        if let lang = vm.originalLanguage {
                            InfoRow(label: "Original Audio", value: languageName(for: lang))
                        }

                        if !vm.audioTracks.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Audio")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.5))
                                Text(vm.audioTracks.map { $0.name }.joined(separator: ", "))
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .lineLimit(4)
                            }
                        }

                        if !vm.subtitleTracks.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Subtitles")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.5))
                                Text(vm.subtitleTracks.map { $0.name }.joined(separator: ", "))
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .lineLimit(6)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Technical / Production column
                VStack(alignment: .leading, spacing: 20) {
                    Text("Technical")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)

                    VStack(alignment: .leading, spacing: 16) {
                        if let version = vm.activeVersionDetail {
                            if let res = version.technical.resolution {
                                InfoRow(label: "Resolution", value: res)
                            }
                            if let codec = version.technical.videoCodec {
                                InfoRow(label: "Video", value: codec.uppercased())
                            }
                            if let audio = version.technical.audioCodec {
                                let channels = version.technical.audioChannels.map { " \($0)ch" } ?? ""
                                InfoRow(label: "Audio", value: audio.uppercased() + channels)
                            }
                            if let hdr = version.technical.hdrFormat {
                                InfoRow(label: "HDR", value: hdr)
                            }
                            if let container = version.technical.container {
                                InfoRow(label: "Container", value: container.uppercased())
                            }
                            if let bitrate = version.technical.bitrate {
                                InfoRow(label: "Bitrate", value: "\(bitrate / 1000) Mbps")
                            }
                            if let size = version.technical.fileSizeMB {
                                let gb = size / 1024
                                let sizeStr = gb >= 1 ? String(format: "%.1f GB", gb) : String(format: "%.0f MB", size)
                                InfoRow(label: "File Size", value: sizeStr)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Collections (from Plex) - if any
            if !vm.collections.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Collections")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)

                    FlowLayout(spacing: 8) {
                        ForEach(vm.collections, id: \.self) { collection in
                            Text(collection)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.white.opacity(0.1))
                                )
                        }
                    }
                }
            }

            // External Links
            if vm.imdbId != nil || vm.tmdbId != nil {
                VStack(alignment: .leading, spacing: 12) {
                    Text("External Links")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)

                    HStack(spacing: 12) {
                        if let imdbId = vm.imdbId {
                            Link(destination: URL(string: "https://www.imdb.com/title/\(imdbId)")!) {
                                HStack(spacing: 8) {
                                    Image("imdb")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(height: 18)
                                    Text("View on IMDb")
                                        .font(.system(size: 13, weight: .medium))
                                }
                                .foregroundStyle(.black)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color(red: 0.96, green: 0.77, blue: 0.09)) // IMDb yellow
                                )
                            }
                        }
                        if let tmdbId = vm.tmdbId {
                            let mediaPath = vm.mediaKind == "tv" ? "tv" : "movie"
                            Link(destination: URL(string: "https://www.themoviedb.org/\(mediaPath)/\(tmdbId)")!) {
                                HStack(spacing: 8) {
                                    // TMDB logo representation
                                    ZStack {
                                        Circle()
                                            .fill(Color(red: 0.02, green: 0.82, blue: 0.61)) // TMDB teal
                                            .frame(width: 20, height: 20)
                                        Text("T")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                    Text("View on TMDB")
                                        .font(.system(size: 13, weight: .medium))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color(red: 0.03, green: 0.21, blue: 0.33)) // TMDB dark blue
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    // Combine cast and crew for display
    private var allCastCrew: [CastCrewCard.Person] {
        var people: [CastCrewCard.Person] = []
        // Add cast (actors) with their character names
        for c in vm.cast.prefix(12) {
            people.append(CastCrewCard.Person(id: c.id, name: c.name, role: c.role, image: c.profile))
        }
        // Add key crew (directors, writers)
        for c in vm.crew.prefix(4) {
            people.append(CastCrewCard.Person(id: c.id, name: c.name, role: c.job, image: c.profile))
        }
        return people
    }

    private func formattedRuntime(_ minutes: Int) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            if mins == 0 { return "\(hours) hr" }
            return "\(hours) hr \(mins) min"
        }
        return "\(minutes) min"
    }

    private func formatCurrency(_ amount: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }

    private func languageName(for code: String) -> String {
        let locale = Locale(identifier: "en")
        return locale.localizedString(forLanguageCode: code)?.capitalized ?? code.uppercased()
    }
}

// MARK: - Cast & Crew Circle Card (Apple TV+ style)
private struct CastCrewCircleCard: View {
    let person: CastCrewCard.Person
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                // Circular profile image
                Group {
                    if let imageURL = person.image {
                        CachedAsyncImage(url: imageURL)
                            .scaledToFill()
                    } else {
                        // Initials fallback
                        ZStack {
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                            Text(initials(for: person.name))
                                .font(.system(size: 28, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }
                .frame(width: 100, height: 100)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(isHovered ? 0.4 : 0.15), lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)

                // Name
                Text(person.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                // Role/Character
                if let role = person.role {
                    Text(role)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            .frame(width: 110)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func initials(for name: String) -> String {
        let parts = name.components(separatedBy: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

// MARK: - Info Row Component
private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}

// MARK: - Production Section
private struct ProductionSection: View {
    let title: String
    let companies: [DetailsViewModel.ProductionCompany]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailsSectionHeader(title: title)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(companies) { company in
                        VStack(spacing: 8) {
                            if let logoURL = company.logoURL {
                                CachedAsyncImage(url: logoURL)
                                    .frame(width: 80, height: 40)
                                    .background(Color.white.opacity(0.9))
                                    .cornerRadius(6)
                            } else {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white.opacity(0.1))
                                    .frame(width: 80, height: 40)
                                    .overlay(
                                        Image(systemName: "building.2")
                                            .foregroundStyle(.white.opacity(0.4))
                                    )
                            }
                            Text(company.name)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(width: 80)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Flow Layout for Tags/Collections
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
                self.size.width = max(self.size.width, x)
            }
            self.size.height = y + rowHeight
        }
    }
}

// MARK: - Info Column Component
private struct InfoColumn: View {
    let title: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .textCase(.uppercase)

            Text(content)
                .font(.system(size: 15))
                .lineSpacing(3)
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Metadata Badge Component
private struct MetadataBadge: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.75))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

private struct EpisodesTabContent: View {
    @ObservedObject var vm: DetailsViewModel
    let layout: DetailsLayoutMetrics
    let onPlayEpisode: (DetailsViewModel.Episode) -> Void
    var hasPlexSource: Bool = true

    @AppStorage("episodeLayout") private var episodeLayout: String = "horizontal"

    private let cardWidth: CGFloat = 340
    private var cardHeight: CGFloat { 180 }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Season selector (hide in season-only mode)
            if !vm.isSeason && vm.seasons.count > 1 {
                SeasonSelector(
                    seasons: vm.seasons,
                    selectedKey: vm.selectedSeasonKey ?? "",
                    onSelect: { key in
                        Task { await vm.selectSeason(key) }
                    }
                )
            } else if let season = vm.seasons.first(where: { $0.id == vm.selectedSeasonKey }) {
                Text(season.title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }

            if vm.episodesLoading {
                HStack {
                    Spacer()
                    ProgressView().progressViewStyle(.circular)
                    Spacer()
                }
                .padding(.vertical, 40)
            } else if vm.episodes.isEmpty {
                Text("No episodes found").foregroundStyle(.secondary)
            } else if episodeLayout == "horizontal" {
                // Horizontal scroll of episode cards (like mobile)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(Array(vm.episodes.enumerated()), id: \.element.id) { index, episode in
                            HorizontalEpisodeCard(
                                episode: episode,
                                episodeNumber: index + 1,
                                width: cardWidth,
                                height: cardHeight,
                                isDisabled: !hasPlexSource,
                                onPlay: { onPlayEpisode(episode) }
                            )
                        }
                    }
                    .padding(.leading, 24)
                    .padding(.trailing, 60)
                }
            } else {
                // Vertical list layout (original)
                VStack(spacing: 12) {
                    ForEach(Array(vm.episodes.enumerated()), id: \.element.id) { index, episode in
                        VerticalEpisodeRow(
                            episode: episode,
                            episodeNumber: index + 1,
                            layout: layout,
                            isDisabled: !hasPlexSource,
                            onPlay: { onPlayEpisode(episode) }
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Season Selector

private struct SeasonSelector: View {
    let seasons: [DetailsViewModel.Season]
    let selectedKey: String
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(seasons) { season in
                    Button(action: { onSelect(season.id) }) {
                        Text(season.title)
                            .font(.system(size: 14, weight: selectedKey == season.id ? .bold : .medium))
                            .foregroundStyle(selectedKey == season.id ? .black : .white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(selectedKey == season.id ? Color.white : Color.white.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Horizontal Episode Card (like mobile)

private struct HorizontalEpisodeCard: View {
    let episode: DetailsViewModel.Episode
    let episodeNumber: Int
    let width: CGFloat
    let height: CGFloat
    var isDisabled: Bool = false
    let onPlay: () -> Void

    @State private var isHovered = false

    private var progressPct: Double {
        Double(episode.progressPct ?? 0)
    }

    private var showProgress: Bool {
        progressPct > 0 && progressPct < 85
    }

    private var isCompleted: Bool {
        progressPct >= 85
    }

    var body: some View {
        Button(action: onPlay) {
            ZStack(alignment: .bottomLeading) {
                // Thumbnail background
                if let imgURL = episode.image {
                    CachedAsyncImage(url: imgURL)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: width, height: height)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color(white: 0.15))
                        .frame(width: width, height: height)
                }

                // Gradient overlay
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.05), location: 0),
                        .init(color: .black.opacity(0.2), location: 0.25),
                        .init(color: .black.opacity(0.6), location: 0.6),
                        .init(color: .black.opacity(0.9), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Hover play overlay
                if isHovered {
                    ZStack {
                        Color.black.opacity(0.3)
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 8)
                    }
                }

                // Content
                VStack(alignment: .leading, spacing: 6) {
                    // Episode badge
                    Text("EPISODE \(episodeNumber)")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Color(white: 0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    // Title
                    Text(episode.title)
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    // Overview
                    if let overview = episode.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(3)
                    }

                    // Meta info
                    if let duration = episode.durationMin {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 11))
                            Text("\(duration)m")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(Color(white: 0.6))
                    }
                }
                .padding(12)

                // Progress bar
                if showProgress {
                    VStack {
                        Spacer()
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.33))
                                    .frame(height: 4)

                                Rectangle()
                                    .fill(Color.white)
                                    .frame(width: geo.size.width * CGFloat(min(100, max(0, progressPct))) / 100.0, height: 4)
                            }
                        }
                        .frame(height: 4)
                    }
                }

                // Completed checkmark
                if isCompleted {
                    VStack {
                        HStack {
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 22, height: 22)

                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.black)
                            }
                            .padding(10)
                        }
                        Spacer()
                    }
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(isHovered ? 0.5 : 0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: isHovered ? 12 : 6, y: isHovered ? 6 : 3)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1.0)
        .animation(.easeOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            if !isDisabled {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Vertical Episode Row (original list layout)

private struct VerticalEpisodeRow: View {
    let episode: DetailsViewModel.Episode
    let episodeNumber: Int
    let layout: DetailsLayoutMetrics
    var isDisabled: Bool = false
    let onPlay: () -> Void

    @State private var isHovered = false

    private var progressPct: Double {
        Double(episode.progressPct ?? 0)
    }

    private var showProgress: Bool {
        progressPct > 0 && progressPct < 85
    }

    private var isCompleted: Bool {
        progressPct >= 85
    }

    var body: some View {
        Button(action: onPlay) {
            HStack(alignment: .top, spacing: 16) {
                // Thumbnail
                ZStack(alignment: .bottomLeading) {
                    if let imgURL = episode.image {
                        CachedAsyncImage(url: imgURL)
                            .aspectRatio(16/9, contentMode: .fill)
                            .frame(width: layout.episodeThumbnailWidth)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(Color(white: 0.15))
                            .aspectRatio(16/9, contentMode: .fill)
                            .frame(width: layout.episodeThumbnailWidth)
                    }

                    // Progress bar
                    if showProgress {
                        GeometryReader { geo in
                            VStack {
                                Spacer()
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.33))
                                        .frame(height: 4)

                                    Rectangle()
                                        .fill(Color.white)
                                        .frame(width: geo.size.width * CGFloat(min(100, max(0, progressPct))) / 100.0, height: 4)
                                }
                            }
                        }
                    }

                    // Hover play overlay
                    if isHovered {
                        ZStack {
                            Color.black.opacity(0.4)
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(isHovered ? 0.4 : 0.12), lineWidth: 1)
                )

                // Info
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(episodeNumber). \(episode.title)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        Spacer()

                        if isCompleted {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.green)
                        }
                    }

                    if let overview = episode.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(3)
                    }

                    if let duration = episode.durationMin {
                        Text("\(duration) min")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(isHovered ? 0.06 : 0.03))
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1.0)
        .onHover { hovering in
            if !isDisabled {
                isHovered = hovering
            }
        }
    }
}

private struct HeroTrailerCard: View {
    let trailer: Trailer
    let width: CGFloat
    var onPlay: (() -> Void)?

    @State private var isHovered = false

    private var height: CGFloat { width * 0.5625 }

    var body: some View {
        Button(action: { onPlay?() }) {
            ZStack(alignment: .bottomLeading) {
                // Thumbnail
                CachedAsyncImage(url: trailer.thumbnailURL)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipped()
                    .background(Color.gray.opacity(0.2))

                // Play overlay
                ZStack {
                    Color.black.opacity(isHovered ? 0.5 : 0.3)

                    Image(systemName: "play.circle.fill")
                        .font(.system(size: isHovered ? 48 : 42))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 8)
                }

                // Gradient for text
                LinearGradient(
                    colors: [.clear, .black.opacity(0.8)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Spacer()

                    // Type badge
                    Text(trailer.type.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(trailerBadgeColor)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(.white)

                    // Title
                    Text(trailer.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(10)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(isHovered ? 0.5 : 0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: isHovered ? 12 : 6)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var trailerBadgeColor: Color {
        switch trailer.type.lowercased() {
        case "trailer": return Color.red.opacity(0.85)
        case "teaser": return Color.orange.opacity(0.85)
        case "featurette": return Color.purple.opacity(0.85)
        case "clip": return Color.green.opacity(0.85)
        default: return Color.gray.opacity(0.85)
        }
    }
}

// MARK: - Tabs data

private extension DetailsView {
    var tabsData: [DetailsTab] {
        var t: [DetailsTab] = []
        // Show EPISODES tab for TV shows and seasons
        if vm.mediaKind == "tv" || vm.isSeason { t.append(DetailsTab(id: "EPISODES", label: "Episodes", count: nil)) }
        // Hide SUGGESTED tab for season-only mode
        if !vm.isSeason {
            t.append(DetailsTab(id: "SUGGESTED", label: "Suggested", count: nil))
        }
        t.append(DetailsTab(id: "DETAILS", label: "Details", count: nil))
        return t
    }
}

// MARK: - Badge helper

private struct HeroMetaPill: View {
    enum Style {
        case `default`
        case highlighted  // For HDR/DV - purple background
        case source       // For Plex - subtle white
        case warning      // For "No local source" - red background
    }

    let text: String
    var style: Style = .default

    private var palette: (background: Color, foreground: Color, border: Color?) {
        switch style {
        case .highlighted:
            // Purple for HDR/DV badges
            return (Color(red: 0.6, green: 0.35, blue: 0.71).opacity(0.85), Color.white, nil)
        case .source:
            // Subtle white for Plex source
            return (Color.white.opacity(0.18), Color.white, Color.white.opacity(0.25))
        case .warning:
            // Red for no local source
            return (Color.red.opacity(0.7), Color.white, nil)
        case .default:
            return (Color.white.opacity(0.12), Color.white, Color.white.opacity(0.2))
        }
    }

    var body: some View {
        let colors = palette
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(colors.background)
            )
            .overlay(
                Group {
                    if let border = colors.border {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(border, lineWidth: 1)
                    }
                }
            )
            .foregroundStyle(colors.foreground)
    }
}

private struct RatingsStrip: View {
    let ratings: DetailsViewModel.ExternalRatings

    var body: some View {
        HStack(spacing: 10) {
            if let imdbScore = ratings.imdb?.score {
                RatingsPill {
                    HStack(spacing: 8) {
                        IMDbMark()
                        Text(String(format: "%.1f", imdbScore))
                            .font(.system(size: 12, weight: .semibold))
                        if let votes = ratings.imdb?.votes, let display = formattedVotes(votes) {
                            Text(display)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
            }
            if let critic = ratings.rottenTomatoes?.critic {
                RatingsPill {
                    HStack(spacing: 8) {
                        TomatoIcon(score: critic)
                        Text("\(critic)%")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(scoreColor(critic))
                    }
                }
            }
            if let audience = ratings.rottenTomatoes?.audience {
                RatingsPill {
                    HStack(spacing: 8) {
                        PopcornIcon(score: audience)
                        Text("\(audience)%")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(scoreColor(audience))
                    }
                }
            }
        }
    }

    private func formattedVotes(_ votes: Int) -> String? {
        guard votes > 0 else { return nil }
        switch votes {
        case 1_000_000...:
            return String(format: "%.1fM", Double(votes) / 1_000_000)
        case 10_000...:
            return String(format: "%.1fk", Double(votes) / 1_000)
        case 1_000...:
            return String(format: "%.1fk", Double(votes) / 1_000)
        default:
            return NumberFormatter.localizedString(from: NSNumber(value: votes), number: .decimal)
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 85 { return Color(red: 0.42, green: 0.87, blue: 0.44) }
        if score >= 60 { return Color(red: 0.97, green: 0.82, blue: 0.35) }
        return Color(red: 0.94, green: 0.32, blue: 0.28)
    }
}

private struct RatingsPill<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.18))
            )
    }
}

private struct IMDbMark: View {
    var body: some View {
        Image("imdb")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: 16)
    }
}

private struct TomatoIcon: View {
    let score: Int

    var body: some View {
        Image(score >= 60 ? "tomato-fresh" : "tomato-rotten")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 18, height: 18)
    }
}

private struct PopcornIcon: View {
    let score: Int

    var body: some View {
        Image(score >= 60 ? "popcorn-full" : "popcorn-fallen")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 18, height: 18)
    }
}

private struct TechnicalDetailsSection: View {
    let version: DetailsViewModel.VersionDetail
    let layout: DetailsLayoutMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            DetailsSectionHeader(title: "Technical Details")

            // Main technical specs grid
            LazyVGrid(columns: [GridItem(.adaptive(minimum: layout.technicalGridMinimum), spacing: 16)], spacing: 16) {
                ForEach(technicalPairs(), id: \.0) { pair in
                    TechnicalInfoTile(label: pair.0, value: pair.1)
                }
            }

            // Audio & Subtitle tracks
            if !version.audioTracks.isEmpty || !version.subtitleTracks.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    if !version.audioTracks.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Audio Tracks")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.6))
                                .textCase(.uppercase)
                            FlowChipGroup(texts: version.audioTracks.map { $0.name })
                        }
                    }
                    if !version.subtitleTracks.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Subtitles")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.6))
                                .textCase(.uppercase)
                            FlowChipGroup(texts: version.subtitleTracks.map { $0.name })
                        }
                    }
                }
            }
        }
    }

    private func technicalPairs() -> [(String, String)] {
        var list: [(String, String)] = []
        list.append(("Version", version.label))
        if let reso = version.technical.resolution { list.append(("Resolution", reso)) }
        if let video = version.technical.videoCodec { list.append(("Video", video.uppercased())) }
        if let profile = version.technical.videoProfile, !profile.isEmpty { list.append(("Profile", profile.uppercased())) }
        if let audio = version.technical.audioCodec { list.append(("Audio", audio.uppercased())) }
        if let channels = version.technical.audioChannels { list.append(("Channels", "\(channels)")) }
        if let bitrate = version.technical.bitrate {
            let mbps = Double(bitrate) / 1000.0
            list.append(("Bitrate", String(format: "%.1f Mbps", mbps)))
        }
        if let size = version.technical.fileSizeMB {
            if size >= 1024 {
                list.append(("File Size", String(format: "%.2f GB", size / 1024.0)))
            } else {
                list.append(("File Size", String(format: "%.0f MB", size)))
            }
        }
        if let runtime = version.technical.durationMin {
            list.append(("Runtime", "\(runtime)m"))
        }
        if let subs = version.technical.subtitleCount, subs > 0 {
            list.append(("Subtitles", "\(subs)"))
        }
        return list
    }
}

private struct CastCrewSection: View {
    let cast: [DetailsViewModel.Person]
    let crew: [DetailsViewModel.CrewPerson]
    let layout: DetailsLayoutMetrics
    var onPersonTap: (CastCrewCard.Person) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            DetailsSectionHeader(title: "Cast & Crew")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: layout.castGridMinimum), spacing: 20)], spacing: 24) {
                ForEach(Array(people.prefix(15))) { person in
                    CastCrewCard(person: person, onTap: { onPersonTap(person) })
                }
            }
        }
    }

    private var people: [CastCrewCard.Person] {
        var seen = Set<String>()
        var combined: [CastCrewCard.Person] = []
        for c in cast {
            if seen.insert(c.id).inserted {
                combined.append(CastCrewCard.Person(id: c.id, name: c.name, role: nil, image: c.profile))
            }
        }
        for m in crew {
            if seen.insert(m.id).inserted {
                combined.append(CastCrewCard.Person(id: m.id, name: m.name, role: m.job, image: m.profile))
            }
        }
        return combined
    }
}

private struct CastCrewCard: View, Identifiable {
    struct Person: Identifiable {
        let id: String
        let name: String
        let role: String?
        let image: URL?
    }

    let person: Person
    var onTap: () -> Void
    var id: String { person.id }
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    if let imageURL = person.image {
                        CachedAsyncImage(url: imageURL)
                            .aspectRatio(2/3, contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .aspectRatio(2/3, contentMode: .fit)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.white.opacity(0.25))
                            )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)

                VStack(alignment: .leading, spacing: 3) {
                    Text(person.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                        .foregroundStyle(.white.opacity(0.95))
                    if let role = person.role, !role.isEmpty {
                        Text(role)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.bottom, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.06 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(isHovered ? 0.18 : 0.12), lineWidth: isHovered ? 1 : 0.5)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(color: .black.opacity(isHovered ? 0.35 : 0.2), radius: isHovered ? 12 : 6, y: isHovered ? 6 : 3)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .accessibilityLabel(Text("\(person.name)\(person.role.map { ", \($0)" } ?? "")"))
    }
}

private struct TechnicalInfoTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.95))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

private struct DetailsSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(.white.opacity(0.95))
    }
}

private struct FlowChipGroup: View {
    let texts: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(texts, id: \.self) { text in
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            )
                    )
            }
        }
    }
}

private struct Badge: View { let text: String; var body: some View { Text(text).font(.caption).padding(.horizontal, 8).padding(.vertical, 4).background(Color.white.opacity(0.12)).cornerRadius(6) } }

// MARK: - Collapsible Overview Component

private struct CollapsibleOverview: View {
    let text: String
    let maxWidth: CGFloat
    @Binding var isExpanded: Bool

    @State private var intrinsicHeight: CGFloat = 0
    @State private var truncatedHeight: CGFloat = 0

    private var isTruncated: Bool {
        intrinsicHeight > truncatedHeight && truncatedHeight > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.88))
                .lineSpacing(4)
                .lineLimit(isExpanded ? nil : 2)
                .frame(maxWidth: maxWidth, alignment: .leading)
                .multilineTextAlignment(.leading)
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: TruncatedHeightPreferenceKey.self,
                            value: geometry.size.height
                        )
                    }
                )
                .onPreferenceChange(TruncatedHeightPreferenceKey.self) { height in
                    if !isExpanded {
                        truncatedHeight = height
                    }
                }
                .background(
                    // Hidden text without line limit to get intrinsic height
                    Text(text)
                        .font(.system(size: 16))
                        .lineSpacing(4)
                        .frame(maxWidth: maxWidth, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .background(
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: IntrinsicHeightPreferenceKey.self,
                                    value: geometry.size.height
                                )
                            }
                        )
                        .onPreferenceChange(IntrinsicHeightPreferenceKey.self) { height in
                            intrinsicHeight = height
                        }
                )

            if isTruncated {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 6) {
                        Text(isExpanded ? "Less" : "More")
                            .font(.system(size: 14, weight: .semibold))
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.18))
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: maxWidth, alignment: .leading)
            }
        }
    }
}

private struct TruncatedHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct IntrinsicHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#if DEBUG && canImport(PreviewsMacros)
#Preview {
    DetailsView(item: MediaItem(
        id: "plex:1",
        title: "Sample Title",
        type: "movie",
        thumb: nil,
        art: nil,
        year: 2024,
        rating: 8.1,
        duration: 7200000,
        viewOffset: nil,
        summary: "A minimal details preview",
        grandparentTitle: nil,
        grandparentThumb: nil,
        grandparentArt: nil,
        parentIndex: nil,
        index: nil
    ))
}
#endif
