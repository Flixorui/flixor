import SwiftUI
import FlixorKit

struct TVBillboardView: View {
    let item: MediaItem
    var focusNS: Namespace.ID? = nil
    var defaultFocus: Bool = false

    @State private var showingDetails: MediaItem?

    // Hero focus state
    enum HeroButton: Hashable { case play, moreInfo, myList }
    @FocusState private var focusedButton: HeroButton?
    @State private var isHeroFocused: Bool = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Backdrop
            TVImage(
                url: ImageService.shared.artURL(for: item, width: 1920, height: 1080),
                corner: UX.billboardRadius,
                height: 800
            )
            .overlay(
                // 3-stop gradient per spec: 0.55 → 0.1 → 0 alpha
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color.black.opacity(0.65), location: 0.0),
                        .init(color: Color.black.opacity(0.18), location: 0.55),
                        .init(color: .clear, location: 1.0)
                    ]),
                    startPoint: .bottom,
                    endPoint: .top
                )
                .clipShape(RoundedRectangle(cornerRadius: UX.billboardRadius, style: .continuous))
            )
            .overlay(
                // Subtle outer stroke to lift the billboard
                RoundedRectangle(cornerRadius: UX.billboardRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 18, y: 8)

            // Text + actions
            VStack(alignment: .leading, spacing: 14) {
                // Display clear logo if available, otherwise fallback to text title
                if let logoURL = item.logo, let url = URL(string: logoURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 500, maxHeight: 140, alignment: .leading)
                                .shadow(color: .black.opacity(0.8), radius: 12, x: 0, y: 4)
                        case .failure, .empty:
                            // Fallback to text if logo fails to load
                            Text(item.title)
                                .font(.system(size: 56, weight: .bold))
                                .lineLimit(2)
                        @unknown default:
                            Text(item.title)
                                .font(.system(size: 56, weight: .bold))
                                .lineLimit(2)
                        }
                    }
                } else {
                    // No logo available, use text title
                    Text(item.title)
                        .font(.system(size: 56, weight: .bold))
                        .lineLimit(2)
                }

                MetaLine(item: item)
                    .font(.system(size: 22, weight: .medium))
                    .opacity(0.9)

                if let summary = item.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 22))
                        .opacity(0.85)
                        .lineLimit(3)
                        .frame(maxWidth: 1000, alignment: .leading)
                }

                HStack(spacing: 16) {
                    CTAButton(title: item.viewOffset != nil ? "Resume" : "Play", systemName: "play.fill", style: .secondary, isDefaultFocusTarget: true, focusNS: focusNS)
                        .focused($focusedButton, equals: .play)
                        .applyDefaultBillboardFocus(ns: focusNS, enabled: true)

                    CTAButton(title: "More Info", systemName: "info.circle", style: .secondary)
                        .focused($focusedButton, equals: .moreInfo)
                        .onTapGesture { showingDetails = item }

                    CTAButton(title: "My List", systemName: "plus", style: .secondary)
                        .focused($focusedButton, equals: .myList)
                }
                .offset(y: isHeroFocused ? 0 : 50)
                .opacity(isHeroFocused ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.3).delay(isHeroFocused ? 0.1 : 0), value: isHeroFocused)
                .focusSection()
                .padding(.top, 8)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 20)
        }
        .overlay(
            RoundedRectangle(cornerRadius: UX.billboardRadius, style: .continuous)
                .stroke(Color.white.opacity(isHeroFocused ? 0.35 : 0.0), lineWidth: 3)
        )
        .animation(.easeInOut(duration: 0.3), value: isHeroFocused)
        .padding(.horizontal, UX.billboardSide)
        .frame(height: 820)
        .focusSection()
        .fullScreenCover(item: $showingDetails) { item in
            TVDetailsView(item: item)
        }
        .onChange(of: focusedButton) { newValue in
            isHeroFocused = (newValue != nil)
        }
        .preference(key: BillboardFocusKey.self, value: focusedButton != nil)
    }
}

// Preference key to report billboard focus state
struct BillboardFocusKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

// MARK: - Metadata line with separators
private struct MetaLine: View {
    let item: MediaItem

    enum Segment: Hashable { case year(Int), duration(Int), rating(Double) }

    var segments: [Segment] {
        var s: [Segment] = []
        if let y = item.year { s.append(.year(y)) }
        if let d = item.duration, d > 0 { s.append(.duration(d)) }
        if let r = item.rating, r > 0 { s.append(.rating(r)) }
        return s
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(segments.enumerated()), id: \.offset) { idx, seg in
                HStack(spacing: 6) {
                    switch seg {
                    case .year(let y): Text(String(y))
                    case .duration(let d): Text("\(d / 60000)m")
                    case .rating(let r): HStack(spacing: 4) {
                        Image(systemName: "star.fill").font(.system(size: 16))
                        Text(String(format: "%.1f", r))
                    }
                    }
                    if idx < segments.count - 1 { Text("•").opacity(0.7) }
                }
            }
        }
    }
}

private struct CTAButton: View {
    enum Style { case primary, secondary }
    let title: String
    let systemName: String
    let style: Style
    var isDefaultFocusTarget: Bool = false
    var focusNS: Namespace.ID? = nil

    @State private var focused = false

    // Computed property for background color
    private var backgroundColor: Color {
        if focused {
            return Color.white  // Full white when focused
        } else if style == .primary {
            return Color.white.opacity(0.55)  // 55% white when primary but not focused
        } else {
            return Color.white.opacity(focused ? 0.18 : 0.10)  // 10-18% white for secondary
        }
    }

    // Computed property for text color
    private var textColor: Color {
        if focused {
            return Color.black  // Black when focused (any button)
        } else if style == .primary {
            return Color.black  // Black for primary when not focused
        } else {
            return Color.white.opacity(0.85)  // Dimmed white for secondary when not focused
        }
    }

    // Show stroke only when focused
    private var strokeOpacity: Double {
        focused ? 0.4 : 0.0
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemName)
            Text(title)
        }
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(textColor)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Capsule().fill(backgroundColor))
        .overlay(Capsule().stroke(Color.white.opacity(strokeOpacity), lineWidth: 2))
        .focusable(true) { focused in self.focused = focused }
        .modifier(PreferredDefaultFocusModifier(enabled: isDefaultFocusTarget, ns: focusNS))
        .scaleEffect(focused ? UX.focusScale : 1.0)
        .shadow(color: .black.opacity(focused ? 0.35 : 0.0), radius: 12, y: 4)
        .animation(.easeOut(duration: 0.18), value: focused)
    }
}

private struct PreferredDefaultFocusModifier: ViewModifier {
    let enabled: Bool
    let ns: Namespace.ID?
    func body(content: Content) -> some View {
        if let ns, enabled {
            content.prefersDefaultFocus(true, in: ns)
        } else {
            content
        }
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
