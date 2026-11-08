//
//  PlayerTrackMenus.swift
//  FlixorMac
//
//  Audio/subtitle/source modal (tracks, sync offsets, subtitle styling) and playback speed modal
//

import SwiftUI

// MARK: - Audio & Subtitles Combined Modal

struct AudioSubtitlesModal: View {
    @ObservedObject var viewModel: PlayerViewModel
    let onClose: () -> Void

    @State private var selectedTab: Int = 0 // 0 = Audio, 1 = Subtitles, 2 = Sources

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
                if viewModel.canSwitchStreamSources {
                    TabButton(title: "Sources", isSelected: selectedTab == 2) { selectedTab = 2 }
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)

            Divider().background(Color.white.opacity(0.1)).padding(.top, 8)

            // Tab Content
            if selectedTab == 0 {
                AudioTabContent(viewModel: viewModel)
            } else if selectedTab == 1 {
                SubtitlesTabContent(viewModel: viewModel)
            } else {
                SourcesTabContent(viewModel: viewModel)
            }
        }
        .frame(width: 340)
        .background(Color.black.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
        .padding(.trailing, 32)
        .padding(.bottom, 140)
    }
}

private struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isSelected ? Color.white.opacity(0.1) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
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
                VStack(spacing: 2) {
                    ForEach(viewModel.availableAudioTracks, id: \.id) { track in
                        TrackRow(
                            title: track.displayName,
                            isSelected: track.id == viewModel.currentAudioTrackId
                        ) {
                            viewModel.setAudioTrack(track.id)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
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
            .padding(12)
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
                VStack(alignment: .leading, spacing: 10) {
                    VStack(spacing: 2) {
                        TrackRow(title: "Off", isSelected: viewModel.currentSubtitleTrackId == nil && viewModel.selectedExternalSubtitleId == nil) {
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
                        VStack(alignment: .leading, spacing: 6) {
                            Text("External")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)

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
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
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
            .padding(.horizontal, 12)
            .padding(.top, 12)

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

private struct SourcesTabContent: View {
    @ObservedObject var viewModel: PlayerViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(viewModel.availableStremioSources) { source in
                    Button(action: { viewModel.switchStreamSource(source) }) {
                        HStack(spacing: 10) {
                            Image(systemName: source.id == viewModel.currentStremioSourceId ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 16))
                                .foregroundStyle(source.id == viewModel.currentStremioSourceId ? Color.accentColor : .white.opacity(0.3))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.title ?? source.name ?? "Source")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text(source.addonName ?? "Stremio")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if let quality = source.quality {
                                Text(quality.uppercased())
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.16), in: Capsule())
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(source.id == viewModel.currentStremioSourceId ? Color.white.opacity(0.08) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(maxHeight: 180)
    }
}

private struct TrackRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Color.accentColor : .white.opacity(0.3))

                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.7))
                    .lineLimit(1)

                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(isSelected ? Color.white.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

private struct SyncOffsetControl: View {
    let label: String
    let value: Double
    let onDecrement: () -> Void
    let onIncrement: () -> Void
    let onReset: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.8))

            Spacer()

            HStack(spacing: 8) {
                // Decrement button
                Button(action: onDecrement) {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                // Value display (tappable to reset)
                Button(action: onReset) {
                    Text(String(format: "%+.0fms", value * 1000))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(value == 0 ? .white.opacity(0.6) : .orange)
                        .frame(width: 70)
                }
                .buttonStyle(.plain)
                .help("Click to reset")

                // Increment button
                Button(action: onIncrement) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct CompactSliderRow: View {
    let label: String
    let value: String
    let sliderValue: Double
    let range: ClosedRange<Double>
    let step: Double
    let onChange: (Double) -> Void

    @State private var localValue: Double = 0

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 70, alignment: .leading)

            Slider(value: $localValue, in: range, step: step)
                .tint(Color.accentColor)
                .onAppear { localValue = sliderValue }
                .onChange(of: localValue) { newValue in onChange(newValue) }

            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 40, alignment: .trailing)
        }
    }
}

// MARK: - Playback Speed Modal

struct PlaybackSpeedModal: View {
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
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 24)
                .padding(.bottom, 20)

            speedSlider
                .padding(.bottom, 24)
        }
        .frame(width: 600, height: 240)
        .background(Color.black.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.trailing, 32)
        .padding(.bottom, 140)
    }

    private var speedSlider: some View {
        VStack(spacing: 16) {
            // Current speed display
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s8) {
                Text(String(format: "%.2fx", displaySpeed))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)

                if abs(displaySpeed - 1.0) < 0.01 {
                    Text("Normal")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            // Draggable slider track
            GeometryReader { geometry in
                draggableTrack(width: geometry.size.width)
            }
            .frame(height: 28)
            .padding(.horizontal, 40)

            // Speed labels
            speedLabels
                .padding(.horizontal, 40)
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
            .cornerRadius(2)
    }

    private func progressFill(width: CGFloat) -> some View {
        Rectangle()
            .fill(Color.white)
            .frame(width: width, height: 4)
            .cornerRadius(2)
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
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 44)
                        .offset(x: xPosition - 22)
                }
            }
        }
        .frame(height: 14)
    }
}
