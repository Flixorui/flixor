//
//  StremioStreamRow.swift
//  FlixorMac
//

import SwiftUI

struct StremioStreamRow: View {
    let stream: StremioPlayableStream
    let addonName: String
    let onSelect: () -> Void

    private var rowTitle: String {
        stream.title ?? stream.name ?? stream.description ?? "Unnamed Stream"
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(rowTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(stream.playable ? .white : .secondary)
                            .multilineTextAlignment(.leading)

                        Text(addonName)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if stream.playable {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.orange)
                    }
                }

                HStack(spacing: 8) {
                    if let quality = stream.quality, !quality.isEmpty {
                        badge(quality.uppercased(), color: .blue)
                    }
                    if let size = stream.size, size > 0 {
                        badge(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file), color: .white.opacity(0.7), background: Color.white.opacity(0.06))
                    }
                    if stream.behaviorHints?.cached == true {
                        badge("Cached", color: .green)
                    }
                    if stream.isDebrid == true {
                        badge("Debrid", color: .mint)
                    }
                    let subtitleCount = stream.subtitles?.count ?? 0
                    if subtitleCount > 0 {
                        badge("\(subtitleCount) Subs", color: .purple)
                    }
                }

                if let disabledReason = stream.disabledReason, !stream.playable {
                    Text(disabledReason)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(stream.playable ? 0.05 : 0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(stream.playable ? Color.white.opacity(0.08) : Color.orange.opacity(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!stream.playable)
    }

    private func badge(_ title: String, color: Color, background: Color? = nil) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(
                Capsule()
                    .fill(background ?? color.opacity(0.14))
            )
    }
}
