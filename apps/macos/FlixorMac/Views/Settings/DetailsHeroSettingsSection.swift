//
//  DetailsHeroSettingsSection.swift
//  FlixorMac
//
//  "Hero Trailer" settings for the details screen, embedded in
//  DetailsScreenSettingsView.
//

import SwiftUI

struct DetailsHeroSettingsSection: View {
    @StateObject private var settings = DetailsHeroSettingsStore()

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s24) {
            SettingsSectionHeader(title: "Hero Trailer")
            SettingsGroupCard {
                SettingsRow(
                    icon: "play.rectangle.fill",
                    iconColor: .red,
                    title: "Play Trailer in Background",
                    subtitle: "After a few seconds on a details page, play the trailer behind the title"
                ) {
                    Toggle("", isOn: $settings.inlineTrailerEnabled)
                        .labelsHidden()
                        .accessibilityLabel("Play trailer in background")
                }
                SettingsRow(
                    icon: "speaker.slash.fill",
                    iconColor: .gray,
                    title: "Start Muted",
                    subtitle: "Unmute any time with the speaker button on the hero",
                    showDivider: false
                ) {
                    Toggle("", isOn: $settings.startsMuted)
                        .labelsHidden()
                        .accessibilityLabel("Start trailer muted")
                        .disabled(!settings.inlineTrailerEnabled)
                }
            }
        }
    }
}

@MainActor
private final class DetailsHeroSettingsStore: ObservableObject {
    @Published var inlineTrailerEnabled: Bool {
        didSet { UserDefaults.standard.detailsHeroInlineTrailerEnabled = inlineTrailerEnabled }
    }
    @Published var startsMuted: Bool {
        didSet { UserDefaults.standard.detailsHeroTrailerStartsMuted = startsMuted }
    }

    init() {
        inlineTrailerEnabled = UserDefaults.standard.detailsHeroInlineTrailerEnabled
        startsMuted = UserDefaults.standard.detailsHeroTrailerStartsMuted
    }
}
