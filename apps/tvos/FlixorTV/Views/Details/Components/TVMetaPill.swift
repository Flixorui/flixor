import SwiftUI

struct TVMetaPill: View {
    let text: String
    var isFocusable: Bool = false
    @State private var focused: Bool = false

    private var palette: (background: Color, foreground: Color, border: Color?) {
        switch text.lowercased() {
        case "plex":
            return (Color.white.opacity(0.18), Color.white, nil)
        case "no local source":
            return (Color.red.opacity(0.7), Color.white, nil)
        default:
            return (Color.white.opacity(0.18), Color.white, Color.white.opacity(0.2))
        }
    }

    var body: some View {
        let colors = palette
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isFocusable && focused ? Color.white.opacity(0.22) : colors.background)
            )
            .overlay(
                Group {
                    if let border = colors.border {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isFocusable && focused ? Color.white.opacity(0.85) : border, lineWidth: isFocusable && focused ? 2 : 1)
                    }
                }
            )
            .foregroundStyle(colors.foreground)
            .scaleEffect(isFocusable && focused ? 1.06 : 1.0)
            .animation(.easeOut(duration: 0.18), value: focused)
            .focusable(isFocusable) { f in focused = f }
    }
}
