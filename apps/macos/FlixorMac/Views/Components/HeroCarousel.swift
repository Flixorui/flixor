//
//  HeroCarousel.swift
//  FlixorMac
//
//  Full-bleed carousel hero: artwork to the window edges, logo, genres, summary
//  and a View Details button, with page dots and a full screen button.
//

import AppKit
import FlixorKit
import SwiftUI

private enum HeroCarouselMetrics {
    static let backgroundParallax: CGFloat = 0.055
    static let contentParallax: CGFloat = 0.18
    static let scrollParallax: CGFloat = 0.38
    static let scrollDownScale: CGFloat = 0.0001
    static let scrollUpScale: CGFloat = 0.002
    static let maxScrollScale: CGFloat = 1.3
    static let swipeThreshold: CGFloat = 0.16
    static let topFadeHeight: CGFloat = 160
    static let bottomFadeHeight: CGFloat = 300
    static let contentWidthFraction: CGFloat = 0.58
    static let contentMaxWidth: CGFloat = 760
    static let logoWidthFraction: CGFloat = 0.74
    static let logoHeight: CGFloat = 120
    static let contentBottom: CGFloat = 40
    static let pageAnimation = Animation.easeInOut(duration: 0.5)
}

private extension VerticalAlignment {
    /// Crops artwork from the bottom more than the top, keeping faces in frame.
    private enum HeroBackdrop: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d.height * 0.2 }
    }
    static let heroBackdrop = VerticalAlignment(HeroBackdrop.self)
}

// MARK: - Scroll position

/// Home's scroll offset for the artwork parallax, watched only by the artwork.
@MainActor
final class HomeHeroScrollOffset: ObservableObject {
    static let shared = HomeHeroScrollOffset()

    @Published private(set) var value: CGFloat = 0

    func update(_ offset: CGFloat) {
        let clamped = min(offset, 800).rounded()
        if clamped != value { value = clamped }
    }
}

// MARK: - Carousel

struct HeroCarousel: View {
    let items: [MediaItem]
    @Binding var currentIndex: Int
    var onInfo: ((MediaItem) -> Void)?
    /// A manual page change, so automatic rotation can restart its wait.
    var onUserNavigate: (() -> Void)?

