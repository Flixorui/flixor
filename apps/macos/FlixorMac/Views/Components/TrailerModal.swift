//
//  TrailerModal.swift
//  FlixorMac
//
//  Modal for playing YouTube trailers using YouTubePlayerKit
//

import SwiftUI
import YouTubePlayerKit

// MARK: - Trailer Modal

struct TrailerModal: View {
    let trailer: Trailer
    var onClose: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

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
                    VStack(alignment: .leading, spacing: 4) {
                        Text(trailer.name)
                            .font(.headline)
                            .foregroundStyle(.white)

                        Text(trailer.type)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    Spacer()

                    // Close button
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(Color.black.opacity(0.6))

                // Video player
                if trailer.site.lowercased() == "youtube" {
                    YouTubePlayerView(
                        YouTubePlayer(
                            source: .video(id: trailer.key),
                            parameters: .init(autoPlay: true)
                        )
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Fallback if not YouTube
                    VStack(spacing: 16) {
                        Image(systemName: "play.slash")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)

                        Text("Unable to play trailer")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        if let youtubeURL = trailer.youtubeURL {
                            Link(destination: youtubeURL) {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.up.right.square")
                                    Text("Open in Browser")
                                }
                                .font(.subheadline)
                                .foregroundStyle(.blue)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                }
            }
            .frame(width: 960, height: 600)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 30)
        }
    }

    private func close() {
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
