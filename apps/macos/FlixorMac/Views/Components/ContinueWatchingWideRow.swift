//
//  ContinueWatchingWideRow.swift
//  FlixorMac
//
//  "Wide" Continue Watching style: a larger landscape card with the episode
//  still, show and episode title, S·E label, progress bar and time left.
//  Up-next episode stills can be blurred (spoiler protection).
//

import SwiftUI

struct ContinueWatchingWideRow: View {
    var title: String = "Continue Watching"
    let items: [MediaItem]
    /// Item ids with a watch-state action running (menus disabled).
    var busyItemIds: Set<String> = []
    var blurUpNext: Bool = false
    var onTap: ((MediaItem) -> Void)?
    var onAction: ContinueWatchingActionHandler?

    static let cardWidth: CGFloat = 520

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.itemGap) {
            HStack {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
            }
            .padding(.horizontal, DS.Space.s20)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: DS.Space.s16) {
                    ForEach(items) { item in
                        ContinueWatchingWideCard(
                            item: item,
                            width: Self.cardWidth,
                            isBusy: busyItemIds.contains(item.id),
                            blurStill: blurUpNext && item.isUpNextEpisode,
                            onTap: { onTap?(item) },
                            onAction: onAction
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                }
                .padding(.horizontal, DS.Space.s20)
                .padding(.vertical, DS.Space.s4)
            }
        }
    }
}

// MARK: - Card

struct ContinueWatchingWideCard: View {
    let item: MediaItem
    let width: CGFloat
    var isBusy: Bool = false
    var blurStill: Bool = false
    var onTap: (() -> Void)?
    var onAction: ContinueWatchingActionHandler?

    @Environment(\.flixorTheme) private var theme
    @State private var isHovered = false

    private var height: CGFloat { (width * DS.Layout.landscapeAspect).rounded() }

    private var isEpisode: Bool { item.type == "episode" }

    private var showTitle: String {
        isEpisode ? (item.grandparentTitle ?? item.title) : item.title
    }

    private var episodeTitle: String? {
        guard isEpisode, item.grandparentTitle != nil else { return nil }
        return item.title
    }

    /// "S2 · E5" for episodes.
    private var seasonEpisodeLabel: String? {
        guard isEpisode, let season = item.parentIndex, let episode = item.index else { return nil }
        return "S\(season) · E\(episode)"
    }

    private var progress: Double {
        guard let duration = item.duration, duration > 0, let offset = item.viewOffset, offset > 0 else { return 0 }
        return min(1, max(0, Double(offset) / Double(duration)))
    }

    private var timeText: String? {
        guard let duration = item.duration, duration > 0 else {
            return item.isUpNextEpisode ? "Up next" : nil
        }
        if let offset = item.viewOffset, offset > 0 {
            return "\(Self.format(milliseconds: max(0, duration - offset))) left"
        }
        let length = Self.format(milliseconds: duration)
        return item.isUpNextEpisode ? "Up next · \(length)" : length
    }

    /// Episode still for Plex episodes; backdrop otherwise (local history
    /// stores a poster in `thumb`, which would not fit a landscape card).
    private var imageURL: URL? {
        let isPlexItem = !item.id.hasPrefix("tmdb:") && !item.id.hasPrefix("stremio:")
        let path: String?
        if isEpisode {
            path = isPlexItem
                ? (item.thumb ?? item.art ?? item.grandparentArt)
                : (item.art ?? item.grandparentArt ?? item.thumb)
        } else {
            path = item.art ?? item.thumb
        }
        guard let path else { return nil }
        if path.hasPrefix("http") { return URL(string: path) }
        return ImageService.shared.plexImageURL(path: path, width: Int(width * 2), height: Int(height * 2), quality: 70)
    }

    var body: some View {
        Button(action: { onTap?() }) {
            ZStack(alignment: .bottomLeading) {
                CachedAsyncImage(url: imageURL)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .blur(radius: blurStill ? 24 : 0, opaque: true)
                    .clipped()
                    .background(theme.surfaceElevated)

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.35),
                        .init(color: theme.scrim(DS.Opacity.scrimMedium), location: 0.7),
                        .init(color: theme.scrim(DS.Opacity.scrimHeavy), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                if blurStill {
                    Label("Spoiler hidden", systemImage: "eye.slash")
                        .flixorFont(.caption, weight: .semibold)
                        .foregroundStyle(theme.textSecondary)
                        .padding(.horizontal, DS.Space.s8)
                        .padding(.vertical, DS.Space.s4)
                        .background(Capsule().fill(theme.scrim(DS.Opacity.scrimLight)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, DS.Space.s12)
                }

                info
                    .padding(DS.Space.cardPadding)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .strokeBorder(
                        isHovered ? theme.focusRing.opacity(DS.Opacity.secondary) : theme.separator,
                        lineWidth: isHovered ? DS.Border.medium : DS.Border.thin
                    )
            )
            .flixorShadow(isHovered ? .floating : .card)
            .scaleEffect(isHovered ? 1.02 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityText))
        .opacity(isBusy ? DS.Opacity.muted : 1)
        .overlay(alignment: .topTrailing) {
            if let onAction {
                ContinueWatchingMoreButton(item: item, isBusy: isBusy, onAction: onAction)
                    .background(Circle().fill(theme.scrim(DS.Opacity.scrimLight)))
                    .padding(DS.Space.s10)
            }
        }
        .continueWatchingContextMenu(item: item, isBusy: isBusy, onAction: onAction)
        .onHover { hovering in
            withAnimation(DS.Motion.quick) { isHovered = hovering }
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            if let label = seasonEpisodeLabel {
                Text(label)
                    .flixorFont(.micro)
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, DS.Space.s6)
                    .padding(.vertical, DS.Space.s2)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.badge, style: .continuous)
                            .fill(Color.white.opacity(DS.Opacity.selected))
                    )
            }

            Text(showTitle)
                .flixorFont(.title3)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)

            if let episodeTitle {
                Text(episodeTitle)
                    .flixorFont(.callout)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }

            HStack(spacing: DS.Space.s10) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(DS.Opacity.disabled))
                        Capsule()
                            .fill(theme.accent)
                            .frame(width: proxy.size.width * progress)
                    }
                }
                .frame(height: 4)

                if let timeText {
                    Text(timeText)
                        .flixorFont(.caption, weight: .medium)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.top, DS.Space.s2)
        }
        .padding(.trailing, DS.Space.s4)
    }

    private var accessibilityText: String {
        [showTitle, seasonEpisodeLabel, episodeTitle, timeText].compactMap { $0 }.joined(separator: ", ")
    }

    static func format(milliseconds: Int) -> String {
        let totalMinutes = max(1, Int((Double(milliseconds) / 60000).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes)m" }
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }
}
