import SwiftUI

struct TVTrailerModal: View {
    let trailer: TVTrailer
    let onClose: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(trailer.name)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                        Text(trailer.type)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    Spacer()

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(Circle().fill(Color.white.opacity(0.18)))
                    }
                    .buttonStyle(.card)
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 24)

                VStack(spacing: 18) {
                    CachedAsyncImage(url: trailer.thumbnailURL, contentMode: .fit) {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                    }
                    .frame(maxWidth: 960, maxHeight: 540)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Text("Inline trailer playback is unavailable on this tvOS build.")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))
                        .multilineTextAlignment(.center)

                    if let youtubeURL = trailer.youtubeURL {
                        Button(action: {
                            openURL(youtubeURL)
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.up.right.square")
                                Text("Open on YouTube")
                            }
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white))
                        }
                        .buttonStyle(.card)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
        .onExitCommand {
            onClose()
        }
    }
}
