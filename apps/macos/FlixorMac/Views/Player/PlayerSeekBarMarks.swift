//
//  PlayerSeekBarMarks.swift
//  FlixorMac
//
//  Chapter ticks and intro/recap/credits ranges drawn on the seek bar. A single
//  non-interactive layer: it never takes the seek bar's drag or hover.
//

import SwiftUI

/// Seek bar marks as fractions of the duration (0...1).
struct SeekBarMarksModel: Equatable {
    struct Segment: Equatable {
        let start: Double
        let end: Double
    }

    let segments: [Segment]
    let ticks: [Double]

    init(markers: [PlayerMarker], chapters: [MPVChapter], duration: TimeInterval) {
        guard duration > 0 else {
            segments = []
            ticks = []
            return
        }
        let durationMs = duration * 1000
        segments = markers.compactMap { marker in
            guard marker.segmentType != nil else { return nil }
            let start = max(0, Double(marker.startTimeOffset) / durationMs)
            let end = min(1, Double(marker.endTimeOffset) / durationMs)
            return end > start ? Segment(start: start, end: end) : nil
        }
        // A tick at the very start or end of the bar marks nothing useful.
        ticks = chapters.compactMap { chapter in
            guard chapter.time > 1, chapter.time < duration - 1 else { return nil }
            return chapter.time / duration
        }
    }
}

/// `.equatable()` keeps playback-time updates from redrawing the marks.
struct SeekBarMarksView: View, Equatable {
    let model: SeekBarMarksModel
    let segmentColor: Color

    private let barHeight: CGFloat = 4
    private let tickHeight: CGFloat = 8
    private let tickWidth: CGFloat = 2
    private let minimumSegmentWidth: CGFloat = 2

    var body: some View {
        Canvas { context, size in
            let barTop = (size.height - barHeight) / 2
            for segment in model.segments {
                let x = size.width * segment.start
                let width = max(minimumSegmentWidth, size.width * (segment.end - segment.start))
                context.fill(Path(CGRect(x: x, y: barTop, width: width, height: barHeight)), with: .color(segmentColor))
            }

            let tickTop = (size.height - tickHeight) / 2
            for tick in model.ticks {
                let rect = CGRect(x: size.width * tick - tickWidth / 2, y: tickTop, width: tickWidth, height: tickHeight)
                context.fill(Path(rect), with: .color(.white.opacity(DS.Opacity.strong)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
