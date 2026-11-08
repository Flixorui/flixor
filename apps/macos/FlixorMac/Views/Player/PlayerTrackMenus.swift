//
//  PlayerTrackMenus.swift
//  FlixorMac
//
//  Audio/subtitle/source modal (tracks, sync offsets, subtitle styling) and playback speed modal
//

import SwiftUI

// MARK: - Audio & Subtitles Combined Modal

struct AudioSubtitlesModal: View {
    @Environment(\.flixorTheme) private var theme
    @ObservedObject var viewModel: PlayerViewModel
    let onClose: () -> Void

    @State private var selectedTab: Int = 0 // 0 = Audio, 1 = Subtitles

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    modalContent
                }
            }
        }
    }

    private var modalContent: some View {
        VStack(spacing: 0) {
            // Tab Header
            HStack(spacing: 0) {
                TabButton(title: "Audio", isSelected: selectedTab == 0) { selectedTab = 0 }
                TabButton(title: "Subtitles", isSelected: selectedTab == 1) { selectedTab = 1 }
            }
            .padding(.horizontal, DS.Space.s4)
            .padding(.top, DS.Space.s4)

            Divider().background(Color.white.opacity(0.1)).padding(.top, DS.Space.s8)

            // Tab Content
            if selectedTab == 0 {
                AudioTabContent(viewModel: viewModel)
            } else {
                SubtitlesTabContent(viewModel: viewModel)
            }
        }
        .frame(width: 340)
        .background(theme.playerPanelBackground())
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r12))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.r12).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
        .padding(.trailing, DS.Space.s32)
        .padding(.bottom, 140)
    }
}

private struct TabButton: View {
    let title: LocalizedStringKey
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Space.s10)
                .background(isSelected ? Color.white.opacity(0.1) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r8))
        }
        .buttonStyle(.plain)
    }
}

private struct AudioTabContent: View {
    @ObservedObject var viewModel: PlayerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Track Selection
            ScrollView {
                VStack(spacing: DS.Space.s2) {
                    ForEach(viewModel.availableAudioTracks, id: \.id) { track in
                        TrackRow(
                            title: track.displayName,
                            isSelected: track.id == viewModel.currentAudioTrackId
                        ) {
                            viewModel.setAudioTrack(track.id)
                        }
                    }
                }
                .padding(.horizontal, DS.Space.s12)
                .padding(.vertical, DS.Space.s8)
            }
            .frame(maxHeight: 150)

            Divider().background(Color.white.opacity(0.1))

            // Audio Sync
            SyncOffsetControl(
                label: "Audio Sync",
                value: viewModel.audioDelay,
                onDecrement: { viewModel.setAudioDelay(max(-2.0, viewModel.audioDelay - 0.05)) },
                onIncrement: { viewModel.setAudioDelay(min(2.0, viewModel.audioDelay + 0.05)) },
                onReset: { viewModel.setAudioDelay(0) }
            )
            .padding(DS.Space.s12)
        }
    }
}

private struct SubtitlesTabContent: View {
    @ObservedObject var viewModel: PlayerViewModel

    private enum Page {
        case tracks, appearance, syncByLine
    }

    @State private var page: Page = .tracks

    /// `syncSubtitle(to:)` can set offsets far beyond a few seconds; keep the +/- buttons working there.
    private let subtitleDelayLimit = 3600.0

    var body: some View {
        switch page {
        case .tracks:
            tracksPage
        case .appearance:
            SubtitleAppearancePanel(viewModel: viewModel, onBack: { page = .tracks })
        case .syncByLine:
            SubtitleSyncByLinePanel(viewModel: viewModel, onBack: { page = .tracks })
        }
    }

