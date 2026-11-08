//
//  PlayerOverlays.swift
//  FlixorMac
//
//  Player overlays: loading/error states, skip-marker button, next-episode countdown and hover card
//

import SwiftUI

// MARK: - Loading Overlay

struct PlayerLoadingOverlay: View {
    @ObservedObject var viewModel: PlayerViewModel

    var body: some View {
        VStack(spacing: DS.Space.s12) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)

            if viewModel.isResolvingNextEpisode {
                Button("Cancel") { viewModel.cancelNextEpisodeLookup() }
                    .buttonStyle(.plain)
                    .font(.flixor(.callout, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, DS.Space.s16)
                    .padding(.vertical, DS.Space.s8)
                    .background(Color.black.opacity(0.55), in: Capsule())
            }

            // Show quality change message if applicable
            if viewModel.isChangingQuality {
                VStack(spacing: DS.Space.s4) {
                    Text("Switching to \(viewModel.selectedQuality.rawValue)")
                        .font(.flixor(.headline, weight: .semibold))
                        .foregroundStyle(.white)

                    if viewModel.isTranscoding {
                        Text("Starting transcode...")
                            .font(.flixor(.callout))
                            .foregroundStyle(.white.opacity(0.7))
                    } else {
                        Text("Loading direct play...")
                            .font(.flixor(.callout))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
        }
    }
}

// MARK: - Error Overlay

struct PlayerErrorOverlay: View {
    let message: String
    let onClose: () -> Void
    let onRetry: () -> Void
    /// Offered when another source can be tried (addon streams).
    var onChooseSource: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: DS.Space.s16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.flixorIcon(DS.Icon.huge))
                .foregroundStyle(.orange)

            Text("Playback Error")
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text(message)
                .font(.body)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.Space.s40)

            HStack(spacing: DS.Space.s12) {
                Button("Close") {
                    onClose()
                }
                .buttonStyle(.bordered)

                if let onChooseSource {
                    Button("Retry") {
                        onRetry()
                    }
                    .buttonStyle(.bordered)

                    Button("Choose another source") {
                        onChooseSource()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Choose another source for this title")
                } else {
                    Button("Retry") {
                        onRetry()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

// MARK: - Skip Marker Button (Plezy Style)

/// Skip button for the current marker, titled for its type ("Skip Recap", ...).
struct SkipMarkerButton: View {
    @ObservedObject var viewModel: PlayerViewModel
    let marker: PlayerMarker

    private var title: String {
        if let countdown = viewModel.autoSkipCountdown, countdown > 0 {
            return "\(marker.skipButtonTitle) (\(countdown))"
        }
        return marker.skipButtonTitle
    }

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button(action: {
                    viewModel.skipMarker()
                }) {
                    HStack(spacing: DS.Space.s8) {
                        Text(title)
                            .font(.flixor(.headline, weight: .semibold))
                            .foregroundStyle(.black)
                        Image(systemName: "forward.fill")
                            .font(.flixorIcon(DS.Icon.sm, weight: .semibold))
                            .foregroundStyle(.black)
                    }
                    .padding(.horizontal, DS.Space.s16)
                    .padding(.vertical, DS.Space.s12)
                    .background(Color.white.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r8))
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(marker.skipButtonTitle)
                .padding(.trailing, DS.Space.s24)
                .padding(.bottom, 115)
            }
        }
    }
}

// MARK: - Next Episode Overlay (Plezy Style)

struct NextEpisodeOverlay: View {
    @Environment(\.flixorTheme) private var theme
    let episode: EpisodeMetadata
    let countdown: Int
    let onCancel: () -> Void
    let onPlayNow: () -> Void

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: DS.Space.s12) {
                    // Header
                    Text("Next Episode")
                        .font(.flixor(.footnote, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))

                    // Episode info
                    if let parentIndex = episode.parentIndex, let index = episode.index {
                        Text("S\(parentIndex) E\(index) · \(episode.title)")
                            .font(.flixor(.body, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                    } else {
                        Text(episode.title)
                            .font(.flixor(.body, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                    }

                    // Action buttons
                    HStack(spacing: DS.Space.s8) {
                        // Cancel button (outlined)
                        Button(action: onCancel) {
                            Text("Cancel")
                                .font(.flixor(.body, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, DS.Space.s12)
                                .background(Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: DS.Radius.r6)
                                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)

                        // Play button (filled white with countdown)
                        Button(action: onPlayNow) {
                            HStack(spacing: DS.Space.s4) {
                                if countdown > 0 {
                                    Text("\(countdown)")
                                        .font(.flixor(.body, weight: .semibold))
                                        .foregroundStyle(.black)
                                    Image(systemName: "play.fill")
                                        .font(.flixorIcon(DS.Icon.xs, weight: .semibold))
                                        .foregroundStyle(.black)
                                } else {
                                    Text("Play Now")
                                        .font(.flixor(.body, weight: .semibold))
                                        .foregroundStyle(.black)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DS.Space.s12)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(DS.Space.s16)
                .frame(width: 320)
                .background(theme.playerPanelBackground(opacity: 0.9))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r12))
                .padding(.trailing, DS.Space.s24)
                .padding(.bottom, 100)
            }
        }
    }
}

// MARK: - Next Episode Hover Card

struct NextEpisodeHoverCard: View {
    @Environment(\.flixorTheme) private var theme
    let episode: EpisodeMetadata
    @ObservedObject var viewModel: PlayerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("Next Episode")
                .font(.flixor(.headline, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, DS.Space.s16)
                .padding(.vertical, DS.Space.s12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.05))

            // Content grid
            HStack(spacing: DS.Space.s12) {
                // Episode thumbnail with play icon overlay
                ZStack {
                    // Thumbnail
                    if let thumbPath = episode.thumb,
                       let imageURL = ImageService.shared.episodeThumbnailURL(thumbPath, width: 320, height: 180) {
                        CachedAsyncImage(url: imageURL)
                            .frame(width: 180, height: 100)
                            .background(Color.black.opacity(0.4))
                    } else {
                        Rectangle()
                            .fill(Color.black.opacity(0.4))
                            .frame(width: 180, height: 100)
                    }

                    // Play icon overlay
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.5))
                            .frame(width: 40, height: 40)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                            )

                        // Nudged right so the triangle looks centered in the circle.
                        Image(systemName: "play.fill")
                            .font(.flixorIcon(DS.Icon.md))
                            .foregroundStyle(.white)
                            .offset(x: 1)
                    }
                }
                .frame(width: 180, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r6))

                // Episode info
                VStack(alignment: .leading, spacing: DS.Space.s4) {
                    // Season and Episode number (compact)
                    if let parentIndex = episode.parentIndex, let index = episode.index {
                        Text("Season \(String(parentIndex)) · Episode \(String(index))")
                            .font(.flixor(.body, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }

                    // Episode title
                    Text(episode.title)
                        .font(.flixor(.headline, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    // Episode summary
                    if let summary = episode.summary {
                        Text(summary)
                            .font(.flixor(.footnote))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineSpacing(2)
                            .lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(DS.Space.s12)
        }
        .frame(width: 440)
        .background(theme.playerPanelBackground(opacity: 0.9))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r12))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.r12)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
    }
}
