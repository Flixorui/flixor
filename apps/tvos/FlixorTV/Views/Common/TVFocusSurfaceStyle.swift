import SwiftUI

struct TVFocusSurfaceStyle: ViewModifier {
    var isFocused: Bool
    var cornerRadius: CGFloat = 16

    @Environment(\.tvThemePalette) private var theme
    @Environment(\.tvCardVisualTokens) private var cardTokens

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(isFocused ? theme.strokeFocused : theme.strokeDefault, lineWidth: isFocused ? cardTokens.focusedStrokeWidth : 1)
            )
            .scaleEffect(isFocused ? cardTokens.focusedScale : 1.0)
            .shadow(color: .black.opacity(isFocused ? 0.45 : 0.22), radius: isFocused ? 18 : 8, y: isFocused ? 9 : 4)
            .animation(.easeOut(duration: UX.focusDur), value: isFocused)
    }
}

extension View {
    func tvFocusSurface(isFocused: Bool, cornerRadius: CGFloat = 16) -> some View {
        modifier(TVFocusSurfaceStyle(isFocused: isFocused, cornerRadius: cornerRadius))
    }
}
