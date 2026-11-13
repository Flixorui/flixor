//
//  HoverPreviewCard.swift
//  FlixorMac
//
//  The expanded card shown over a hovered poster/landscape card: 16:9 artwork
//  (or an inline trailer), logo or title, year · runtime · rating, genres, a
//  short overview and quick actions. Layout has a fixed height (reserved lines)
//  so the floating panel never has to resize while data arrives.
//

import SwiftUI

struct HoverPreviewActions {
    var onOpen: (() -> Void)?
    var onPlay: (() -> Void)?
    var watchlistController: WatchlistController?
    /// Called before any action that navigates, so the panel goes away first.
    var dismiss: () -> Void
}

struct HoverPreviewCard: View {
    @ObservedObject var model: HoverPreviewModel
    let width: CGFloat
    let actions: HoverPreviewActions

    @Environment(\.flixorTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var watchState = WatchStateService.shared

    @State private var isMuted: Bool
    @State private var isTrailerPlaying = false
    @State private var isInList = false
    @State private var isWorkingOnList = false
    @State private var appeared = false

    static let shadowInset: CGFloat = DS.Space.s20

    init(model: HoverPreviewModel, width: CGFloat, actions: HoverPreviewActions) {
        self.model = model
        self.width = width
        self.actions = actions
        _isMuted = State(initialValue: model.trailerMode != .sound)
    }

    private var artworkHeight: CGFloat { (width * 9 / 16).rounded() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            artwork
            info
        }
        .frame(width: width, alignment: .leading)
        .background(theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(theme.separatorStrong, lineWidth: DS.Border.thin)
        )
        .flixorShadow(.floating)
        .scaleEffect(appeared || reduceMotion ? 1 : 0.94)
        .opacity(appeared || reduceMotion ? 1 : 0)
        .padding(Self.shadowInset)
        .onAppear {
            refreshListState()
            withAnimation(reduceMotion ? nil : DS.Motion.spring) { appeared = true }
            model.start()
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchlistDidChange)) { _ in refreshListState() }
        .onChange(of: model.tmdbId) { _ in refreshListState() }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Artwork

    private var artwork: some View {
        ZStack(alignment: .bottomLeading) {
            CachedAsyncImage(url: model.backdropURL, aspectRatio: 16 / 9, contentMode: .fill) {
                theme.surface
            }
            .frame(width: width, height: artworkHeight)
            .clipped()
            .accessibilityHidden(true)

            if let trailer = model.trailer, model.trailerMode != .off {
                HoverPreviewTrailer(trailer: trailer, isMuted: $isMuted, isPlaying: $isTrailerPlaying)
                    .frame(width: width, height: artworkHeight)
                    .clipped()
                    .opacity(isTrailerPlaying ? 1 : 0)
                    .animation(reduceMotion ? nil : DS.Motion.slow, value: isTrailerPlaying)
            }

            LinearGradient(
                colors: [.clear, theme.surfaceElevated.opacity(DS.Opacity.strong)],
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(width: width, height: artworkHeight)
            .allowsHitTesting(false)

            titleBlock
                .padding(.horizontal, DS.Space.cardPadding)
                .padding(.bottom, DS.Space.s10)

            if isTrailerPlaying {
                muteButton
                    .padding(DS.Space.s10)
                    .frame(width: width, height: artworkHeight, alignment: .bottomTrailing)
                    .transition(.opacity)
            }
        }
        .frame(width: width, height: artworkHeight)
    }

    @ViewBuilder
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if let logo = model.logoURL {
                CachedAsyncImage(url: logo, contentMode: .fit) {
                    Text(model.title)
                        .flixorFont(.title3)
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                }
                .frame(maxWidth: width * 0.55, maxHeight: DS.Space.s48, alignment: .bottomLeading)
                .accessibilityLabel(Text(model.title))
            } else {
                Text(model.title)
                    .flixorFont(.title3)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(DS.Opacity.tertiary), radius: 4)
            }
            if let subtitle = model.subtitle {
                Text(subtitle)
                    .flixorFont(.footnote, weight: .medium)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private var muteButton: some View {
        Button {
            isMuted.toggle()
        } label: {
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.flixorIcon(DS.Icon.xs, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .frame(width: DS.Space.s28, height: DS.Space.s28)
                .background(Circle().fill(theme.scrim(DS.Opacity.scrimMedium)))
                .overlay(Circle().strokeBorder(theme.separatorStrong, lineWidth: DS.Border.thin))
        }
        .buttonStyle(.plain)
        .help(isMuted ? "Unmute trailer" : "Mute trailer")
        .accessibilityLabel(isMuted ? "Unmute trailer" : "Mute trailer")
    }

    // MARK: - Info

    private var info: some View {
        VStack(alignment: .leading, spacing: DS.Space.s8) {
            buttonRow

            metadataLine
                .frame(height: DS.Space.s16, alignment: .leading)

            Text(model.genres.isEmpty ? " " : model.genres.joined(separator: " · "))
                .flixorFont(.caption, weight: .medium)
                .foregroundStyle(theme.textTertiary)
                .lineLimit(1)

            Text(model.overview ?? " ")
                .flixorParagraph(.footnote)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(3, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Space.s14)
    }

    private var metadataLine: some View {
        HStack(spacing: DS.Space.s6) {
            if let typeLabel {
                Text(typeLabel)
                    .flixorFont(.micro)
                    .foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.vertical, DS.Space.s2)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.badge)
                            .strokeBorder(theme.separatorStrong, lineWidth: DS.Border.thin)
                    )
            }
            Text(metadataText)
                .flixorFont(.footnote, weight: .medium)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
            if let rating = model.rating {
                HStack(spacing: DS.Space.s2) {
                    Image(systemName: "star.fill")
                        .font(.flixorIcon(DS.Icon.xs - 3))
                    Text(String(format: "%.1f", rating))
                        .flixorFont(.footnote, weight: .semibold)
                }
                .foregroundStyle(theme.warning)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Rating \(String(format: "%.1f", rating))")
            }
        }
    }

