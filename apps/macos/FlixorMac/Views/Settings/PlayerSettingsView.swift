//
//  PlayerSettingsView.swift
//  FlixorMac
//
//  Player and MPV configuration settings
//

import SwiftUI

struct PlayerSettingsView: View {
    // MARK: - Profile Settings (profile-scoped)
    @ObservedObject private var profileSettings = ProfileSettings.shared
    @StateObject private var engineSettings = PlaybackEngineSettingsModel()
    @StateObject private var skipSettings = SkipSegmentSettingsModel()

    // MARK: - Global Hardware Settings (device-specific, not profile-scoped)
    private let defaults = UserDefaults.standard

    // Hardware decoding binding (global)
    private var hardwareDecodingBinding: Binding<Bool> {
        Binding(
            get: { defaults.hardwareDecoding },
            set: { defaults.hardwareDecoding = $0 }
        )
    }

    // HDR binding (global)
    private var hdrEnabledBinding: Binding<Bool> {
        Binding(
            get: { defaults.hdrEnabled },
            set: { defaults.hdrEnabled = $0 }
        )
    }

    // Buffer size binding (global)
    private var bufferSizeBinding: Binding<Int> {
        Binding(
            get: { defaults.bufferSize },
            set: { defaults.bufferSize = $0 }
        )
    }

    // Max volume binding (global)
    private var maxVolumeBinding: Binding<Int> {
        Binding(
            get: { defaults.maxVolume },
            set: { defaults.maxVolume = $0 }
        )
    }

    // For color pickers, we need state
    @State private var subtitleTextColor: Color = .white
    @State private var subtitleBorderColor: Color = .black
    @State private var subtitleBackgroundColor: Color = .black

    // MARK: - Navigation State
    @State private var showMpvConfigView = false

    private let bufferOptions = [64, 128, 256, 512, 1024]
    /// Font families offered here and in the player's subtitle panel.
    static let subtitleFontFamilies = [
        "Helvetica Neue", "Arial", "Avenir Next", "Futura", "Gill Sans",
        "Verdana", "Trebuchet MS", "Georgia", "Times New Roman", "Menlo",
    ]
    private var subtitleFontOptions: [String] { Self.subtitleFontFamilies }

    /// 0.25x-2x, plus a faster default saved by an earlier version so it stays selected.
    private var playbackSpeedOptions: [Double] {
        var options = PlayerViewModel.playbackSpeedPresets.map(Double.init)
        if !options.contains(profileSettings.defaultPlaybackSpeed) {
            options.append(profileSettings.defaultPlaybackSpeed)
        }
        return options.sorted()
    }