    @Environment(\.windowMetrics) private var metrics
    @Environment(\.flixorTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isGoingForward = true
    @State private var dragTranslation: CGFloat = 0

    private var height: CGFloat { metrics.homeCarouselHeight }

    private var currentItem: MediaItem? {
        items.indices.contains(currentIndex) ? items[currentIndex] : items.first
    }

    var body: some View {
        GeometryReader { geo in
            let size = CGSize(width: geo.size.width, height: height)

            ZStack(alignment: .bottomLeading) {
                theme.background

                if let item = currentItem {
                    HeroCarouselBackdrop(item: item, size: size)
                        .id(item.id)
                        .transition(pageTransition(parallax: size.width * HeroCarouselMetrics.backgroundParallax))
                }

                fades

                if let item = currentItem {
                    HeroCarouselContent(item: item, onInfo: { onInfo?(item) })
                        .id(item.id)
                        .transition(pageTransition(parallax: size.width * HeroCarouselMetrics.contentParallax))
                        .padding(.leading, DetailsSectionStyle.inset)
                        .padding(.trailing, DS.Space.s32)
                        .padding(.bottom, HeroCarouselMetrics.contentBottom)
                        .frame(
                            width: min(size.width * HeroCarouselMetrics.contentWidthFraction, HeroCarouselMetrics.contentMaxWidth),
                            alignment: .bottomLeading
                        )
                }

                if items.count > 1 {
                    HeroCarouselPageDots(
                        count: items.count,
                        currentIndex: currentIndex,
                        onSelect: { go(to: $0) }
                    )
                    .padding(.trailing, DetailsSectionStyle.inset)
                    .padding(.bottom, DS.Space.s40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(swipe(width: size.width))
        }
        .frame(height: height)
        .animation(reduceMotion ? nil : HeroCarouselMetrics.pageAnimation, value: currentIndex)
        .task(id: currentIndex) { await prefetchNext() }
    }

    private var fades: some View {
        ZStack {
            // Top, behind the navigation bar
            LinearGradient(
                colors: [theme.background.opacity(0.82), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: HeroCarouselMetrics.topFadeHeight)
            .frame(maxHeight: .infinity, alignment: .top)

            // Left, behind the text
            LinearGradient(
                stops: [
                    .init(color: theme.background.opacity(0.96), location: 0),
                    .init(color: theme.background.opacity(0.90), location: 0.08),
                    .init(color: theme.background.opacity(0.76), location: 0.16),
                    .init(color: theme.background.opacity(0.54), location: 0.26),
                    .init(color: theme.background.opacity(0.30), location: 0.36),
                    .init(color: theme.background.opacity(0.12), location: 0.46),
                    .init(color: .clear, location: 0.54),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            // Bottom, into the page
            LinearGradient(
                colors: [theme.background.opacity(0), theme.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: HeroCarouselMetrics.bottomFadeHeight)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .allowsHitTesting(false)
    }

    private func pageTransition(parallax: CGFloat) -> AnyTransition {
        let incoming = isGoingForward ? parallax : -parallax
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: incoming)),
            removal: .opacity.combined(with: .offset(x: -incoming))
        )
    }

    private func swipe(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard items.count > 1,
                      abs(value.translation.width) > abs(value.translation.height),
                      abs(value.translation.width) > width * HeroCarouselMetrics.swipeThreshold else { return }
                let step = value.translation.width < 0 ? 1 : -1
                go(to: (currentIndex + step + items.count) % items.count, forward: step > 0)
            }
    }

    private func go(to index: Int, forward: Bool? = nil) {
        guard index != currentIndex else { return }
        isGoingForward = forward ?? (index > currentIndex)
        currentIndex = index
        onUserNavigate?()
    }

    /// Loads the next page ahead of time so it doesn't flash in empty.
    private func prefetchNext() async {
        guard items.count > 1, items.indices.contains(currentIndex) else { return }
        let next = items[(currentIndex + 1) % items.count]
        let metadata = await HeroCarouselMetadataStore.shared.metadata(for: next)
        guard let url = metadata.backdropURL, ImageCache.shared.get(url: url) == nil,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = NSImage(data: data) else { return }
        ImageCache.shared.set(image: image, url: url)
    }
}

// MARK: - Artwork

private struct HeroCarouselBackdrop: View {
    let item: MediaItem
    let size: CGSize

    @ObservedObject private var scroll = HomeHeroScrollOffset.shared
    @Environment(\.flixorTheme) private var theme
    @State private var metadata: HeroCarouselMetadata?

    private var imageURL: URL? {
        metadata?.backdropURL ?? ImageService.shared.artURL(
            for: item,
            width: Int(size.width * 2),
            height: Int(size.height * 2)
        )
    }

    private var scale: CGFloat {
        let increase = scroll.value < 0
            ? -scroll.value * HeroCarouselMetrics.scrollUpScale
            : scroll.value * HeroCarouselMetrics.scrollDownScale
        return min(1 + increase, HeroCarouselMetrics.maxScrollScale)
    }

    var body: some View {
        Group {
            if metadata != nil {
                CachedAsyncImage(url: imageURL, contentMode: .fill) {
                    theme.background
                }
            } else {
                theme.background
            }
        }
        .frame(
            width: size.width,
            height: size.height,
            alignment: Alignment(horizontal: .center, vertical: .heroBackdrop)
        )
        .clipped()
        .scaleEffect(scale)
        .offset(y: scroll.value * HeroCarouselMetrics.scrollParallax)
        .accessibilityHidden(true)
        .task {
            metadata = await HeroCarouselMetadataStore.shared.metadata(for: item)
        }
    }
}

// MARK: - Text

private struct HeroCarouselContent: View {
    let item: MediaItem
    let onInfo: () -> Void

    @Environment(\.flixorTheme) private var theme
    @State private var metadata: HeroCarouselMetadata?

    private var displayTitle: String { metadata?.title ?? item.title }

    private var metaLine: String {
        let genres = metadata?.genres ?? []
        if !genres.isEmpty { return genres.joined(separator: " • ") }
        return item.type == "movie" ? String(localized: "Movie") : String(localized: "Series")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            title

            Text(verbatim: metaLine)
                .font(.flixor(.callout, weight: .medium))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
                .padding(.top, DS.Space.s12)

            if let summary = metadata?.summary, !summary.isEmpty {
                Text(verbatim: summary)
                    .font(.flixor(.bodyLarge))
                    .lineSpacing(3)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(4)
                    .padding(.top, DS.Space.s16)
            }

            Button(action: onInfo) {
                Text("View Details")
                    .font(.flixor(.callout, weight: .bold))
                    .foregroundStyle(theme.background)
                    .padding(.horizontal, DS.Space.s24)
                    .frame(height: 48)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: DS.Space.s40, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: DS.Space.s40, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, DS.Space.s24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onInfo)
        .task {
            metadata = await HeroCarouselMetadataStore.shared.metadata(for: item)
        }
    }

    @ViewBuilder private var title: some View {
        if let logo = metadata?.logoURL {
            GeometryReader { geo in
                CachedAsyncImage(url: logo, contentMode: .fit) { Color.clear }
                    .frame(
                        width: geo.size.width * HeroCarouselMetrics.logoWidthFraction,
                        height: geo.size.height,
                        alignment: .leading
                    )
            }
            .frame(height: HeroCarouselMetrics.logoHeight)
            .accessibilityLabel(Text(verbatim: displayTitle))
        } else if metadata != nil {
            Text(verbatim: displayTitle)
                .font(.flixor(.displayLarge, weight: .heavy))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Color.clear.frame(height: HeroCarouselMetrics.logoHeight)
        }
    }
}

// MARK: - Controls

private struct HeroCarouselPageDots: View {
    let count: Int
    let currentIndex: Int
    let onSelect: (Int) -> Void

    @Environment(\.flixorTheme) private var theme

    var body: some View {
        HStack(spacing: DS.Space.s8) {
            ForEach(0..<count, id: \.self) { index in
                let isActive = index == currentIndex
                Button { onSelect(index) } label: {
                    Capsule(style: .continuous)
                        .fill(theme.textPrimary.opacity(isActive ? 0.92 : 0.35))
                        .frame(width: isActive ? 32 : 8, height: 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Show item \(index + 1) of \(count)"))
                .accessibilityAddTraits(isActive ? .isSelected : [])
            }
        }
    }
}

/// Level with the navigation bar. Pinned to the window rather than the hero, so
/// scrolling can't push it into the top edge; it fades out once Home has scrolled.
struct HeroCarouselFullScreenOverlay: View {
    @ObservedObject private var scroll = TabScrollState.shared

    private var isVisible: Bool { !scroll.scrolledTabs.contains(.home) }

    var body: some View {
        HeroCarouselFullScreenButton()
            .padding(.top, FloatingNavMetrics.topPadding)
            .padding(.trailing, DetailsSectionStyle.inset)
            .opacity(isVisible ? 1 : 0)
            .allowsHitTesting(isVisible)
            .animation(DS.Motion.standard, value: isVisible)
    }
}

private struct HeroCarouselFullScreenButton: View {
    @Environment(\.flixorTheme) private var theme
    @State private var isFullScreen = false

    private var label: String {
        isFullScreen ? String(localized: "Exit Full Screen") : String(localized: "Full Screen")
    }

    var body: some View {
        Button {
            (NSApp.keyWindow ?? NSApp.mainWindow)?.toggleFullScreen(nil)
        } label: {
            Image(systemName: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "viewfinder")
                .font(.flixorIcon(DS.Icon.xl, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .frame(width: 48, height: 48)
                .background(theme.surfaceElevated.opacity(0.82), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(Text(verbatim: label))
        .onAppear { isFullScreen = NSApp.mainWindow?.styleMask.contains(.fullScreen) == true }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            isFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            isFullScreen = false
        }
    }
}

// MARK: - Metadata

struct HeroCarouselMetadata {
    var backdropURL: URL?
    var logoURL: URL?
    var title: String
    var summary: String?
    var genres: [String]
}

/// Artwork, title and genres per item, loaded once and shared by the page layers.
@MainActor
final class HeroCarouselMetadataStore {
    static let shared = HeroCarouselMetadataStore()

    private var cache: [String: HeroCarouselMetadata] = [:]
    private var inFlight: [String: Task<HeroCarouselMetadata, Never>] = [:]

    func metadata(for item: MediaItem) async -> HeroCarouselMetadata {
        if let cached = cache[item.id] { return cached }
        if let task = inFlight[item.id] { return await task.value }

        let task = Task { await Self.load(item) }
        inFlight[item.id] = task
        let result = await task.value
        inFlight[item.id] = nil
        cache[item.id] = result
        return result
    }

    private struct PlexMeta: Codable {
        struct PlexGuid: Codable { let id: String? }
        let type: String?
        let title: String?
        let summary: String?
        let Guid: [PlexGuid]?
    }

    private struct TMDBReference {
        let mediaType: String
        let id: String
    }

    private static func load(_ item: MediaItem) async -> HeroCarouselMetadata {
        var result = HeroCarouselMetadata(
            backdropURL: nil,
            logoURL: nil,
            title: item.title,
            summary: item.summary,
            genres: []
        )

        // Episodes and seasons present their series.
        let seriesKey = item.type == "episode" ? item.grandparentRatingKey : (item.type == "season" ? item.parentRatingKey : nil)
        if item.type == "episode" { result.title = item.grandparentTitle ?? item.title }
        if item.type == "season" { result.title = item.parentTitle ?? item.grandparentTitle ?? item.title }

        var reference: TMDBReference?
        if let key = seriesKey ?? plexKey(for: item),
           let meta: PlexMeta = try? await APIClient.shared.get("/api/plex/metadata/\(key)") {
            if seriesKey != nil {
                result.title = meta.title ?? result.title
                result.summary = meta.summary ?? result.summary
            }
            let mediaType = seriesKey != nil ? "tv" : (meta.type == "movie" ? "movie" : "tv")
            if let guid = meta.Guid?.compactMap(\.id).first(where: { $0.contains("tmdb://") || $0.contains("themoviedb://") }),
               let id = guid.components(separatedBy: "://").last {
                reference = TMDBReference(mediaType: mediaType, id: id)
            }
        } else if item.id.hasPrefix("tmdb:") {
            let parts = item.id.split(separator: ":")
            if parts.count >= 3 {
                reference = TMDBReference(mediaType: parts[1] == "movie" ? "movie" : "tv", id: String(parts[2]))
            }
        }

        guard let reference else { return result }

        let cacheKey = seriesKey.map { "series:\($0)" } ?? item.id
        if let cached = BillboardImageCache.shared.get(itemId: cacheKey) {
            result.backdropURL = cached.0
            result.logoURL = cached.1
        } else if let images = try? await fetchImages(reference) {
            result.backdropURL = images.backdrop
            result.logoURL = images.logo
            BillboardImageCache.shared.set(itemId: cacheKey, backdrop: images.backdrop, logo: images.logo)
        }

        if let id = Int(reference.id) {
            let tmdb = FlixorCore.shared.tmdb
            if reference.mediaType == "movie", let details = try? await tmdb.getMovieDetails(id: id) {
                result.genres = Array(details.genres.prefix(3).map(\.name))
                if result.summary?.isEmpty ?? true { result.summary = details.overview }
            } else if reference.mediaType == "tv", let details = try? await tmdb.getTVDetails(id: id) {
                result.genres = Array(details.genres.prefix(3).map(\.name))
                if result.summary?.isEmpty ?? true { result.summary = details.overview }
            }
        }
        return result
    }

    private static func plexKey(for item: MediaItem) -> String? {
        if item.id.hasPrefix("plex:") { return String(item.id.dropFirst(5)) }
        if !item.id.isEmpty, item.id.allSatisfy(\.isNumber) { return item.id }
        return nil
    }

    private static func fetchImages(_ reference: TMDBReference) async throws -> (backdrop: URL?, logo: URL?) {
        struct TMDBImages: Codable { let backdrops: [TMDBImage]?; let logos: [TMDBImage]? }
        struct TMDBImage: Codable { let file_path: String?; let iso_639_1: String?; let vote_average: Double? }

        let images: TMDBImages = try await APIClient.shared.get(
            "/api/tmdb/\(reference.mediaType)/\(reference.id)/images",
            queryItems: [URLQueryItem(name: "language", value: "en,hi,null")]
        )

        // Textless artwork first, since the logo goes on top.
        let backdrops = images.backdrops ?? []
        func best(_ list: [TMDBImage]) -> TMDBImage? {
            list.max { ($0.vote_average ?? 0) < ($1.vote_average ?? 0) }
        }
        let backdrop = best(backdrops.filter { $0.iso_639_1 == nil }) ?? best(backdrops)

        let logos = images.logos ?? []
        let logo = logos.first { $0.iso_639_1 == "en" } ?? logos.first

        return (
            backdrop?.file_path.flatMap { URL(string: "https://image.tmdb.org/t/p/original\($0)") },
            logo?.file_path.flatMap { URL(string: "https://image.tmdb.org/t/p/w500\($0)") }
        )
    }
}
