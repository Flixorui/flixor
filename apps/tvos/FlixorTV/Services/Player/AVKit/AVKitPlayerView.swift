//
//  AVKitPlayerView.swift
//  FlixorTV
//
//  SwiftUI wrapper for AVPlayerViewController
//

import SwiftUI
import AVKit

struct AVKitPlayerView: UIViewControllerRepresentable {
    let controller: AVKitPlayerController

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let playerVC = AVPlayerViewController()
        playerVC.player = controller.player

        // Configure for tvOS
        playerVC.showsPlaybackControls = true  // Native tvOS controls
        playerVC.allowsPictureInPicturePlayback = true

        // Note: tvOS automatically handles display mode switching for 4K HDR
        // AVPlayer will request the appropriate display mode based on content

        // Configure audio session
        configureAudioSession()

        print("✅ [AVKitView] Player view controller created")
        return playerVC
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // No updates needed - player is managed by controller
    }

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: ()) {
        print("🛑 [AVKitView] Player view controller dismantled")
        uiViewController.player?.pause()
    }

    // MARK: - Audio Session

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .moviePlayback,
                options: [.allowAirPlay, .allowBluetoothA2DP]
            )
            try AVAudioSession.sharedInstance().setActive(true)
            print("✅ [AVKitView] Audio session configured for playback")
        } catch {
            print("⚠️ [AVKitView] Failed to configure audio session: \(error)")
        }
    }
}
