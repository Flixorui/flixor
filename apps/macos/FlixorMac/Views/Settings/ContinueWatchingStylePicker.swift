//
//  ContinueWatchingStylePicker.swift
//  FlixorMac
//
//  Card style buttons (Landscape / Poster / Wide) and the Wide card preview,
//  shared by Continue Watching settings and Home Screen appearance.
//

import SwiftUI

struct ContinueWatchingStylePicker: View {
    @ObservedObject private var profileSettings = ProfileSettings.shared

    var body: some View {
        HStack(spacing: DS.Space.itemGap) {
            ForEach(ContinueWatchingCardStyle.allCases) { style in
                LayoutOptionButton(
                    title: .verbatim(style.title),
                    icon: style.iconName,
                    isSelected: ContinueWatchingCardStyle(storageValue: profileSettings.continueWatchingLayout) == style
                ) {
                    profileSettings.continueWatchingLayout = style.rawValue
                }
                .accessibilityLabel(Text("\(style.title) Continue Watching cards"))
            }
        }
    }
}

/// Mock of the Wide Continue Watching card for settings previews.
struct ContinueWatchingWidePreview: View {
    var blurUpNext: Bool = false
    @Environment(\.flixorTheme) private var theme

    private let samples: [(show: String, episode: String, label: String, progress: Double, time: String, upNext: Bool)] = [
        ("Breaking Bad", "Ozymandias", "S5 · E14", 0.45, String(localized: "26m left"), false),
        ("Stranger Things", "The Massacre at Hawkins Lab", "S4 · E2", 0, String(localized: "Up next · 1h 15m"), true),
    ]

    var body: some View {
        HStack(spacing: DS.Space.itemGap) {
            ForEach(samples.indices, id: \.self) { index in
                let sample = samples[index]
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: DS.Radius.thumbnail, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: index == 0 ? [.teal.opacity(0.5), .indigo.opacity(0.4)] : [.orange.opacity(0.5), .red.opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blur(radius: blurUpNext && sample.upNext ? 8 : 0)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.thumbnail, style: .continuous))

                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        Text(sample.label)
                            .flixorFont(.nano)
                            .foregroundStyle(theme.textPrimary)
                        Text(sample.show)
                            .flixorFont(.footnote, weight: .semibold)
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                        Text(sample.episode)
                            .flixorFont(.micro, weight: .regular)
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                        HStack(spacing: DS.Space.s6) {
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(DS.Opacity.disabled))
                                    Capsule().fill(theme.accent).frame(width: proxy.size.width * sample.progress)
                                }
                            }
                            .frame(height: 3)
                            Text(sample.time)
                                .flixorFont(.nano, weight: .medium)
                                .foregroundStyle(theme.textSecondary)
                                .fixedSize()
                        }
                    }
                    .padding(DS.Space.s8)
                }
                .frame(width: 190)
            }
        }
    }
}
