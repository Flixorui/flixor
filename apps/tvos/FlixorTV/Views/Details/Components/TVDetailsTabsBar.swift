import SwiftUI

struct TVDetailsTabsBar: View {
    let tabs: [DetailsTab]
    @Binding var active: DetailsTab
    var focusNS: Namespace.ID? = nil
    @Binding var reportFocus: Bool
    @FocusState private var focused: DetailsTab?
    @State private var previousFocused: DetailsTab? = nil

    var body: some View {
        HStack(spacing: 18) {
            ForEach(tabs, id: \.self) { tab in
                let isSelected = active == tab
                let isFocused = focused == tab

                let backgroundColor: Color = {
                    if isSelected && isFocused {
                        return Color.white  // Selected + Focused: White 100%
                    } else if isSelected || isFocused {
                        return Color.white.opacity(0.18)  // Selected OR Focused: White 18%
                    } else {
                        return Color.clear  // Default: No background
                    }
                }()

                let textColor: Color = {
                    if isSelected && isFocused {
                        return Color.black  // Selected + Focused: Black text
                    } else if isFocused {
                        return Color.white.opacity(0.95)  // Focused only: Bright white
                    } else {
                        return Color.white.opacity(0.78)  // Default: Dimmed white
                    }
                }()

                Text(tab.rawValue)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(textColor)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule(style: .circular).fill(backgroundColor))
                    .overlay(
                        Capsule(style: .circular)
                            .stroke(Color.white.opacity(isFocused && !isSelected ? 0.35 : 0.0), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                    .focusable(true) { f in if f { focused = tab } }
                    .focused($focused, equals: tab)
                    .onTapGesture { active = tab }
                    .scaleEffect(isFocused ? UX.focusScale : 1.0)
                    .shadow(color: .black.opacity(isFocused ? 0.35 : 0.0), radius: 12, y: 4)
                    .animation(.easeOut(duration: UX.focusDur), value: isFocused)
            }
            Spacer()
        }
        .padding(.horizontal, 48)
        .onChange(of: focused) { newTab in
            // Report focus state to parent
            reportFocus = (newTab != nil)

            if let newTab = newTab {
                // Only correct focus when ENTERING tabs section (previousFocused was nil)
                // Don't interfere with horizontal navigation within tabs
                if previousFocused == nil && newTab != active {
                    // tvOS landed on wrong tab due to horizontal position matching
                    // Correct it to the active tab
                    print("🎯 [TVDetailsTabsBar] Entering tabs, correcting focus from \(newTab.rawValue) to \(active.rawValue)")
                    DispatchQueue.main.async {
                        focused = active
                    }
                } else {
                    // Normal horizontal navigation - update active tab
                    active = newTab
                }
            }

            previousFocused = newTab
        }
    }
}
