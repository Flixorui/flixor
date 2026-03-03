import SwiftUI
import FlixorKit

enum DetailsTab: String { case suggested = "SUGGESTED", details = "DETAILS", episodes = "EPISODES", extras = "EXTRAS" }

struct TVDetailsView: View {
    let item: MediaItem
    @StateObject private var vm = TVDetailsViewModel()
    @EnvironmentObject private var profileSettings: TVProfileSettings
    @EnvironmentObject private var watchlistController: TVWatchlistController
    @EnvironmentObject private var focusCoordinator: TVFocusCoordinator

    @State private var playbackItem: MediaItem?
    @State private var selectedTrailer: TVTrailer?
    @State private var focusRestoreToken = UUID()
    @State private var shouldRestoreFocusAfterDismiss = false

    @Namespace private var heroFocusNS
    @Namespace private var nsSuggested
    @Namespace private var nsEpisodes
    @Namespace private var nsDetails
    @State private var scrollY: CGFloat = 0
    @State private var contentSectionHasFocus: Bool = false

    private let compactHeaderHeight: CGFloat = 86
    private var detailsFocusScreenKey: String { "details:\(item.id)" }

    private var hasPlexSource: Bool {
        vm.playableId != nil || vm.plexRatingKey != nil
    }

    private var collapsedHeaderOpacity: Double {
        let scrollProgress = Double(min(max((scrollY - 36) / 96, 0), 1))
        let focusProgress = contentSectionHasFocus ? 1.0 : 0
        return max(scrollProgress, focusProgress)
    }

    private var shouldShowCollapsedHeader: Bool {
        collapsedHeaderOpacity > 0.01
    }

    private var collapsedHeaderInset: CGFloat {
        CGFloat(collapsedHeaderOpacity) * compactHeaderHeight
    }

    private var shouldShowBlur: Bool {
        contentSectionHasFocus || scrollY > 140
    }

