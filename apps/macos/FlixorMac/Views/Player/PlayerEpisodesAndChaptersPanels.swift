//
//  PlayerEpisodesAndChaptersPanels.swift
//  FlixorMac
//
//  Episode list and chapter list panels shown over the player
//

import SwiftUI

// MARK: - Episodes List Panel

extension ImageService {
    /// Episode artwork: addon streams carry full URLs, Plex carries server paths.
    func episodeThumbnailURL(_ thumb: String, width: Int, height: Int) -> URL? {
        if thumb.hasPrefix("http://") || thumb.hasPrefix("https://") { return URL(string: thumb) }
        return plexImageURL(path: thumb, width: width, height: height)
    }
}

struct EpisodesListPanel: View {
    @Environment(\.flixorTheme) private var theme
    let episodes: [EpisodeMetadata]
    let currentEpisodeKey: String
    var seasons: [Int] = []
    var selectedSeason: Int? = nil
    var isLoading: Bool = false
    var onSelectSeason: (Int) -> Void = { _ in }
    let onSelectEpisode: (EpisodeMetadata) -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    panelContent
                }
            }
        }
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Episodes")
                    .font(.flixor(.bodyLarge, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.flixorIcon(DS.Icon.xs, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DS.Space.s16)
            .padding(.vertical, DS.Space.s12)

            Divider().background(Color.white.opacity(0.1))

            if seasons.count > 1 {
                seasonChips
                Divider().background(Color.white.opacity(0.1))
            }

            // Episodes List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: DS.Space.s2) {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .frame(maxWidth: .infinity)
                                .padding(DS.Space.s24)
                        }
                        ForEach(isLoading ? [] : episodes) { episode in
                            EpisodeListRow(
                                episode: episode,
                                isCurrentEpisode: episode.ratingKey == currentEpisodeKey,
                                onSelect: { onSelectEpisode(episode) }
                            )
                            .id(episode.ratingKey)
                        }
                    }
                    .padding(DS.Space.s8)
                }
                .onAppear {
                    proxy.scrollTo(currentEpisodeKey, anchor: .center)
                }
            }
            .frame(maxHeight: 350)
        }
        .frame(width: 360)
        .background(theme.playerPanelBackground())
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r12))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.r12).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
        .padding(.trailing, DS.Space.s32)
        .padding(.bottom, 140)
    }
}

private extension EpisodesListPanel {
    var seasonChips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s6) {
                    ForEach(seasons, id: \.self) { season in
                        Button(action: { onSelectSeason(season) }) {
                            Text(season == 0 ? String(localized: "Specials") : String(localized: "Season \(String(season))"))
                                .font(.flixor(.footnote, weight: season == selectedSeason ? .semibold : .regular))
                                .foregroundStyle(season == selectedSeason ? theme.onAccent : .white.opacity(0.8))
                                .padding(.horizontal, DS.Space.s10)
                                .padding(.vertical, DS.Space.s6)
                                .background(season == selectedSeason ? theme.accent : Color.white.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .id(season)
                        .accessibilityAddTraits(season == selectedSeason ? .isSelected : [])
                    }
                }
                .padding(.horizontal, DS.Space.s12)
                .padding(.vertical, DS.Space.s8)
            }
            .onAppear { proxy.scrollTo(selectedSeason, anchor: .center) }
        }
    }
}

