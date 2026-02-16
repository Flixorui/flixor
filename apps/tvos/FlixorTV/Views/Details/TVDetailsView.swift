import SwiftUI
import FlixorKit

enum DetailsTab: String { case suggested = "SUGGESTED", details = "DETAILS", episodes = "EPISODES", extras = "EXTRAS" }

struct TVDetailsView: View {
    let item: MediaItem
    @StateObject private var vm = TVDetailsViewModel()

    @State private var playbackItem: MediaItem?
    @State private var selectedTrailer: TVTrailer?

    @Namespace private var heroFocusNS
    @Namespace private var nsSuggested
    @Namespace private var nsEpisodes
    @Namespace private var nsDetails
    @State private var scrollY: CGFloat = 0
    @State private var contentSectionHasFocus: Bool = false

    private let compactHeaderHeight: CGFloat = 86

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
                        hasPlexSource: hasPlexSource,
                        onPlay: playContent,
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
                            TVEpisodesRail(vm: vm, focusNS: nsEpisodes)
                                .focusScope(nsEpisodes)
                        }
                    }

                    if !vm.isSeason && !vm.isEpisode {
                        SuggestedSection(vm: vm, focusNS: nsSuggested, onFocusChange: { focused in
                            contentSectionHasFocus = focused
                        })
                            .focusScope(nsSuggested)
                            .id("suggested-section")
                    }

                    TVDetailsInfoGrid(vm: vm, focusNS: nsDetails, onFocusChange: { focused in
                        contentSectionHasFocus = focused
                    })
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
        .fullScreenCover(item: $playbackItem) { item in
            PlayerView(item: item)
        }
        .fullScreenCover(item: $selectedTrailer) { trailer in
            TVTrailerModal(trailer: trailer, onClose: {
                selectedTrailer = nil
            })
        }
        .task {
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

        let ratingKey = vm.plexRatingKey
            ?? vm.playableId?.replacingOccurrences(of: "plex:", with: "")

        guard let ratingKey, !ratingKey.isEmpty else {
            print("🎬 [TVDetailsView] No ratingKey, returning")
            return
        }

        print("🎬 [TVDetailsView] ratingKey: \(ratingKey)")

        let playbackId: String
        if let playableId = vm.playableId, playableId.hasPrefix("plex:") {
            playbackId = playableId
        } else {
            playbackId = "plex:\(ratingKey)"
        }

        let playbackType: String = {
            if item.type == "episode" || vm.isEpisode { return "episode" }
            if item.type == "season" || vm.isSeason { return "season" }
            if vm.mediaKind == "movie" { return "movie" }
            if vm.mediaKind == "tv" { return "show" }
            return item.type
        }()

        let candidate = MediaItem(
            id: playbackId,
            title: vm.title.isEmpty ? item.title : vm.title,
            type: playbackType,
            thumb: item.thumb,
            art: item.art,
            logo: item.logo,
            year: vm.year.flatMap { Int($0) } ?? item.year,
            rating: item.rating,
            duration: vm.runtime.map { $0 * 60000 } ?? item.duration,
            viewOffset: item.viewOffset,
            summary: vm.overview.isEmpty ? item.summary : vm.overview,
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
}

private struct TVDetailsHeroSection: View {
    @ObservedObject var vm: TVDetailsViewModel
    let item: MediaItem
    let focusNS: Namespace.ID
    let hasPlexSource: Bool
    let onPlay: () -> Void
    let onTrailerTapped: (TVTrailer) -> Void
    var onFocusChange: ((Bool) -> Void)?

    @FocusState private var focusedButton: HeroAction?

    enum HeroAction: Hashable {
        case play
        case myList
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

        let hasIMDb = baseIMDb != nil || baseVotes != nil
        let hasRT = critic != nil || audience != nil
        guard hasIMDb || hasRT else { return nil }

        return TVDetailsViewModel.ExternalRatings(
            imdb: hasIMDb ? TVDetailsViewModel.ExternalRatings.IMDb(score: baseIMDb, votes: baseVotes) : nil,
            rottenTomatoes: hasRT ? TVDetailsViewModel.ExternalRatings.RottenTomatoes(critic: critic, audience: audience) : nil
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
                                .font(.system(size: 24, weight: .regular))
                                .foregroundStyle(.white.opacity(0.86))
                                .lineLimit(4)
                                .frame(maxWidth: 780, alignment: .leading)
                        }

                        technicalRow

                        HStack(spacing: 28) {
                            Button(action: onPlay) {
                                HStack(spacing: 8) {
                                    Image(systemName: "play.fill")
                                    Text(hasPlexSource ? "Play" : "Unavailable")
                                }
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(hasPlexSource ? Color.black : Color.gray)
                                .padding(.horizontal, 28)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .fill(hasPlexSource ? Color.white : Color.white.opacity(0.5))
                                )
                            }
                            .buttonStyle(.card)
                            .disabled(!hasPlexSource)
                            .focused($focusedButton, equals: .play)
                            .prefersDefaultFocus(true, in: focusNS)

                            Button(action: {}) {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus")
                                    Text("My List")
                                }
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 14)
                                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.14)))
                            }
                            .buttonStyle(.card)
                            .focused($focusedButton, equals: .myList)
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

}

