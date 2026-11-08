//
//  HeroCarousel.swift
//  FlixorMac
//
//  Elegant carousel-style hero component with auto-advancement and looping
//

import SwiftUI

struct HeroCarousel: View {
    let items: [MediaItem]
    @Binding var currentIndex: Int
    var onPlay: ((MediaItem) -> Void)?
    var onInfo: ((MediaItem) -> Void)?
    var onMyList: ((MediaItem) -> Void)?
    var autoAdvanceInterval: TimeInterval = 8.0

    @ObservedObject private var profileSettings = ProfileSettings.shared
    @State private var isHovered = false
    @State private var timer: Timer?
    @State private var direction: TransitionDirection = .forward

    @Environment(\.windowMetrics) private var metrics

    /// Follows the window (see HomeHeroMetrics.swift) instead of a fixed 580 pt.
    private var carouselHeight: CGFloat { metrics.homeCarouselHeight }

    private enum TransitionDirection {
        case forward, backward
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background with blur for smooth transitions
                Color.black

                // Current Card
                if !items.isEmpty && currentIndex < items.count {
                    let item = items[currentIndex]
                    HeroCarouselCard(
                        item: item,
                        width: geometry.size.width,
                        height: carouselHeight,
                        onPlay: { onPlay?(item) },
                        onInfo: { onInfo?(item) },
                        onMyList: { onMyList?(item) }
                    )
                    .id(item.id)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 1.02)),
                            removal: .opacity.combined(with: .scale(scale: 0.98))
                        )
                    )
                }

                // Navigation Overlays
                VStack {
                    Spacer()

                    // Bottom controls
                    HStack(alignment: .bottom) {
                        // Left arrow (shown on hover)
                        Button(action: previousItem) {
                            Image(systemName: "chevron.left")
                                .font(.flixorIcon(DS.Icon.xl, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 48, height: 48)
                                .background(.ultraThinMaterial.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .opacity(isHovered && items.count > 1 ? 1 : 0)
                        .accessibilityLabel(Text("Previous featured item"))

                        Spacer()

                        // Page indicators
                        if items.count > 1 {
                            HeroPageIndicator(
                                count: items.count,
                                currentIndex: currentIndex,
                                style: .bars,
                                onSelect: { goToIndex($0) }
                            )
                        }

                        Spacer()

                        // Right arrow (shown on hover)
                        Button(action: nextItem) {
                            Image(systemName: "chevron.right")
                                .font(.flixorIcon(DS.Icon.xl, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 48, height: 48)
                                .background(.ultraThinMaterial.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .opacity(isHovered && items.count > 1 ? 1 : 0)
                        .accessibilityLabel(Text("Next featured item"))
                    }
                    .padding(.horizontal, DS.Space.s40)
                    .padding(.bottom, DS.Space.s28)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.r20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 30, y: 15)
        }
        .frame(height: carouselHeight)
        .onHover { hovering in
            withAnimation(DS.Motion.standard) {
                isHovered = hovering
            }
            // Pause/resume auto-advance on hover (only if auto-rotate is enabled)
            if profileSettings.heroAutoRotate {
                if hovering {
                    stopTimer()
                } else {
                    startTimer()
                }
            }
        }
        .animation(DS.Motion.slow, value: currentIndex)
        .onAppear {
            if profileSettings.heroAutoRotate {
                startTimer()
            }
        }
        .onDisappear {
            stopTimer()
        }
        .onChange(of: profileSettings.heroAutoRotate) { newValue in
            if newValue {
                startTimer()
            } else {
                stopTimer()
            }
        }
    }

    // MARK: - Navigation

    private func previousItem() {
        direction = .backward
        withAnimation(DS.Motion.slow) {
            if currentIndex > 0 {
                currentIndex -= 1
            } else {
                // Loop to end
                currentIndex = items.count - 1
            }
        }
        restartTimer()
    }

    private func nextItem() {
        direction = .forward
        withAnimation(DS.Motion.slow) {
            if currentIndex < items.count - 1 {
                currentIndex += 1
            } else {
                // Loop to start
                currentIndex = 0
            }
        }
        restartTimer()
    }

    private func goToIndex(_ index: Int) {
        direction = index > currentIndex ? .forward : .backward
        withAnimation(DS.Motion.slow) {
            currentIndex = index
        }
        restartTimer()
    }

    // MARK: - Auto-Advance Timer

    private func startTimer() {
        guard items.count > 1 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: autoAdvanceInterval, repeats: true) { _ in
            Task { @MainActor in
                nextItem()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func restartTimer() {
        stopTimer()
        if profileSettings.heroAutoRotate {
            startTimer()
        }
    }
}

// MARK: - Individual Carousel Card

struct HeroCarouselCard: View {
    let item: MediaItem
    let width: CGFloat
    let height: CGFloat
    var onPlay: (() -> Void)?
    var onInfo: (() -> Void)?
    var onMyList: (() -> Void)?

    @Environment(\.windowMetrics) private var metrics
    @State private var backdropURL: URL?
    @State private var logoURL: URL?
    @State private var seriesData: SeriesMetadata?

    private var isCompact: Bool { metrics.isCompactHero(height: height) }

    // Data structure for fetched series metadata
    private struct SeriesMetadata {
        let title: String
        let summary: String?
        let year: Int?
    }

    // Check if this is an episode or season that should show series data
    private var isEpisode: Bool { item.type == "episode" }
    private var isSeason: Bool { item.type == "season" }
    private var isEpisodeOrSeason: Bool { isEpisode || isSeason }

    // Get the series rating key - different for episodes vs seasons
    private var seriesRatingKey: String? {
        if isEpisode {
            return item.grandparentRatingKey
        } else if isSeason {
            return item.parentRatingKey
        }
        return nil
    }

    // Get fallback series title - different for episodes vs seasons
    private var fallbackSeriesTitle: String? {
        if isEpisode {
            return item.grandparentTitle
        } else if isSeason {
            return item.parentTitle ?? item.grandparentTitle
        }
        return nil
    }

    // Display title - use series title for episodes/seasons
    private var displayTitle: String {
        if isEpisodeOrSeason {
            return seriesData?.title ?? fallbackSeriesTitle ?? item.title
        }
        return item.title
    }

    // Display summary - use series summary for episodes/seasons
    private var displaySummary: String? {
        if isEpisodeOrSeason {
            return seriesData?.summary ?? item.summary
        }
        return item.summary
    }

    // Display year - use series year for episodes/seasons
    private var displayYear: Int? {
        if isEpisodeOrSeason {
            return seriesData?.year ?? item.year
        }
        return item.year
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Background Image with Ken Burns effect
            CachedAsyncImage(
                url: backdropURL ?? ImageService.shared.artURL(
                    for: item,
                    width: Int(width * 2),
                    height: Int(height * 2)
                )
            )
            .aspectRatio(contentMode: .fill)
            .frame(width: width, height: height)
            .clipped()
            .background(Color.black)

            // Gradient Overlays
            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.0), location: 0.0),
                    .init(color: Color.black.opacity(0.2), location: 0.4),
                    .init(color: Color.black.opacity(0.7), location: 0.7),
                    .init(color: Color.black.opacity(0.95), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.8), location: 0.0),
                    .init(color: Color.black.opacity(0.4), location: 0.3),
                    .init(color: Color.black.opacity(0.0), location: 0.6)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            // Content
            VStack(alignment: .leading, spacing: isCompact ? DS.Space.s12 : DS.Space.s18) {
                Spacer(minLength: 0)

                // Logo or Title
                if let logo = logoURL {
                    CachedAsyncImage(url: logo, aspectRatio: nil, contentMode: .fit)
                        .frame(maxWidth: isCompact ? 340 : 420, maxHeight: min(140, height * 0.24))
                        .shadow(color: .black.opacity(0.7), radius: 16)
                } else {
                    Text(displayTitle)
                        .font(.flixor(isCompact ? .display : .displayLarge, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.7), radius: 16)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }

                // Metadata Row
                HStack(spacing: DS.Space.s12) {
                    if let year = displayYear {
                        Text(String(year))
                            .font(.flixor(.bodyLarge, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                    }

                    if let rating = item.rating {
                        HStack(spacing: 5) {
                            Image(systemName: "star.fill")
                                .font(.flixorIcon(DS.Icon.xs))
                            Text(String(format: "%.1f", rating))
                                .font(.flixor(.body, weight: .semibold))
                        }
                        .foregroundStyle(.yellow)
                    }

                    if let duration = item.duration {
                        Text(formatDuration(duration))
                            .font(.flixor(.bodyLarge, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                    }

                    // Type badge - always show "Series" for episodes/seasons
                    Text(item.type == "movie" ? "Movie" : "Series")
                        .font(.flixor(.footnote, weight: .semibold))
                        .padding(.horizontal, DS.Space.s8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r4))
                }

                // Summary/Overview
                if let summary = displaySummary, !summary.isEmpty {
                    Text(summary)
                        .font(.flixor(.bodyLarge))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(isCompact ? 2 : 3)
                        .frame(maxWidth: 520, alignment: .leading)
                        .lineSpacing(3)
                }

                // Action Buttons
                HStack(spacing: DS.Space.s14) {
                    // Play Button
                    Button(action: { onPlay?() }) {
                        HStack(spacing: DS.Space.s8) {
                            Image(systemName: "play.fill")
                                .font(.flixorIcon(DS.Icon.md))
                            Text("Play")
                                .font(.flixor(.headline, weight: .semibold))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, DS.Space.s28)
                        .padding(.vertical, DS.Space.s14)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)

                    // More Info Button
                    Button(action: { onInfo?() }) {
                        HStack(spacing: DS.Space.s8) {
                            Image(systemName: "info.circle")
                                .font(.flixorIcon(DS.Icon.md))
                            Text("More Info")
                                .font(.flixor(.headline, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, DS.Space.s24)
                        .padding(.vertical, DS.Space.s14)
                        .background(.ultraThinMaterial.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.r8, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    // My List Button
                    Button(action: { onMyList?() }) {
                        Image(systemName: "plus")
                            .font(.flixor(.title3, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .background(.ultraThinMaterial.opacity(0.5))
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, DS.Space.s6)
            }
            .padding(.horizontal, isCompact ? DS.Space.s40 : 56)
            .padding(.bottom, isCompact ? DS.Space.s60 : 72)
        }
        .task {
            await loadImages()
        }
    }

    private func formatDuration(_ milliseconds: Int) -> String {
        let minutes = milliseconds / 60000
        let hours = minutes / 60
        let mins = minutes % 60

        if hours > 0 {
            return String(localized: "\(hours)h \(mins)m")
        } else {
            return String(localized: "\(minutes)m")
        }
    }

    private func loadImages() async {
        // For episodes/seasons, fetch series data first
        if isEpisodeOrSeason {
            await loadSeriesData()
        }

        // Use series rating key for cache if available
        let cacheKey = isEpisodeOrSeason && seriesRatingKey != nil
            ? "series:\(seriesRatingKey!)"
            : item.id

        // Check cache first
        if let cached = BillboardImageCache.shared.get(itemId: cacheKey) {
            await MainActor.run {
                self.backdropURL = cached.0
                self.logoURL = cached.1
            }
            return
        }

        // Parse the item ID to get TMDB info
        do {
            if let (backdrop, logo) = try await resolveTMDBImages() {
                await MainActor.run {
                    self.backdropURL = backdrop
                    self.logoURL = logo
                    BillboardImageCache.shared.set(itemId: cacheKey, backdrop: backdrop, logo: logo)
                }
            }
        } catch {
            // Silent fallback - cache empty result
            BillboardImageCache.shared.set(itemId: cacheKey, backdrop: nil, logo: nil)
        }
    }

    private func loadSeriesData() async {
        guard let seriesKey = seriesRatingKey else { return }

        do {
            struct PlexMeta: Codable {
                let title: String?
                let summary: String?
                let year: Int?
            }
            let meta: PlexMeta = try await APIClient.shared.get("/api/plex/metadata/\(seriesKey)")
            await MainActor.run {
                self.seriesData = SeriesMetadata(
                    title: meta.title ?? fallbackSeriesTitle ?? item.title,
                    summary: meta.summary,
                    year: meta.year
                )
            }
        } catch {
            // Silent fallback - use fallback title
            await MainActor.run {
                self.seriesData = SeriesMetadata(
                    title: fallbackSeriesTitle ?? item.title,
                    summary: nil,
                    year: nil
                )
            }
        }
    }

    private func resolveTMDBImages() async throws -> (URL?, URL?)? {
        // For episodes/seasons, use seriesRatingKey to get series images
        if isEpisodeOrSeason, let seriesKey = seriesRatingKey {
            struct PlexMeta: Codable { let type: String?; let Guid: [PlexGuid]? }
            struct PlexGuid: Codable { let id: String? }
            let meta: PlexMeta = try await APIClient.shared.get("/api/plex/metadata/\(seriesKey)")
            if let guid = meta.Guid?.compactMap({ $0.id }).first(where: { $0.contains("tmdb://") || $0.contains("themoviedb://") }),
               let tid = guid.components(separatedBy: "://").last {
                return try await fetchTMDBImages(mediaType: "tv", id: tid)
            }
            return nil
        }

        // Handle tmdb:movie:123 or tmdb:tv:123 format
        if item.id.hasPrefix("tmdb:") {
            let parts = item.id.split(separator: ":")
            if parts.count == 3 {
                let mediaType = (parts[1] == "movie") ? "movie" : "tv"
                let id = String(parts[2])
                return try await fetchTMDBImages(mediaType: mediaType, id: id)
            }
            return nil
        }

        // Handle plex:123 format - need to get TMDB ID from Plex metadata
        if item.id.hasPrefix("plex:") {
            let rk = String(item.id.dropFirst(5))
            struct PlexMeta: Codable { let type: String?; let Guid: [PlexGuid]? }
            struct PlexGuid: Codable { let id: String? }
            let meta: PlexMeta = try await APIClient.shared.get("/api/plex/metadata/\(rk)")
            let mediaType = (meta.type == "movie") ? "movie" : "tv"
            if let guid = meta.Guid?.compactMap({ $0.id }).first(where: { $0.contains("tmdb://") || $0.contains("themoviedb://") }),
               let tid = guid.components(separatedBy: "://").last {
                return try await fetchTMDBImages(mediaType: mediaType, id: tid)
            }
        }

        // Handle raw numeric Plex IDs
        if item.id.allSatisfy({ $0.isNumber }) {
            struct PlexMeta: Codable { let type: String?; let Guid: [PlexGuid]? }
            struct PlexGuid: Codable { let id: String? }
            let meta: PlexMeta = try await APIClient.shared.get("/api/plex/metadata/\(item.id)")
            let mediaType = (meta.type == "movie") ? "movie" : "tv"
            if let guid = meta.Guid?.compactMap({ $0.id }).first(where: { $0.contains("tmdb://") || $0.contains("themoviedb://") }),
               let tid = guid.components(separatedBy: "://").last {
                return try await fetchTMDBImages(mediaType: mediaType, id: tid)
            }
        }

        return nil
    }

    private func fetchTMDBImages(mediaType: String, id: String) async throws -> (URL?, URL?) {
        struct TMDBImages: Codable { let backdrops: [TMDBImage]?; let logos: [TMDBImage]? }
        struct TMDBImage: Codable { let file_path: String?; let iso_639_1: String?; let vote_average: Double? }

        let imgs: TMDBImages = try await APIClient.shared.get(
            "/api/tmdb/\(mediaType)/\(id)/images",
            queryItems: [URLQueryItem(name: "language", value: "en,hi,null")]
        )

        // Pick best backdrop - prefer textless (null language) for hero since we overlay title/logo
        let backs = imgs.backdrops ?? []
        func pickBest(_ arr: [TMDBImage]) -> TMDBImage? {
            arr.sorted { ($0.vote_average ?? 0) > ($1.vote_average ?? 0) }.first
        }
        // Priority: textless (null) first, then any
        let selectedBackdrop = pickBest(backs.filter { $0.iso_639_1 == nil })
            ?? pickBest(backs)

        // Pick best logo - prefer English
        let logos = imgs.logos ?? []
        let englishLogos = logos.filter { $0.iso_639_1 == "en" }
        let selectedLogo = englishLogos.first ?? logos.first

        let backdropURL: URL? = {
            guard let path = selectedBackdrop?.file_path else { return nil }
            return URL(string: "https://image.tmdb.org/t/p/original\(path)")
        }()

        let logoURL: URL? = {
            guard let path = selectedLogo?.file_path else { return nil }
            return URL(string: "https://image.tmdb.org/t/p/w500\(path)")
        }()

        return (backdropURL, logoURL)
    }
}
