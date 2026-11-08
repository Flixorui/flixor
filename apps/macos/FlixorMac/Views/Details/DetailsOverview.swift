//
//  DetailsOverview.swift
//  FlixorMac
//
//  Full overview modal and collapsible overview text
//

import SwiftUI
import FlixorKit

// MARK: - Overview Modal
struct OverviewModal: View {
    let title: String
    let overview: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s20) {
            HStack {
                Text(title)
                    .font(.flixor(.title3, weight: .semibold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                Text(overview)
                    .font(.flixor(.body))
                    .foregroundStyle(.primary.opacity(0.9))
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(DS.Space.s24)
        .frame(width: 500, height: 400)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Collapsible Overview Component

private struct CollapsibleOverview: View {
    let text: String
    let maxWidth: CGFloat
    @Binding var isExpanded: Bool

    @State private var intrinsicHeight: CGFloat = 0
    @State private var truncatedHeight: CGFloat = 0

    private var isTruncated: Bool {
        intrinsicHeight > truncatedHeight && truncatedHeight > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s10) {
            Text(text)
                .font(.flixor(.headline))
                .foregroundStyle(.white.opacity(0.88))
                .lineSpacing(4)
                .lineLimit(isExpanded ? nil : 2)
                .frame(maxWidth: maxWidth, alignment: .leading)
                .multilineTextAlignment(.leading)
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: TruncatedHeightPreferenceKey.self,
                            value: geometry.size.height
                        )
                    }
                )
                .onPreferenceChange(TruncatedHeightPreferenceKey.self) { height in
                    if !isExpanded {
                        truncatedHeight = height
                    }
                }
                .background(
                    // Hidden text without line limit to get intrinsic height
                    Text(text)
                        .font(.flixor(.headline))
                        .lineSpacing(4)
                        .frame(maxWidth: maxWidth, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .background(
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: IntrinsicHeightPreferenceKey.self,
                                    value: geometry.size.height
                                )
                            }
                        )
                        .onPreferenceChange(IntrinsicHeightPreferenceKey.self) { height in
                            intrinsicHeight = height
                        }
                )

            if isTruncated {
                Button(action: {
                    withAnimation(DS.Motion.standard) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack(spacing: DS.Space.s6) {
                        Text(isExpanded ? "Less" : "More")
                            .font(.flixor(.body, weight: .semibold))
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.flixorIcon(DS.Icon.xs, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, DS.Space.s16)
                    .padding(.vertical, DS.Space.s8)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.18))
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: maxWidth, alignment: .leading)
            }
        }
    }
}

private struct TruncatedHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct IntrinsicHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
