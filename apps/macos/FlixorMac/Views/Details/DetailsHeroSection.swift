//
//  DetailsHeroSection.swift
//  FlixorMac
//
//  Hero: backdrop, logo/title, metadata and ratings rows, overview, trailers, credits
//

import SwiftUI
import FlixorKit

// MARK: - Hero Section

struct DetailsHeroSection: View {
    @ObservedObject var vm: DetailsViewModel
    let item: MediaItem
    let trailers: [Trailer]
    let onPlay: () -> Void
    let onStremio: () -> Void
    let showsStremioButton: Bool
    let onViewShow: () -> Void
    let layout: DetailsLayoutMetrics
    var onChooseStremioSource: () -> Void = {}

    var isEpisode: Bool { item.type == "episode" }
    private var seasonNumber: Int? { item.parentIndex }
    private var episodeNumber: Int? { item.index }

    @State private var isOverviewExpanded = false
    @State private var selectedTrailer: Trailer?

    // Profile-scoped rating visibility settings
    @ObservedObject private var ratingPrefs = RatingPreferencesStore.shared
    @Environment(\.flixorTheme) var theme
    @Environment(\.detailsTitleActions) var titleActions
    @Environment(\.detailsHeroTrailer) var heroTrailer

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

    // HDR/DV badge from technical info (uses hdrFormat which checks both videoProfile and displayTitle)
    private var hdrBadge: String? {
        guard let hdrFormat = vm.activeVersionDetail?.technical.hdrFormat else { return nil }
        // Convert full format name to short badge
        switch hdrFormat {
        case "Dolby Vision": return "DV"
        case "HDR10+": return "HDR10+"
        case "HDR10": return "HDR10"
        case "HLG": return "HLG"
        case "HDR": return "HDR"
        default: return hdrFormat
        }
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
            if mins == 0 { return String(localized: "\(hours)h") }
            return String(localized: "\(hours)h \(mins)m")
        }
        return String(localized: "\(minutes)m")
    }

    private func hasRatings(_ ratings: DetailsViewModel.ExternalRatings) -> Bool {
        if let score = ratings.imdb?.score, score > 0 { return true }
        if let critic = ratings.rottenTomatoes?.critic, critic > 0 { return true }
        if let audience = ratings.rottenTomatoes?.audience, audience > 0 { return true }
        return false
    }

    @State private var showFullOverview = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // The artwork sits behind the page: see DetailsPersistentBackdrop.
            // Two-column layout: content left, credits right
            HStack(alignment: .bottom, spacing: DS.Space.s40) {
                // LEFT COLUMN - Primary Content
                VStack(alignment: .leading, spacing: DS.Space.s10) {
                    Spacer(minLength: 0)

                    // Availability above the title (where Apple TV shows "Available
                    // for Rent"): positive only, never a warning when addons can play
                    // it, and never a Plex mention in Stremio-only mode.
                    availabilityBadge
                        .fixedSize()

                    // Logo or Title
                    if let logo = vm.logoURL {
                        FittedLogoLayout(maxWidth: logoWidth, maxHeight: logoMaxHeight) {
                            CachedAsyncImage(url: logo, contentMode: .fit)
                        }
                        .shadow(color: .black.opacity(0.7), radius: 16, y: 6)
                            .padding(.bottom, DS.Space.s4)
                    } else {
                        Text(vm.title)
                            .font(.system(size: titleFontSize, weight: .heavy))
                            .kerning(0.4)
                            .shadow(color: .black.opacity(0.6), radius: 12)
                    }

                    // Type · Genres · Rating row
                    typeGenreRatingRow

                    // Description with MORE button
                    if !vm.overview.isEmpty {
                        descriptionSection
                    }

                    // Technical metadata row (includes ratings at end)
                    technicalMetadataRow

                    // Action buttons (Play + circle buttons)
                    actionButtonsRow
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.top, DS.Space.s6)
                }
                .frame(maxWidth: contentColumnMaxWidth, maxHeight: .infinity, alignment: .bottomLeading)

                Spacer(minLength: 20)

                // RIGHT COLUMN - Credits (only on wider screens)
                if width >= 900 {
                    creditsSection
                        .frame(maxWidth: creditsColumnWidth, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            .frame(maxHeight: .infinity)
            .padding(.leading, layout.heroHorizontalPadding)
            .padding(.trailing, layout.heroHorizontalPadding)
            .padding(.top, layout.heroTopPadding)
            .padding(.bottom, layout.heroBottomPadding)
        }
        .frame(maxWidth: .infinity, minHeight: layout.heroHeight, maxHeight: layout.heroHeight)
        .overlay(alignment: .topTrailing) {
            if let heroTrailer {
                DetailsHeroTrailerControls(controller: heroTrailer)
                    .padding(.top, DS.Space.s80)
                    .padding(.trailing, layout.heroHorizontalPadding)
            }
        }
        .reportsDetailsHeroFrame()
        .sheet(item: $selectedTrailer) { trailer in
            TrailerModal(
                trailer: trailer,
                onClose: { selectedTrailer = nil }
            )
        }
        .sheet(isPresented: $showFullOverview) {
            OverviewModal(
                title: vm.title,
                overview: vm.overview,
                onClose: { showFullOverview = false }
            )
        }
    }

    // MARK: - Type/Genre/Rating Row (Apple TV+ style)
    @ViewBuilder private var typeGenreRatingRow: some View {
        HStack(spacing: DS.Space.s8) {
            // Media type with icon
            HStack(spacing: DS.Space.s4) {
                Image(systemName: isEpisode ? "tv" : (vm.mediaKind == "movie" ? "film" : "tv"))
                    .font(.flixor(.caption))
                Text(isEpisode ? "Episode" : (vm.mediaKind == "movie" ? "Movie" : (vm.isSeason ? "Season" : "Series")))
            }
            .font(.flixor(.callout, weight: .medium))

            // Episode/Season info for episodes
            if isEpisode {
                Text("·")
                    .foregroundStyle(.white.opacity(0.5))
                if let season = seasonNumber, let episode = episodeNumber {
                    Text("S\(season) E\(episode)")
                        .font(.flixor(.callout, weight: .semibold))
                } else if let episode = episodeNumber {
                    Text("E\(episode)")
                        .font(.flixor(.callout, weight: .semibold))
                }
            }

            // Episode count for TV shows (not episodes, not movies)
            if !isEpisode && vm.mediaKind != "movie", let count = vm.episodeCount, count > 0 {
                Text("·")
                    .foregroundStyle(.white.opacity(0.5))
                Text("\(count) Episodes")
            }

            // Separator
            if !vm.genres.isEmpty {
                Text("·")
                    .foregroundStyle(.white.opacity(0.5))
            }

            // Genres (up to 3)
            ForEach(Array(vm.genres.prefix(3).enumerated()), id: \.offset) { index, genre in
                Text(genre)
                if index < min(vm.genres.count, 3) - 1 {
                    Text("·")
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            // Content rating badge
            if let rating = vm.rating, !rating.isEmpty {
                ContentRatingBadge(rating: rating)
            }
        }
        .font(.flixor(.callout))
        .foregroundStyle(.white.opacity(0.9))
    }

    // MARK: - Description with MORE button
    @ViewBuilder private var descriptionSection: some View {
        HStack(alignment: .bottom, spacing: DS.Space.s8) {
            Text(vm.overview)
                .font(.flixor(.body))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .frame(maxWidth: min(layout.heroTextMaxWidth, contentColumnMaxWidth - 70), alignment: .leading)

            if vm.overview.count > 100 {
                Button(action: { showFullOverview = true }) {
                    Text("MORE")
                        .font(.flixor(.caption, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, DS.Space.s10)
                        .padding(.vertical, DS.Space.s4)
                        .background(Color.white.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r4))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Technical Metadata Row
    /// The year, runtime, ratings and badges on one line. With several
    /// ratings turned on the line can outgrow the column, so it drops the
    /// technical badges first, then all but the first three ratings, rather
    /// than truncating the year and runtime.
    @ViewBuilder private var technicalMetadataRow: some View {
        let ratings = ratingPrefs.merged(vm.ratingInputs)
        ViewThatFits(in: .horizontal) {
            technicalMetadataContent(ratings: ratings, showBadges: true)
            technicalMetadataContent(ratings: ratings, showBadges: false)
            technicalMetadataContent(ratings: Array(ratings.prefix(3)), showBadges: false)
        }
        .font(.flixor(.footnote, weight: .medium))
        .foregroundStyle(.white.opacity(0.7))
        .lineLimit(1)
    }

    @ViewBuilder private func technicalMetadataContent(ratings: [MergedRating], showBadges: Bool) -> some View {
        HStack(spacing: DS.Space.s10) {
            // Year and Edition
            if let year = vm.year, !year.isEmpty {
                if let edition = vm.editionTitle, !edition.isEmpty {
                    Text("\(year) · \(edition)")
                } else {
                    Text(year)
                }
            } else if let edition = vm.editionTitle, !edition.isEmpty {
                Text(edition)
            }

            // Runtime
            if let runtime = formattedRuntime(vm.runtime) {
                Text("·").foregroundStyle(.white.opacity(0.5))
                Text(runtime)
            }

            // Ratings right after year and length (Apple TV order), then
            // badges. Which ratings, and the source of each, are chosen in
            // Settings → Details (RatingPreferencesStore / RatingsMerger).
            ForEach(ratings) { rating in
                MergedRatingView(rating: rating)
            }

            if showBadges {
                technicalBadges
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder private var technicalBadges: some View {
        // Resolution badge from technical details (4K, HD, 720p)
        if let resBadge = resolutionBadge {
            TechnicalBadge(text: resBadge, isHighlighted: false)
        }

        // HDR/DV badge from technical details
        if let hdr = hdrBadge {
            TechnicalBadge(text: hdr, isHighlighted: true)
        }

        // Technical badges from vm.badges (Atmos, etc.)
        // Filter out resolution, HDR, Plex, and "No local source" - those are shown separately
        ForEach(vm.badges.filter { badge in
            let lower = badge.lowercased()
            return lower != "plex" &&
                   !lower.contains("no local") &&
                   !lower.contains("4k") &&
                   !lower.contains("hd") &&
                   !lower.contains("1080") &&
                   !lower.contains("720") &&
                   !lower.contains("hdr") &&
                   !lower.contains("dolby vision") &&
                   lower != "dv"
        }, id: \.self) { badge in
            TechnicalBadge(text: badge, isHighlighted: false)
        }
    }

    // MARK: - Ratings Row
    @ViewBuilder private var ratingsRow: some View {
        let hasExternalRatings = vm.externalRatings.map(hasRatings) ?? false
        let hasMdbRatings = vm.mdblistRatings?.hasAnyRating ?? false

        if hasExternalRatings || hasMdbRatings {
            HStack(spacing: DS.Space.s12) {
                if let ratings = vm.externalRatings, hasRatings(ratings) {
                    RatingsStrip(ratings: ratings)
                }
                if let mdbRatings = vm.mdblistRatings, mdbRatings.hasAnyRating {
                    RatingsDisplay(ratings: mdbRatings)
                }
            }
        }
    }

    // MARK: - Trailers Section
    @ViewBuilder private var trailersSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            Text("Trailers & Videos").textCase(.uppercase)
                .font(.flixor(.caption, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(theme.textTertiary)

            // A horizontal ScrollView takes every bit of height it is offered, which
            // inside this bottom-aligned column left a large gap above the cards.
            // Pin it to the card height (plus room for the hover shadow).
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: DS.Space.s10) {
                    ForEach(trailers.prefix(5)) { trailer in
                        HeroTrailerCard(
                            trailer: trailer,
                            width: Self.trailerCardWidth,
                            onPlay: { selectedTrailer = trailer }
                        )
                    }
                }
                .padding(.vertical, Self.trailerRowShadowInset)
            }
            .frame(height: Self.trailerCardWidth * DS.Layout.landscapeAspect + Self.trailerRowShadowInset * 2)
        }
    }

    static let trailerCardWidth: CGFloat = 160
    static let trailerRowShadowInset: CGFloat = DS.Space.s8

    // MARK: - Credits Section (Right Column)
    @ViewBuilder private var creditsSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if !vm.castShort.isEmpty {
                creditLine(String(localized: "Starring"), vm.castShort.prefix(3).map { $0.name }.joined(separator: ", "))
            }
            if !vm.directors.isEmpty {
                creditLine(vm.directors.count > 1 ? String(localized: "Directors") : String(localized: "Director"),
                           vm.directors.prefix(2).joined(separator: ", "))
            }
            if vm.mediaKind == "tv", !vm.creators.isEmpty {
                creditLine(vm.creators.count > 1 ? String(localized: "Creators") : String(localized: "Creator"),
                           vm.creators.prefix(2).joined(separator: ", "))
            }
        }
        .font(.flixor(.footnote, weight: .medium))
        .shadow(color: .black.opacity(0.6), radius: 6)
        .padding(.bottom, DS.Space.s4)
    }

    /// "Starring Tom Holland, Zendaya": grey label, white names, wrapping as one paragraph.
    private func creditLine(_ label: String, _ names: String) -> some View {
        (Text(label + " ").foregroundColor(.white.opacity(0.55)) + Text(names).foregroundColor(.white.opacity(0.92)))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var castSummary: String {
        if vm.cast.isEmpty { return "—" }
        let names = vm.castShort.map { $0.name }
        let summary = names.joined(separator: ", ")
        if vm.castMoreCount > 0 {
            return String(localized: "\(summary) +\(vm.castMoreCount) more")
        }
        return summary
    }

    @ViewBuilder
    private func heroFactBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            Text(title.uppercased())
                .font(.flixor(.footnote, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.72))
            Text(value)
                .font(.flixor(.callout))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(2)
        }
    }

    private var width: CGFloat { layout.width }

    private var titleFontSize: CGFloat {
        if width < 820 { return 36 }
        if width < 1100 { return 42 }
        return 48
    }

    private var logoWidth: CGFloat {
        if width < 900 { return 240 }
        if width < 1300 { return 290 }
        return 340
    }

    /// Tall logos (stacked titles) stay compact too.
    private var logoMaxHeight: CGFloat {
        if width < 900 { return 90 }
        if width < 1300 { return 110 }
        return 130
    }

    // Content column max width for two-column layout
    private var contentColumnMaxWidth: CGFloat {
        if width < 900 { return .infinity }
        if width < 1200 { return 480 }
        return 520
    }

    // Credits column width for right side
    private var creditsColumnWidth: CGFloat {
        if width < 900 { return 220 }
        if width < 1200 { return 260 }
        return 300
    }
}

/// Sizes the logo to its fitted size inside a max box, so a wide, short logo
/// takes only its own height (a plain max frame keeps the full box height,
/// leaving a gap above the logo).
private struct FittedLogoLayout: Layout {
    let maxWidth: CGFloat
    let maxHeight: CGFloat

    private func box(_ proposal: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(width: min(proposal.width ?? maxWidth, maxWidth), height: maxHeight)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(box(proposal)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
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
                VStack(alignment: .leading, spacing: DS.Space.s4) {
                    Spacer()

                    if let label = trailer.typeLabel {
                        TrailerTypeLabel(text: label, compact: true)
                    }

                    // Title
                    Text(trailer.name)
                        .font(.flixor(.callout, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(DS.Space.s10)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.r10, style: .continuous)
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

}
