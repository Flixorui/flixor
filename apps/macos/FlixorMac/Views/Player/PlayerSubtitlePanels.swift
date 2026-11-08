//
//  PlayerSubtitlePanels.swift
//  FlixorMac
//
//  Sub-pages of the player's subtitle panel: appearance options and sync by line.
//

import SwiftUI

// MARK: - Shared rows

/// Row in the subtitle panel that opens a sub-page.
struct SubtitlePanelNavRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s10) {
                Image(systemName: systemImage)
                    .font(.flixorIcon(DS.Icon.xs))
                    .foregroundStyle(.white.opacity(DS.Opacity.secondary))
                    .frame(width: DS.Icon.md)
                Text(title)
                    .font(.flixor(.callout))
                    .foregroundStyle(.white.opacity(DS.Opacity.strong))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.flixorIcon(DS.Icon.xs, weight: .semibold))
                    .foregroundStyle(.white.opacity(DS.Opacity.tertiary))
            }
            .padding(.horizontal, DS.Space.s12)
            .padding(.vertical, DS.Space.s10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct SubtitlePanelPageHeader: View {
    let title: LocalizedStringKey
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.s8) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.flixorIcon(DS.Icon.xs, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to subtitle tracks")

            Text(title)
                .font(.flixor(.body, weight: .semibold))
                .foregroundStyle(.white)

            Spacer()
        }
        .padding(.horizontal, DS.Space.s8)
        .padding(.vertical, DS.Space.s6)
    }
}

private enum SubtitlePanelLayout {
    /// Fits below the top bar at the app's minimum window height.
    static let pageHeight: CGFloat = 420
}

// MARK: - Appearance

struct SubtitleAppearancePanel: View {
    @ObservedObject var viewModel: PlayerViewModel
    let onBack: () -> Void

    private static let textColors: [SubtitleColorOption] = [
        .init(name: "White", hex: "#FFFFFF"),
        .init(name: "Yellow", hex: "#FFD60A"),
        .init(name: "Cyan", hex: "#64D2FF"),
        .init(name: "Green", hex: "#30D158"),
        .init(name: "Black", hex: "#000000"),
    ]
    private static let boxColors: [SubtitleColorOption] = [
        .init(name: "Black", hex: "#000000"),
        .init(name: "Grey", hex: "#3A3A3C"),
        .init(name: "White", hex: "#FFFFFF"),
    ]

    private var fontChoices: [String] {
        let saved = viewModel.subtitleAppearance.fontName
        let families = PlayerSettingsView.subtitleFontFamilies
        return saved.isEmpty || families.contains(saved) ? families : [saved] + families
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SubtitlePanelPageHeader(title: "Appearance", onBack: onBack)

            Divider().background(Color.white.opacity(DS.Opacity.selected))

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s12) {
                    fontRow
                    toggleRow(
                        String(localized: "Bold"),
                        isOn: Binding(
                            get: { viewModel.subtitleAppearance.bold },
                            set: { viewModel.setSubtitleBold($0) }
                        )
                    )
                    toggleRow(
                        String(localized: "Hide hearing-impaired text"),
                        isOn: Binding(
                            get: { viewModel.subtitleFilterSDH },
                            set: { viewModel.setSubtitleFilterSDH($0) }
                        )
                    )

                    CompactSliderRow(
                        label: "Size",
                        value: "\(viewModel.subtitleFontSize)",
                        sliderValue: Double(viewModel.subtitleFontSize),
                        range: 30...80,
                        step: 5
                    ) { viewModel.setSubtitleFontSize(Int($0)) }

                    CompactSliderRow(
                        label: "Position",
                        value: "\(viewModel.subtitleAppearance.position)",
                        sliderValue: Double(viewModel.subtitleAppearance.position),
                        range: 0...100,
                        step: 5
                    ) { viewModel.setSubtitlePosition(Int($0)) }

                    SubtitleColorRow(
                        label: String(localized: "Text"),
                        selection: viewModel.subtitleAppearance.textColor,
                        options: Self.textColors
                    ) { viewModel.setSubtitleTextColor($0) }

                    SubtitleColorRow(
                        label: String(localized: "Border"),
                        selection: viewModel.subtitleAppearance.borderColor,
                        options: Self.boxColors
                    ) { viewModel.setSubtitleBorderColor($0) }

                    CompactSliderRow(
                        label: "Thickness",
                        value: String(format: "%.1f", viewModel.subtitleBorderSize),
                        sliderValue: viewModel.subtitleBorderSize,
                        range: 0...5,
                        step: 0.5
                    ) { viewModel.setSubtitleBorderSize($0) }

                    SubtitleColorRow(
                        label: String(localized: "Background"),
                        selection: viewModel.subtitleAppearance.backgroundColor,
                        options: Self.boxColors
                    ) { viewModel.setSubtitleBackgroundColor($0) }

                    CompactSliderRow(
                        label: "Opacity",
                        value: "\(Int(viewModel.subtitleBackgroundOpacity * 100))%",
                        sliderValue: viewModel.subtitleBackgroundOpacity,
                        range: 0...1,
                        step: 0.1
                    ) { viewModel.setSubtitleBackgroundOpacity($0) }

                    Text("Applies to plain text subtitles. Styled ASS and image subtitles (PGS, VobSub) keep their own look.")
                        .font(.flixor(.caption))
                        .foregroundStyle(.white.opacity(DS.Opacity.tertiary))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(DS.Space.s12)
            }
        }
        .frame(height: SubtitlePanelLayout.pageHeight)
    }

    private var fontRow: some View {
        HStack(spacing: DS.Space.s10) {
            Text("Font")
                .font(.flixor(.footnote))
                .foregroundStyle(.white.opacity(DS.Opacity.muted))
            Spacer()
            Picker("", selection: Binding(
                get: { viewModel.subtitleAppearance.fontName },
                set: { viewModel.setSubtitleFont($0) }
            )) {
                Text("Default").tag("")
                ForEach(fontChoices, id: \.self) { font in
                    Text(font).tag(font)
                }
            }
            .labelsHidden()
            .frame(width: 170)
            .accessibilityLabel("Subtitle font")
        }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.flixor(.footnote))
                .foregroundStyle(.white.opacity(DS.Opacity.muted))
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .accessibilityLabel(title)
        }
    }
}

