//
//  MPVTestPlayerView.swift
//  FlixorTV
//
//  Simple test view for MPV rendering pipeline
//  Tests OpenGL ES + IOSurface + Metal without Plex integration
//

import SwiftUI

struct MPVTestPlayerView: View {
    @State private var controller: MPVPlayerController?
    @State private var isLoaded = false
    @State private var errorMessage: String?

    // Test video URLs
    private let testVideos = [
        ("1080p Sample", "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"),
        ("1080p Sample 2", "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4"),
        ("1080p 10s", "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/1080/Big_Buck_Bunny_1080_10s_10MB.mp4"),
        ("4K Plex Test", "http://192.168.51.14:32400/library/parts/9080859/1708414370/file.mkv?X-Plex-Token=yFGyeFjjZwavbUGiAzs9")
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if !isLoaded {
                VStack(spacing: 40) {
                    Text("MPV Rendering Pipeline Test")
                        .font(.title)
                        .foregroundColor(.white)

                    ForEach(Array(testVideos.enumerated()), id: \.offset) { index, video in
                        Button(action: {
                            loadVideo(video.1)
                        }) {
                            VStack {
                                Text(video.0)
                                    .font(.headline)
                                Text(video.1.split(separator: "/").last.map(String.init) ?? "")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }
                            .padding()
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
            } else if let controller = controller {
                // Show MPV video view
                MPVMetalViewRepresentable(controller: controller)
                    .ignoresSafeArea()

                // Simple overlay with basic info
                VStack {
                    HStack {
                        Button(action: {
                            controller.shutdown()
                            self.controller = nil
                            isLoaded = false
                            errorMessage = nil
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white)
                        }
                        .padding()

                        Spacer()
                    }

                    Spacer()

                    // Playback controls
                    HStack(spacing: 60) {
                        Button(action: {
                            controller.command("cycle pause")
                        }) {
                            Image(systemName: "playpause.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.white)
                        }

                        Button(action: {
                            controller.command("seek -10")
                        }) {
                            Image(systemName: "gobackward.10")
                                .font(.system(size: 40))
                                .foregroundColor(.white)
                        }

                        Button(action: {
                            controller.command("seek 10")
                        }) {
                            Image(systemName: "goforward.10")
                                .font(.system(size: 40))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.bottom, 60)
                }
            }
        }
        .onAppear {
            print("🧪 [Test] MPV Test View appeared")
        }
    }

    private func loadVideo(_ urlString: String) {
        print("🧪 [Test] Loading video: \(urlString)")
        errorMessage = nil

        // Create a new MPV controller
        let newController = MPVPlayerController()
        self.controller = newController

        // Give it a moment to initialize, then load the video
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            newController.loadFile(urlString)

            // Show the player view
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isLoaded = true
                print("🧪 [Test] Video loaded, rendering should begin")
            }
        }
    }
}

struct MPVMetalViewRepresentable: UIViewRepresentable {
    let controller: MPVPlayerController

    func makeUIView(context: Context) -> MPVUIView {
        print("🧪 [Test] Creating MPVUIView")
        let view = MPVUIView()
        // Setup will happen when the view is laid out with valid bounds
        view.setupMPVRendering(controller: controller)
        return view
    }

    func updateUIView(_ uiView: MPVUIView, context: Context) {
        // No updates needed
    }

    static func dismantleUIView(_ uiView: MPVUIView, coordinator: ()) {
        print("🧪 [Test] Dismantling MPVUIView")
        // Stop rendering but don't shutdown MPV controller (parent view manages that)
        uiView.stopRendering()
    }
}

#Preview {
    MPVTestPlayerView()
}
