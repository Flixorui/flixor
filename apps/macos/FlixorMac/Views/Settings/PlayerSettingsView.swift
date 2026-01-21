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

    // MARK: - Global Hardware Settings (device-specific, not profile-scoped)
    private let defaults = UserDefaults.standard

    // Player Backend binding (global) - uses property from PlayerBackend.swift
    private var playerBackendBinding: Binding<PlayerBackend> {
        Binding(
            get: { defaults.playerBackend },
            set: { defaults.playerBackend = $0 }
        )
    }

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
    private let playbackSpeedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Player Backend Selection
            SettingsCard(title: "Player Backend") {
                SettingsRow(
                    icon: "play.rectangle.fill",
                    iconColor: .blue,
                    title: "Video Player",
                    subtitle: playerBackendBinding.wrappedValue.description,
                    showDivider: false
                ) {
                    Picker("", selection: playerBackendBinding) {
                        ForEach(PlayerBackend.allCases) { backend in
                            Text(backend.displayName).tag(backend)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
            }

            Text("MPV offers better codec support and advanced features. AVPlayer is Apple's native player with better system integration.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

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
                    subtitle: "Double-tap or hold seek duration",
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
                            Text("\(speed, specifier: "%.2g")x").tag(speed)
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
                    showDivider: false
                ) {
                    Toggle("", isOn: $profileSettings.rememberTrackSelections)
                        .labelsHidden()
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

            // Subtitle Styling - PROFILE-SCOPED
            SettingsCard(title: "Subtitle Styling") {
                SettingsRow(
                    icon: "textformat.size",
                    iconColor: .blue,
                    title: "Font Size",
                    subtitle: "Subtitle text size"
                ) {
                    Stepper("\(profileSettings.subtitleFontSize)", value: $profileSettings.subtitleFontSize, in: 30...80, step: 5)
                        .frame(width: 80)
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
                    HStack(spacing: 8) {
                        Slider(value: $profileSettings.subtitleBackgroundOpacity, in: 0...1, step: 0.1)
                            .frame(width: 100)
                        Text("\(Int(profileSettings.subtitleBackgroundOpacity * 100))%")
                            .font(.system(size: 11))
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
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
        .sheet(isPresented: $showMpvConfigView) {
            MpvConfigView()
        }
        .onAppear(perform: loadColors)
        .onChange(of: subtitleTextColor) { newColor in
            saveColor(newColor, forKey: "subtitleTextColor")
        }
        .onChange(of: subtitleBorderColor) { newColor in
            saveColor(newColor, forKey: "subtitleBorderColor")
        }
        .onChange(of: subtitleBackgroundColor) { newColor in
            saveColor(newColor, forKey: "subtitleBackgroundColor")
        }
    }

    // MARK: - Color Helpers

    private func loadColors() {
        subtitleTextColor = loadColor(forKey: "subtitleTextColor", default: .white)
        subtitleBorderColor = loadColor(forKey: "subtitleBorderColor", default: .black)
        subtitleBackgroundColor = loadColor(forKey: "subtitleBackgroundColor", default: .black)
    }

    private func loadColor(forKey key: String, default defaultColor: Color) -> Color {
        guard let hex = UserDefaults.standard.string(forKey: key) else { return defaultColor }
        return Color(hex: hex)
    }

    private func saveColor(_ color: Color, forKey key: String) {
        UserDefaults.standard.set(color.toHex(), forKey: key)
    }

    private func resetToDefaults() {
        UserDefaults.standard.resetPlayerSettings()
        // Reload colors after reset
        loadColors()
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
