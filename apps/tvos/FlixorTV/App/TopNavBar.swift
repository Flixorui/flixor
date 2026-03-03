import SwiftUI

struct TopNavBar: View {
    @Binding var selected: MainTVDestination
    var onProfileTapped: () -> Void
    var onSearchTapped: () -> Void

    @Environment(\.tvThemePalette) private var theme
    @Environment(\.tvTypography) private var typography
    @FocusState private var focusedTab: MainTVDestination?
    @State private var profileFocused = false
    @State private var searchFocused = false

    // Netflix-style center tabs; Search moved to icon, Settings moved to profile
    private let tabs: [MainTVDestination] = [.home, .shows, .movies, .myList]

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Left cluster: Profile + Search icons
            HStack(spacing: 18) {
                IconButton(systemName: "person.crop.circle.fill", focused: $profileFocused) {
                    onProfileTapped()
                }
                IconButton(systemName: "magnifyingglass", focused: $searchFocused) {
                    onSearchTapped()
                }
            }
            .padding(.leading, 0)

            Spacer(minLength: 40)

            // Center tabs with pill selection
            HStack(spacing: 24) {
                ForEach(tabs, id: \.self) { tab in
                    NavPill(title: tab.title, isSelected: tab == selected, isFocused: focusedTab == tab)
                        .focusable(true) { focused in
                            if focused { focusedTab = tab }
                        }
                        .focused($focusedTab, equals: tab)
                        .simultaneousGesture(
                            TapGesture().onEnded { selected = tab }
                        )
                }
            }

            Spacer(minLength: 40)

            // Right side - Brand glyph
            Text("F")
                .font(typography.custom(size: 32, weight: .black))
                .foregroundStyle(theme.accent)
                .padding(.trailing, 0)
        }
        .frame(height: 92)
        .background(.clear)
        .focusSection()
        .onAppear { focusedTab = selected }
        .onChange(of: selected) { newValue in
            // Keep visual focus aligned when selected tab changes externally.
            if tabs.contains(newValue) && focusedTab != newValue {
                focusedTab = newValue
            }
        }
    }
}

private struct NavPill: View {
    let title: String
    let isSelected: Bool
    let isFocused: Bool

    @Environment(\.tvThemePalette) private var theme
    @Environment(\.tvTypography) private var typography

    var body: some View {
        let backgroundColor: Color = {
            if isSelected && isFocused {
                return theme.accent
            } else if isSelected || isFocused {
                return isSelected ? theme.focusFill : theme.surfaceGlass
            } else {
                return Color.clear
            }
        }()

        let textColor: Color = {
            if isSelected && isFocused {
                return theme.background
            } else if isFocused {
                return theme.textPrimary
            } else {
                return theme.textSecondary
            }
        }()

        Text(title)
            .font(typography.nav)
            .foregroundStyle(textColor)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(Capsule(style: .circular).fill(backgroundColor))
            .overlay(
                Capsule(style: .circular)
                    .stroke(isFocused && !isSelected ? theme.focusRing.opacity(0.75) : .clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .scaleEffect(isFocused ? UX.focusScale : 1.0)
            .shadow(color: .black.opacity(isFocused ? 0.35 : 0.0), radius: 12, y: 4)
            .animation(.easeOut(duration: UX.focusDur), value: isFocused)
    }
}

private struct IconButton: View {
    let systemName: String
    @Binding var focused: Bool
    var action: () -> Void

    @Environment(\.tvThemePalette) private var theme

    var body: some View {
        Image(systemName: systemName)
            .foregroundStyle(theme.textPrimary)
            .font(.system(size: 26, weight: .semibold))
            .frame(width: 48, height: 48)
            .background(Circle().fill(focused ? theme.focusFill : theme.surfaceMuted))
            .overlay(Circle().stroke(focused ? theme.focusRing : theme.strokeDefault, lineWidth: focused ? 1.5 : 1))
            .scaleEffect(focused ? UX.focusScale : 1.0)
            .animation(.easeOut(duration: UX.focusDur), value: focused)
            .focusable(true) { f in focused = f }
            .onTapGesture { action() }
    }
}
