import Foundation
import SwiftUI

struct MPVPlayerView: UIViewControllerRepresentable {
    let coordinator: Coordinator

    func makeUIViewController(context: Context) -> MPVPlayerViewController {
        let mpv = MPVPlayerViewController(options: coordinator.options)
        mpv.playDelegate = coordinator
        mpv.playUrl = coordinator.playUrl
        mpv.setPlaybackRate(coordinator.playbackRate)

        context.coordinator.player = mpv
        return mpv
    }

    func updateUIViewController(_ uiViewController: MPVPlayerViewController, context _: Context) {
        uiViewController.updateMetalLayerLayout()
    }

    func makeCoordinator() -> Coordinator {
        coordinator
    }

    @MainActor
    final class Coordinator: MPVPlayerDelegate, PlayerCoordinating {
        weak var player: MPVPlayerViewController?

        var playUrl: URL?
        var options = PlayerOptions()
        var playbackRate: Float = 1.0
        var onPropertyChange: ((MPVPlayerViewController, PlayerProperty, Any?) -> Void)?
        var onPlaybackEnded: (() -> Void)?
        var onMediaLoaded: (() -> Void)?

        func setPendingURL(_ url: URL) {
            playUrl = url
        }

        func play(_ url: URL) {
            playUrl = url
            player?.loadFile(url)
        }

        func togglePlayback() {
            player?.togglePause()
        }

        func pause() {
            player?.pause()
        }

        func resume() {
            player?.play()
        }

        func seek(to time: Double) {
            player?.seek(to: time)
        }

        func seek(by delta: Double) {
            player?.seek(by: delta)
        }

        func setPlaybackRate(_ rate: Float) {
            playbackRate = rate
            player?.setPlaybackRate(rate)
        }

        func setVolume(_ volume: Double) {
            player?.setVolume(volume)
        }

        func selectAudioTrack(id: Int?) {
            player?.setAudioTrack(id: id)
        }

        func selectSubtitleTrack(id: Int?) {
            player?.setSubtitleTrack(id: id)
        }

        func trackList() -> [PlayerTrack] {
            player?.trackList() ?? []
        }

        func destruct() {
            player?.destruct()
            player = nil
        }

        func propertyChange(mpv _: OpaquePointer, property: PlayerProperty, data: Any?) {
            guard let player else { return }

            if property == .videoParamsSigPeak {
                let supportsHdr = (data as? Double ?? 1.0) > 1.0
                player.hdrEnabled = supportsHdr
            }
            onPropertyChange?(player, property, data)
        }

        func playbackEnded() {
            onPlaybackEnded?()
        }

        func fileLoaded() {
            player?.setPlaybackRate(playbackRate)
            onMediaLoaded?()
        }
    }
}
