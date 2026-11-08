//
//  HoverPreviewTrailer.swift
//  FlixorMac
//
//  Inline YouTube trailer for the hover preview. The player is created with
//  autoplay off; once it is ready it is muted (if asked) and only then started,
//  so muted mode never leaks sound. It stays invisible until it is actually
//  playing, so the backdrop shows while YouTube loads. Removing the view tears
//  the web view down, which stops playback.
//

import SwiftUI
import YouTubePlayerKit

struct HoverPreviewTrailer: View {
    @Binding var isMuted: Bool
    @Binding var isPlaying: Bool

    @StateObject private var player: YouTubePlayer
    @State private var didStart = false

    init(videoKey: String, isMuted: Binding<Bool>, isPlaying: Binding<Bool>) {
        _isMuted = isMuted
        _isPlaying = isPlaying
        _player = StateObject(wrappedValue: YouTubePlayer(
            source: .video(id: videoKey),
            parameters: .init(
                autoPlay: false,
                loopEnabled: false,
                showControls: false,
                showFullscreenButton: false,
                keyboardControlsDisabled: true,
                showCaptions: false,
                restrictRelatedVideosToSameChannel: true
            )
        ))
    }

    var body: some View {
        YouTubePlayerView(player) { _ in EmptyView() }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onReceive(player.statePublisher) { state in
                guard state == .ready, !didStart else { return }
                didStart = true
                Task { await startPlayback() }
            }
            .onReceive(player.playbackStatePublisher) { state in
                switch state {
                case .playing: isPlaying = true
                case .ended, .unstarted: isPlaying = false
                default: break
                }
            }
            .onChange(of: isMuted) { muted in
                Task {
                    if muted { try? await player.mute() } else { try? await player.unmute() }
                }
            }
            .onDisappear {
                isPlaying = false
                Task { try? await player.stop() }
            }
    }

    private func startPlayback() async {
        if isMuted {
            try? await player.mute()
        } else {
            try? await player.unmute()
        }
        try? await player.play()
    }
}
