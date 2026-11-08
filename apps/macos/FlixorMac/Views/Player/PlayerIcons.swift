//
//  PlayerIcons.swift
//  FlixorMac
//
//  Custom icon views used by the player controls
//

import SwiftUI

// MARK: - Custom PNG Icons

struct BackArrowIcon: View {
    var body: some View {
        if let nsImage = NSImage(named: "back-arrow") {
            Image(nsImage: nsImage)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "chevron.left")
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

struct PlayIcon: View {
    var body: some View {
        if let nsImage = NSImage(named: "play") {
            Image(nsImage: nsImage)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "play.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

struct PauseIcon: View {
    var body: some View {
        if let nsImage = NSImage(named: "pause") {
            Image(nsImage: nsImage)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "pause.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

struct Replay10Icon: View {
    var body: some View {
        if let nsImage = NSImage(named: "replay10") {
            Image(nsImage: nsImage)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "gobackward.10")
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

struct Forward10Icon: View {
    var body: some View {
        if let nsImage = NSImage(named: "forward10") {
            Image(nsImage: nsImage)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "goforward.10")
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

struct NextEpisodeIcon: View {
    var body: some View {
        if let nsImage = NSImage(named: "next-episode") {
            Image(nsImage: nsImage)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "forward.end.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

struct EpisodeListIcon: View {
    var body: some View {
        if let nsImage = NSImage(named: "episode-list") {
            Image(nsImage: nsImage)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "list.bullet")
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

struct FullscreenEnterIcon: View {
    var body: some View {
        if let nsImage = NSImage(named: "fullscreen-enter") {
            Image(nsImage: nsImage)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

struct FullscreenExitIcon: View {
    var body: some View {
        if let nsImage = NSImage(named: "fullscreen-exit") {
            Image(nsImage: nsImage)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

struct PlaybackSpeedIcon: View {
    var body: some View {
        if let nsImage = NSImage(named: "playback-speed") {
            Image(nsImage: nsImage)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "gauge")
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

struct SubtitlesIcon: View {
    var body: some View {
        if let nsImage = NSImage(named: "subtitles") {
            Image(nsImage: nsImage)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "captions.bubble")
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

// MARK: - Volume Components

struct VolumeIcon: View {
    let volume: Float
    let isMuted: Bool

    var body: some View {
        let level: VolumeLevel = isMuted || volume == 0 ? .off : volume <= 0.33 ? .low : volume <= 0.66 ? .medium : .high

        GeometryReader { geometry in
            Path { path in
                switch level {
                case .off:
                    // Volume off with X
                    path.addPath(volumeOffPath(in: geometry.size))
                case .low:
                    // Low volume - one wave
                    path.addPath(volumeLowPath(in: geometry.size))
                case .medium:
                    // Medium volume - two waves
                    path.addPath(volumeMediumPath(in: geometry.size))
                case .high:
                    // High volume - three waves
                    path.addPath(volumeHighPath(in: geometry.size))
                }
            }
            .fill(Color.white)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    enum VolumeLevel {
        case off, low, medium, high
    }

    private func volumeOffPath(in size: CGSize) -> Path {
        let scale = size.width / 24
        var path = Path()
        // Speaker base
        path.move(to: CGPoint(x: 11 * scale, y: 4 * scale))
        path.addLine(to: CGPoint(x: 11 * scale, y: 20 * scale))
        path.addLine(to: CGPoint(x: 4.586 * scale, y: 16 * scale))
        path.addLine(to: CGPoint(x: 1 * scale, y: 16 * scale))
        path.addLine(to: CGPoint(x: 1 * scale, y: 8 * scale))
        path.addLine(to: CGPoint(x: 4.586 * scale, y: 8 * scale))
        path.closeSubpath()
        // X mark
        path.move(to: CGPoint(x: 15.293 * scale, y: 9.707 * scale))
        path.addLine(to: CGPoint(x: 17.586 * scale, y: 12 * scale))
        path.addLine(to: CGPoint(x: 15.293 * scale, y: 14.293 * scale))
        path.addLine(to: CGPoint(x: 16.707 * scale, y: 15.707 * scale))
        path.addLine(to: CGPoint(x: 19 * scale, y: 13.414 * scale))
        path.addLine(to: CGPoint(x: 21.293 * scale, y: 15.707 * scale))
        path.addLine(to: CGPoint(x: 22.707 * scale, y: 14.293 * scale))
        path.addLine(to: CGPoint(x: 20.414 * scale, y: 12 * scale))
        path.addLine(to: CGPoint(x: 22.707 * scale, y: 9.707 * scale))
        path.addLine(to: CGPoint(x: 21.293 * scale, y: 8.293 * scale))
        path.addLine(to: CGPoint(x: 19 * scale, y: 10.586 * scale))
        path.addLine(to: CGPoint(x: 16.707 * scale, y: 8.293 * scale))
        path.closeSubpath()
        return path
    }

    private func volumeLowPath(in size: CGSize) -> Path {
        let scale = size.width / 24
        var path = Path()
        // Speaker base
        path.move(to: CGPoint(x: 11 * scale, y: 4 * scale))
        path.addLine(to: CGPoint(x: 11 * scale, y: 20 * scale))
        path.addLine(to: CGPoint(x: 4.586 * scale, y: 16 * scale))
        path.addLine(to: CGPoint(x: 1 * scale, y: 16 * scale))
        path.addLine(to: CGPoint(x: 1 * scale, y: 8 * scale))
        path.addLine(to: CGPoint(x: 4.586 * scale, y: 8 * scale))
        path.closeSubpath()
        // One wave
        path.move(to: CGPoint(x: 14.243 * scale, y: 7.757 * scale))
        path.addLine(to: CGPoint(x: 12.828 * scale, y: 9.172 * scale))
        path.addCurve(to: CGPoint(x: 14 * scale, y: 12 * scale), control1: CGPoint(x: 13.579 * scale, y: 9.922 * scale), control2: CGPoint(x: 14 * scale, y: 10.939 * scale))
        path.addCurve(to: CGPoint(x: 12.828 * scale, y: 14.828 * scale), control1: CGPoint(x: 14 * scale, y: 13.061 * scale), control2: CGPoint(x: 13.579 * scale, y: 14.078 * scale))
        path.addLine(to: CGPoint(x: 14.243 * scale, y: 16.243 * scale))
        path.addCurve(to: CGPoint(x: 16 * scale, y: 12 * scale), control1: CGPoint(x: 15.368 * scale, y: 15.118 * scale), control2: CGPoint(x: 16 * scale, y: 13.591 * scale))
        path.addCurve(to: CGPoint(x: 14.243 * scale, y: 7.757 * scale), control1: CGPoint(x: 16 * scale, y: 10.409 * scale), control2: CGPoint(x: 15.368 * scale, y: 8.882 * scale))
        path.closeSubpath()
        return path
    }

    private func volumeMediumPath(in size: CGSize) -> Path {
        let scale = size.width / 24
        var path = Path()
        // Speaker base
        path.move(to: CGPoint(x: 11 * scale, y: 4 * scale))
        path.addLine(to: CGPoint(x: 11 * scale, y: 20 * scale))
        path.addLine(to: CGPoint(x: 4.586 * scale, y: 16 * scale))
        path.addLine(to: CGPoint(x: 1 * scale, y: 16 * scale))
        path.addLine(to: CGPoint(x: 1 * scale, y: 8 * scale))
        path.addLine(to: CGPoint(x: 4.586 * scale, y: 8 * scale))
        path.closeSubpath()
        // Two waves
        path.move(to: CGPoint(x: 17.071 * scale, y: 4.929 * scale))
        path.addLine(to: CGPoint(x: 15.657 * scale, y: 6.343 * scale))
        path.addCurve(to: CGPoint(x: 18 * scale, y: 12 * scale), control1: CGPoint(x: 17.157 * scale, y: 7.844 * scale), control2: CGPoint(x: 18 * scale, y: 9.878 * scale))
        path.addCurve(to: CGPoint(x: 15.657 * scale, y: 17.657 * scale), control1: CGPoint(x: 18 * scale, y: 14.122 * scale), control2: CGPoint(x: 17.157 * scale, y: 16.156 * scale))
        path.addLine(to: CGPoint(x: 17.071 * scale, y: 19.071 * scale))
        path.addCurve(to: CGPoint(x: 20 * scale, y: 12 * scale), control1: CGPoint(x: 18.946 * scale, y: 17.195 * scale), control2: CGPoint(x: 20 * scale, y: 14.652 * scale))
        path.addCurve(to: CGPoint(x: 17.071 * scale, y: 4.929 * scale), control1: CGPoint(x: 20 * scale, y: 9.348 * scale), control2: CGPoint(x: 18.946 * scale, y: 6.805 * scale))
        path.closeSubpath()
        path.move(to: CGPoint(x: 14.243 * scale, y: 7.757 * scale))
        path.addLine(to: CGPoint(x: 12.828 * scale, y: 9.172 * scale))
        path.addCurve(to: CGPoint(x: 14 * scale, y: 12 * scale), control1: CGPoint(x: 13.579 * scale, y: 9.922 * scale), control2: CGPoint(x: 14 * scale, y: 10.939 * scale))
        path.addCurve(to: CGPoint(x: 12.828 * scale, y: 14.828 * scale), control1: CGPoint(x: 14 * scale, y: 13.061 * scale), control2: CGPoint(x: 13.579 * scale, y: 14.078 * scale))
        path.addLine(to: CGPoint(x: 14.243 * scale, y: 16.243 * scale))
        path.addCurve(to: CGPoint(x: 16 * scale, y: 12 * scale), control1: CGPoint(x: 15.368 * scale, y: 15.118 * scale), control2: CGPoint(x: 16 * scale, y: 13.591 * scale))
        path.addCurve(to: CGPoint(x: 14.243 * scale, y: 7.757 * scale), control1: CGPoint(x: 16 * scale, y: 10.409 * scale), control2: CGPoint(x: 15.368 * scale, y: 8.882 * scale))
        path.closeSubpath()
        return path
    }

    private func volumeHighPath(in size: CGSize) -> Path {
        let scale = size.width / 24
        var path = Path()
        // Speaker base
        path.move(to: CGPoint(x: 11 * scale, y: 4 * scale))
        path.addLine(to: CGPoint(x: 11 * scale, y: 20 * scale))
        path.addLine(to: CGPoint(x: 4.586 * scale, y: 16 * scale))
        path.addLine(to: CGPoint(x: 1 * scale, y: 16 * scale))
        path.addLine(to: CGPoint(x: 1 * scale, y: 8 * scale))
        path.addLine(to: CGPoint(x: 4.586 * scale, y: 8 * scale))
        path.closeSubpath()
        // Three waves
        path.move(to: CGPoint(x: 19.9 * scale, y: 2.1 * scale))
        path.addLine(to: CGPoint(x: 18.485 * scale, y: 3.515 * scale))
        path.addCurve(to: CGPoint(x: 22 * scale, y: 12 * scale), control1: CGPoint(x: 20.736 * scale, y: 5.765 * scale), control2: CGPoint(x: 22 * scale, y: 8.817 * scale))
        path.addCurve(to: CGPoint(x: 18.485 * scale, y: 20.485 * scale), control1: CGPoint(x: 22 * scale, y: 15.183 * scale), control2: CGPoint(x: 20.736 * scale, y: 18.235 * scale))
        path.addLine(to: CGPoint(x: 19.9 * scale, y: 21.9 * scale))
        path.addCurve(to: CGPoint(x: 24 * scale, y: 12 * scale), control1: CGPoint(x: 22.525 * scale, y: 19.274 * scale), control2: CGPoint(x: 24 * scale, y: 15.713 * scale))
        path.addCurve(to: CGPoint(x: 19.9 * scale, y: 2.1 * scale), control1: CGPoint(x: 24 * scale, y: 8.287 * scale), control2: CGPoint(x: 22.525 * scale, y: 4.726 * scale))
        path.closeSubpath()
        path.move(to: CGPoint(x: 17.071 * scale, y: 4.929 * scale))
        path.addLine(to: CGPoint(x: 15.657 * scale, y: 6.343 * scale))
        path.addCurve(to: CGPoint(x: 18 * scale, y: 12 * scale), control1: CGPoint(x: 17.157 * scale, y: 7.844 * scale), control2: CGPoint(x: 18 * scale, y: 9.878 * scale))
        path.addCurve(to: CGPoint(x: 15.657 * scale, y: 17.657 * scale), control1: CGPoint(x: 18 * scale, y: 14.122 * scale), control2: CGPoint(x: 17.157 * scale, y: 16.156 * scale))
        path.addLine(to: CGPoint(x: 17.071 * scale, y: 19.071 * scale))
        path.addCurve(to: CGPoint(x: 20 * scale, y: 12 * scale), control1: CGPoint(x: 18.946 * scale, y: 17.195 * scale), control2: CGPoint(x: 20 * scale, y: 14.652 * scale))
        path.addCurve(to: CGPoint(x: 17.071 * scale, y: 4.929 * scale), control1: CGPoint(x: 20 * scale, y: 9.348 * scale), control2: CGPoint(x: 18.946 * scale, y: 6.805 * scale))
        path.closeSubpath()
        path.move(to: CGPoint(x: 14.243 * scale, y: 7.757 * scale))
        path.addLine(to: CGPoint(x: 12.828 * scale, y: 9.172 * scale))
        path.addCurve(to: CGPoint(x: 14 * scale, y: 12 * scale), control1: CGPoint(x: 13.579 * scale, y: 9.922 * scale), control2: CGPoint(x: 14 * scale, y: 10.939 * scale))
        path.addCurve(to: CGPoint(x: 12.828 * scale, y: 14.828 * scale), control1: CGPoint(x: 14 * scale, y: 13.061 * scale), control2: CGPoint(x: 13.579 * scale, y: 14.078 * scale))
        path.addLine(to: CGPoint(x: 14.243 * scale, y: 16.243 * scale))
        path.addCurve(to: CGPoint(x: 16 * scale, y: 12 * scale), control1: CGPoint(x: 15.368 * scale, y: 15.118 * scale), control2: CGPoint(x: 16 * scale, y: 13.591 * scale))
        path.addCurve(to: CGPoint(x: 14.243 * scale, y: 7.757 * scale), control1: CGPoint(x: 16 * scale, y: 10.409 * scale), control2: CGPoint(x: 15.368 * scale, y: 8.882 * scale))
        path.closeSubpath()
        return path
    }
}
