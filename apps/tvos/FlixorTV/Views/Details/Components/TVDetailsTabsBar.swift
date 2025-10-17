import SwiftUI

struct TVDetailsTabsBar: View {
    let tabs: [DetailsTab]
    @Binding var active: DetailsTab
    var focusNS: Namespace.ID? = nil
    var defaultFocus: Bool = false
    @FocusState private var focused: DetailsTab?

    var body: some View {
        HStack(spacing: 18) {
            ForEach(tabs, id: \.self) { tab in
                Text(tab.rawValue)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(active == tab ? Color.black : Color.white.opacity(focused == tab ? 0.95 : 0.78))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        Capsule(style: .circular)
                            .fill(active == tab ? Color.white : (focused == tab ? Color.white.opacity(0.18) : .clear))
                    )
                    .overlay(
                        Capsule(style: .circular)
                            .stroke(Color.white.opacity(focused == tab && active != tab ? 0.35 : 0.0), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                    .focusable(true) { f in if f { focused = tab } }
                    .focused($focused, equals: tab)
                    .modifier(PreferredFocusModifier(enabled: defaultFocus && active == tab, ns: focusNS))
                    .onTapGesture { active = tab }
                    .scaleEffect(focused == tab ? UX.focusScale : 1.0)
                    .animation(.easeOut(duration: UX.focusDur), value: focused == tab)
            }
            Spacer()
        }
        .padding(.horizontal, 48)
    }
}

private struct PreferredFocusModifier: ViewModifier {
    let enabled: Bool
    let ns: Namespace.ID?
    func body(content: Content) -> some View {
        if let ns, enabled {
            content.prefersDefaultFocus(true, in: ns)
        } else { content }
    }
}
