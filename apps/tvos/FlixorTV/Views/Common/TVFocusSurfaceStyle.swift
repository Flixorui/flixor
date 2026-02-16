import SwiftUI

struct TVFocusSurfaceStyle: ViewModifier {
    var isFocused: Bool
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(isFocused ? Color.white.opacity(0.78) : Color.white.opacity(0.12), lineWidth: isFocused ? 3 : 1)
            )
            .scaleEffect(isFocused ? UX.focusScale : 1.0)
            .shadow(color: .black.opacity(isFocused ? 0.45 : 0.22), radius: isFocused ? 18 : 8, y: isFocused ? 9 : 4)
            .animation(.easeOut(duration: UX.focusDur), value: isFocused)
    }
}

extension View {
    func tvFocusSurface(isFocused: Bool, cornerRadius: CGFloat = 16) -> some View {
        modifier(TVFocusSurfaceStyle(isFocused: isFocused, cornerRadius: cornerRadius))
    }
}
