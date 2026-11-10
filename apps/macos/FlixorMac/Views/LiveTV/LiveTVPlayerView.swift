//
//  LiveTVPlayerView.swift
//  FlixorMac
//
//  Personal build only (FLIXOR_LIVE_TV). Full-window live video with an
//  overlay in the Flixor player's language: the player's own icons, a channel
//  and program block, a live progress line, and floating panels for audio and
//  subtitles, sources and the channel list.
//

#if FLIXOR_LIVE_TV
import SwiftUI
import AppKit

struct LiveTVPlayerView: View {
    @ObservedObject var player: LiveTVPlayerModel
    @ObservedObject private var store = LiveTVStore.shared
    @Environment(\.flixorTheme) private var theme

    private enum Panel { case none, tracks, sources, channels }

    @State private var overlayVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var panel: Panel = .none
    @State private var numberEntry = ""
    @State private var numberTask: Task<Void, Never>?
    @State private var previousChannel: LiveChannel?
    @State private var isFullScreen = NSApp.keyWindow?.styleMask.contains(.fullScreen) ?? false
    /// Picture in Picture, through the shared mpv PiP window (as the VOD player).
    @State private var isPiPActive = false
    @State private var mpvPiPViewController: NSViewController?
    /// The list the viewer zaps through: the filter at the time playback began.
    @State private var zapList: [LiveChannel] = []

    var body: some View {
        ZStack {
            Color.black
            if let controller = player.controller {
                MPVVideoViewWrapper(mpvController: controller, isPiPActive: $isPiPActive, mpvPiPViewController: $mpvPiPViewController)
                    .onTapGesture(count: 2) { toggleFullScreen() }
                    .onTapGesture { panel != .none ? (panel = .none) : toggleOverlay() }
            }

            if isPiPActive {
                VStack(spacing: DS.Space.s12) {
                    Image(systemName: "pip").font(.flixorIcon(DS.Icon.xxl, weight: .light))
                    Text("Playing in Picture in Picture").flixorFont(.title3, weight: .bold)
                    Text(channel?.displayName ?? "").flixorFont(.callout).foregroundStyle(.white.opacity(0.6))
                    LiveTVPillButton(icon: "pip.exit", title: "Bring back here", prominent: true) { togglePiP() }
                        .padding(.top, DS.Space.s4)
                }
                .foregroundStyle(.white)
            }

            if player.state == .starting || (player.isBuffering && player.state == .playing) {
                VStack(spacing: DS.Space.s12) {
                    ProgressView().controlSize(.large).tint(.white)
                    if let label = player.sourceIndexLabel, player.state == .starting {
                        Text("Trying source \(label)").flixorFont(.footnote).foregroundStyle(.white.opacity(0.7))
                    }
                }
                .allowsHitTesting(false)
            }

            if case .failed(let message) = player.state { errorView(message) }

            if overlayVisible || player.state != .playing || panel != .none {
                overlay.transition(.opacity)
            }

            panelView

            if !numberEntry.isEmpty {
                Text(numberEntry)
                    .font(.system(size: 48, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, DS.Space.s24).padding(.vertical, DS.Space.s10)
                    .background(theme.playerPanelBackground(opacity: 0.8), in: RoundedRectangle(cornerRadius: DS.Radius.r12))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(DS.Space.s40)
                    .allowsHitTesting(false)
            }
        }
        .onContinuousHover { phase in
            if case .active = phase { showOverlay() }
        }
        .animation(DS.Motion.standard, value: overlayVisible)
        .animation(DS.Motion.standard, value: panel)
        .onAppear {
            zapList = store.filteredChannels
            if let playing = store.playing, !zapList.contains(playing) { zapList.insert(playing, at: 0) }
            LiveTVKeyRouter.shared.player = { event in handleKey(event) }
            PlaybackCommandState.shared.isPlayerActive = true
            showOverlay()
        }
        .onDisappear {
            // Never leave a floating window behind with no player feeding it.
            MPVPiPWindowManager.shared.exitPiP()
            LiveTVKeyRouter.shared.player = nil
            PlaybackCommandState.shared.isPlayerActive = false
            hideTask?.cancel()
            NSCursor.setHiddenUntilMouseMoves(false)
        }
        .onChange(of: store.playing) { _ in showOverlay() }
        .onReceive(NotificationCenter.default.publisher(for: .togglePlayPause)) { _ in player.togglePause() }
        .onReceive(NotificationCenter.default.publisher(for: .togglePictureInPicture)) { _ in togglePiP() }
        .onReceive(NotificationCenter.default.publisher(for: .mpvPiPDidClose)) { _ in isPiPActive = false; showOverlay() }
        .onReceive(NotificationCenter.default.publisher(for: .mpvPiPRequestedPlayerClose)) { _ in close() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in isFullScreen = true }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in isFullScreen = false }
    }

