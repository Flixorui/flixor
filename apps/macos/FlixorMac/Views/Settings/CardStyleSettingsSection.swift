//
//  CardStyleSettingsSection.swift
//  FlixorMac
//
//  Card customization (per profile): size, corners, titles, rating badges and
//  the hover preview. Embedded in HomeScreenAppearanceView.
//

import SwiftUI

struct CardStyleSettingsSection: View {
    @ObservedObject private var profileSettings = ProfileSettings.shared
    @ObservedObject private var style = CardStyleStore.shared

    private let pickerWidth: CGFloat = 140

    private var posterSize: Binding<CardPosterSize> {
        Binding(
            get: { CardPosterSize(stored: profileSettings.posterSize) },
            set: { profileSettings.posterSize = $0.rawValue }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.itemGap) {
            SettingsSectionHeader(title: "Cards")
            SettingsGroupCard {
                SettingsRow(icon: "arrow.up.left.and.arrow.down.right", iconColor: .green, title: "Card Poster Size") {
                    picker(selection: posterSize, label: "Card poster size")
                }
                SettingsRow(icon: "square.on.square", iconColor: .orange, title: "Corner Style") {
                    picker(selection: $style.cornerStyle, label: "Corner style")
                }
                SettingsRow(icon: "textformat", iconColor: .purple, title: "Titles Under Posters") {
                    picker(selection: $style.titleMode, label: "Titles under posters")
                }
                SettingsRow(icon: "star.fill", iconColor: .yellow, title: "Rating Badges", showDivider: false) {
                    Toggle("", isOn: $style.showRatingBadges)
                        .labelsHidden()
                        .accessibilityLabel("Rating badges")
                }
            }

            SettingsSectionHeader(title: "Hover Preview")
            SettingsGroupCard {
                SettingsRow(
                    icon: "rectangle.expand.vertical",
                    iconColor: .blue,
                    title: "Show Preview on Hover",
                    subtitle: "Expands a card with details after resting the pointer on it",
                    showDivider: style.hoverPreviewEnabled
                ) {
                    Toggle("", isOn: $style.hoverPreviewEnabled)
                        .labelsHidden()
                        .accessibilityLabel("Show preview on hover")
                }
                if style.hoverPreviewEnabled {
                    SettingsRow(icon: "timer", iconColor: .teal, title: "Delay") {
                        HStack(spacing: DS.Space.controlGap) {
                            Slider(value: $style.hoverPreviewDelay, in: UserDefaults.cardHoverPreviewDelayRange, step: 0.1)
                                .frame(width: pickerWidth)
                                .accessibilityLabel("Hover preview delay")
                                .accessibilityValue(delayText)
                            Text(delayText)
                                .flixorFont(.footnote)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: DS.Space.s40, alignment: .trailing)
                                .accessibilityHidden(true)
                        }
                    }
                    SettingsRow(icon: "play.rectangle", iconColor: .red, title: "Trailer", showDivider: false) {
                        picker(selection: $style.hoverTrailerMode, label: "Hover preview trailer")
                    }
                }
            }
        }
    }

    private var delayText: String {
        String(format: "%.1f s", style.hoverPreviewDelay)
    }

    private func picker<Option>(selection: Binding<Option>, label: String) -> some View
    where Option: CaseIterable & Identifiable & Hashable & CardSettingOption, Option.AllCases: RandomAccessCollection {
        Picker("", selection: selection) {
            ForEach(Option.allCases) { option in
                Text(option.displayName).tag(option)
            }
        }
        .labelsHidden()
        .frame(width: pickerWidth)
        .accessibilityLabel(label)
    }
}

/// Options that can appear in the card settings pickers.
protocol CardSettingOption {
    var displayName: String { get }
}

extension CardPosterSize: CardSettingOption {}
extension CardCornerStyle: CardSettingOption {}
extension CardTitleMode: CardSettingOption {}
extension HoverTrailerMode: CardSettingOption {}
