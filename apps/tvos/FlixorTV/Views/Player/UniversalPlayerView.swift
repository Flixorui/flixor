//
//  UniversalPlayerView.swift
//  FlixorTV
//
//  Universal player view with AVKit/MPV backend toggle
//

import SwiftUI

struct UniversalPlayerView: View {
    @StateObject private var playerSettings = PlayerSettings()
    @State private var avkitController: AVKitPlayerController?
    @State private var mpvController: MPVPlayerController?
    @State private var isLoaded = false
    @State private var errorMessage: String?

    // Test video URLs
    private let testVideos = [
        ("MP4 1080p (DirectPlay)", "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"),
        ("MP4 Sample 2", "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4"),
        ("4K Plex MKV (DirectStream)", "http://192.168.51.14:32400/library/metadata/9080859?X-Plex-Token=yFGyeFjjZwavbUGiAzs9"),
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if !isLoaded {
                VStack(spacing: 40) {
                    Text("Flixor Player Test")
                        .font(.title)
                        .foregroundColor(.white)

                    // Player backend selector
                    VStack(spacing: 16) {
                        Text("Player Backend")
                            .font(.headline)
                            .foregroundColor(.white)

                        Picker("Backend", selection: $playerSettings.backend) {
                            ForEach(PlayerBackend.allCases, id: \.self) { backend in
                                Text(backend.rawValue)
                                    .tag(backend)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 100)

                        // Show backend details
                        VStack(spacing: 8) {
                            Text(playerSettings.backend.description)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.9))

                            Text(playerSettings.backend.detailedDescription)
                                .font(.caption)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 50)
                    }

                    // Test videos
                    ForEach(Array(testVideos.enumerated()), id: \.offset) { index, video in
                        Button(action: {
                            loadVideo(video.1)
                        }) {
                            VStack(spacing: 8) {
                                Text(video.0)
                                    .font(.headline)
                                Text(video.1.split(separator: "/").last.map(String.init) ?? "")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }
                            .padding()
                            .frame(width: 600)
                            .background(Color.blue)
                            .cornerRadius(10)
                        }
                    }

                    if let error = errorMessage {
                        Text("Error: \(error)")
                            .foregroundColor(.red)
                            .padding()
                    }
                }
            } else {
                // Show appropriate player view
                if playerSettings.backend == .avkit, let controller = avkitController {
                    AVKitPlayerView(controller: controller)
                        .ignoresSafeArea()
                } else if playerSettings.backend == .mpv, let controller = mpvController {
                    MPVMetalView(mpvController: controller)
                        .ignoresSafeArea()
                }

                // Back button overlay
                VStack {
                    HStack {
                        Button(action: {
                            cleanup()
                            isLoaded = false
                            errorMessage = nil
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
        }
        .onAppear {
            print("🧪 [Test] Universal Player View appeared")
        }
    }

    private func loadVideo(_ urlString: String) {
        print("🧪 [Test] Loading video with \(playerSettings.backend.rawValue): \(urlString)")
        errorMessage = nil

        switch playerSettings.backend {
        case .avkit:
            let controller = AVKitPlayerController()
            self.avkitController = controller

            // Set up callbacks
            controller.onEvent = { event in
                print("🎬 [Test/AVKit] Event: \(event)")
            }

            controller.onHDRDetected = { isHDR, gamma, primaries in
                if isHDR {
                    print("🌈 [Test/AVKit] HDR Detected! Gamma: \(gamma ?? "unknown"), Primaries: \(primaries ?? "unknown")")
                } else {
                    print("📺 [Test/AVKit] SDR Content")
                }
            }

            controller.loadFile(urlString)

        case .mpv:
            let controller = MPVPlayerController()
            self.mpvController = controller

            // Set up callbacks
            controller.onEvent = { event in
                print("🎬 [Test/MPV] Event: \(event)")
            }

            controller.onHDRDetected = { isHDR, gamma, primaries in
                if isHDR {
                    print("🌈 [Test/MPV] HDR Detected! Gamma: \(gamma ?? "unknown"), Primaries: \(primaries ?? "unknown")")
                } else {
                    print("📺 [Test/MPV] SDR Content")
                }
            }

            // MPV needs a delay for view setup
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                controller.loadFile(urlString)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isLoaded = true
            print("🧪 [Test] Player view loaded")
        }
    }

    private func cleanup() {
        print("🧹 [Test] Cleaning up player")

        avkitController?.shutdown()
        avkitController = nil

        mpvController?.shutdown()
        mpvController = nil
    }
}

#Preview {
    UniversalPlayerView()
}
