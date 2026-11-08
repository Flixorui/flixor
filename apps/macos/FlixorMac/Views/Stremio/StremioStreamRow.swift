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
        stream.title ?? stream.name ?? stream.description ?? String(localized: "Unnamed Stream")
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: DS.Space.s10) {
                HStack(alignment: .top, spacing: DS.Space.s12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(rowTitle)
                            .font(.flixor(.body, weight: .semibold))
                            .foregroundStyle(stream.playable ? .white : .secondary)
                            .multilineTextAlignment(.leading)

                        Text(addonName)
                            .font(.flixor(.caption))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if stream.playable {
                        Image(systemName: "play.circle.fill")
                            .font(.flixor(.title3))
                            .foregroundStyle(.orange)
                    }
                }

                HStack(spacing: DS.Space.s8) {
                    if let quality = stream.quality, !quality.isEmpty {
                        badge(quality.uppercased(), color: .blue)
                    }
                    if let size = stream.size, size > 0 {
                        badge(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file), color: .white.opacity(0.7), background: Color.white.opacity(0.06))
                    }
                    if stream.behaviorHints?.cached == true {
                        badge(String(localized: "Cached"), color: .green)
                    }
                    if stream.isDebrid == true {
                        badge(String(localized: "Debrid"), color: .mint)
                    }
                    let subtitleCount = stream.subtitles?.count ?? 0
                    if subtitleCount > 0 {
                        badge(String(localized: "\(subtitleCount) Subs"), color: .purple)
                    }
                }

                if let disabledReason = stream.disabledReason, !stream.playable {
                    Text(disabledReason)
                        .font(.flixor(.caption))
                        .foregroundStyle(.orange)
                }
            }
            .padding(DS.Space.s14)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.r14, style: .continuous)
                    .fill(Color.white.opacity(stream.playable ? 0.05 : 0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.r14, style: .continuous)
                    .stroke(stream.playable ? Color.white.opacity(0.08) : Color.orange.opacity(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!stream.playable)
    }

    private func badge(_ title: String, color: Color, background: Color? = nil) -> some View {
        Text(title)
            .font(.flixor(.micro, weight: .semibold))
            .padding(.horizontal, DS.Space.s8)
            .padding(.vertical, DS.Space.s4)
            .foregroundStyle(color)
            .background(
                Capsule()
                    .fill(background ?? color.opacity(0.14))
            )
    }
}
