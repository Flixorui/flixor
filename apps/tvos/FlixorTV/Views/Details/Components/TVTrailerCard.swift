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
            .shadow(color: .black.opacity(isFocused ? 0.6 : 0.2), radius: isFocused ? 18 : 6, y: isFocused ? 10 : 4)
            .scaleEffect(isFocused ? 1.08 : 1)
        }
        .buttonStyle(NoHighlightButtonStyle())
        .focused($isFocused)
        .animation(.easeOut(duration: 0.18), value: isFocused)
        .onChange(of: isFocused) { newValue in
            if newValue {
                onFocusChange?(true)
            }
        }
    }
}

private struct NoHighlightButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
