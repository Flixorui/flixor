//
//  DetailsVersionPicker.swift
//  FlixorMac
//
//  Version picker sheet shown before playback
//

import SwiftUI
import FlixorKit

// MARK: - Version Picker Sheet

struct VersionPickerSheet: View {
    let versions: [DetailsViewModel.VersionDetail]
    let title: String
    let onSelect: (DetailsViewModel.VersionDetail) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Select Version")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            // Subtitle
            Text("Multiple versions available for \"\(title)\"")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 16)
                .padding(.horizontal, 20)

            // Version list
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(versions) { version in
                        VersionRowButton(version: version) {
                            onSelect(version)
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 500, height: min(CGFloat(versions.count) * 90 + 180, 500))
        .background(.ultraThinMaterial)
    }
}

private struct VersionRowButton: View {
    let version: DetailsViewModel.VersionDetail
    let onTap: () -> Void

    @State private var isHovered = false

    private var resolutionBadge: String? {
        guard let res = version.technical.resolution else { return nil }
        let width = Int(res.split(separator: "x").first ?? "0") ?? 0
        if width >= 3800 { return "4K" }
        if width >= 1900 { return "1080p" }
        if width >= 1260 { return "720p" }
        return nil
    }

    private var fileSizeText: String? {
        guard let mb = version.technical.fileSizeMB else { return nil }
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024)
        }
        return String(format: "%.0f MB", mb)
    }

    private var hasAtmos: Bool {
        guard let audioCodec = version.technical.audioCodec?.lowercased() else { return false }
        return audioCodec.contains("truehd") || audioCodec.contains("atmos")
    }

    private var hasCC: Bool {
        // Show CC badge if any subtitles are available
        !version.subtitleTracks.isEmpty
    }

    private var hasSDH: Bool {
        version.subtitleTracks.contains { track in
            let name = track.name.uppercased()
            return name.contains("SDH") || name.contains("DEAF") || name.contains("HARD OF HEARING")
        }
    }

    private var hasAD: Bool {
        version.audioTracks.contains { track in
            let name = track.name.uppercased()
            return name.contains("AUDIO DESC") || name.contains("DESCRIPTIVE") || name.contains(" AD")
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Play icon
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white)

                // Version info
                VStack(alignment: .leading, spacing: 6) {
                    // Main label (e.g., "4K HEVC 8CH")
                    Text(version.label)
                        .font(.headline)
                        .foregroundStyle(.white)

                    // Technical badges row
                    HStack(spacing: 6) {
                        // Resolution badge (4K, HD, etc.)
                        if let res = resolutionBadge {
                            TechnicalBadge(text: res, isHighlighted: false)
                        }

                        // HDR/Dolby Vision badge
                        if let hdr = version.technical.hdrFormat {
                            TechnicalBadge(text: hdr, isHighlighted: true)
                        }

                        // Dolby Atmos badge
                        if hasAtmos {
                            TechnicalBadge(text: "Dolby Atmos", isHighlighted: false)
                        }

                        // CC badge
                        if hasCC {
                            TechnicalBadge(text: "CC", isHighlighted: false)
                        }

                        // SDH badge
                        if hasSDH {
                            TechnicalBadge(text: "SDH", isHighlighted: false)
                        }

                        // AD badge
                        if hasAD {
                            TechnicalBadge(text: "AD", isHighlighted: false)
                        }
                    }

                    // Additional info row
                    HStack(spacing: 8) {
                        if let codec = version.technical.videoCodec?.uppercased() {
                            Text(codec)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let channels = version.technical.audioChannels {
                            Text("\(channels)CH")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let bitrate = version.technical.bitrate, bitrate > 0 {
                            Text("·")
                                .foregroundStyle(.secondary)
                            Text(bitrate >= 1000 ? "\(bitrate / 1000) Mbps" : "\(bitrate) Kbps")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let size = fileSizeText {
                            Text("·")
                                .foregroundStyle(.secondary)
                            Text(size)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isHovered ? Color.white.opacity(0.15) : Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(isHovered ? 0.3 : 0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