    private var channel: LiveChannel? { store.playing }

    // MARK: Overlay

    private var overlay: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.s16) {
                LiveTVPlayerIconButton(help: "Back (Esc)", size: 40) { close() } icon: {
                    BackArrowIcon().frame(width: 26, height: 26)
                }
                if let channel {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(channel.displayName).flixorFont(.headline, weight: .semibold)
                        Text(store.screen == .guide ? "Back to Guide" : "Back to Channels").flixorFont(.caption).foregroundStyle(.white.opacity(0.6))
                    }
                }
                Spacer()
                LiveTVPillButton(icon: "chevron.left", title: "Flixor", help: "Leave Live TV (⌘L)") { store.exit() }
            }
            .padding(.leading, DS.Space.s32)
            .padding(.trailing, DS.Space.s32)
            .padding(.top, DS.Space.s20)
            .padding(.bottom, DS.Space.s48)
            .background(LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: .top, endPoint: .bottom))

            Spacer()

            if let channel { bottomBlock(channel) }
        }
        .foregroundStyle(.white)
    }

    private func bottomBlock(_ channel: LiveChannel) -> some View {
        let entry = store.guideEntry(for: channel)
        let now = store.now
        let current = entry?.current(at: now)
        let next = entry?.next(after: current?.end ?? now)
        return VStack(alignment: .leading, spacing: DS.Space.s14) {
            HStack(alignment: .center, spacing: DS.Space.s16) {
                LiveTVLogo(channel: channel, width: 84, height: 52)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.r6, style: .continuous))
                VStack(alignment: .leading, spacing: DS.Space.s6) {
                    HStack(spacing: DS.Space.s8) {
                        LiveBadge()
                        Text(current != nil ? channel.displayName : LiveTVFormat.context(channel))
                            .flixorFont(.callout, weight: .semibold).foregroundStyle(.white.opacity(0.75))
                    }
                    Text(current?.title ?? channel.displayName)
                        .flixorFont(.title1, weight: .bold).lineLimit(1)
                    if let current, !current.description.isEmpty {
                        Text(current.description).flixorFont(.callout).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                    }
                }
                Spacer(minLength: DS.Space.s24)
                if let next {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Up next · \(LiveTVFormat.time.string(from: next.start))").flixorFont(.caption).foregroundStyle(.white.opacity(0.55))
                        Text(next.title).flixorFont(.callout, weight: .semibold).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                    }
                    .frame(maxWidth: 280, alignment: .trailing)
                }
            }

            if let current {
                HStack(spacing: DS.Space.s12) {
                    Text(LiveTVFormat.time.string(from: current.start)).font(.caption).monospacedDigit()
                    LiveTVProgressBar(value: LiveTVFormat.progress(current, now: now), height: 4)
                    Text(LiveTVFormat.time.string(from: current.end)).font(.caption).monospacedDigit()
                }
                .foregroundStyle(.white)
            }

            controls
        }
        .padding(.horizontal, DS.Space.s32)
        .padding(.bottom, DS.Space.s24)
        .padding(.top, 90)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.88)], startPoint: .top, endPoint: .bottom))
    }

    private var controls: some View {
        HStack(spacing: DS.Space.s20) {
            LiveTVPlayerIconButton(help: "Play/Pause (Space)", size: 44) { player.togglePause() } icon: {
                if player.isPaused { PlayIcon().frame(width: 36, height: 36) } else { PauseIcon().frame(width: 36, height: 36) }
            }
            LiveTVPlayerIconButton(help: "Previous channel (↑)") { zap(-1) } icon: {
                Image(systemName: "chevron.up").font(.flixorIcon(DS.Icon.lg, weight: .semibold))
            }
            LiveTVPlayerIconButton(help: "Next channel (↓)") { zap(1) } icon: {
                Image(systemName: "chevron.down").font(.flixorIcon(DS.Icon.lg, weight: .semibold))
            }
            HStack(spacing: DS.Space.s10) {
                LiveTVPlayerIconButton(help: "Mute (M)") { player.isMuted.toggle() } icon: {
                    VolumeIcon(volume: Float(player.volume / 100), isMuted: player.isMuted).frame(width: 28, height: 28)
                }
                Slider(value: $player.volume, in: 0...100)
                    .frame(width: 100)
                    .controlSize(.small)
            }
            if player.isPaused {
                LiveTVPillButton(title: "Go live", prominent: true) { player.goLive() }
            }

            Spacer()

            if let label = player.sourceIndexLabel {
                LiveTVPlayerIconButton(help: "Source (\(player.pinnedSourceId == nil ? "Auto" : "Pinned"), \(label))") { toggle(.sources) } icon: {
                    Image(systemName: "antenna.radiowaves.left.and.right").font(.flixorIcon(DS.Icon.lg, weight: .medium))
                }
            }
            LiveTVPlayerIconButton(help: "Audio & Subtitles") { toggle(.tracks) } icon: {
                SubtitlesIcon().frame(width: 30, height: 30)
            }
            LiveTVPlayerIconButton(help: isPiPActive ? "Exit Picture in Picture (P)" : "Picture in Picture (P)") { togglePiP() } icon: {
                Image(systemName: isPiPActive ? "pip.exit" : "pip.enter").font(.flixorIcon(DS.Icon.lg, weight: .medium))
            }
            LiveTVPlayerIconButton(help: "Channels (C)") { toggle(.channels) } icon: {
                EpisodeListIcon().frame(width: 30, height: 30)
            }
            LiveTVPlayerIconButton(help: isFullScreen ? "Exit Full Screen" : "Full Screen") { toggleFullScreen() } icon: {
                if isFullScreen { FullscreenExitIcon().frame(width: 26, height: 26) } else { FullscreenEnterIcon().frame(width: 26, height: 26) }
            }
        }
    }

    // MARK: Panels

    @ViewBuilder
    private var panelView: some View {
        switch panel {
        case .none:
            EmptyView()
        case .tracks:
            floatingPanel(width: 340) { LiveTVTracksPanel(player: player) }
        case .sources:
            if let channel {
                floatingPanel(width: 320) {
                    VStack(alignment: .leading, spacing: DS.Space.s4) {
                        Text("Source").flixorFont(.headline, weight: .semibold).padding(.horizontal, DS.Space.s10).padding(.bottom, DS.Space.s4)
                        LiveTVTrackRow(title: "Auto", detail: "Switches after an error or 25 s without progress",
                                       isSelected: player.pinnedSourceId == nil) { player.selectSource(nil) }
                        ForEach(Array(channel.sources.enumerated()), id: \.element.id) { index, source in
                            LiveTVTrackRow(title: "Source \(index + 1)\(player.currentSourceId == source.id ? " · playing" : "")",
                                           detail: [source.coast, source.quality, source.language].filter { !$0.isEmpty }.joined(separator: " · "),
                                           isSelected: player.pinnedSourceId == source.id) { player.selectSource(source.id) }
                        }
                    }
                    .padding(DS.Space.s12)
                }
            }
        case .channels:
            HStack {
                Spacer()
                channelPanel
            }
            .transition(.move(edge: .trailing))
        }
    }

    private func floatingPanel<Content: View>(width: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: width)
            .background(theme.playerPanelBackground())
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r12))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.r12).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, DS.Space.s32)
            .padding(.bottom, 96)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private var channelPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(LiveTVStore.genreLabel(store.genre, market: store.market) == "All" ? store.market.title : LiveTVStore.genreLabel(store.genre, market: store.market))
                    .flixorFont(.headline, weight: .semibold)
                Spacer()
                LiveTVIconButton(icon: "xmark", help: "Close", size: 28) { panel = .none }
            }
            .padding(.horizontal, DS.Space.s16).padding(.top, DS.Space.s60).padding(.bottom, DS.Space.s10)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: DS.Space.s4) {
                        ForEach(zapList) { c in
                            Button { tune(c) } label: { zapRow(c) }
                                .buttonStyle(.plain)
                                .id(c.id)
                                .onAppear { store.noteGuideVisible(c.id) }
                        }
                    }
                    .padding(.horizontal, DS.Space.s10)
                    .padding(.bottom, DS.Space.s20)
                }
                .onAppear { if let id = channel?.id { proxy.scrollTo(id, anchor: .center) } }
            }
        }
        .frame(width: 340)
        .frame(maxHeight: .infinity)
        .background(theme.playerPanelBackground())
        .overlay(alignment: .leading) { Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1) }
        .foregroundStyle(.white)
    }

    private func zapRow(_ c: LiveChannel) -> some View {
        let current = store.guideEntry(for: c)?.current(at: store.now)
        let isCurrent = c == channel
        return HStack(spacing: DS.Space.s12) {
            LiveTVLogo(channel: c, width: 52, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(current?.title ?? c.displayName).flixorFont(.callout, weight: .semibold).lineLimit(1)
                Text(current != nil ? c.displayName : LiveTVFormat.context(c)).flixorFont(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                if let current { LiveTVProgressBar(value: LiveTVFormat.progress(current, now: store.now), height: 2).padding(.top, 2) }
            }
            Spacer(minLength: 0)
            if isCurrent { LiveDot() }
        }
        .padding(DS.Space.s8)
        .background(RoundedRectangle(cornerRadius: DS.Radius.button).fill(isCurrent ? Color.white.opacity(0.12) : .clear))
        .contentShape(Rectangle())
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: DS.Space.s14) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash").font(.flixorIcon(DS.Icon.xxl, weight: .light))
            Text("Can't play this channel").flixorFont(.title3, weight: .bold)
            Text(message).flixorFont(.callout).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center).frame(maxWidth: 420)
            HStack(spacing: DS.Space.s10) {
                LiveTVPillButton(title: "Try again", prominent: true) { player.retry() }.keyboardShortcut(.defaultAction)
                LiveTVPillButton(title: "Back") { close() }
            }
        }
        .padding(DS.Space.s32)
        .background(theme.playerPanelBackground(opacity: 0.85), in: RoundedRectangle(cornerRadius: DS.Radius.dialog))
        .foregroundStyle(.white)
    }

    // MARK: Actions

    private func toggle(_ p: Panel) { panel = panel == p ? .none : p; showOverlay() }

    private func close() {
        MPVPiPWindowManager.shared.exitPiP()
        store.playing = nil
    }

    private func togglePiP() {
        guard let controller = mpvPiPViewController as? MPVVideoViewWrapper.MPVPiPViewController, let channel else { return }
        let current = store.guideEntry(for: channel)?.current(at: store.now)
        MPVPiPWindowManager.shared.togglePiP(
            mpvViewController: controller,
            stateBinding: $isPiPActive,
            title: channel.displayName,
            subtitle: current?.title ?? "Live",
            aspectRatio: CGSize(width: 16, height: 9),
            isPlaying: !player.isPaused
        )
    }

    private func tune(_ c: LiveChannel) {
        guard c != channel else { return }
        previousChannel = channel
        store.playing = c
    }

    private func zap(_ step: Int) {
        guard !zapList.isEmpty else { return }
        let index = channel.flatMap { zapList.firstIndex(of: $0) } ?? 0
        tune(zapList[(index + step + zapList.count) % zapList.count])
    }

    private func toggleFullScreen() { NSApp.keyWindow?.toggleFullScreen(nil) }

    private func showOverlay() {
        overlayVisible = true
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled, player.state == .playing, panel == .none else { return }
            overlayVisible = false
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }

    private func toggleOverlay() {
        if overlayVisible { overlayVisible = false; hideTask?.cancel() } else { showOverlay() }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty { return false }
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        switch event.keyCode {
        case 53: // Esc
            if panel != .none { panel = .none } else { close() }
            return true
        case 126, 116: zap(-1); return true          // ↑, Page Up
        case 125, 121: zap(1); return true           // ↓, Page Down
        case 49: player.togglePause(); showOverlay(); return true   // Space
        case 51:                                      // Delete: previous channel
            if let previousChannel { tune(previousChannel) }
            return true
        case 36:                                      // Return: tune the typed number
            if !numberEntry.isEmpty { commitNumber(); return true }
            return false
        default: break
        }
        if let digit = chars.first, digit.isNumber, chars.count == 1 {
            numberEntry = String((numberEntry + chars).suffix(4))
            numberTask?.cancel()
            numberTask = Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { return }
                commitNumber()
            }
            return true
        }
        switch chars {
        case "m": player.isMuted.toggle(); showOverlay(); return true
        case "c": toggle(.channels); return true
        case "f": if let channel { store.toggleFavorite(channel) }; showOverlay(); return true
        case "g": store.screen = .guide; close(); return true
        case "i": toggleOverlay(); return true
        case "p": togglePiP(); return true
        default: return false
        }
    }

    private func commitNumber() {
        numberTask?.cancel()
        if let n = Int(numberEntry), n >= 1, n <= zapList.count { tune(zapList[n - 1]) }
        numberEntry = ""
    }
}

