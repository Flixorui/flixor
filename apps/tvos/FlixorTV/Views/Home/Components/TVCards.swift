import SwiftUI
import FlixorKit

// MARK: - Progress bar (avoids GeometryReader per card)
private struct ProgressCapsule: View {
    let progress: CGFloat
    @Environment(\.tvThemePalette) private var theme

    var body: some View {
        Capsule().fill(theme.surfaceGlass)
            .frame(height: 6)
            .overlay(alignment: .leading) {
                Capsule().fill(theme.accent)
                    .frame(width: nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .scaleEffect(x: max(0.01, min(progress, 1.0)), anchor: .leading)
            }
            .clipShape(Capsule())
    }
}

// MARK: - Image helper
struct TVImage: View {
    enum Layout { case aspect(CGFloat), heightFixed(CGFloat) }

    let url: URL?
    let corner: CGFloat
    let layout: Layout

    @Environment(\.tvThemePalette) private var theme

    init(url: URL?, corner: CGFloat = 14, aspect: CGFloat) {
        self.url = url
        self.corner = corner
        self.layout = .aspect(aspect)
    }

    init(url: URL?, corner: CGFloat = 14, height: CGFloat) {
        self.url = url
        self.corner = corner
        self.layout = .heightFixed(height)
    }

    var body: some View {
        ZStack {
            theme.backgroundCard
            LinearGradient(colors: [Color.black.opacity(0.2), Color.black.opacity(0.0)], startPoint: .bottom, endPoint: .top)

            if let url = url {
                CachedAsyncImage(url: url, contentMode: .fill) {
                    theme.surfaceMuted
                }
            } else {
                theme.surfaceMuted
            }
        }
        .modifier(LayoutModifier(layout: layout))
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(theme.strokeDefault, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

private struct TVLogoImage: View {
    let url: URL
    let maxWidth: CGFloat
    let maxHeight: CGFloat
    let fallbackText: String
    let fallbackFont: Font

    var body: some View {
        CachedAsyncImage(url: url, contentMode: .fit, showsErrorView: false) {
            Text(fallbackText)
                .font(fallbackFont)
                .lineLimit(1)
        }
        .frame(maxWidth: maxWidth, maxHeight: maxHeight, alignment: .leading)
        .shadow(color: .black.opacity(0.7), radius: 8, x: 0, y: 2)
    }
}

private struct LayoutModifier: ViewModifier {
    let layout: TVImage.Layout
    func body(content: Content) -> some View {
        switch layout {
        case .aspect(let ar):
            content.aspectRatio(ar, contentMode: .fit)
        case .heightFixed(let h):
            content
                .frame(maxWidth: .infinity)
                .frame(height: h)
        }
    }
}

// MARK: - Poster (2:3)
struct TVPosterCard: View {
    let item: MediaItem
    let isFocused: Bool
    var respectLibraryTitles: Bool = false
    @EnvironmentObject private var profileSettings: TVProfileSettings
    @Environment(\.tvThemePalette) private var theme
    @Environment(\.tvTypography) private var typography
    @Environment(\.tvCardVisualTokens) private var cardTokens

    // For episodes, use series poster (grandparentThumb)
    private var posterURL: URL? {
        if item.type == "episode", let grandparentThumb = item.grandparentThumb {
            return ImageService.shared.plexImageURL(path: grandparentThumb, width: 360, height: 540)
        }
        return ImageService.shared.thumbURL(for: item, width: 360, height: 540)
    }

    private var posterCornerRadius: CGFloat {
        profileSettings.posterCornerRadius
    }

    private var shouldShowFocusedTitle: Bool {
        guard isFocused, profileSettings.showPosterLabels else { return false }
        if respectLibraryTitles {
            return profileSettings.showLibraryTitles
        }
        return true
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            TVImage(url: posterURL, corner: posterCornerRadius, aspect: 2/3)

            // For episodes: show series logo + episode title
            if item.type == "episode" {
                LinearGradient(colors: [Color.black.opacity(0.7), .clear], startPoint: .bottom, endPoint: .top)
                    .clipShape(RoundedRectangle(cornerRadius: posterCornerRadius, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    // Series logo or series title
                    if let logoURL = item.logo, let url = URL(string: logoURL) {
                        TVLogoImage(
                            url: url,
                            maxWidth: 160,
                            maxHeight: 50,
                            fallbackText: item.grandparentTitle ?? item.title,
                            fallbackFont: typography.custom(size: 18, weight: .semibold)
                        )
                    } else if let seriesTitle = item.grandparentTitle {
                        // No logo, show series title
                        Text(seriesTitle)
                            .font(typography.custom(size: 18, weight: .semibold))
                            .lineLimit(1)
                    }

                    // Episode title
                    Text(item.title)
                        .font(typography.meta)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(2)
                }
                .foregroundStyle(theme.textPrimary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // For non-episodes: show title on focus only
                if shouldShowFocusedTitle {
                    LinearGradient(colors: [Color.black.opacity(0.6), .clear], startPoint: .bottom, endPoint: .top)
                        .clipShape(RoundedRectangle(cornerRadius: posterCornerRadius, style: .continuous))
                    Text(item.title)
                        .font(typography.custom(size: 22, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .padding(12)
                }
            }

            // Progress overlay for Continue Watching items
            if let viewOffset = item.viewOffset, let duration = item.duration, duration > 0 {
                VStack {
                    Spacer()
                    ProgressCapsule(progress: CGFloat(viewOffset) / CGFloat(duration))
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
                }
            }
        }
        .overlay(
            Group {
                if isFocused {
                    RoundedRectangle(cornerRadius: posterCornerRadius, style: .continuous)
                        .stroke(theme.strokeFocused, lineWidth: cardTokens.focusedStrokeWidth)
                }
            }
        )
        // scale/shadow handled by row wrapper for consistent neighbor treatment
    }
}

// MARK: - Landscape (16:9)
struct TVLandscapeCard: View {
    let item: MediaItem
    let showBadges: Bool
    var isFocused: Bool = false
    var outlined: Bool = false
    var focusOutlineOnFocus: Bool = false
    var heightOverride: CGFloat? = nil
    var overrideURL: URL? = nil
    var previewTrailer: TVTrailer? = nil
    var previewTrailerMuted: Bool = true

    @Environment(\.tvThemePalette) private var theme
    @Environment(\.tvTypography) private var typography
    @Environment(\.tvCardVisualTokens) private var cardTokens

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                let imgURL = overrideURL ?? ImageService.shared.continueWatchingURL(for: item, width: 960, height: 540)
                if let h = heightOverride {
                    ZStack {
                        TVImage(url: imgURL, corner: cardTokens.landscapeRadius, height: h)
                        if let previewTrailer {
                            TVInlineTrailerPreview(trailer: previewTrailer, muted: previewTrailerMuted)
                                .clipShape(RoundedRectangle(cornerRadius: cardTokens.landscapeRadius, style: .continuous))
                        }
                    }
                } else {
                    ZStack {
                        TVImage(url: imgURL, corner: cardTokens.landscapeRadius, aspect: 16/9)
                        if let previewTrailer {
                            TVInlineTrailerPreview(trailer: previewTrailer, muted: previewTrailerMuted)
                                .clipShape(RoundedRectangle(cornerRadius: cardTokens.landscapeRadius, style: .continuous))
                        }
                    }
                }
            }
            LinearGradient(colors: [Color.black.opacity(0.65), Color.black.opacity(0.0)], startPoint: .bottom, endPoint: .top)
                .clipShape(RoundedRectangle(cornerRadius: cardTokens.landscapeRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                // For episodes: show series logo, then episode title and info
                if item.type == "episode" {
                    // Series logo or series title
                    if let logoURL = item.logo, let url = URL(string: logoURL) {
                        TVLogoImage(
                            url: url,
                            maxWidth: 280,
                            maxHeight: 80,
                            fallbackText: item.grandparentTitle ?? item.title,
                            fallbackFont: typography.custom(size: 28, weight: .semibold)
                        )
                    } else if let seriesTitle = item.grandparentTitle {
                        // No logo, show series title
                        Text(seriesTitle)
                            .font(typography.custom(size: 28, weight: .semibold))
                            .lineLimit(1)
                    }

                    // Episode season and number
                    if let season = item.parentIndex, let episode = item.index {
                        Text("S\(season) • E\(episode)")
                            .font(typography.body)
                            .foregroundStyle(theme.textSecondary)
                    }

                    // Episode title
                    Text(item.title)
                        .font(typography.body)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(2)
                } else {
                    // For non-episodes: display clear logo if available, otherwise fallback to text title
                    if let logoURL = item.logo, let url = URL(string: logoURL) {
                        TVLogoImage(
                            url: url,
                            maxWidth: 280,
                            maxHeight: 80,
                            fallbackText: item.title,
                            fallbackFont: typography.custom(size: 28, weight: .semibold)
                        )
                    } else {
                        // No logo available, use text title
                        Text(item.title)
                            .font(typography.custom(size: 28, weight: .semibold))
                            .lineLimit(1)
                    }

                    if showBadges {
                        HStack(spacing: 6) {
                            Text("HD").font(typography.custom(size: 14, weight: .semibold))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(theme.surfaceGlass).clipShape(Capsule())
                            Text("5.1").font(typography.custom(size: 14, weight: .semibold))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(theme.surfaceGlass).clipShape(Capsule())
                        }
                    }
                }

                if let viewOffset = item.viewOffset, let duration = item.duration, duration > 0 {
                    ProgressCapsule(progress: CGFloat(viewOffset) / CGFloat(duration))
                        .padding(.top, 6)

                    // time-left pill overlay for Continue Watching parity
                    if duration > viewOffset {
                        let remaining = max(0, (duration - viewOffset) / 60000)
                        Text("\(remaining)m left")
                            .font(typography.custom(size: 14, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(theme.surfaceGlass)
                            .clipShape(Capsule())
                            .padding(.top, 6)
                    }
                }
            }
            .foregroundStyle(theme.textPrimary)
            .padding(18)
            .compositingGroup()
            .shadow(color: .black.opacity(0.6), radius: 12, y: 4)
        }
        .overlay(
            Group {
                if outlined || (focusOutlineOnFocus && isFocused) {
                    RoundedRectangle(cornerRadius: cardTokens.landscapeRadius, style: .continuous)
                        .stroke(theme.strokeFocused, lineWidth: cardTokens.focusedStrokeWidth)
                }
            }
        )
    }
}

private struct TVInlineTrailerPreview: View {
    let trailer: TVTrailer
    let muted: Bool
    @State private var coordinator: MPVPlayerView.Coordinator

    init(trailer: TVTrailer, muted: Bool) {
        self.trailer = trailer
        self.muted = muted

        let coordinator = MPVPlayerView.Coordinator()
        coordinator.onMediaLoaded = {
            TrailerPreviewDiagnostics.debug(
                "MPV media loaded key=\(TrailerPreviewDiagnostics.summarizeKey(trailer.key))"
            )
        }
        coordinator.onPlaybackEnded = {
            TrailerPreviewDiagnostics.debug(
                "MPV playback ended key=\(TrailerPreviewDiagnostics.summarizeKey(trailer.key))"
            )
        }
        coordinator.onPropertyChange = { _, property, data in
            switch property {
            case .pause, .pausedForCache, .duration:
                TrailerPreviewDiagnostics.debug(
                    "MPV property key=\(TrailerPreviewDiagnostics.summarizeKey(trailer.key)) property=\(property.rawValue) value=\(String(describing: data))"
                )
            default:
                break
            }
        }
        if let trailerURL = trailer.inlinePlaybackURL {
            coordinator.setPendingURL(trailerURL)
            TrailerPreviewDiagnostics.debug(
                "Prepared inline trailer key=\(TrailerPreviewDiagnostics.summarizeKey(trailer.key)) url=\(TrailerPreviewDiagnostics.summarizeURL(trailerURL))"
            )
        } else {
            TrailerPreviewDiagnostics.debug("Prepared inline trailer without playable URL key=\(TrailerPreviewDiagnostics.summarizeKey(trailer.key))")
        }
        _coordinator = State(initialValue: coordinator)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
            MPVPlayerView(coordinator: coordinator)
                .allowsHitTesting(false)
        }
        .onAppear {
            if let trailerURL = trailer.inlinePlaybackURL {
                TrailerPreviewDiagnostics.debug(
                    "Inline trailer play request key=\(TrailerPreviewDiagnostics.summarizeKey(trailer.key)) url=\(TrailerPreviewDiagnostics.summarizeURL(trailerURL)) muted=\(muted)"
                )
                coordinator.play(trailerURL)
            } else {
                TrailerPreviewDiagnostics.debug("Inline trailer play skipped because playback URL is nil key=\(TrailerPreviewDiagnostics.summarizeKey(trailer.key))")
            }
            coordinator.setVolume(muted ? 0 : 100)
        }
        .onDisappear {
            TrailerPreviewDiagnostics.debug("Inline trailer teardown key=\(TrailerPreviewDiagnostics.summarizeKey(trailer.key))")
            coordinator.pause()
            coordinator.destruct()
        }
    }
}


// MARK: - Expanded Preview (morph target)
struct TVExpandedPreviewCard: View {
    let item: MediaItem
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TVLandscapeCard(item: item, showBadges: true, outlined: true)
            TVHoverMeta(item: item)
        }
        .padding(.horizontal, 12)
    }
}

// Hover metadata block used under expanded preview
struct TVHoverMeta: View {
    let item: MediaItem
    @Environment(\.tvThemePalette) private var theme
    @Environment(\.tvTypography) private var typography

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TVMetaLine(item: item)
                .font(typography.custom(size: 22, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .opacity(0.9)
            if let summary = item.summary, !summary.isEmpty {
                Text(summary)
                    .font(typography.body)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(2)
            }
        }
    }
}

// Local meta line (year • runtime • ★ rating)
struct TVMetaLine: View {
    let item: MediaItem

    enum Segment: Hashable { case year(Int), duration(Int), rating(Double) }

    var segments: [Segment] {
        var s: [Segment] = []
        if let y = item.year { s.append(.year(y)) }
        if let d = item.duration, d > 0 { s.append(.duration(d)) }
        if let r = item.rating, r > 0 { s.append(.rating(r)) }
        return s
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(segments.enumerated()), id: \.offset) { idx, seg in
                HStack(spacing: 6) {
                    switch seg {
                    case .year(let y): Text(String(y))
                    case .duration(let d): Text("\(d / 60000)m")
                    case .rating(let r): HStack(spacing: 4) {
                        Image(systemName: "star.fill").font(.system(size: 16))
                        Text(String(format: "%.1f", r))
                    }
                    }
                    if idx < segments.count - 1 { Text("•").opacity(0.7) }
                }
            }
        }
    }
}