    private var tracksPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Track Selection
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.s10) {
                    VStack(spacing: DS.Space.s2) {
                        TrackRow(title: String(localized: "Off"), isSelected: viewModel.currentSubtitleTrackId == nil && viewModel.selectedExternalSubtitleId == nil) {
                            viewModel.disableSubtitles()
                        }

                        ForEach(viewModel.availableSubtitleTracks, id: \.id) { track in
                            TrackRow(
                                title: track.displayName,
                                isSelected: track.id == viewModel.currentSubtitleTrackId && viewModel.selectedExternalSubtitleId == nil
                            ) {
                                viewModel.setSubtitleTrack(track.id)
                            }
                        }
                    }

                    if !viewModel.availableExternalSubtitleOptions.isEmpty {
                        VStack(alignment: .leading, spacing: DS.Space.s6) {
                            Text("External")
                                .font(.flixor(.caption, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, DS.Space.s10)

                            ForEach(viewModel.availableExternalSubtitleOptions) { subtitle in
                                TrackRow(
                                    title: "\(subtitle.lang.uppercased()) • \(subtitle.addonName ?? "Stremio")",
                                    isSelected: subtitle.id == viewModel.selectedExternalSubtitleId
                                ) {
                                    viewModel.loadExternalSubtitle(subtitle)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, DS.Space.s12)
                .padding(.vertical, DS.Space.s8)
            }
            .frame(maxHeight: 150)

            Divider().background(Color.white.opacity(0.1))

            // Subtitle Sync
            SyncOffsetControl(
                label: "Subtitle Sync",
                value: viewModel.subtitleDelay,
                onDecrement: { viewModel.setSubtitleDelay(max(-subtitleDelayLimit, viewModel.subtitleDelay - 0.05)) },
                onIncrement: { viewModel.setSubtitleDelay(min(subtitleDelayLimit, viewModel.subtitleDelay + 0.05)) },
                onReset: { viewModel.setSubtitleDelay(0) }
            )
            .padding(.horizontal, DS.Space.s12)
            .padding(.top, DS.Space.s12)

            SubtitlePanelNavRow(title: "Sync by Line", systemImage: "text.line.first.and.arrowtriangle.forward") {
                page = .syncByLine
            }
            .padding(.top, DS.Space.s4)

            SubtitlePanelNavRow(title: "Appearance", systemImage: "textformat") {
                page = .appearance
            }
            .padding(.bottom, DS.Space.s4)
        }
    }
}

private struct TrackRow: View {
    @Environment(\.flixorTheme) private var theme
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.flixorIcon(DS.Icon.md))
                    .foregroundStyle(isSelected ? theme.accent : .white.opacity(0.3))

                Text(title)
                    .font(.flixor(.callout))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.7))
                    .lineLimit(1)

                Spacer()
            }
            .padding(.vertical, DS.Space.s8)
            .padding(.horizontal, DS.Space.s10)
            .background(isSelected ? Color.white.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r6))
        }
        .buttonStyle(.plain)
    }
}