    var body: some View {
        ZStack {
            // Layer 1: Full-page backdrop image
            CachedAsyncImage(url: vm.backdropURL, contentMode: .fill) {
                Color.black.opacity(0.35)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(edges: .all)

            // Layer 2: Subtle left-to-right gradient for text readability (hero area only)
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color.black.opacity(0.65), location: 0.0),
                    .init(color: Color.black.opacity(0.25), location: 0.4),
                    .init(color: .clear, location: 0.7)
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
            .ignoresSafeArea(edges: .all)

            // Layer 3: Frosted glass blur (shows when content sections have focus or scrolled past hero)
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)

                if let colors = vm.ultraBlurColors {
                    UltraBlurGradientBackground(colors: colors, opacity: 0.6)
                }
            }
            .opacity(shouldShowBlur ? 1 : 0)
            .animation(.easeInOut(duration: 0.4), value: shouldShowBlur)
            .ignoresSafeArea(edges: .all)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 38) {
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: DetailsScrollOffsetKey.self, value: -geo.frame(in: .named("detailsScroll")).minY)
                    }
                    .frame(height: 0)

                    TVDetailsHeroSection(
                        vm: vm,
                        item: item,
                        focusNS: heroFocusNS,
                        focusScreenKey: detailsFocusScreenKey,
                        focusRestoreToken: focusRestoreToken,
                        shouldRestoreFocus: shouldRestoreFocusAfterDismiss,
                        hasPlexSource: hasPlexSource,
                        onPlay: playContent,
                        onMyList: addToMyList,
                        onMarkWatched: {
                            Task { _ = await vm.markWatched() }
                        },
                        onTrailerCTA: {
                            if let trailer = vm.trailers.first {
                                selectedTrailer = trailer
                            }
                        },
                        onTrailerTapped: { trailer in
                            selectedTrailer = trailer
                        },
                        onFocusChange: { heroHasFocus in
                            if heroHasFocus {
                                contentSectionHasFocus = false
                            }
                        }
                    )
                    .id("details-hero")

                    if (vm.mediaKind == "tv" || vm.isSeason) && !vm.isEpisode {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Episodes")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 80)
                            TVEpisodesRail(
                                vm: vm,
                                focusNS: nsEpisodes,
                                focusScreenKey: detailsFocusScreenKey,
                                focusRestoreToken: focusRestoreToken,
                                shouldRestoreFocus: shouldRestoreFocusAfterDismiss,
                                onFocusChange: { focused in
                                    if focused {
                                        contentSectionHasFocus = true
                                    }
                                }
                            )
                                .focusScope(nsEpisodes)
                        }
                    }

                    if profileSettings.showRelatedContent && !vm.isSeason && !vm.isEpisode {
                        SuggestedSection(
                            vm: vm,
                            focusNS: nsSuggested,
                            focusScreenKey: detailsFocusScreenKey,
                            focusRestoreToken: focusRestoreToken,
                            shouldRestoreFocus: shouldRestoreFocusAfterDismiss,
                            onFocusChange: { focused in
                                contentSectionHasFocus = focused
                            },
                            onDismissSelection: restoreFocusAfterModal
                        )
                            .focusScope(nsSuggested)
                            .id("suggested-section")
                    }

                    TVDetailsInfoGrid(
                        vm: vm,
                        focusNS: nsDetails,
                        focusScreenKey: detailsFocusScreenKey,
                        focusRestoreToken: focusRestoreToken,
                        shouldRestoreFocus: shouldRestoreFocusAfterDismiss,
                        onFocusChange: { focused in
                            contentSectionHasFocus = focused
                        }
                    )
                        .focusScope(nsDetails)
                        .id("details-info")
                }
                .padding(.bottom, 80)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear
                    .frame(height: collapsedHeaderInset)
                    .allowsHitTesting(false)
            }
            .animation(.easeOut(duration: 0.22), value: collapsedHeaderInset)
            .coordinateSpace(name: "detailsScroll")

            // Layer 4: Pinned compact header (always above content, fades by focus/scroll)
            if shouldShowCollapsedHeader {
                VStack {
                    HStack {
                        if let logo = vm.logoURL {
                            CachedAsyncImage(url: logo, contentMode: .fit, showsErrorView: false) {
                                Text(vm.title.isEmpty ? item.title : vm.title)
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: 180, maxHeight: 46, alignment: .leading)
                            .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
                        } else {
                            Text(vm.title.isEmpty ? item.title : vm.title)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 80)
                    .padding(.top, 28)
                    .padding(.bottom, 14)
                    .background(
                        ZStack {
                            Rectangle()
                                .fill(.ultraThinMaterial)
                            LinearGradient(
                                colors: [Color.black.opacity(0.58), Color.black.opacity(0.24), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                    )
                    Spacer()
                }
                .opacity(collapsedHeaderOpacity)
                .animation(.easeOut(duration: 0.22), value: collapsedHeaderOpacity)
                .allowsHitTesting(false)
                .ignoresSafeArea(edges: .top)
                .zIndex(500)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: .all)
        .fullScreenCover(item: $playbackItem, onDismiss: restoreFocusAfterModal) { item in
            PlayerView(item: item)
        }
        .fullScreenCover(item: $selectedTrailer, onDismiss: restoreFocusAfterModal) { trailer in
            TVTrailerModal(trailer: trailer, onClose: {
                selectedTrailer = nil
            })
        }
        .task {
            shouldRestoreFocusAfterDismiss = false
            await vm.load(for: item)
        }
        .onPreferenceChange(DetailsScrollOffsetKey.self) { value in
            scrollY = max(0, value)
        }
    }

    private func playContent() {
        print("🎬 [TVDetailsView] playContent called")
        print("🎬 [TVDetailsView] hasPlexSource: \(hasPlexSource)")
        print("🎬 [TVDetailsView] vm.playableId: \(vm.playableId ?? "nil")")
        print("🎬 [TVDetailsView] vm.plexRatingKey: \(vm.plexRatingKey ?? "nil")")

        guard hasPlexSource else {
            print("🎬 [TVDetailsView] No Plex source, returning")
            return
        }

        let onDeckEpisode = (!vm.isSeason && !vm.isEpisode && vm.mediaKind == "tv") ? vm.onDeck : nil
        let ratingKey = onDeckEpisode?.id.replacingOccurrences(of: "plex:", with: "")
            ?? vm.plexRatingKey
            ?? vm.playableId?.replacingOccurrences(of: "plex:", with: "")

        guard let ratingKey, !ratingKey.isEmpty else {
            print("🎬 [TVDetailsView] No ratingKey, returning")
            return
        }

        print("🎬 [TVDetailsView] ratingKey: \(ratingKey)")

        let playbackId: String
        if let onDeckEpisode {
            playbackId = onDeckEpisode.id
        } else if let playableId = vm.playableId, playableId.hasPrefix("plex:") {
            playbackId = playableId
        } else {
            playbackId = "plex:\(ratingKey)"
        }

        let playbackType: String = {
            if onDeckEpisode != nil { return "episode" }
            if item.type == "episode" || vm.isEpisode { return "episode" }
            if item.type == "season" || vm.isSeason { return "season" }
            if vm.mediaKind == "movie" { return "movie" }
            if vm.mediaKind == "tv" { return "show" }
            return item.type
        }()

        let candidate = MediaItem(
            id: playbackId,
            title: onDeckEpisode?.title ?? (vm.title.isEmpty ? item.title : vm.title),
            type: playbackType,
            thumb: item.thumb,
            art: item.art,
            logo: item.logo,
            year: vm.year.flatMap { Int($0) } ?? item.year,
            rating: item.rating,
            duration: onDeckEpisode?.durationMin.map { $0 * 60000 } ?? vm.runtime.map { $0 * 60000 } ?? item.duration,
            viewOffset: onDeckEpisode?.viewOffset ?? vm.resumeViewOffset ?? item.viewOffset,
            summary: onDeckEpisode?.overview ?? (vm.overview.isEmpty ? item.summary : vm.overview),
            grandparentTitle: vm.showTitle ?? item.grandparentTitle,
            grandparentThumb: item.grandparentThumb,
            grandparentArt: item.grandparentArt,
            parentIndex: vm.seasonNumber ?? item.parentIndex,
            index: vm.episodeNumber ?? item.index,
            parentRatingKey: item.parentRatingKey,
            parentTitle: item.parentTitle,
            leafCount: item.leafCount,
            viewedLeafCount: item.viewedLeafCount
        )

        print("🎬 [TVDetailsView] Setting playbackItem with id: \(candidate.id)")
        playbackItem = candidate
    }

    private func restoreFocusAfterModal() {
        shouldRestoreFocusAfterDismiss = true
        focusRestoreToken = UUID()
    }

    private func addToMyList() {
        Task {
            if profileSettings.traktSyncWatchlist,
               FlixorCore.shared.isTraktAuthenticated,
               let tmdbId = vm.tmdbId,
               let tmdbInt = Int(tmdbId) {
                struct TraktPayload: Codable {
                    let tmdbId: Int
                    let mediaType: String
                }
                let mediaType = (vm.mediaKind == "tv" || vm.mediaKind == "show" || vm.mediaKind == "episode") ? "show" : "movie"
                do {
                    let _: SimpleOkResponse = try await APIClient.shared.post(
                        "/api/trakt/watchlist",
                        body: TraktPayload(tmdbId: tmdbInt, mediaType: mediaType)
                    )
                    watchlistController.registerAdd(id: "tmdb:\(mediaType == "show" ? "tv" : "movie"):\(tmdbInt)")
                    return
                } catch {
                    #if DEBUG
                    print("⚠️ [TVDetails] Trakt watchlist add failed: \(error)")
                    #endif
                }
            }

            guard let plexId = vm.plexGuid ?? vm.plexRatingKey else { return }
            let encoded = plexId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? plexId
            do {
                let _: SimpleOkResponse = try await APIClient.shared.put("/api/plextv/watchlist/\(encoded)")
                let canonical = vm.playableId ?? (plexId.hasPrefix("plex:") ? plexId : "plex:\(plexId)")
                watchlistController.registerAdd(id: canonical)
            } catch {
                #if DEBUG
                print("⚠️ [TVDetails] Plex watchlist add failed: \(error)")
                #endif
            }
        }
    }
}

private struct TVDetailsHeroSection: View {
    @ObservedObject var vm: TVDetailsViewModel
    let item: MediaItem
    let focusNS: Namespace.ID
    let focusScreenKey: String
    let focusRestoreToken: UUID
    let shouldRestoreFocus: Bool
    let hasPlexSource: Bool
    let onPlay: () -> Void
    let onMyList: () -> Void
    let onMarkWatched: () -> Void
    let onTrailerCTA: () -> Void
    let onTrailerTapped: (TVTrailer) -> Void
    var onFocusChange: ((Bool) -> Void)?
    @EnvironmentObject private var profileSettings: TVProfileSettings
    @EnvironmentObject private var focusCoordinator: TVFocusCoordinator
    @Environment(\.tvThemePalette) private var theme
    @Environment(\.tvTypography) private var typography

    @FocusState private var focusedButton: HeroAction?

    enum HeroAction: Hashable {
        case play
        case myList
        case watched
        case trailer

        var storageID: String {
            switch self {
            case .play: return "play"
            case .myList: return "myList"
            case .watched: return "watched"
            case .trailer: return "trailer"
            }
        }

        static func fromStorageID(_ value: String?) -> HeroAction? {
            switch value {
            case "play": return .play
            case "myList": return .myList
            case "watched": return .watched
            case "trailer": return .trailer
            default: return nil
            }
        }
    }

    private var metaItems: [String] {
        var values: [String] = []
        if let year = vm.year, !year.isEmpty { values.append(year) }
        if let runtime = vm.runtime {
            if runtime >= 60 {
                values.append("\(runtime / 60)h \(runtime % 60)m")
            } else {
                values.append("\(runtime)m")
            }
        }
        return values
    }

    private var resolutionBadge: String? {
        guard let raw = vm.activeVersionDetail?.technical.resolution else { return nil }
        let lower = raw.lowercased()
        if lower.contains("2160") || lower.contains("4k") || lower.contains("uhd") { return "4K" }
        if lower.contains("1080") || lower.contains("fhd") { return "HD" }
        if lower.contains("720") || lower == "hd" || lower.contains("hd ready") { return "HD" }

        let parts = raw.split(separator: "x")
        if parts.count == 2,
           let width = Int(parts[0]),
           let height = Int(parts[1]) {
            if width >= 3800 || height >= 2100 { return "4K" }
            if width >= 1900 || height >= 1000 { return "HD" }
            if width >= 1260 || height >= 700 { return "HD" }
        }
        return nil
    }

    private var hdrBadgeValue: String? {
        if let technicalHDR = vm.activeVersionDetail?.technical.hdrFormat {
            return technicalHDR
        }

        for badge in vm.badges {
            let lower = badge.lowercased()
            if lower.contains("dolby vision") || lower == "dv" || lower.contains("dovi") { return "Dolby Vision" }
            if lower.contains("hdr10+") { return "HDR10+" }
            if lower.contains("hdr10") { return "HDR10" }
            if lower.contains("hlg") { return "HLG" }
            if lower == "hdr" || lower.contains(" hdr") { return "HDR" }
        }
        return nil
    }

    private var containerBadge: String? {
        guard let container = vm.activeVersionDetail?.technical.container?.trimmingCharacters(in: .whitespacesAndNewlines),
              !container.isEmpty else { return nil }
        return container.uppercased()
    }

    private var accessibilityBadges: [String] {
        let subtitleTokens = vm.subtitleTracks
            .map { ($0.name + " " + ($0.language ?? "")).lowercased() }
            .joined(separator: " ")
        let audioTokens = vm.audioTracks
            .map { ($0.name + " " + ($0.language ?? "")).lowercased() }
            .joined(separator: " ")

        var badges: [String] = []
        if !vm.subtitleTracks.isEmpty || subtitleTokens.contains("cc") || subtitleTokens.contains("closed caption") { badges.append("CC") }
        if subtitleTokens.contains("sdh") || subtitleTokens.contains("hard of hearing") || subtitleTokens.contains("deaf") { badges.append("SDH") }
        if audioTokens.contains("audio description") || audioTokens.contains("descriptive") || audioTokens.contains("ad") { badges.append("AD") }
        return badges
    }

    private var filteredTechnicalBadges: [String] {
        var output: [String] = []
        for badge in vm.badges {
            let lower = badge.lowercased()
            if lower == "plex" || lower.contains("no local") { continue }
            if lower.contains("2160") || lower.contains("4k") || lower.contains("1080") || lower.contains("720") || lower == "hd" { continue }
            if lower.contains("hdr") || lower.contains("dolby vision") || lower == "dv" || lower.contains("dovi") { continue }
            if lower.contains("atmos") || lower.contains("truehd") {
                output.append("Dolby Atmos")
                continue
            }
            if lower == "cc" || lower.contains("closed caption") {
                output.append("CC")
                continue
            }
            if lower == "sdh" || lower.contains("hard of hearing") || lower.contains("deaf") {
                output.append("SDH")
                continue
            }
            if lower == "ad" || lower.contains("audio description") {
                output.append("AD")
                continue
            }
        }

        output.append(contentsOf: accessibilityBadges)
        var seen = Set<String>()
        return output.filter { seen.insert($0).inserted }
    }

    private var effectiveRatings: TVDetailsViewModel.ExternalRatings? {
        let baseIMDb = vm.externalRatings?.imdb?.score ?? vm.plexImdbRating ?? vm.tmdbRating
        let baseVotes = vm.externalRatings?.imdb?.votes
        let critic = vm.externalRatings?.rottenTomatoes?.critic
        let audience = vm.externalRatings?.rottenTomatoes?.audience ?? vm.plexAudienceRating

        let imdbScore = profileSettings.showIMDbRating ? baseIMDb : nil
        let imdbVotes = profileSettings.showIMDbRating ? baseVotes : nil
        let rtCritic = profileSettings.showRottenTomatoesCritic ? critic : nil
        let rtAudience = profileSettings.showRottenTomatoesAudience ? audience : nil

        let hasIMDb = imdbScore != nil || imdbVotes != nil
        let hasRT = rtCritic != nil || rtAudience != nil
        guard hasIMDb || hasRT else { return nil }

        return TVDetailsViewModel.ExternalRatings(
            imdb: hasIMDb ? TVDetailsViewModel.ExternalRatings.IMDb(score: imdbScore, votes: imdbVotes) : nil,
            rottenTomatoes: hasRT ? TVDetailsViewModel.ExternalRatings.RottenTomatoes(critic: rtCritic, audience: rtAudience) : nil
        )
    }

    private var hasPlexAvailability: Bool {
        vm.badges.contains(where: { $0.lowercased() == "plex" }) || vm.plexRatingKey != nil
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                HStack(alignment: .bottom, spacing: 40) {
                    VStack(alignment: .leading, spacing: 16) {
                        if let logo = vm.logoURL {
                            CachedAsyncImage(url: logo, contentMode: .fit, showsErrorView: false) {
                                Text(vm.title.isEmpty ? item.title : vm.title)
                                    .font(.system(size: 68, weight: .heavy))
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: 520, maxHeight: 120, alignment: .leading)
                            .shadow(color: .black.opacity(0.7), radius: 12, y: 6)
                        } else {
                            Text(vm.title.isEmpty ? item.title : vm.title)
                                .font(.system(size: 68, weight: .heavy))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                        }

                        typeGenreRow

                        if !vm.overview.isEmpty {
                            Text(vm.overview)
                                .font(typography.custom(size: 24, weight: .regular))
                                .foregroundStyle(theme.textSecondary)
                                .lineLimit(4)
                                .frame(maxWidth: 780, alignment: .leading)
                        }

                        technicalRow

                        HStack(spacing: 18) {
                            heroActionButton(
                                title: hasPlexSource ? vm.primaryPlayActionTitle : "Unavailable",
                                systemImage: "play.fill",
                                action: onPlay,
                                heroAction: .play,
                                emphasized: true,
                                disabled: !hasPlexSource
                            )
                            .prefersDefaultFocus(true, in: focusNS)

                            heroActionButton(
                                title: "My List",
                                systemImage: "plus",
                                action: onMyList,
                                heroAction: .myList
                            )

                            if vm.shouldShowTrailerCTA {
                                heroActionButton(
                                    title: "Trailer",
                                    systemImage: "play.rectangle.fill",
                                    action: onTrailerCTA,
                                    heroAction: .trailer
                                )
                            }

                            if vm.canMarkWatched || vm.isWatchedState {
                                heroActionButton(
                                    title: vm.isWatchedState ? "Watched" : "Mark Watched",
                                    systemImage: vm.isWatchedState ? "checkmark.circle.fill" : "checkmark.circle",
                                    action: onMarkWatched,
                                    heroAction: .watched,
                                    disabled: vm.isWatchedState
                                )
                            }
                        }

                        if !vm.trailers.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(vm.trailers.prefix(5)) { trailer in
                                        TVTrailerCard(trailer: trailer, onPlay: {
                                            onTrailerTapped(trailer)
                                        }, onFocusChange: { focused in
                                            if focused {
                                                onFocusChange?(true)
                                            }
                                        })
                                    }
                                }
                                .padding(.leading, 12)
                                .padding(.trailing, 20)
                                .padding(.vertical, 14)
                            }
                            .padding(.leading, -12)
                        }
                    }
                    .frame(maxWidth: 930, alignment: .leading)

                    Spacer(minLength: 20)

                    if profileSettings.showCastCrew {
                        VStack(alignment: .trailing, spacing: 18) {
                            if !vm.castShort.isEmpty {
                                creditsBlock(title: "Starring", value: vm.castShort.map { $0.name }.joined(separator: ", "))
                            }
                            if !vm.directors.isEmpty {
                                creditsBlock(title: vm.directors.count > 1 ? "Directors" : "Director", value: vm.directors.prefix(2).joined(separator: ", "))
                            }
                            if vm.mediaKind == "tv", !vm.creators.isEmpty {
                                creditsBlock(title: vm.creators.count > 1 ? "Creators" : "Creator", value: vm.creators.prefix(2).joined(separator: ", "))
                            }
                        }
                        .frame(maxWidth: 420, alignment: .trailing)
                        .padding(.bottom, 36)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.top, 120)
                .padding(.bottom, 70)
            }
            .clipShape(Rectangle())
        }
        .frame(height: 840)
        .onChange(of: focusedButton) { newValue in
            // Only report when hero gains focus (to reset blur)
            if newValue != nil {
                onFocusChange?(true)
            }
            guard let newValue else { return }
            focusCoordinator.remember(screen: focusScreenKey, sectionID: "hero", itemID: newValue.storageID)
        }
        .onAppear {
            guard shouldRestoreFocus else { return }
            restoreFocusedButton()
        }
        .onChange(of: focusRestoreToken) { _ in
            guard shouldRestoreFocus else { return }
            restoreFocusedButton()
        }
    }

    private var typeGenreRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: vm.isEpisode ? "tv" : (vm.mediaKind == "movie" ? "film" : "tv"))
                    .font(.system(size: 14))
                Text(vm.isEpisode ? "Episode" : (vm.mediaKind == "movie" ? "Movie" : (vm.isSeason ? "Season" : "Series")))
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.white.opacity(0.9))

            if vm.isEpisode, let season = vm.seasonNumber, let episode = vm.episodeNumber {
                Text("·")
                    .foregroundStyle(.white.opacity(0.5))
                Text("S\(season) E\(episode)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }

            if !vm.genres.isEmpty {
                Text("·")
                    .foregroundStyle(.white.opacity(0.5))
                Text(vm.genres.prefix(3).joined(separator: " · "))
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.white.opacity(0.88))
            }

            if let rating = vm.rating, !rating.isEmpty {
                TVContentRatingBadge(rating: rating)
            }
        }
    }

    private var technicalRow: some View {
        HStack(spacing: 10) {
            if !metaItems.isEmpty {
                Text(metaItems.joined(separator: " • "))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }

            if let resolution = resolutionBadge {
                TVTechnicalBadge(text: resolution)
            }

            if let hdr = hdrBadgeValue {
                TVTechnicalBadge(text: hdr)
            }

            if let container = containerBadge {
                TVTechnicalBadge(text: container)
            }

            ForEach(filteredTechnicalBadges, id: \.self) { badge in
                TVTechnicalBadge(text: badge)
            }

            if hasPlexAvailability {
                Label("Available", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.green.opacity(0.95))
            } else if vm.tmdbId != nil {
                Label("Not available", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.orange.opacity(0.95))
            }

            if let ratings = effectiveRatings {
                TVRatingsStrip(ratings: ratings)
            }
        }
    }

    private func creditsBlock(title: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }

    private func restoreFocusedButton() {
        guard focusCoordinator.lastFocusedSection(screen: focusScreenKey) == "hero" else { return }
        let storedItemID = focusCoordinator.lastFocusedItem(screen: focusScreenKey, sectionID: "hero")
        guard let action = HeroAction.fromStorageID(storedItemID) else { return }
        DispatchQueue.main.async {
            focusedButton = action
        }
    }

    private func heroActionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void,
        heroAction: HeroAction,
        emphasized: Bool = false,
        disabled: Bool = false
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(typography.custom(size: emphasized ? 26 : 24, weight: .semibold))
            .foregroundStyle(emphasized ? theme.background : theme.textPrimary)
            .padding(.horizontal, emphasized ? 28 : 24)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(emphasized ? theme.accent : theme.surfaceGlass)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        focusedButton == heroAction ? theme.strokeFocused : theme.strokeDefault,
                        lineWidth: focusedButton == heroAction ? 3 : 1
                    )
            )
        }
        .buttonStyle(.card)
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1.0)
        .focused($focusedButton, equals: heroAction)
    }

}

