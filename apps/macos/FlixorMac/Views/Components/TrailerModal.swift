//
//  TrailerModal.swift
//  FlixorMac
//
//  Modal for playing YouTube trailers: natively with AVKit controls when
//  TrailerPlayer finds a direct stream, in the YouTube embed otherwise.
//

import SwiftUI
import YouTubePlayerKit

// MARK: - Trailer Modal

struct TrailerModal: View {
    let trailer: Trailer
    var onClose: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var player: TrailerPlayer

    init(trailer: Trailer, onClose: (() -> Void)? = nil) {
        self.trailer = trailer
        self.onClose = onClose
        var options = TrailerPlayer.Options()
        options.embedShowsControls = true
        options.preventsDisplaySleep = true
        options.detectsLetterbox = false
        // Apple TV trailers can play in up to 4K HDR when "Best quality" is on.
        options.allowsUHD = UserDefaults.standard.myblurayOptionActive(.highQualityTrailers)
        // AVPlayerView shows HDR10 and Dolby Vision correctly; keep them with "Best quality".
        options.sdrOnly = !options.allowsUHD
        _player = StateObject(wrappedValue: TrailerPlayer(trailer: trailer, muted: false, options: options))
    }

    var body: some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture {
                    close()
                }

            // Modal content
            VStack(spacing: 0) {
                // Header bar
                HStack {
                    VStack(alignment: .leading, spacing: DS.Space.s4) {
                        Text(trailer.name)
                            .font(.headline)
                            .foregroundStyle(.white)

                        Text(trailer.isDirect ? "\(trailer.type) · \(trailer.site)" : trailer.type)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    Spacer()

                    // Close button
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.flixorIcon(DS.Icon.md, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, DS.Space.s24)
                .padding(.vertical, DS.Space.s16)
                .background(Color.black.opacity(0.6))

                // Video player
                Group {
                    if canPlay {
                        switch player.backend {
                        case .native(let avPlayer):
                            TrailerAVPlayerControlsView(player: avPlayer)
                        case .embed(let ytPlayer):
                            YouTubePlayerView(ytPlayer)
                        case nil:
                            if player.status == .failed {
                                unavailable
                            } else {
                                ProgressView()
                                    .controlSize(.large)
                                    .tint(.white)
                            }
                        }
                    } else {
                        unavailable
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            }
            .frame(width: 960, height: 600)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.r16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 30)
        }
        .onAppear {
            if canPlay { player.load() }
        }
        .onReceive(player.$status) { status in
            if status == .ready { player.play() }
        }
        .onDisappear { player.stop() }
    }

    /// YouTube trailers, and direct streams (Apple TV) with their YouTube fallback.
    private var canPlay: Bool {
        trailer.isDirect || trailer.site.lowercased() == "youtube"
    }

    /// Shown when the trailer can't be played here.
    private var unavailable: some View {
        VStack(spacing: DS.Space.s16) {
            Image(systemName: "play.slash")
                .font(.flixorIcon(DS.Icon.huge))
                .foregroundStyle(.secondary)

            Text("Unable to play trailer")
                .font(.headline)
                .foregroundStyle(.secondary)

            if let youtubeURL = trailer.youtubeURL {
                Link(destination: youtubeURL) {
                    HStack(spacing: DS.Space.s8) {
                        Image(systemName: "arrow.up.right.square")
                        Text("Open in Browser")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.blue)
                }
            }
        }
    }

    private func close() {
        player.stop()
        dismiss()
        onClose?()
    }
}

// MARK: - Preview

#if DEBUG
struct TrailerModal_Previews: PreviewProvider {
    static var previews: some View {
        TrailerModal(
            trailer: Trailer(
                id: "1",
                name: "Official Trailer",
                key: "dQw4w9WgXcQ",
                site: "YouTube",
                type: "Trailer",
                official: true,
                publishedAt: nil
            )
        )
    }
}
#endif