private struct EpisodeListRow: View {
    let episode: EpisodeMetadata
    let isCurrentEpisode: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: DS.Space.s12) {
                // Episode number with progress indicator
                ZStack {
                    Circle()
                        .fill(progressColor)
                        .frame(width: 32, height: 32)

                    if let progress = episode.progressPercent, progress > 0, progress < 95 {
                        Circle()
                            .trim(from: 0, to: CGFloat(progress) / 100.0)
                            .stroke(Color.accentColor, lineWidth: 2)
                            .frame(width: 32, height: 32)
                            .rotationEffect(.degrees(-90))
                    }

                    if let index = episode.index {
                        Text("\(index)")
                            .font(.flixor(.footnote, weight: .semibold))
                            .foregroundStyle(isCurrentEpisode ? .white : .white.opacity(0.8))
                    }
                }

                // Thumbnail
                ZStack {
                    if let thumbPath = episode.thumb,
                       let imageURL = ImageService.shared.episodeThumbnailURL(thumbPath, width: 200, height: 112) {
                        CachedAsyncImage(url: imageURL)
                            .frame(width: 100, height: 56)
                    } else {
                        RoundedRectangle(cornerRadius: DS.Radius.r4)
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 100, height: 56)
                    }

                    // Hover play overlay
                    if isHovered {
                        RoundedRectangle(cornerRadius: DS.Radius.r4)
                            .fill(Color.black.opacity(0.4))
                            .frame(width: 100, height: 56)

                        Image(systemName: "play.fill")
                            .font(.flixorIcon(DS.Icon.lg))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 100, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r4))

                // Episode info
                VStack(alignment: .leading, spacing: 3) {
                    Text(episode.title)
                        .font(.system(size: 13, weight: isCurrentEpisode ? .semibold : .regular))
                        .foregroundStyle(isCurrentEpisode ? .white : .white.opacity(0.85))
                        .lineLimit(1)

                    HStack(spacing: DS.Space.s6) {
                        if let duration = episode.duration {
                            Text("\(duration / 60000) min")
                                .font(.flixor(.caption))
                                .foregroundStyle(.white.opacity(0.5))
                        }

                        if let progress = episode.progressPercent, progress >= 95 {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.flixor(.micro))
                                .foregroundStyle(.green.opacity(0.8))
                        }
                    }
                }

                Spacer()

                if isCurrentEpisode {
                    Image(systemName: "play.fill")
                        .font(.flixor(.micro))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, DS.Space.s12)
            .padding(.vertical, DS.Space.s10)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.r8)
                    .fill(isCurrentEpisode ? Color.white.opacity(0.1) : (isHovered ? Color.white.opacity(0.05) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var progressColor: Color {
        if let progress = episode.progressPercent {
            if progress >= 95 {
                return Color.accentColor.opacity(0.3)
            } else if progress > 0 {
                return Color.white.opacity(0.15)
            }
        }
        return Color.white.opacity(0.1)
    }
}

// MARK: - Chapters Panel

struct ChaptersPanel: View {
    @Environment(\.flixorTheme) private var theme
    @ObservedObject var viewModel: PlayerViewModel
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    panelContent
                }
            }
        }
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Chapters")
                    .font(.flixor(.bodyLarge, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.flixorIcon(DS.Icon.xs, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DS.Space.s16)
            .padding(.vertical, DS.Space.s12)

            Divider().background(Color.white.opacity(0.1))

            // Chapters List
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: DS.Space.s2) {
                        ForEach(viewModel.chapters) { chapter in
                            ChapterListRow(
                                chapter: chapter,
                                isCurrent: chapter.index == viewModel.currentChapterIndex,
                                progress: calculateProgress(for: chapter)
                            ) {
                                viewModel.seekToChapter(chapter.index)
                            }
                            .id(chapter.index)
                        }
                    }
                    .padding(DS.Space.s8)
                }
                .onAppear {
                    if let currentIndex = viewModel.currentChapterIndex {
                        proxy.scrollTo(currentIndex, anchor: .center)
                    }
                }
            }
            .frame(maxHeight: 350)
        }
        .frame(width: 320)
        .background(theme.playerPanelBackground())
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r12))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.r12).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
        .padding(.trailing, DS.Space.s32)
        .padding(.bottom, 140)
    }

    private func calculateProgress(for chapter: MPVChapter) -> Double? {
        guard let currentIndex = viewModel.currentChapterIndex else { return nil }
        if chapter.index < currentIndex {
            return 1.0 // Completed
        } else if chapter.index == currentIndex {
            let chapterStart = chapter.time
            let nextChapterStart = viewModel.chapters.count > chapter.index + 1
                ? viewModel.chapters[chapter.index + 1].time
                : viewModel.duration
            let chapterDuration = nextChapterStart - chapterStart
            guard chapterDuration > 0 else { return 0 }
            return min(1.0, max(0, (viewModel.currentTime - chapterStart) / chapterDuration))
        }
        return nil
    }
}

private struct ChapterListRow: View {
    let chapter: MPVChapter
    let isCurrent: Bool
    let progress: Double?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s12) {
                // Chapter number with progress indicator
                ZStack {
                    Circle()
                        .fill(progressColor)
                        .frame(width: 28, height: 28)

                    if let progress = progress, progress < 1.0 && progress > 0 {
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(Color.accentColor, lineWidth: 2)
                            .frame(width: 28, height: 28)
                            .rotationEffect(.degrees(-90))
                    }

                    Text("\(chapter.index + 1)")
                        .font(.flixor(.caption, weight: .semibold))
                        .foregroundStyle(isCurrent ? .white : .white.opacity(0.8))
                }

                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    Text(chapter.displayName)
                        .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? .white : .white.opacity(0.85))
                        .lineLimit(1)

                    Text(chapter.formattedTime)
                        .font(.flixor(.caption, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()

                if isCurrent {
                    Image(systemName: "play.fill")
                        .font(.flixor(.micro))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, DS.Space.s12)
            .padding(.vertical, DS.Space.s10)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.r8)
                    .fill(isCurrent ? Color.white.opacity(0.1) : (isHovered ? Color.white.opacity(0.05) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var progressColor: Color {
        if let progress = progress {
            if progress >= 1.0 {
                return Color.accentColor.opacity(0.3)
            } else if progress > 0 {
                return Color.white.opacity(0.15)
            }
        }
        return Color.white.opacity(0.1)
    }
}
