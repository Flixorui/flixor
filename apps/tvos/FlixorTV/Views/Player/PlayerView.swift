//
//  PlayerView.swift
//  FlixorTV
//
//  Player view for actual playback (from details screen)
//

import SwiftUI
import FlixorKit

struct PlayerView: View {
    let item: MediaItem
    @StateObject private var playerSettings = PlayerSettings()
    @State private var avkitController: AVKitPlayerController?
    @State private var mpvController: MPVPlayerController?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Show appropriate player view
            if playerSettings.backend == .avkit, let controller = avkitController {
                AVKitPlayerView(controller: controller)
                    .ignoresSafeArea()
            } else if playerSettings.backend == .mpv, let controller = mpvController {
                MPVPlayerView(coordinator: controller.coordinator)
                    .ignoresSafeArea()
            }

            // Back button overlay
            VStack {
                HStack {
                    Button(action: {
                        cleanup()
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white)
                    }
                    .padding()

                    Spacer()

                    // Show current backend
                    Text(playerSettings.backend.rawValue)
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(8)
                        .padding()
                }

                Spacer()
            }
        }
        .onAppear {
            print("🎬 [PlayerView] Loading item: \(item.id)")
            loadVideo()
        }
        .onDisappear {
            cleanup()
        }
    }

    private func loadVideo() {
        switch playerSettings.backend {
        case .avkit:
            let controller = AVKitPlayerController()
            self.avkitController = controller

            // Set up callbacks
            controller.onEvent = { event in
                print("🎬 [PlayerView/AVKit] Event: \(event)")
            }

            controller.onHDRDetected = { isHDR, gamma, primaries in
                if isHDR {
                    print("🌈 [PlayerView/AVKit] HDR Detected! Gamma: \(gamma ?? "unknown"), Primaries: \(primaries ?? "unknown")")
                } else {
                    print("📺 [PlayerView/AVKit] SDR Content")
                }
            }

            controller.loadFile(item.id)

        case .mpv:
            let controller = MPVPlayerController()
            self.mpvController = controller

            // Set up callbacks
            controller.onEvent = { event in
                print("🎬 [PlayerView/MPV] Event: \(event)")
            }

            controller.onHDRDetected = { isHDR, gamma, primaries in
                if isHDR {
                    print("🌈 [PlayerView/MPV] HDR Detected! Gamma: \(gamma ?? "unknown"), Primaries: \(primaries ?? "unknown")")
                } else {
                    print("📺 [PlayerView/MPV] SDR Content")
                }
            }

            controller.loadFile(item.id)
        }
    }

    private func cleanup() {
        print("🧹 [PlayerView] Cleaning up player")

        avkitController?.shutdown()
        avkitController = nil

        mpvController?.shutdown()
        mpvController = nil
    }
}
