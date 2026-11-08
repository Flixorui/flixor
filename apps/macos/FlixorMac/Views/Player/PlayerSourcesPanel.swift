//
//  PlayerSourcesPanel.swift
//  FlixorMac
//
//  Switch addon source during playback. Playback continues from the same spot.
//

import SwiftUI

struct PlayerSourcesPanel: View {
    @Environment(\.flixorTheme) private var theme
    @ObservedObject var viewModel: PlayerViewModel
    let onClose: () -> Void

    private var groups: [(addon: String, sources: [StremioPlayableStream])] {
        var order: [String] = []
        var byAddon: [String: [StremioPlayableStream]] = [:]
        for source in viewModel.availableStremioSources {
            let addon = source.addonName ?? "Stremio"
            if byAddon[addon] == nil { order.append(addon) }
            byAddon[addon, default: []].append(source)
        }
        return order.map { ($0, byAddon[$0] ?? []) }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    panel
                }
            }
        }
        .onAppear { viewModel.refreshStreamSourcesIfNeeded() }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.s12) {
                Text("Sources")
                    .font(.flixor(.bodyLarge, weight: .semibold))
                    .foregroundStyle(.white)
                if viewModel.isLoadingStreamSources {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button(action: { viewModel.refreshStreamSources() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.flixorIcon(DS.Icon.xs, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Refresh sources")
                .accessibilityLabel(Text("Refresh sources"))
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.flixorIcon(DS.Icon.xs, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
            }
            .padding(.horizontal, DS.Space.s16)
            .padding(.vertical, DS.Space.s12)

            Divider().background(Color.white.opacity(0.1))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.Space.s4) {
                    if viewModel.availableStremioSources.isEmpty && !viewModel.isLoadingStreamSources {
                        Text("No other sources found for this title.")
                            .font(.flixor(.callout))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(DS.Space.s16)
                    }
                    ForEach(groups, id: \.addon) { group in
                        Text(group.addon)
                            .font(.flixor(.caption, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.horizontal, DS.Space.s8)
                            .padding(.top, DS.Space.s8)
                        ForEach(group.sources) { source in
                            sourceRow(source)
                        }
                    }
                }
                .padding(DS.Space.s8)
            }
            .frame(maxHeight: 380)
        }
        .frame(width: 440)
        .background(theme.playerPanelBackground())
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r12))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.r12).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
        .padding(.trailing, DS.Space.s32)
        .padding(.bottom, 140)
    }

    private func sourceRow(_ source: StremioPlayableStream) -> some View {
        let isCurrent = source.id == viewModel.currentStremioSourceId
        return Button(action: {
            onClose()
            viewModel.switchStreamSource(source)
        }) {
            HStack(alignment: .top, spacing: DS.Space.s10) {
                Image(systemName: isCurrent ? "checkmark.circle.fill" : "circle")
                    .font(.flixorIcon(DS.Icon.md))
                    .foregroundStyle(isCurrent ? theme.accent : .white.opacity(0.4))

                VStack(alignment: .leading, spacing: DS.Space.s4) {
                    Text(verbatim: source.title ?? source.name ?? String(localized: "Source"))
                        .font(.flixor(.callout))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: DS.Space.s6) {
                        if let quality = source.quality { badge(quality.uppercased(), color: .orange) }
                        if source.isDebrid == true { badge("Debrid", color: .green) }
                        if let size = source.size, size > 0 {
                            badge(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file), color: .white)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, DS.Space.s8)
            .padding(.horizontal, DS.Space.s8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isCurrent ? Color.white.opacity(0.08) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: source.title ?? source.name ?? "Source"))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(verbatim: text)
            .font(.flixor(.micro, weight: .semibold))
            .foregroundStyle(color.opacity(0.9))
            .padding(.horizontal, DS.Space.s6)
            .padding(.vertical, DS.Space.s2)
            .background(color.opacity(0.14), in: Capsule())
    }
}
