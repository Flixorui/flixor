//
//  LiveTVChannelList.swift
//  FlixorMac
//
//  Personal build only (FLIXOR_LIVE_TV). The channel grid: one card per
//  channel with the airing program's artwork (from the xtream-web server),
//  the channel logo, now/next and a live progress bar. Also the channel
//  details and custom order sheets.
//

#if FLIXOR_LIVE_TV
import SwiftUI

struct LiveTVChannelGrid: View {
    @ObservedObject private var store = LiveTVStore.shared
    let onPlay: (LiveChannel) -> Void
    @Binding var showOrder: Bool
    @State private var details: LiveChannel?
    @Environment(\.flixorTheme) private var theme

    private let columns = [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: DS.Space.s20, alignment: .top)]

    var body: some View {
        let channels = store.filteredChannels
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s20) {
                header(count: channels.count)
                if channels.isEmpty {
                    Text(emptyText)
                        .flixorFont(.body).foregroundStyle(theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: DS.Space.s28) {
                        ForEach(channels) { channel in
                            LiveTVChannelCard(channel: channel, onPlay: { onPlay(channel) }, onDetails: { details = channel })
                                .onAppear { store.noteGuideVisible(channel.id) }
                                .onDisappear { store.noteGuideHidden(channel.id) }
                        }
                    }
                }
            }
            .padding(.horizontal, DS.Space.s32)
            .padding(.top, DS.Space.s12)
            .padding(.bottom, DS.Space.s48)
        }
        .sheet(item: $details) { channel in
            LiveTVChannelDetails(channel: channel) { details = nil }
        }
    }

    private func header(count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s12) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                Text(title).flixorFont(.largeTitle, weight: .bold).foregroundStyle(theme.textPrimary)
                Text(subtitle(count: count)).flixorFont(.callout).foregroundStyle(theme.textTertiary)
            }
            Spacer()
            if let error = store.guideServerError {
                Label("Guide server unavailable", systemImage: "exclamationmark.triangle.fill")
                    .flixorFont(.footnote).foregroundStyle(theme.warning)
                    .help(error)
            }
            Menu {
                Picker("Sort", selection: $store.sort) {
                    ForEach(LiveTVSort.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline)
                Divider()
                Button("Edit custom order…") { showOrder = true }
            } label: {
                HStack(spacing: DS.Space.s6) {
                    Image(systemName: "arrow.up.arrow.down").font(.flixorIcon(DS.Icon.xs, weight: .semibold))
                    Text(store.sort.rawValue).flixorFont(.callout, weight: .semibold)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, DS.Space.s14)
                .frame(height: 32)
                .background(Capsule().fill(Color.white.opacity(0.10)))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var title: String {
        switch store.section {
        case .favorites: return "Favorites"
        case .recent: return "Recent"
        case .channels:
            if store.genre == "All" { return store.market == .us ? "All channels" : "Indian channels" }
            return LiveTVStore.genreLabel(store.genre, market: store.market)
        }
    }

    private func subtitle(count: Int) -> String {
        var parts = ["\(count) channel\(count == 1 ? "" : "s")"]
        if store.section != .channels || store.genre != "All" { parts.insert(store.market.title, at: 0) }
        if store.market == .india, store.language != "All" { parts.append(store.language) }
        if !store.query.isEmpty { parts.append("matching “\(store.query)”") }
        return parts.joined(separator: " · ")
    }

    private var emptyText: String {
        if !store.query.isEmpty { return "No channels match “\(store.query)”." }
        switch store.section {
        case .favorites: return "No favorites yet. Hover a channel and click the star, or press F while watching."
        case .recent: return "Channels you watch show up here."
        case .channels: return "No channels in this category."
        }
    }
}

struct LiveTVChannelCard: View {
    @ObservedObject private var store = LiveTVStore.shared
    let channel: LiveChannel
    let onPlay: () -> Void
    let onDetails: () -> Void
    @State private var hovering = false
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        let entry = store.guideEntry(for: channel)
        let now = store.now
        let current = entry?.current(at: now)
        let next = entry?.next(after: current?.end ?? now)
        let hasServer = store.guideServer?.isComplete == true

        Button(action: onPlay) {
            VStack(alignment: .leading, spacing: DS.Space.s10) {
                ZStack {
                    // Artwork: the airing program's poster, else the logo on a quiet tile.
                    Rectangle().fill(theme.surface)
                    LiveTVLogo(channel: channel, width: 120, height: 64, plain: true)
                    if hasServer {
                        LiveTVRemoteImage(path: LiveTVArtwork.thumbnailPath(channelId: channel.id, title: current?.title)) { Color.clear }
                    }
                    LinearGradient(colors: [.clear, .clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)

                    VStack {
                        HStack(alignment: .top) {
                            LiveTVLogo(channel: channel, width: 52, height: 34)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.r6, style: .continuous))
                            Spacer()
                            if hovering || store.isFavorite(channel) {
                                Button { store.toggleFavorite(channel) } label: {
                                    Image(systemName: store.isFavorite(channel) ? "star.fill" : "star")
                                        .font(.flixorIcon(DS.Icon.sm, weight: .semibold))
                                        .foregroundStyle(store.isFavorite(channel) ? theme.warning : .white)
                                        .frame(width: 30, height: 30)
                                        .background(.ultraThinMaterial, in: Circle())
                                }
                                .buttonStyle(.plain)
                                .help(store.isFavorite(channel) ? "Remove from Favorites" : "Add to Favorites")
                            }
                        }
                        Spacer()
                        HStack(alignment: .bottom) {
                            if current != nil { LiveBadge() }
                            Spacer()
                            if let current {
                                Text(LiveTVFormat.remaining(current, now: now))
                                    .flixorFont(.caption, weight: .semibold).foregroundStyle(.white.opacity(0.9))
                            }
                        }
                    }
                    .padding(DS.Space.s10)

                    if hovering {
                        Image(systemName: "play.fill")
                            .font(.flixorIcon(DS.Icon.xl))
                            .foregroundStyle(.black)
                            .frame(width: 52, height: 52)
                            .background(Circle().fill(.white))
                            .flixorShadow(.floating)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay(alignment: .bottom) {
                    if let current { LiveTVProgressBar(value: LiveTVFormat.progress(current, now: now), height: 3) }
                }
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .strokeBorder(Color.white.opacity(hovering ? 0.22 : 0.06), lineWidth: DS.Border.thin))
                .flixorShadow(hovering ? .floating : .card)
                .scaleEffect(hovering ? 1.03 : 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(current?.title ?? channel.displayName)
                        .flixorFont(.bodyLarge, weight: .semibold)
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    Text(current != nil ? channel.displayName : LiveTVFormat.context(channel))
                        .flixorFont(.footnote)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                    if let next {
                        Text("Next · \(next.title) · \(LiveTVFormat.time.string(from: next.start))")
                            .flixorFont(.caption)
                            .foregroundStyle(theme.textTertiary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(DS.Motion.standard) { hovering = h } }
        .contextMenu {
            Button("Watch") { onPlay() }
            Button(store.isFavorite(channel) ? "Remove from Favorites" : "Add to Favorites") { store.toggleFavorite(channel) }
            Button("Show in Guide") { store.screen = .guide }
            Divider()
            Button("Channel details") { onDetails() }
        }
    }
}

/// Channel identity and evidence, as in xtream-web's details modal.
struct LiveTVChannelDetails: View {
    let channel: LiveChannel
    let onClose: () -> Void
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            HStack(spacing: DS.Space.s14) {
                LiveTVLogo(channel: channel, width: 72, height: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.displayName).flixorFont(.title2, weight: .bold)
                    Text(channel.category).flixorFont(.callout).foregroundStyle(theme.textSecondary)
                }
                Spacer()
                LiveTVIconButton(icon: "xmark", help: "Close", size: 30, action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            VStack(alignment: .leading, spacing: DS.Space.s8) {
                detail("Provider name", channel.originalName)
                detail("Feed", channel.feed)
                detail("Genre", channel.genre)
                if let location = channel.location { detail("Station", "\(location.callsign) · \(location.city), \(location.state)") }
                detail("Sources", channel.sources.isEmpty ? "1 (no verified alternates)" : "\(channel.sources.count) verified")
            }
            if let evidence = channel.evidence {
                Rectangle().fill(theme.separator).frame(height: DS.Border.hairline)
                Text("Evidence · \(evidence.status)").flixorFont(.headline, weight: .semibold)
                Text(evidence.note).flixorFont(.callout).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                Text("Checked \(evidence.checkedAt)").flixorFont(.caption).foregroundStyle(theme.textTertiary)
            }
        }
        .padding(DS.Space.s24)
        .frame(width: 500)
        .background(theme.surfaceElevated)
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s12) {
            Text(label).flixorFont(.callout).foregroundStyle(theme.textTertiary).frame(width: 110, alignment: .leading)
            Text(value).flixorFont(.callout).foregroundStyle(theme.textPrimary).textSelection(.enabled)
        }
    }
}

/// Custom channel order (the reorder modal in tv-app.tsx).
struct LiveTVCustomOrderSheet: View {
    @ObservedObject private var store = LiveTVStore.shared
    let onClose: () -> Void
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        let ordered = store.customOrderedLineup
        VStack(alignment: .leading, spacing: DS.Space.s12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Custom channel order").flixorFont(.title2, weight: .bold)
                    Text("Used when Sort is set to Custom.").flixorFont(.callout).foregroundStyle(theme.textSecondary)
                }
                Spacer()
                LiveTVIconButton(icon: "xmark", help: "Done", size: 30, action: onClose).keyboardShortcut(.cancelAction)
            }
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(ordered.enumerated()), id: \.element) { index, channel in
                        HStack(spacing: DS.Space.s12) {
                            LiveTVLogo(channel: channel, width: 40, height: 26)
                            Text(channel.displayName).flixorFont(.body)
                            Spacer()
                            LiveTVIconButton(icon: "chevron.up", size: 26) { store.moveChannel(channel.id, by: -1) }
                                .disabled(index == 0).opacity(index == 0 ? 0.3 : 1)
                            LiveTVIconButton(icon: "chevron.down", size: 26) { store.moveChannel(channel.id, by: 1) }
                                .disabled(index == ordered.count - 1).opacity(index == ordered.count - 1 ? 0.3 : 1)
                        }
                        .padding(.horizontal, DS.Space.s10).padding(.vertical, DS.Space.s6)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.button).fill(index % 2 == 0 ? theme.surfaceOverlay : .clear))
                    }
                }
            }
            .frame(height: 440)
        }
        .padding(DS.Space.s24)
        .frame(width: 480)
        .background(theme.surfaceElevated)
    }
}
#endif
