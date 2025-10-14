import SwiftUI

struct TopNavBar: View {
    @Binding var selected: MainTVView.Tab
    @FocusState private var focusedTab: MainTVView.Tab?

    private let tabs: [MainTVView.Tab] = [.home, .shows, .movies, .myNetflix]

    var body: some View {
        ZStack {
            // Subtle top gradient bar
            LinearGradient(colors: [Color.white.opacity(0.06), Color.black.opacity(0.0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 120)
                .ignoresSafeArea(edges: .top)

            HStack(alignment: .center, spacing: 0) {
                // Left controls
                HStack(spacing: 20) {
                    Circle().fill(Color.white.opacity(0.2))
                        .frame(width: 32, height: 32)
                        .overlay(Image(systemName: "person.crop.circle").foregroundStyle(.white).font(.system(size: 22)))
                        .clipShape(Circle())
                        .padding(.leading, 40)

                    Button(action: { selected = .search }) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 40)

                // Center tabs with pill selection
                HStack(spacing: 26) {
                    ForEach(tabs, id: \.self) { tab in
                        NavPill(title: tab.rawValue, isSelected: tab == selected, isFocused: focusedTab == tab)
                            .focusable(true) { focused in
                                if focused { focusedTab = tab }
                            }
                            .focused($focusedTab, equals: tab)
                            .onTapGesture { selected = tab }
                            .onLongPressGesture(minimumDuration: 0.01) { selected = tab }
                    }
                }

                Spacer(minLength: 40)

                // Right brand placeholder
                Text("N")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.red)
                    .padding(.trailing, 40)
            }
            .frame(height: 92)
        }
        .onAppear { focusedTab = selected }
    }
}

private struct NavPill: View {
    let title: String
    let isSelected: Bool
    let isFocused: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 26, weight: .semibold))
            .foregroundStyle(isSelected ? Color.black : Color.white.opacity(isFocused ? 0.95 : 0.78))
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .circular)
                    .fill(isSelected ? Color.white : (isFocused ? Color.white.opacity(0.18) : Color.clear))
            )
            .overlay(
                Capsule(style: .circular)
                    .stroke(Color.white.opacity(isFocused && !isSelected ? 0.35 : 0.0), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .scaleEffect(isFocused ? 1.06 : 1.0)
            .animation(.easeOut(duration: 0.18), value: isFocused)
    }
}
