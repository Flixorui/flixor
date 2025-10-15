import SwiftUI

struct TopNavBar: View {
    @Binding var selected: MainTVView.Tab
    var onProfileTapped: () -> Void
    var onSearchTapped: () -> Void
    var onMoveDown: () -> Void = {}

    @FocusState private var focusedTab: MainTVView.Tab?
    @State private var profileFocused = false
    @State private var searchFocused = false

    // Netflix-style center tabs; Search moved to icon, Settings moved to profile
    private let tabs: [MainTVView.Tab] = [.home, .shows, .movies, .myNetflix]

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
            .padding(.leading, 50)

            Spacer(minLength: 40)

            // Center tabs with pill selection
            HStack(spacing: 24) {
                ForEach(tabs, id: \.self) { tab in
                    NavPill(title: tab.rawValue, isSelected: tab == selected, isFocused: focusedTab == tab)
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
                .font(.system(size: 32, weight: .black))
                .foregroundStyle(Color.red)
                .padding(.trailing, 50)
        }
        .frame(height: 92)
        .background(.clear)
        .onAppear { focusedTab = selected }
        .onChange(of: focusedTab) { newTab in
            if let newTab = newTab { selected = newTab }
        }
        .onMoveCommand { dir in if dir == .down { onMoveDown() } }
    }
}

private struct NavPill: View {
    let title: String
    let isSelected: Bool
    let isFocused: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(isSelected ? Color.black : Color.white.opacity(isFocused ? 0.95 : 0.78))
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(
                Capsule(style: .circular)
                    .fill(isSelected ? Color.white : (isFocused ? Color.white.opacity(0.18) : Color.clear))
            )
            .overlay(
                Capsule(style: .circular)
                    .stroke(Color.white.opacity(isFocused && !isSelected ? 0.35 : 0.0), lineWidth: 1)
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

    var body: some View {
        Image(systemName: systemName)
            .foregroundStyle(.white)
            .font(.system(size: 26, weight: .semibold))
            .frame(width: 48, height: 48)
            .background(Circle().fill(Color.white.opacity(focused ? 0.18 : 0.12)))
            .overlay(Circle().stroke(Color.white.opacity(focused ? 0.35 : 0.0), lineWidth: 1))
            .scaleEffect(focused ? UX.focusScale : 1.0)
            .animation(.easeOut(duration: UX.focusDur), value: focused)
            .focusable(true) { f in focused = f }
            .onTapGesture { action() }
    }
}
