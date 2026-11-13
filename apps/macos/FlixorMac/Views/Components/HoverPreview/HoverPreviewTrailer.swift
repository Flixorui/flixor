//
//  HoverPreviewTrailer.swift
//  FlixorMac
//
//  Inline trailer for the hover preview. TrailerPlayer plays it natively when
//  a direct stream is found, and in the YouTube embed otherwise. It starts muted
//  (if asked) before playback begins, so muted mode never leaks sound, and stays
//  invisible until it is actually playing, so the backdrop shows while it loads.
//  Removing the view stops playback and releases the player.
//

import SwiftUI

struct HoverPreviewTrailer: View {
    @Binding var isMuted: Bool
    @Binding var isPlaying: Bool

    @StateObject private var player: TrailerPlayer

    /// The card is small; starting on 720p loads faster and looks the same.
    private static let maxHeight = 720
    /// The embed is 16:9 with a little chrome at the edges; overscan to hide it.
    private static let embedOverscan: CGFloat = 1.02

    init(trailer: Trailer, isMuted: Binding<Bool>, isPlaying: Binding<Bool>) {
        _isMuted = isMuted
        _isPlaying = isPlaying
        var options = TrailerPlayer.Options()
        options.maxHeight = Self.maxHeight
        options.forwardBufferSeconds = 20
        _player = StateObject(wrappedValue: TrailerPlayer(
            trailer: trailer,
            muted: isMuted.wrappedValue,
            options: options
        ))
    }

    var body: some View {
        TrailerVideoSurface(player: player, fill: true, embedOverscan: Self.embedOverscan)
            .onAppear { player.load() }
            .onReceive(player.$status) { status in
                if status == .ready { player.play() }
            }
            .onReceive(player.$playback) { state in
                switch state {
                case .playing: isPlaying = true
                case .ended, .idle: isPlaying = false
                case .paused: break
                }
            }
            .onChange(of: isMuted) { muted in
                player.setMuted(muted)
            }
            .onDisappear {
                isPlaying = false
                player.stop()
            }
    }
}
