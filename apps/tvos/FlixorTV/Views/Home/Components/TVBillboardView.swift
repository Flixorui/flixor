import SwiftUI
import FlixorKit

struct TVBillboardView: View {
    let item: MediaItem
    var focusNS: Namespace.ID? = nil
    var defaultFocus: Bool = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Backdrop
            TVImage(url: nil, corner: 26, aspect: 16/9)
                .overlay(
                    LinearGradient(colors: [Color.black.opacity(0.55), Color.black.opacity(0.1), Color.clear], startPoint: .bottom, endPoint: .top)
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                )

            // Text + actions
            VStack(alignment: .leading, spacing: 14) {
                Text(item.title)
                    .font(.system(size: 56, weight: .bold))
                HStack(spacing: 16) {
                    Text("Comedy")
                    Text("2014")
                    Text("TV‑14")
                }
                .font(.system(size: 22, weight: .medium))
                .opacity(0.9)

                Text("Committed bachelor Ted recounts how he met his future wife.")
                    .font(.system(size: 22))
                    .opacity(0.85)
                    .lineLimit(2)

                HStack(spacing: 16) {
                    CTAButton(title: "Play", systemName: "play.fill", style: .primary)
                        .applyDefaultBillboardFocus(ns: focusNS, enabled: defaultFocus)
                    CTAButton(title: "More Info", systemName: "info.circle", style: .secondary)
                    CTAButton(title: "My List", systemName: "plus", style: .secondary)
                }
                .padding(.top, 6)
            }
            .foregroundStyle(.white)
            .padding(32)
        }
        .padding(.horizontal, 40)
    }
}

private struct CTAButton: View {
    enum Style { case primary, secondary }
    let title: String
    let systemName: String
    let style: Style

    @State private var focused = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemName)
            Text(title)
        }
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(style == .primary ? Color.black : Color.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(style == .primary ? Color.white : Color.white.opacity(focused ? 0.18 : 0.10))
        )
        .overlay(
            Capsule().stroke(Color.white.opacity(style == .secondary && focused ? 0.35 : 0.0), lineWidth: 1)
        )
        .focusable(true) { focused in self.focused = focused }
        .scaleEffect(focused ? 1.06 : 1.0)
        .animation(.easeOut(duration: 0.18), value: focused)
    }
}

private extension View {
    @ViewBuilder
    func applyDefaultBillboardFocus(ns: Namespace.ID?, enabled: Bool) -> some View {
        if let ns, enabled {
            self.prefersDefaultFocus(true, in: ns)
        } else {
            self
        }
    }
}