/// The Flixor player's icon button: white glyph, scale on hover.
struct LiveTVPlayerIconButton<Icon: View>: View {
    var help: String
    var size: CGFloat = 36
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            icon()
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering ? 1.1 : 1)
        .onHover { h in withAnimation(DS.Motion.standard) { hovering = h } }
        .help(help)
    }
}

/// Audio and subtitle tracks, styled like the Flixor player's panel.
struct LiveTVTracksPanel: View {
    @ObservedObject var player: LiveTVPlayerModel
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                tabButton("Audio", 0)
                tabButton("Subtitles", 1)
            }
            .padding(.horizontal, DS.Space.s4).padding(.top, DS.Space.s4)
            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1).padding(.top, DS.Space.s8)
            ScrollView {
                VStack(spacing: 2) {
                    if tab == 0 {
                        if player.audioTracks.isEmpty { empty("This channel has one audio track.") }
                        ForEach(player.audioTracks, id: \.id) { t in
                            LiveTVTrackRow(title: Self.name(t, kind: "Audio"), isSelected: t.selected) { player.selectAudio(t.id) }
                        }
                    } else {
                        LiveTVTrackRow(title: "Off", isSelected: !player.subtitleTracks.contains { $0.selected }) { player.selectSubtitle(nil) }
                        if player.subtitleTracks.isEmpty { empty("No subtitles on this channel.") }
                        ForEach(player.subtitleTracks, id: \.id) { t in
                            LiveTVTrackRow(title: Self.name(t, kind: "Subtitles"), isSelected: t.selected) { player.selectSubtitle(t.id) }
                        }
                    }
                }
                .padding(DS.Space.s8)
            }
            .frame(maxHeight: 280)
        }
        .foregroundStyle(.white)
    }

    private func tabButton(_ title: String, _ index: Int) -> some View {
        Button { tab = index } label: {
            Text(title)
                .font(.system(size: 14, weight: tab == index ? .semibold : .regular))
                .foregroundStyle(tab == index ? .white : .white.opacity(0.5))
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Space.s10)
                .background(tab == index ? Color.white.opacity(0.1) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r8))
        }
        .buttonStyle(.plain)
    }

    private func empty(_ text: String) -> some View {
        Text(text).flixorFont(.footnote).foregroundStyle(.white.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .leading).padding(DS.Space.s10)
    }

    static func name(_ track: MPVTrack, kind: String) -> String {
        let parts = [track.title, track.lang?.uppercased()].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? "\(kind) \(track.id)" : parts.joined(separator: " · ")
    }
}

/// A selectable row with a check circle, as in the Flixor player's track panel.
struct LiveTVTrackRow: View {
    let title: String
    var detail: String? = nil
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.flixorIcon(DS.Icon.md))
                    .foregroundStyle(isSelected ? theme.accent : .white.opacity(0.3))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.flixor(.callout)).foregroundStyle(isSelected ? .white : .white.opacity(0.75)).lineLimit(1)
                    if let detail, !detail.isEmpty {
                        Text(detail).font(.flixor(.caption)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(.vertical, DS.Space.s8)
            .padding(.horizontal, DS.Space.s10)
            .background(isSelected ? Color.white.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
#endif
