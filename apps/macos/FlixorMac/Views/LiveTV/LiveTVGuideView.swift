//
//  LiveTVGuideView.swift
//  FlixorMac
//
//  Personal build only (FLIXOR_LIVE_TV). Time grid for the current filter: a
//  three-hour window from the half hour, stepped an hour at a time, with a now
//  line, and a details card (artwork, description, guide source) per program.
//

#if FLIXOR_LIVE_TV
import SwiftUI

struct LiveTVGuideView: View {
    @ObservedObject private var store = LiveTVStore.shared
    let onPlay: (LiveChannel) -> Void
    /// Hours from the current half hour.
    @State private var offsetHours = 0
    @State private var selected: (channel: LiveChannel, program: LiveProgram)?
    @Environment(\.flixorTheme) private var theme

    private static let windowMinutes: Double = 180
    private static let channelColumn: CGFloat = 220
    private static let rowHeight: CGFloat = 64

    private var origin: Date {
        let half = floor(store.now.timeIntervalSince1970 / 1800) * 1800
        return Date(timeIntervalSince1970: half + Double(offsetHours) * 3600)
    }

    var body: some View {
        let channels = store.filteredChannels
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: DS.Space.s4) {
                    Text("Guide").flixorFont(.largeTitle, weight: .bold)
                    Text("\(store.market.title) · \(LiveTVStore.genreLabel(store.genre, market: store.market)) · \(channels.count) channels")
                        .flixorFont(.callout).foregroundStyle(theme.textTertiary)
                }
                Spacer()
                HStack(spacing: DS.Space.s8) {
                    LiveTVIconButton(icon: "chevron.left", help: "Earlier", size: 32) { offsetHours = max(-2, offsetHours - 1) }
                        .disabled(offsetHours <= -2).opacity(offsetHours <= -2 ? 0.35 : 1)
                    LiveTVPillButton(title: "Now", prominent: offsetHours == 0) { offsetHours = 0 }
                    LiveTVIconButton(icon: "chevron.right", help: "Later", size: 32) { offsetHours = min(12, offsetHours + 1) }
                }
            }
            .padding(.horizontal, DS.Space.s32)
            .padding(.top, DS.Space.s12)
            .padding(.bottom, DS.Space.s16)

            GeometryReader { geo in
                let width = max(320, geo.size.width - Self.channelColumn - DS.Space.s32 * 2)
                let perMinute = width / Self.windowMinutes
                VStack(spacing: 0) {
                    timeHeader(perMinute: perMinute, width: width)
                    ScrollView {
                        LazyVStack(spacing: DS.Space.s4) {
                            ForEach(channels) { channel in
                                guideRow(channel, perMinute: perMinute, width: width)
                                    .onAppear { store.noteGuideVisible(channel.id) }
                                    .onDisappear { store.noteGuideHidden(channel.id) }
                            }
                        }
                        .padding(.top, DS.Space.s8)
                        .padding(.bottom, 200)
                    }
                }
                .padding(.horizontal, DS.Space.s32)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let selected {
                detailsCard(selected.channel, selected.program)
                    .padding(DS.Space.s24)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(DS.Motion.standard, value: selected?.program.id)
    }

    private func timeHeader(perMinute: CGFloat, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text(Calendar.current.isDateInToday(origin) ? "Today" : origin.formatted(.dateTime.weekday(.wide)))
                .flixorFont(.footnote, weight: .semibold).foregroundStyle(theme.textSecondary)
                .frame(width: Self.channelColumn, alignment: .leading)
            ZStack(alignment: .topLeading) {
                ForEach(0..<6, id: \.self) { i in
                    Text(LiveTVFormat.time.string(from: origin.addingTimeInterval(Double(i) * 1800)))
                        .flixorFont(.footnote).foregroundStyle(theme.textTertiary)
                        .offset(x: CGFloat(i) * 30 * perMinute + 4)
                }
                let nowX = store.now.timeIntervalSince(origin) / 60 * perMinute
                if nowX >= 0 && nowX <= width {
                    Circle().fill(Color.flixorBrand).frame(width: 8, height: 8).offset(x: nowX - 3, y: 18)
                }
            }
            .frame(width: width, alignment: .leading)
        }
        .frame(height: 28)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.separator).frame(height: DS.Border.hairline) }
    }

    private func guideRow(_ channel: LiveChannel, perMinute: CGFloat, width: CGFloat) -> some View {
        let entry = store.guideEntry(for: channel)
        let start = origin
        let end = origin.addingTimeInterval(Self.windowMinutes * 60)
        let programs = (entry?.programs ?? []).filter { $0.end > start && $0.start < end }
        return HStack(spacing: 0) {
            Button { onPlay(channel) } label: {
                HStack(spacing: DS.Space.s10) {
                    LiveTVLogo(channel: channel, width: 48, height: 32)
                    Text(channel.displayName).flixorFont(.callout, weight: .semibold).foregroundStyle(theme.textPrimary).lineLimit(2)
                    Spacer(minLength: DS.Space.s8)
                }
                .frame(width: Self.channelColumn, height: Self.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Watch \(channel.displayName)")

            ZStack(alignment: .topLeading) {
                if programs.isEmpty {
                    RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                        .frame(width: width - 2, height: Self.rowHeight - 8)
                        .padding(.vertical, 4)
                        .overlay(alignment: .leading) {
                            Text(entry == nil ? "Loading…" : "Schedule not available")
                                .flixorFont(.footnote).foregroundStyle(theme.textTertiary).padding(.leading, DS.Space.s12)
                        }
                }
                ForEach(programs) { program in
                    let x0 = max(0, program.start.timeIntervalSince(start) / 60) * perMinute
                    let x1 = min(Self.windowMinutes, program.end.timeIntervalSince(start) / 60) * perMinute
                    programCell(channel, program, width: max(6, x1 - x0 - 4))
                        .offset(x: x0)
                }
                let nowX = store.now.timeIntervalSince(start) / 60 * perMinute
                if nowX >= 0 && nowX <= width {
                    Rectangle().fill(Color.flixorBrand.opacity(0.9)).frame(width: 2, height: Self.rowHeight).offset(x: nowX)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: width, height: Self.rowHeight, alignment: .topLeading)
            .clipped()
        }
    }

    private func programCell(_ channel: LiveChannel, _ program: LiveProgram, width: CGFloat) -> some View {
        let airing = program.isAiring(at: store.now)
        let isSelected = selected?.program.id == program.id && selected?.channel == channel
        return Button {
            if isSelected, airing { onPlay(channel) } else { selected = (channel, program) }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(program.title)
                    .flixorFont(.callout, weight: airing ? .semibold : .medium)
                    .foregroundStyle(airing ? theme.textPrimary : theme.textSecondary)
                    .lineLimit(1)
                Text(LiveTVFormat.range(program)).flixorFont(.caption).foregroundStyle(theme.textTertiary).lineLimit(1)
            }
            .padding(.horizontal, DS.Space.s12)
            .frame(width: width, height: Self.rowHeight - 8, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                    .fill(Color.white.opacity(airing ? 0.11 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                    .strokeBorder(isSelected ? Color.white : .clear, lineWidth: DS.Border.focus)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }

    private func detailsCard(_ channel: LiveChannel, _ program: LiveProgram) -> some View {
        let airing = program.isAiring(at: store.now)
        let source = store.guideEntry(for: channel)?.source
        return VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Rectangle().fill(theme.surface)
                    LiveTVLogo(channel: channel, width: 110, height: 60, plain: true)
                    if store.guideServer?.isComplete == true, airing {
                        LiveTVRemoteImage(path: LiveTVArtwork.thumbnailPath(channelId: channel.id, title: program.title)) { Color.clear }
                    }
                    LinearGradient(colors: [.clear, theme.surfaceElevated], startPoint: .center, endPoint: .bottom)
                }
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .clipped()
                LiveTVIconButton(icon: "xmark", help: "Close", size: 28) { selected = nil }
                    .padding(DS.Space.s10)
            }
            VStack(alignment: .leading, spacing: DS.Space.s8) {
                HStack(spacing: DS.Space.s8) {
                    if airing { LiveBadge() }
                    Text("\(channel.displayName) · \(LiveTVFormat.range(program))")
                        .flixorFont(.footnote).foregroundStyle(theme.textSecondary).lineLimit(1)
                }
                Text(program.title).flixorFont(.title3, weight: .bold).lineLimit(2)
                if let metadata = program.metadata, !metadata.isEmpty {
                    Text(metadata).flixorFont(.footnote).foregroundStyle(theme.textTertiary).lineLimit(1)
                }
                if !program.description.isEmpty {
                    Text(program.description).flixorFont(.callout).foregroundStyle(theme.textSecondary).lineLimit(4)
                }
                if airing {
                    LiveTVProgressBar(value: LiveTVFormat.progress(program, now: store.now))
                        .padding(.top, DS.Space.s2)
                }
                HStack(spacing: DS.Space.s8) {
                    if airing {
                        LiveTVPillButton(icon: "play.fill", title: "Watch live", prominent: true) { onPlay(channel) }
                            .keyboardShortcut(.defaultAction)
                    } else {
                        Text("Starts at \(LiveTVFormat.time.string(from: program.start))")
                            .flixorFont(.callout, weight: .semibold).foregroundStyle(theme.textSecondary)
                    }
                    Spacer()
                    LiveTVIconButton(icon: store.isFavorite(channel) ? "star.fill" : "star",
                                     help: store.isFavorite(channel) ? "Remove from Favorites" : "Add to Favorites", size: 32) {
                        store.toggleFavorite(channel)
                    }
                }
                .padding(.top, DS.Space.s4)
                if let source {
                    Text(source).flixorFont(.caption).foregroundStyle(theme.textTertiary).lineLimit(2)
                }
            }
            .padding(DS.Space.s16)
        }
        .frame(width: 360)
        .background(theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sheet, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.sheet, style: .continuous).strokeBorder(theme.separator, lineWidth: DS.Border.thin))
        .flixorShadow(.modal)
    }
}
#endif