private struct SubtitleColorOption: Hashable {
    let name: String
    let hex: String
}

private struct SubtitleColorRow: View {
    let label: String
    let selection: String
    let options: [SubtitleColorOption]
    let onSelect: (String) -> Void

    @Environment(\.flixorTheme) private var theme

    private let swatchSize: CGFloat = 20

    var body: some View {
        HStack(spacing: DS.Space.s6) {
            Text(label)
                .font(.flixor(.footnote))
                .foregroundStyle(.white.opacity(DS.Opacity.muted))
                .frame(width: 76, alignment: .leading)
                .lineLimit(1)

            Spacer()

            ForEach(options, id: \.self) { option in
                swatch(option)
            }

            ColorPicker(
                "",
                selection: Binding(
                    get: { Color(hex: selection) },
                    set: { onSelect($0.toHex()) }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
            .frame(width: 32)
            .accessibilityLabel("Custom \(label.lowercased()) colour")
        }
    }

    private func swatch(_ option: SubtitleColorOption) -> some View {
        let isSelected = selection.caseInsensitiveCompare(option.hex) == .orderedSame
        return Button(action: { onSelect(option.hex) }) {
            Circle()
                .fill(Color(hex: option.hex))
                .frame(width: swatchSize, height: swatchSize)
                .overlay(Circle().strokeBorder(Color.white.opacity(DS.Opacity.scrimLight), lineWidth: DS.Border.thin))
                .overlay(
                    Circle()
                        .strokeBorder(isSelected ? theme.focusRing : .clear, lineWidth: DS.Border.focus)
                        .padding(-DS.Space.s2)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) colour \(option.name)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Sync by line

struct SubtitleSyncByLinePanel: View {
    @ObservedObject var viewModel: PlayerViewModel
    let onBack: () -> Void

    @Environment(\.flixorTheme) private var theme

    /// The list holds still under the pointer so a row can't move as it is clicked.
    @State private var isHoveringList = false
    @State private var frozenCues: [SubtitleCue] = []
    @State private var syncedCueId: String?

    private var cues: [SubtitleCue] {
        if isHoveringList, viewModel.subtitleCueSource == .fullFile, !frozenCues.isEmpty {
            return frozenCues
        }
        return viewModel.nearbySubtitleCues()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SubtitlePanelPageHeader(title: "Sync by Line", onBack: onBack)

            Divider().background(Color.white.opacity(DS.Opacity.selected))

            VStack(alignment: .leading, spacing: DS.Space.s8) {
                Text(explanation)
                    .font(.flixor(.footnote))
                    .foregroundStyle(.white.opacity(DS.Opacity.secondary))
                    .fixedSize(horizontal: false, vertical: true)

                offsetRow
            }
            .padding(DS.Space.s12)

            Divider().background(Color.white.opacity(DS.Opacity.selected))

            if viewModel.subtitleCueSource == .none || cues.isEmpty {
                emptyState
            } else {
                cueList
            }
        }
        .frame(height: SubtitlePanelLayout.pageHeight)
    }

    private var explanation: String {
        switch viewModel.subtitleCueSource {
        case .none:
            return String(localized: "Turn on a subtitle track first, then match a line to the moment it is spoken.")
        case .fullFile:
            return String(localized: "Listen for a line, then click it the moment it is spoken. The subtitles shift so that line appears right now.")
        case .observedOnly:
            return String(localized: "Click a line the moment it is spoken. This track is embedded in the video, so only lines already shown can be listed, and upcoming ones are unknown. If subtitles run late, use the offset instead (G / H).")
        }
    }

    private var offsetRow: some View {
        HStack {
            Text("Offset")
                .font(.flixor(.footnote))
                .foregroundStyle(.white.opacity(DS.Opacity.muted))

            Text(String(format: "%+.3f s", viewModel.subtitleDelay))
                .font(.flixor(.footnote, weight: .medium, design: .monospaced))
                .foregroundStyle(viewModel.subtitleDelay == 0 ? .white.opacity(DS.Opacity.muted) : theme.warning)

            Spacer()

            Button("Reset") {
                syncedCueId = nil
                viewModel.setSubtitleDelay(0)
            }
            .buttonStyle(.plain)
            .font(.flixor(.footnote, weight: .medium))
            .foregroundStyle(.white.opacity(viewModel.subtitleDelay == 0 ? DS.Opacity.disabled : DS.Opacity.strong))
            .disabled(viewModel.subtitleDelay == 0)
            .accessibilityLabel("Reset subtitle offset")
        }
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            Text(viewModel.subtitleCueSource == .observedOnly
                 ? "No lines shown yet. Keep playing until a few subtitles have appeared."
                 : "No subtitle lines to show.")
                .font(.flixor(.footnote))
                .foregroundStyle(.white.opacity(DS.Opacity.tertiary))
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.Space.s24)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var cueList: some View {
        let position = viewModel.subtitleTimelinePosition
        let activeId = viewModel.activeSubtitleCue?.id
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: DS.Space.s2) {
                    ForEach(cues) { cue in
                        cueRow(cue, position: position, isActive: cue.id == activeId)
                            .id(cue.id)
                    }
                }
                .padding(DS.Space.s8)
            }
            .onHover { hovering in
                if hovering { frozenCues = viewModel.nearbySubtitleCues() }
                isHoveringList = hovering
            }
            .onAppear {
                if let activeId { proxy.scrollTo(activeId, anchor: .center) }
            }
            .onChange(of: activeId) { newId in
                guard let newId, !isHoveringList else { return }
                withAnimation(DS.Motion.standard) { proxy.scrollTo(newId, anchor: .center) }
            }
        }
    }

    private func cueRow(_ cue: SubtitleCue, position: TimeInterval, isActive: Bool) -> some View {
        Button(action: {
            syncedCueId = cue.id
            viewModel.syncSubtitle(to: cue)
        }) {
            HStack(alignment: .top, spacing: DS.Space.s8) {
                Text(relativeTime(of: cue, position: position, isActive: isActive))
                    .font(.flixor(.caption, weight: .medium, design: .monospaced))
                    .foregroundStyle(isActive ? theme.accent : .white.opacity(DS.Opacity.tertiary))
                    .frame(width: 44, alignment: .trailing)

                Text(cue.text)
                    .font(.flixor(.footnote))
                    .foregroundStyle(.white.opacity(isActive ? DS.Opacity.visible : DS.Opacity.secondary))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if cue.id == syncedCueId {
                    Image(systemName: "checkmark")
                        .font(.flixorIcon(DS.Icon.xs, weight: .semibold))
                        .foregroundStyle(theme.success)
                }
            }
            .padding(.horizontal, DS.Space.s6)
            .padding(.vertical, DS.Space.s6)
            .background(isActive ? Color.white.opacity(DS.Opacity.hover) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sync subtitles to line: \(cue.text)")
    }

    private func relativeTime(of cue: SubtitleCue, position: TimeInterval, isActive: Bool) -> String {
        if isActive { return "now" }
        let seconds = Int((cue.start - position).rounded())
        return seconds == 0 ? String(localized: "now") : String(format: "%+d s", seconds)
    }
}
