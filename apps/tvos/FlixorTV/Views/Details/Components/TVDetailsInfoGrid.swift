import SwiftUI
import FlixorKit

struct TVDetailsInfoGrid: View {
    @ObservedObject var vm: TVDetailsViewModel
    var focusNS: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            // About
            if !vm.overview.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text("About")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                    Text(vm.overview)
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineSpacing(4)
                    HStack(spacing: 12) {
                        if let y = vm.year, !y.isEmpty {
                            TVMetaPill(text: y, isFocusable: true)
                        }
                        if let rt = formattedRuntime(vm.runtime) {
                            TVMetaPill(text: rt, isFocusable: true)
                        }
                        if let cr = vm.rating, !cr.isEmpty {
                            TVMetaPill(text: cr, isFocusable: true)
                        }
                    }
                }
                .padding(.horizontal, 48)
            }

            // Info grid
            VStack(alignment: .leading, spacing: 16) {
                Text("Info")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                HStack(alignment: .top, spacing: 32) {
                    infoCell(title: "Cast", value: castSummary)
                    if !vm.genres.isEmpty { infoCell(title: "Genres", value: vm.genres.joined(separator: ", ")) }
                    if !vm.moodTags.isEmpty { infoCell(title: vm.mediaKind == "tv" ? "This Show Is" : "This Movie Is", value: vm.moodTags.joined(separator: ", ")) }
                }
            }
            .padding(.horizontal, 48)

            // Technical details
            if let tech = vm.activeVersionDetail?.technical {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Technical Details")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)

                    // Single horizontal scroller of chips to reduce clutter
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            if let label = vm.activeVersionDetail?.label, !label.isEmpty { techChip(label: "VERSION", value: label) }
                            if let res = tech.resolution { techChip(label: "RESOLUTION", value: res) }
                            if let v = tech.videoCodec { techChip(label: "VIDEO", value: v.uppercased()) }
                            if let prof = tech.videoProfile { techChip(label: "PROFILE", value: prof.uppercased()) }
                            if let a = tech.audioCodec { techChip(label: "AUDIO", value: a.uppercased()) }
                            if let ch = tech.audioChannels { techChip(label: "CHANNELS", value: String(ch)) }
                            if let b = tech.bitrate { techChip(label: "BITRATE", value: bitrateString(b)) }
                            if let sz = tech.fileSizeMB { techChip(label: "FILE SIZE", value: fileSizeString(sz)) }
                            if let d = tech.durationMin { techChip(label: "RUNTIME", value: "\(d)m") }
                        }
                        .padding(.trailing, 48)
                    }
                    .padding(.bottom, 8)

                    // Audio Tracks
                    if !vm.audioTracks.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Audio Tracks")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(vm.audioTracks) { t in
                                        smallChip(text: t.name)
                                    }
                                }
                                .padding(.trailing, 48)
                            }
                        }
                    }

                    // Subtitles
                    if !vm.subtitleTracks.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Subtitles")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(vm.subtitleTracks) { t in
                                        smallChip(text: (t.language ?? t.name))
                                    }
                                }
                                .padding(.trailing, 48)
                            }
                        }
                    }
                }
                .padding(.horizontal, 48)
            }

            // Cast grid
            if !vm.cast.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Cast & Crew")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(vm.cast) { p in
                                VStack(alignment: .leading, spacing: 8) {
                                    TVImage(url: p.profile, corner: 12, aspect: 2/3)
                                    Text(p.name)
                                        .foregroundStyle(.white)
                                        .font(.system(size: 16, weight: .medium))
                                        .lineLimit(2)
                                }
                                .frame(width: 200)
                                .focusable(true)
                            }
                        }
                        .padding(.horizontal, 48)
                    }
                }
            }
        }
        .padding(.bottom, 40)
    }

    private func infoCell(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 14, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.white.opacity(0.65))
            Text(value)
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(3)
        }
        .frame(maxWidth: 360, alignment: .leading)
    }

    private func techChip(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.3)
                .foregroundStyle(.white.opacity(0.7))
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func smallChip(text: String?) -> some View {
        let value = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return Text(value)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }

    private func formattedRuntime(_ minutes: Int?) -> String? {
        guard let minutes, minutes > 0 else { return nil }
        if minutes >= 60 {
            let h = minutes / 60
            let m = minutes % 60
            return m == 0 ? "\(h)h" : "\(h)h \(m)m"
        }
        return "\(minutes)m"
    }

    private var castSummary: String {
        if vm.cast.isEmpty { return "—" }
        let names = Array(vm.cast.prefix(6)).map { $0.name }
        let more = max(0, vm.cast.count - 6)
        return names.joined(separator: ", ") + (more > 0 ? " +\(more) more" : "")
    }

    private func bitrateString(_ kbps: Int) -> String {
        let mbps = Double(kbps) / 1000.0
        return String(format: "%.1f Mbps", mbps)
    }

    private func fileSizeString(_ mb: Double) -> String {
        if mb >= 1024 { return String(format: "%.2f GB", mb / 1024.0) }
        return String(format: "%.0f MB", mb)
    }
}

// Simple wrapping HStack for chips/grids
private struct WrapHStack<Content: View>: View {
    let spacing: CGFloat
    let content: Content
    init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: spacing)], spacing: spacing) {
            content
        }
    }
}