    /// Font choices, keeping a saved font that isn't in the list selectable.
    private var subtitleFontChoices: [String] {
        let saved = engineSettings.fontName
        return saved.isEmpty || subtitleFontOptions.contains(saved) ? subtitleFontOptions : [saved] + subtitleFontOptions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            SettingsGroupCard {
                SettingsRow(
                    icon: "play.rectangle.fill",
                    iconColor: .blue,
                    title: "Playback Engine",
                    subtitle: "Plex, Stremio, direct URLs and offline files all play through MPV on macOS",
                    showDivider: false
                ) {
                    Text("MPV")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            // Player Engine (MPV-specific settings) - GLOBAL
            SettingsCard(title: "MPV Engine") {
                SettingsRow(
                    icon: "cpu",
                    iconColor: .blue,
                    title: "Hardware Decoding",
                    subtitle: "Use VideoToolbox for GPU-accelerated decoding"
                ) {
                    Toggle("", isOn: hardwareDecodingBinding)
                        .labelsHidden()
                }

                SettingsRow(
                    icon: "sun.max.fill",
                    iconColor: .yellow,
                    title: "HDR / Dolby Vision",
                    subtitle: "Enable high dynamic range playback",
                    showDivider: false
                ) {
                    Toggle("", isOn: hdrEnabledBinding)
                        .labelsHidden()
                }
            }

            // Buffering - GLOBAL
            SettingsCard(title: "Buffering") {
                SettingsRow(
                    icon: "memorychip",
                    iconColor: .purple,
                    title: "Buffer Size",
                    subtitle: "Amount of video data to pre-load",
                    showDivider: false
                ) {
                    Picker("", selection: bufferSizeBinding) {
                        ForEach(bufferOptions, id: \.self) { size in
                            Text("\(size) MB").tag(size)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
            }

            // Seek Durations - PROFILE-SCOPED
            SettingsCard(title: "Seek Durations") {
                SettingsRow(
                    icon: "gobackward.5",
                    iconColor: .orange,
                    title: "Small Seek",
                    subtitle: "Arrow key seek duration"
                ) {
                    Stepper("\(profileSettings.seekTimeSmall)s", value: $profileSettings.seekTimeSmall, in: 1...120, step: 5)
                        .frame(width: 100)
                }

                SettingsRow(
                    icon: "gobackward.30",
                    iconColor: .orange,
                    title: "Large Seek",
                    subtitle: "Shift + arrow key seek duration",
                    showDivider: false
                ) {
                    Stepper("\(profileSettings.seekTimeLarge)s", value: $profileSettings.seekTimeLarge, in: 1...120, step: 10)
                        .frame(width: 100)
                }
            }

            // Volume - GLOBAL
            SettingsCard(title: "Volume") {
                SettingsRow(
                    icon: "speaker.wave.3.fill",
                    iconColor: .green,
                    title: "Max Volume",
                    subtitle: "Allow volume boost beyond 100%",
                    showDivider: false
                ) {
                    Stepper("\(defaults.maxVolume)%", value: maxVolumeBinding, in: 100...300, step: 25)
                        .frame(width: 100)
                }
            }

            // Playback - PROFILE-SCOPED
            SettingsCard(title: "Playback") {
                SettingsRow(
                    icon: "speedometer",
                    iconColor: .cyan,
                    title: "Default Speed",
                    subtitle: "Playback speed for new sessions"
                ) {
                    Picker("", selection: $profileSettings.defaultPlaybackSpeed) {
                        ForEach(playbackSpeedOptions, id: \.self) { speed in
                            Text("\(speed, specifier: "%g")x").tag(speed)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 80)
                }

                SettingsRow(
                    icon: "play.fill",
                    iconColor: .red,
                    title: "Auto-Play Next",
                    subtitle: "Automatically play next episode"
                ) {
                    Toggle("", isOn: $profileSettings.autoPlayNext)
                        .labelsHidden()
                }

                SettingsRow(
                    icon: "list.bullet",
                    iconColor: .indigo,
                    title: "Remember Track Selection",
                    subtitle: "Remember audio/subtitle language choices",
                    showDivider: true
                ) {
                    Toggle("", isOn: $profileSettings.rememberTrackSelections)
                        .labelsHidden()
                }

                SettingsRow(
                    icon: "captions.bubble.fill",
                    iconColor: .orange,
                    title: "Preferred Subtitle Language",
                    subtitle: "Used for auto-select, after languages remembered for a title"
                ) {
                    Picker("", selection: $profileSettings.preferredSubtitleLanguage) {
                        ForEach(PlaybackLanguageOption.subtitleOptions(including: profileSettings.preferredSubtitleLanguage)) { option in
                            Text(option.name).tag(option.code)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                    .accessibilityLabel("Preferred subtitle language")
                }

                SettingsRow(
                    icon: "music.note",
                    iconColor: .pink,
                    title: "Preferred Audio Language",
                    subtitle: "Used for auto-select, after languages remembered for a title"
                ) {
                    Picker("", selection: $profileSettings.preferredAudioLanguage) {
                        ForEach(PlaybackLanguageOption.audioOptions(including: profileSettings.preferredAudioLanguage)) { option in
                            Text(option.name).tag(option.code)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                    .accessibilityLabel("Preferred audio language")
                }

                SettingsRow(
                    icon: "text.bubble.fill",
                    iconColor: .purple,
                    title: "Subtitle Source Preference",
                    subtitle: "How internal and external subtitles are prioritized"
                ) {
                    Picker("", selection: $profileSettings.subtitleSourcePreference) {
                        ForEach(SubtitleSourcePreference.allCases, id: \.self) { preference in
                            Text(preference.description).tag(preference)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }

                SettingsRow(
                    icon: "wand.and.stars",
                    iconColor: .teal,
                    title: "Auto-Select Subtitles",
                    subtitle: "Automatically choose matching subtitles after playback starts"
                ) {
                    Toggle("", isOn: $profileSettings.enableSubtitleAutoSelect)
                        .labelsHidden()
                }

                SettingsRow(
                    icon: "ear.trianglebadge.exclamationmark",
                    iconColor: .orange,
                    title: "Remove Hearing-Impaired Text",
                    subtitle: "Strip captions such as [MUSIC] and speaker names from text subtitles"
                ) {
                    Toggle("", isOn: $engineSettings.filterSDH)
                        .labelsHidden()
                        .accessibilityLabel("Remove hearing-impaired text from subtitles")
                }

                SettingsRow(
                    icon: "aspectratio",
                    iconColor: .blue,
                    title: "Video Aspect",
                    subtitle: "How video fills the player",
                    showDivider: false
                ) {
                    Picker("", selection: $engineSettings.aspectMode) {
                        ForEach(PlayerAspectMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                    .accessibilityLabel("Video aspect mode")
                }
            }

            // Auto-Skip - PROFILE-SCOPED
            SettingsCard(title: "Auto-Skip") {
                SettingsRow(
                    icon: "forward.fill",
                    iconColor: .pink,
                    title: "Skip Intro Automatically",
                    subtitle: "Auto-skip detected intro segments"
                ) {
                    Toggle("", isOn: $profileSettings.skipIntroAutomatically)
                        .labelsHidden()
                }

                SettingsRow(
                    icon: "forward.end.fill",
                    iconColor: .pink,
                    title: "Skip Credits Automatically",
                    subtitle: "Auto-skip detected credits segments"
                ) {
                    Toggle("", isOn: $profileSettings.skipCreditsAutomatically)
                        .labelsHidden()
                }

                SettingsRow(
                    icon: "backward.end.alt.fill",
                    iconColor: .pink,
                    title: "Skip Recaps Automatically",
                    subtitle: "Auto-skip detected \u{201C}previously on\u{201D} recaps"
                ) {
                    Toggle("", isOn: $skipSettings.skipRecapAutomatically)
                        .labelsHidden()
                        .accessibilityLabel("Skip recaps automatically")
                }

                SettingsRow(
                    icon: "timer",
                    iconColor: .teal,
                    title: "Skip Delay",
                    subtitle: "Seconds before auto-skipping"
                ) {
                    Stepper("\(profileSettings.autoSkipDelay)s", value: $profileSettings.autoSkipDelay, in: 1...30, step: 1)
                        .frame(width: 80)
                }

                SettingsRow(
                    icon: "clock.arrow.circlepath",
                    iconColor: .teal,
                    title: "Credits Fallback",
                    subtitle: "Show 'Next' button X seconds before end",
                    showDivider: false
                ) {
                    Stepper("\(profileSettings.creditsCountdownFallback)s", value: $profileSettings.creditsCountdownFallback, in: 10...120, step: 5)
                        .frame(width: 80)
                }
            }

            // Community skip data - PROFILE-SCOPED
            SettingsCard(title: "Skip Data") {
                SettingsRow(
                    icon: "person.3.fill",
                    iconColor: .green,
                    title: "Community Skip Data",
                    subtitle: "Queries IntroDB and AniSkip for the current title's intro and credits timings"
                ) {
                    Toggle("", isOn: $skipSettings.communitySkipSegmentsEnabled)
                        .labelsHidden()
                        .accessibilityLabel("Community skip data")
                }

                SettingsRow(
                    icon: "key.fill",
                    iconColor: .gray,
                    title: "Anime-Skip Client ID",
                    subtitle: "Optional. Your own ID from anime-skip.com adds its timings for anime",
                    showDivider: false
                ) {
                    TextField("Optional", text: $skipSettings.animeSkipClientId)
                        .textFieldStyle(.settings)
                        .frame(width: 200)
                        .disabled(!skipSettings.communitySkipSegmentsEnabled)
                        .accessibilityLabel("Anime-Skip client ID")
                }
            }

            // Subtitle Styling - PROFILE-SCOPED
            SettingsCard(title: "Subtitle Styling") {
                SettingsRow(
                    icon: "textformat",
                    iconColor: .blue,
                    title: "Font",
                    subtitle: "Applies to plain text subtitles"
                ) {
                    Picker("", selection: $engineSettings.fontName) {
                        Text("Default").tag("")
                        ForEach(subtitleFontChoices, id: \.self) { font in
                            Text(font).tag(font)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                    .accessibilityLabel("Subtitle font")
                }

                SettingsRow(
                    icon: "textformat.size",
                    iconColor: .blue,
                    title: "Font Size",
                    subtitle: "Subtitle text size"
                ) {
                    Stepper("\(profileSettings.subtitleFontSize)", value: $profileSettings.subtitleFontSize, in: 12...80, step: 5)
                        .frame(width: 80)
                }

                SettingsRow(
                    icon: "bold",
                    iconColor: .blue,
                    title: "Bold"
                ) {
                    Toggle("", isOn: $engineSettings.bold)
                        .labelsHidden()
                        .accessibilityLabel("Bold subtitles")
                }

                SettingsRow(
                    icon: "arrow.up.and.down",
                    iconColor: .blue,
                    title: "Vertical Position",
                    subtitle: "100 is the bottom of the picture; lower values move subtitles up"
                ) {
                    HStack(spacing: DS.Space.s8) {
                        Slider(
                            value: Binding(
                                get: { Double(engineSettings.position) },
                                set: { engineSettings.position = Int($0) }
                            ),
                            in: 0...100,
                            step: 1
                        )
                        .frame(width: 100)
                        .accessibilityLabel("Subtitle vertical position")
                        Text("\(engineSettings.position)")
                            .font(.flixor(.caption))
                            .foregroundStyle(.secondary)
                            .frame(width: 35, alignment: .trailing)
                    }
                }

                SettingsRow(
                    icon: "a.square.fill",
                    iconColor: .white,
                    title: "Text Color"
                ) {
                    ColorPicker("", selection: $subtitleTextColor, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 44)
                }

                SettingsRow(
                    icon: "square.dashed",
                    iconColor: .gray,
                    title: "Border Size"
                ) {
                    Stepper("\(profileSettings.subtitleBorderSize, specifier: "%.1f")", value: $profileSettings.subtitleBorderSize, in: 0...5, step: 0.5)
                        .frame(width: 80)
                }

                SettingsRow(
                    icon: "square",
                    iconColor: .gray,
                    title: "Border Color"
                ) {
                    ColorPicker("", selection: $subtitleBorderColor, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 44)
                }

                SettingsRow(
                    icon: "rectangle.fill",
                    iconColor: .secondary,
                    title: "Background Opacity"
                ) {
                    HStack(spacing: DS.Space.s8) {
                        Slider(value: $profileSettings.subtitleBackgroundOpacity, in: 0...1, step: 0.1)
                            .frame(width: 100)
                        Text("\(Int(profileSettings.subtitleBackgroundOpacity * 100))%")
                            .font(.flixor(.caption))
                            .foregroundStyle(.secondary)
                            .frame(width: 35, alignment: .trailing)
                    }
                }

                SettingsRow(
                    icon: "rectangle",
                    iconColor: .secondary,
                    title: "Background Color",
                    showDivider: false
                ) {
                    ColorPicker("", selection: $subtitleBackgroundColor, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 44)
                }
            }

            // Advanced MPV Config
            SettingsCard(title: "Advanced") {
                Button(action: { showMpvConfigView = true }) {
                    SettingsRow(
                        icon: "terminal",
                        iconColor: .gray,
                        title: "MPV Configuration",
                        subtitle: "Custom MPV properties and presets",
                        showChevron: true,
                        showDivider: false
                    ) {
                        EmptyView()
                    }
                }
                .buttonStyle(.plain)
            }

            // Reset button
            HStack {
                Spacer()
                Button(action: resetToDefaults) {
                    Text("Reset to Defaults")
                        .font(.flixor(.footnote))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            .padding(.top, DS.Space.s8)
        }
        .sheet(isPresented: $showMpvConfigView) {
            MpvConfigView()
        }
        .onAppear {
            engineSettings.reload()
            skipSettings.reload()
            loadColors()
        }
        .onChange(of: subtitleTextColor) { newColor in
            let hex = newColor.toHex()
            guard hex != defaults.subtitleTextColor else { return }
            defaults.subtitleTextColor = hex
            PlaybackEngineSettingsModel.notifyPlayer()
        }
        .onChange(of: subtitleBorderColor) { newColor in
            let hex = newColor.toHex()
            guard hex != defaults.subtitleBorderColor else { return }
            defaults.subtitleBorderColor = hex
            PlaybackEngineSettingsModel.notifyPlayer()
        }
        .onChange(of: subtitleBackgroundColor) { newColor in
            let hex = newColor.toHex()
            guard hex != defaults.subtitleBackgroundColor else { return }
            defaults.subtitleBackgroundColor = hex
            PlaybackEngineSettingsModel.notifyPlayer()
        }
        .onChange(of: profileSettings.subtitleFontSize) { _ in PlaybackEngineSettingsModel.notifyPlayer() }
        .onChange(of: profileSettings.subtitleBorderSize) { _ in PlaybackEngineSettingsModel.notifyPlayer() }
        .onChange(of: profileSettings.subtitleBackgroundOpacity) { _ in PlaybackEngineSettingsModel.notifyPlayer() }
    }

    // MARK: - Color Helpers

    private func loadColors() {
        subtitleTextColor = Color(hex: defaults.subtitleTextColor)
        subtitleBorderColor = Color(hex: defaults.subtitleBorderColor)
        subtitleBackgroundColor = Color(hex: defaults.subtitleBackgroundColor)
    }

    private func resetToDefaults() {
        defaults.resetPlayerSettings()
        defaults.resetPlaybackEngineSettings()
        engineSettings.reload()
        skipSettings.resetToDefaults()
        // Reload colors after reset
        loadColors()
        PlaybackEngineSettingsModel.notifyPlayer()
    }
}

// MARK: - Color Extensions

extension Color {
    func toHex() -> String {
        guard let components = NSColor(self).usingColorSpace(.sRGB)?.cgColor.components else {
            return "#FFFFFF"
        }

        let r = Int((components[0] * 255).rounded())
        let g = Int((components[1] * 255).rounded())
        let b = Int((components[2] * 255).rounded())

        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

#if DEBUG
struct PlayerSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        PlayerSettingsView()
            .frame(width: 600, height: 800)
    }
}
#endif
