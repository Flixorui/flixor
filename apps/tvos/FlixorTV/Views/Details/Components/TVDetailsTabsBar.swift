import SwiftUI

struct TVDetailsTabsBar: View {
    let tabs: [DetailsTab]
    @Binding var active: DetailsTab
    @Binding var reportFocus: Bool
    @FocusState private var focused: DetailsTab?
    @State private var previousFocused: DetailsTab? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing:80) {
                ForEach(tabs, id: \.self) { tab in
                    tabButton(for: tab)
                }
                Spacer()
            }
            .padding(.horizontal, 0)
            .padding(.bottom, 5)

            baseline
        }
        .padding(.top, 12)
        .onChange(of: focused) { newTab in
            reportFocus = (newTab != nil)

            guard let newTab = newTab else {
                previousFocused = nil
                return
            }

            if previousFocused == nil && newTab != active {
                // When entering the tabs from above/below, ensure focus lands on current selection.
                print("🎯 [TVDetailsTabsBar] Correcting focus to active tab: \(active.rawValue)")
                DispatchQueue.main.async {
                    focused = active
                }
            } else {
                active = newTab
            }

            previousFocused = newTab
        }
    }

    @ViewBuilder
    private func tabButton(for tab: DetailsTab) -> some View {
        let isSelected = active == tab
        let isFocused = focused == tab

        Text(tab.rawValue.uppercased())
            .font(.system(size: 26, weight: isSelected ? .bold : .semibold))
            .kerning(1.2)
            .foregroundStyle(labelColor(isSelected: isSelected, isFocused: isFocused))
            .fixedSize(horizontal: true, vertical: true)
            .contentShape(Rectangle())
            .focusable(true) { focused in
                if focused { self.focused = tab }
            }
            .focused($focused, equals: tab)
            .onTapGesture { active = tab }
    }

    private func labelColor(isSelected: Bool, isFocused: Bool) -> Color {
        switch (isSelected, isFocused) {
        case (true, _):
            return .white
        case (false, true):
            return Color.white.opacity(0.8)
        default:
            return Color.white.opacity(0.55)
        }
    }

    private var baseline: some View {
        Capsule()
            .fill(Color.white.opacity(0.12))
            .frame(height: 2)
            .padding(.horizontal, 0)
    }
}
