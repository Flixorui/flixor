import SwiftUI

struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = 0
    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [Color.white.opacity(0.05), Color.white.opacity(0.18), Color.white.opacity(0.05)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .mask(content)
                .offset(x: phase)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 240
                }
            }
    }
}

extension View {
    func shimmer() -> some View { modifier(Shimmer()) }
}