    private var typeLabel: String? {
        switch model.item.type.lowercased() {
        case "movie": return "MOVIE"
        case "show": return "SERIES"
        case "season": return "SEASON"
        case "episode": return "EPISODE"
        default: return nil
        }
    }

    private var metadataText: String {
        [model.year, model.runtime].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: - Buttons

    private var buttonRow: some View {
        HStack(spacing: DS.Space.s8) {
            if let onPlay = actions.onPlay {
                circleButton(icon: "play.fill", label: String(localized: "Play"), prominent: true) {
                    actions.dismiss()
                    onPlay()
                }
            }

            if CardActions.supportsWatchlist(model.item) {
                circleButton(
                    icon: isInList ? "checkmark" : "plus",
                    label: isInList ? String(localized: "Remove from My List") : String(localized: "Add to My List"),
                    isBusy: isWorkingOnList
                ) {
                    toggleList()
                }
            }

            if !CardActions.isWholeShowLike(model.item), let target = WatchStateTarget(item: model.item) {
                circleButton(
                    icon: model.isWatched ? "eye.slash" : "eye",
                    label: model.isWatched ? String(localized: "Mark as Unwatched") : String(localized: "Mark as Watched"),
                    isBusy: watchState.inFlight.contains(target.actionKey)
                ) {
                    toggleWatched()
                }
            }

            Spacer(minLength: 0)

            if let onOpen = actions.onOpen {
                circleButton(icon: "chevron.down", label: String(localized: "More Info")) {
                    actions.dismiss()
                    onOpen()
                }
            }
        }
    }

    private func circleButton(
        icon: String,
        label: String,
        prominent: Bool = false,
        isBusy: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                if isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: icon)
                        .font(.flixorIcon(DS.Icon.sm, weight: .bold))
                }
            }
            .foregroundStyle(prominent ? Color.black : theme.textPrimary)
            .frame(width: DS.Space.s32, height: DS.Space.s32)
            .background(Circle().fill(prominent ? Color.white : theme.hoverFill))
            .overlay(
                Circle().strokeBorder(prominent ? Color.clear : theme.separatorStrong, lineWidth: DS.Border.thin)
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .help(label)
        .accessibilityLabel(label)
    }

    // MARK: - Actions

    private func refreshListState() {
        isInList = CardActions.isInWatchlist(model.item, controller: actions.watchlistController, tmdbId: model.tmdbId)
    }

    private func toggleList() {
        guard !isWorkingOnList else { return }
        isWorkingOnList = true
        let item = model.item
        let controller = actions.watchlistController
        Task {
            if let nowIn = await CardActions.toggleWatchlist(item, controller: controller) {
                isInList = nowIn
            }
            isWorkingOnList = false
        }
    }

    private func toggleWatched() {
        let item = model.item
        let watched = !model.isWatched
        Task {
            let result = await CardActions.setWatched(item, watched: watched)
            if result.isSuccess || result.isPartialSuccess {
                model.isWatched = watched
            }
        }
    }
}
