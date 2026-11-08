//
//  HeroPageIndicator.swift
//  FlixorMac
//
//  Page indicator for the home hero (billboard and carousel). The marks stay
//  small, but each one sits in a hit target of at least 24 x 24 pt with hover
//  feedback, a pointing-hand cursor and an accessibility label.
//

import AppKit
import SwiftUI

struct HeroPageIndicator: View {
    enum Style {
        /// Round dots; the current one is slightly larger (billboard).
        case dots
        /// Short bars; the current one stretches into a pill (carousel).
        case bars
    }

    let count: Int
    let currentIndex: Int
    var style: Style = .dots
    let onSelect: (Int) -> Void

    /// Minimum hit target for each mark (HIG minimum for pointer targets).
    static let hitTarget: CGFloat = 24

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                HeroPageIndicatorMark(
                    index: index,
                    count: count,
                    isCurrent: index == currentIndex,
                    style: style,
                    onSelect: { onSelect(index) }
                )
            }
        }
        .padding(.horizontal, DS.Space.s6)
        .padding(.vertical, DS.Space.s2)
        .background(.ultraThinMaterial.opacity(0.4))
        .clipShape(Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Featured items"))
    }
}

private struct HeroPageIndicatorMark: View {
    let index: Int
    let count: Int
    let isCurrent: Bool
    let style: HeroPageIndicator.Style
    let onSelect: () -> Void

    @State private var isHovered = false

    private var markWidth: CGFloat {
        switch style {
        case .dots: return isCurrent ? 10 : 8
        case .bars: return isCurrent ? 28 : 8
        }
    }

    private var markHeight: CGFloat {
        switch style {
        case .dots: return isCurrent ? 10 : 8
        case .bars: return 4
        }
    }

    private var fillOpacity: Double {
        if isCurrent { return DS.Opacity.visible }
        return isHovered ? DS.Opacity.strong : 0.4
    }

    var body: some View {
        Button(action: onSelect) {
            RoundedRectangle(cornerRadius: style == .dots ? markHeight / 2 : DS.Radius.r2, style: .continuous)
                .fill(Color.white.opacity(fillOpacity))
                .frame(width: markWidth, height: markHeight)
                .scaleEffect(isHovered && !isCurrent ? 1.25 : 1)
                .frame(
                    width: max(markWidth + DS.Space.s8, HeroPageIndicator.hitTarget),
                    height: HeroPageIndicator.hitTarget
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(DS.Motion.spring, value: isCurrent)
        .animation(DS.Motion.quick, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onDisappear {
            if isHovered { NSCursor.pop() }
        }
        .help("Show item \(index + 1) of \(count)")
        .accessibilityLabel(Text("Show item \(index + 1) of \(count)"))
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
    }
}
