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

    @AppStorage("heroAutoRotate") private var heroAutoRotate: Bool = true
    @State private var isHovered = false
    @State private var timer: Timer?
    @State private var direction: TransitionDirection = .forward

    private let carouselHeight: CGFloat = 580

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
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 48, height: 48)
                                .background(.ultraThinMaterial.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .opacity(isHovered && items.count > 1 ? 1 : 0)

                        Spacer()

                        // Page indicators
                        if items.count > 1 {
                            HStack(spacing: 6) {
                                ForEach(0..<items.count, id: \.self) { index in
                                    Button(action: { goToIndex(index) }) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(index == currentIndex ? Color.white : Color.white.opacity(0.4))
                                            .frame(width: index == currentIndex ? 28 : 8, height: 4)
                                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentIndex)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial.opacity(0.4))
                            .clipShape(Capsule())
                        }

                        Spacer()

                        // Right arrow (shown on hover)
                        Button(action: nextItem) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 48, height: 48)
                                .background(.ultraThinMaterial.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .opacity(isHovered && items.count > 1 ? 1 : 0)
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 28)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 30, y: 15)
        }
        .frame(height: carouselHeight)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
            // Pause/resume auto-advance on hover (only if auto-rotate is enabled)
            if heroAutoRotate {
                if hovering {
                    stopTimer()
                } else {
                    startTimer()
                }
            }
        }
        .animation(.easeInOut(duration: 0.5), value: currentIndex)
        .onAppear {
            if heroAutoRotate {
                startTimer()
            }
        }
        .onDisappear {
            stopTimer()
        }
        .onChange(of: heroAutoRotate) { newValue in
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
        withAnimation(.easeInOut(duration: 0.5)) {
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
        withAnimation(.easeInOut(duration: 0.5)) {
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
        withAnimation(.easeInOut(duration: 0.5)) {
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
        if heroAutoRotate {
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

    @State private var backdropURL: URL?
    @State private var logoURL: URL?
    @State private var seriesData: SeriesMetadata?

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
            VStack(alignment: .leading, spacing: 18) {
                Spacer()

                // Logo or Title
                if let logo = logoURL {
                    CachedAsyncImage(url: logo, aspectRatio: nil, contentMode: .fit)
                        .frame(maxWidth: 420, maxHeight: 140)
                        .shadow(color: .black.opacity(0.7), radius: 16)
                } else {
                    Text(displayTitle)
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.7), radius: 16)
                        .lineLimit(2)
                }

                // Metadata Row
                HStack(spacing: 12) {
                    if let year = displayYear {
                        Text(String(year))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                    }

                    if let rating = item.rating {
                        HStack(spacing: 5) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 12))
                            Text(String(format: "%.1f", rating))
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(.yellow)
                    }

                    if let duration = item.duration {
                        Text(formatDuration(duration))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                    }

                    // Type badge - always show "Series" for episodes/seasons
                    Text(item.type == "movie" ? "Movie" : "Series")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                // Summary/Overview
                if let summary = displaySummary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(3)
                        .frame(maxWidth: 520, alignment: .leading)
                        .lineSpacing(3)
                }

                // Action Buttons
                HStack(spacing: 14) {
                    // Play Button
                    Button(action: { onPlay?() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 16))
                            Text("Play")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)

                    // More Info Button
                    Button(action: { onInfo?() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 16))
                            Text("More Info")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(.ultraThinMaterial.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    // My List Button
                    Button(action: { onMyList?() }) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .medium))
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
                .padding(.top, 6)
            }
            .padding(.horizontal, 56)
            .padding(.bottom, 72)
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
            return "\(hours)h \(mins)m"
        } else {
            return "\(minutes)m"
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

        // Pick best backdrop
        let backs = imgs.backdrops ?? []
        let sortedBackdrops = backs.sorted { ($0.vote_average ?? 0) > ($1.vote_average ?? 0) }
        let selectedBackdrop = sortedBackdrops.first

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