private struct SyncOffsetControl: View {
    let label: LocalizedStringKey
    let value: Double
    let onDecrement: () -> Void
    let onIncrement: () -> Void
    let onReset: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.s12) {
            Text(label)
                .font(.flixor(.callout))
                .foregroundStyle(.white.opacity(0.8))

            Spacer()

            HStack(spacing: DS.Space.s8) {
                // Decrement button
                Button(action: onDecrement) {
                    Image(systemName: "minus")
                        .font(.flixorIcon(DS.Icon.xs, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r6))
                }
                .buttonStyle(.plain)

                // Value display (tappable to reset)
                Button(action: onReset) {
                    Text(String(format: "%+.0fms", value * 1000))
                        .font(.flixor(.callout, weight: .medium, design: .monospaced))
                        .foregroundStyle(value == 0 ? .white.opacity(0.6) : .orange)
                        .frame(width: 70)
                }
                .buttonStyle(.plain)
                .help("Click to reset")

                // Increment button
                Button(action: onIncrement) {
                    Image(systemName: "plus")
                        .font(.flixorIcon(DS.Icon.xs, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r6))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct CompactSliderRow: View {
    @Environment(\.flixorTheme) private var theme
    let label: LocalizedStringKey
    let value: String
    let sliderValue: Double
    let range: ClosedRange<Double>
    let step: Double
    let onChange: (Double) -> Void

    @State private var localValue: Double = 0

    var body: some View {
        HStack(spacing: DS.Space.s10) {
            Text(label)
                .font(.flixor(.footnote))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 70, alignment: .leading)

            Slider(value: $localValue, in: range, step: step)
                .tint(theme.accent)
                .onAppear { localValue = sliderValue }
                .onChange(of: localValue) { newValue in onChange(newValue) }

            Text(value)
                .font(.flixor(.caption, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 40, alignment: .trailing)
        }
    }
}

// MARK: - Playback Speed Modal

struct PlaybackSpeedModal: View {
    @Environment(\.flixorTheme) private var theme
    let currentSpeed: Float
    let onSelectSpeed: (Float) -> Void
    let onClose: () -> Void

    private var speeds: [Float] { PlayerViewModel.playbackSpeedPresets }
    @State private var isDragging = false
    @State private var dragSpeed: Float?

    private var displaySpeed: Float {
        isDragging ? (dragSpeed ?? currentSpeed) : currentSpeed
    }

    /// Nearest preset, so a speed set elsewhere still lands on the track.
    private var currentIndex: Int {
        speeds.indices.min { abs(speeds[$0] - currentSpeed) < abs(speeds[$1] - currentSpeed) } ?? 0
    }

    private var activeIndex: Int {
        if isDragging, let ds = dragSpeed {
            return speeds.firstIndex(of: ds) ?? currentIndex
        }
        return currentIndex
    }

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    onClose()
                }

            // Speed selector card - positioned bottom-right
            VStack {
                Spacer()
                HStack {
                    Spacer()

                    speedSelectorCard
                }
            }
        }
    }

    private var speedSelectorCard: some View {
        VStack(spacing: 0) {
            // Title
            Text("Playback Speed")
                .font(.flixor(.title2, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, DS.Space.s24)
                .padding(.bottom, DS.Space.s20)

            speedSlider
                .padding(.bottom, DS.Space.s24)
        }
        .frame(width: 600, height: 240)
        .background(theme.playerPanelBackground())
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r16))
        .padding(.trailing, DS.Space.s32)
        .padding(.bottom, 140)
    }

    private var speedSlider: some View {
        VStack(spacing: DS.Space.s16) {
            // Current speed display
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s8) {
                Text(String(format: "%.2fx", displaySpeed))
                    .font(.flixor(.largeTitle, weight: .bold))
                    .foregroundStyle(.white)

                if abs(displaySpeed - 1.0) < 0.01 {
                    Text("Normal")
                        .font(.flixor(.body))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            // Draggable slider track
            GeometryReader { geometry in
                draggableTrack(width: geometry.size.width)
            }
            .frame(height: 28)
            .padding(.horizontal, DS.Space.s40)

            // Speed labels
            speedLabels
                .padding(.horizontal, DS.Space.s40)
        }
    }

    private func draggableTrack(width: CGFloat) -> some View {
        let trackWidth = width
        let progressWidth = trackWidth * CGFloat(activeIndex) / CGFloat(speeds.count - 1)
        let thumbPosition = trackWidth * CGFloat(activeIndex) / CGFloat(speeds.count - 1)

        return ZStack(alignment: .leading) {
            // Background track
            backgroundTrack

            // Progress fill
            progressFill(width: progressWidth)

            // Speed markers
            speedMarkers(trackWidth: trackWidth)

            // Draggable thumb
            thumb(position: thumbPosition)
        }
        .frame(height: 28)
        .gesture(dragGesture(trackWidth: trackWidth))
    }

    private var backgroundTrack: some View {
        Rectangle()
            .fill(Color.white.opacity(0.2))
            .frame(height: 4)
            .cornerRadius(DS.Radius.r2)
    }

    private func progressFill(width: CGFloat) -> some View {
        Rectangle()
            .fill(Color.white)
            .frame(width: width, height: 4)
            .cornerRadius(DS.Radius.r2)
    }

    private func speedMarkers(trackWidth: CGFloat) -> some View {
        ForEach(Array(speeds.enumerated()), id: \.offset) { index, _ in
            let xPosition = trackWidth * CGFloat(index) / CGFloat(speeds.count - 1)
            Circle()
                .fill(index <= activeIndex ? Color.white : Color.white.opacity(0.3))
                .frame(width: 16, height: 16)
                .offset(x: xPosition - 8)
        }
    }

    private func thumb(position: CGFloat) -> some View {
        Circle()
            .strokeBorder(Color.white.opacity(0.8), lineWidth: 3)
            .background(Circle().fill(Color.white))
            .frame(width: 28, height: 28)
            .offset(x: position - 14)
            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
    }

    private func dragGesture(trackWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                isDragging = true
                let progress = min(max(0, value.location.x / trackWidth), 1)
                let index = Int(round(progress * CGFloat(speeds.count - 1)))
                dragSpeed = speeds[index]
            }
            .onEnded { _ in
                isDragging = false
                if let selectedSpeed = dragSpeed {
                    onSelectSpeed(selectedSpeed)
                }
                dragSpeed = nil
            }
    }

    private var speedLabels: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                ForEach(Array(speeds.enumerated()), id: \.offset) { index, speed in
                    let xPosition = geometry.size.width * CGFloat(index) / CGFloat(speeds.count - 1)
                    Text(String(format: "%gx", speed))
                        .font(.flixor(.caption))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 44)
                        .offset(x: xPosition - 22)
                }
            }
        }
        .frame(height: 14)
    }
}
