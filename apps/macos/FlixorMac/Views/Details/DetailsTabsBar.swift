//
//  DetailsTabsBar.swift
//  FlixorMac
//
//  Sticky tabs bar to match web DetailsTabs
//

import SwiftUI

struct DetailsTab: Identifiable, Equatable {
    let id: String
    let label: String
    let count: Int?
}

struct DetailsTabsBar: View {
    let tabs: [DetailsTab]
    @Binding var activeTab: String
    @Namespace private var underline
    @State private var hoveredTab: String?

    var body: some View {
        HStack(alignment: .bottom, spacing: DS.Space.s32) {
            HStack(alignment: .bottom, spacing: DS.Space.s32){
                ForEach(tabs) { tab in
                    TabButton(
                        tab: tab,
                        isActive: activeTab == tab.id,
                        isHovered: hoveredTab == tab.id,
                        underlineNamespace: underline,
                        onTap: { withAnimation(DS.Motion.standard) { activeTab = tab.id } },
                        onHover: { hovering in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                hoveredTab = hovering ? tab.id : nil
                            }
                        }
                    )
                }
            }.padding(.horizontal, DS.Space.s20)
            Spacer()
        }
        .padding(.vertical, DS.Space.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial.opacity(0.6))
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1),
            alignment: .bottom
        )
    }
}

// MARK: - Tab Button Component
private struct TabButton: View {
    let tab: DetailsTab
    let isActive: Bool
    let isHovered: Bool
    let underlineNamespace: Namespace.ID
    let onTap: () -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: DS.Space.s8) {
                    Text(tab.label)
                        .font(.flixor(.body, weight: .medium))
                        .foregroundStyle(textColor)

                    if let count = tab.count {
                        Text("(\(count))")
                            .font(.flixor(.footnote))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .fixedSize()
                .padding(.bottom, DS.Space.s8)

                // Underline indicator
                if isActive {
                    Rectangle()
                        .fill(Color.white)
                        .frame(height: 2)
                        .matchedGeometryEffect(id: "underline", in: underlineNamespace)
                } else {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 2)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover(perform: onHover)
    }

    private var textColor: Color {
        if isActive {
            return .white
        } else if isHovered {
            return .white.opacity(0.8)
        } else {
            return .white.opacity(0.5)
        }
    }
}
