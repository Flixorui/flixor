import SwiftUI

struct TVTrailerCard: View {
    let trailer: TVTrailer
    var onPlay: () -> Void
    var onFocusChange: ((Bool) -> Void)?

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: onPlay) {
            ZStack(alignment: .bottomLeading) {
                CachedAsyncImage(url: trailer.thumbnailURL, contentMode: .fill) {
                    Rectangle().fill(Color.white.opacity(0.08))
                }
                .frame(width: 196, height: 112)
                .clipped()

                LinearGradient(colors: [.clear, Color.black.opacity(0.9)], startPoint: .center, endPoint: .bottom)

                VStack(alignment: .leading, spacing: 4) {
                    Spacer()
                    Text(trailer.type.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.red.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))

                    Text(trailer.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(8)
            }
            .frame(width: 196, height: 112)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(isFocused ? 0.65 : 0.2), lineWidth: isFocused ? 2 : 1)
            )
            .shadow(color: .black.opacity(isFocused ? 0.5 : 0.22), radius: isFocused ? 14 : 7)
            .scaleEffect(isFocused ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .animation(.easeOut(duration: 0.18), value: isFocused)
        .onChange(of: isFocused) { newValue in
            if newValue {
                onFocusChange?(true)
            }
        }
    }
}