private struct SuggestedSection: View {
    @ObservedObject var vm: TVDetailsViewModel
    var focusNS: Namespace.ID
    var onFocusChange: (Bool) -> Void
    @State private var selected: MediaItem?
    @State private var focusedRowId: String?
    @State private var rowLastFocusedItem: [String: String] = [:]
    @State private var nextRowToReceiveFocus: String?
    @State private var hasEstablishedInitialFocus = false
    @State private var clearNextRowTask: Task<Void, Never>?
    @State private var isSectionFocused: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if !vm.related.isEmpty {
                TVCarouselRow(
                    title: "Because You Watched",
                    items: vm.related,
                    kind: .poster,
                    focusNS: focusNS,
                    defaultFocus: focusedRowId == "because-you-watched"
                        || nextRowToReceiveFocus == "because-you-watched"
                        || (!hasEstablishedInitialFocus && focusedRowId == nil),
                    preferredFocusItemId: rowLastFocusedItem["because-you-watched"],
                    sectionId: "because-you-watched",
                    onSelect: { selected = $0 }
                )
            }
            if !vm.similar.isEmpty {
                TVCarouselRow(
                    title: "More Like This",
                    items: vm.similar,
                    kind: .poster,
                    focusNS: focusNS,
                    defaultFocus: focusedRowId == "more-like-this"
                        || nextRowToReceiveFocus == "more-like-this"
                        || (!hasEstablishedInitialFocus && vm.related.isEmpty && focusedRowId == nil),
                    preferredFocusItemId: rowLastFocusedItem["more-like-this"],
                    sectionId: "more-like-this",
                    onSelect: { selected = $0 }
                )
            }
        }
        .padding(.vertical, 16)
        .onPreferenceChange(RowFocusKey.self) { newId in
            let previousId = focusedRowId
            let wasFocused = isSectionFocused
            let nowFocused = newId != nil

            if previousId != newId {
                if newId != nil {
                    hasEstablishedInitialFocus = true
                }
                nextRowToReceiveFocus = newId
                focusedRowId = newId
                clearNextRowTask?.cancel()
                clearNextRowTask = Task {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    guard !Task.isCancelled else { return }
                    nextRowToReceiveFocus = nil
                }
            }

            // Only report when gaining focus, not when losing
            // Hero section is responsible for resetting contentSectionHasFocus
            if nowFocused && !wasFocused {
                isSectionFocused = true
                onFocusChange(true)
            } else if !nowFocused {
                isSectionFocused = false
            }
        }
        .onPreferenceChange(RowItemFocusKey.self) { value in
            if let rowId = value.rowId, let itemId = value.itemId {
                rowLastFocusedItem[rowId] = itemId
            }
        }
        .fullScreenCover(item: $selected) { selectedItem in
            TVDetailsView(item: selectedItem)
        }
        .onDisappear {
            clearNextRowTask?.cancel()
        }
    }
}

private struct DetailsScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