private struct SuggestedSection: View {
    @ObservedObject var vm: TVDetailsViewModel
    var focusNS: Namespace.ID
    let focusScreenKey: String
    let focusRestoreToken: UUID
    let shouldRestoreFocus: Bool
    var onFocusChange: (Bool) -> Void
    var onDismissSelection: () -> Void
    @EnvironmentObject private var focusCoordinator: TVFocusCoordinator
    @State private var selected: MediaItem?
    @State private var restoreRowID: String?
    @State private var clearRestoreTask: Task<Void, Never>?
    @State private var isSectionFocused: Bool = false

    var body: some View {
        let availableRows = [
            !vm.related.isEmpty ? "because-you-watched" : nil,
            !vm.similar.isEmpty ? "more-like-this" : nil
        ].compactMap { $0 }
        let defaultRowID = resolvedDefaultRowID(availableRows: availableRows)

        VStack(alignment: .leading, spacing: 28) {
            if !vm.related.isEmpty {
                TVCarouselRow(
                    title: "Because You Watched",
                    items: vm.related,
                    kind: .poster,
                    focusNS: focusNS,
                    defaultFocus: defaultRowID == "because-you-watched",
                    sectionId: "because-you-watched",
                    onSelect: { selected = $0 },
                    focusScreenKey: focusScreenKey
                )
            }
            if !vm.similar.isEmpty {
                TVCarouselRow(
                    title: "More Like This",
                    items: vm.similar,
                    kind: .poster,
                    focusNS: focusNS,
                    defaultFocus: defaultRowID == "more-like-this",
                    sectionId: "more-like-this",
                    onSelect: { selected = $0 },
                    focusScreenKey: focusScreenKey
                )
            }
        }
        .padding(.vertical, 16)
        .onPreferenceChange(RowFocusKey.self) { newId in
            let wasFocused = isSectionFocused
            let nowFocused = newId != nil

            if nowFocused && !wasFocused {
                isSectionFocused = true
                onFocusChange(true)
            } else if !nowFocused {
                isSectionFocused = false
            }
        }
        .onAppear {
            guard shouldRestoreFocus else { return }
            armRestoreRow()
        }
        .onChange(of: focusRestoreToken) { _ in
            guard shouldRestoreFocus else { return }
            armRestoreRow()
        }
        .fullScreenCover(item: $selected, onDismiss: {
            onDismissSelection()
            armRestoreRow()
        }) { selectedItem in
            TVDetailsView(item: selectedItem)
        }
        .onDisappear {
            clearRestoreTask?.cancel()
        }
    }

    private func resolvedDefaultRowID(availableRows: [String]) -> String? {
        guard shouldRestoreFocus else { return nil }
        if let restoreRowID, availableRows.contains(restoreRowID) {
            return restoreRowID
        }
        if let remembered = focusCoordinator.lastFocusedSection(screen: focusScreenKey),
           availableRows.contains(remembered) {
            return remembered
        }
        return availableRows.first
    }

    private func armRestoreRow() {
        clearRestoreTask?.cancel()
        restoreRowID = focusCoordinator.lastFocusedSection(screen: focusScreenKey)
        clearRestoreTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            restoreRowID = nil
        }
    }
}

private struct DetailsScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
