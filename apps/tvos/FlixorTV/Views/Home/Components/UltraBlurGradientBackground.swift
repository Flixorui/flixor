import SwiftUI
import FlixorKit

struct UltraBlurGradientBackground: View {
    let colors: UltraBlurColors
    var opacity: Double = 0.85

    init(colors: UltraBlurColors, opacity: Double = 0.85) {
        self.colors = colors
        self.opacity = opacity
    }

    var body: some View {
        ZStack {
            // Top half gradient
            LinearGradient(
                stops: [
                    .init(color: hexToColor(colors.topLeft), location: 0.0),
                    .init(color: hexToColor(colors.topRight), location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(maxHeight: .infinity, alignment: .top)

            // Bottom half gradient
            VStack(spacing: 0) {
                Color.clear
                LinearGradient(
                    stops: [
                        .init(color: hexToColor(colors.bottomLeft), location: 0.0),
                        .init(color: hexToColor(colors.bottomRight), location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }

            // Vertical blend overlay
            LinearGradient(
                stops: [
                    .init(color: hexToColor(colors.topLeft).opacity(0.6), location: 0.0),
                    .init(color: Color.clear, location: 0.5),
                    .init(color: hexToColor(colors.bottomLeft).opacity(0.6), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .compositingGroup()
        .opacity(opacity)
        .blur(radius: 120)
        .drawingGroup()
        .ignoresSafeArea()
    }

    private func hexToColor(_ hex: String) -> Color {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)

        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0

        return Color(red: r, green: g, blue: b)
    }
}

// Preview helper
#if DEBUG
struct UltraBlurGradientBackground_Previews: PreviewProvider {
    static var previews: some View {
        UltraBlurGradientBackground(
            colors: UltraBlurColors(
                topLeft: "2c2d33",
                topRight: "0b0209",
                bottomRight: "0b090b",
                bottomLeft: "19191b"
            )
        )
    }
}
#endif
