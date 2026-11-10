//
//  LiveTVRootView.swift
//  FlixorMac
//
//  Personal build only (FLIXOR_LIVE_TV). The full-window Live TV interface in
//  Flixor's design language: a quiet top bar with the always-visible way back
//  to Flixor, a sidebar for market, favorites and genres, the channel grid or
//  the guide, and the live player on top. Red is used only for "live".
//

#if FLIXOR_LIVE_TV
import SwiftUI
import AppKit

struct LiveTVRootView: View {
    /// Height of the top bar; the traffic lights are moved to its centre.
    static let barHeight: CGFloat = 60
    @ObservedObject private var store = LiveTVStore.shared
    @StateObject private var player = LiveTVPlayerModel()
    @State private var showSetup = false
    @State private var showOrder = false
    @State private var keyMonitor: Any?
    /// Where the window's traffic lights are, so the top bar lines up with them.
    @State private var titlebar = LiveTVTitlebarMetrics()
    @FocusState private var searchFocused: Bool
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                HStack(spacing: 0) {
                    LiveTVSidebar()
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .ignoresSafeArea(edges: .top)

            if store.playing != nil {
                LiveTVPlayerView(player: player)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(5)
            }
        }
        .background(LiveTVWindowButtonsReader(barHeight: Self.barHeight, active: store.playing == nil) { titlebar = $0 })
        .tint(.white)
        // Hiding the window toolbar also hides the traffic lights in this
        // window style: keep them while browsing, hide them only in the
        // player (as Flixor's own player does).
        .toolbar(store.playing != nil ? .hidden : .visible, for: .windowToolbar)
        .preferredColorScheme(.dark)
        .onAppear {
            installKeyMonitor()
            if !store.isConfigured { showSetup = true }
        }
        .onDisappear {
            removeKeyMonitor()
            MPVPiPWindowManager.shared.exitPiP()
            player.stop()
        }
        .onChange(of: store.playing) { channel in
            if let channel {
                player.play(channel)
                store.recordWatch(channel)
            } else {
                MPVPiPWindowManager.shared.exitPiP()
                player.stop()
            }
        }
        .sheet(isPresented: $showSetup) {
            LiveTVSetupSheet { showSetup = false }
        }
        .sheet(isPresented: $showOrder) {
            LiveTVCustomOrderSheet { showOrder = false }
        }
        .animation(DS.Motion.standard, value: store.playing)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: DS.Space.s16) {
            LiveTVPillButton(icon: "chevron.left", title: "Flixor", help: "Back to Flixor (⌘L)") { store.exit() }

            HStack(spacing: DS.Space.s8) {
                LiveDot()
                Text("Live TV").flixorFont(.title3, weight: .bold).foregroundStyle(theme.textPrimary)
            }

            Spacer(minLength: DS.Space.s16)

            HStack(spacing: DS.Space.s8) {
                Image(systemName: "magnifyingglass").font(.flixorIcon(DS.Icon.sm)).foregroundStyle(theme.textTertiary)
                TextField("", text: $store.query, prompt: Text("Search channels").foregroundColor(theme.textTertiary))
                    .textFieldStyle(.plain)
                    .flixorFont(.callout)
                    .focused($searchFocused)
                if !store.query.isEmpty {
                    Button { store.query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.Space.s14)
            .frame(width: 260, height: 32)
            .background(Color.white.opacity(DS.Opacity.subtle), in: Capsule())
            .overlay(Capsule().strokeBorder(searchFocused ? theme.separatorStrong : theme.separator, lineWidth: DS.Border.thin))

            if case .loading = store.loadState { ProgressView().controlSize(.small) }

            LiveTVIconButton(icon: "gearshape", asset: "nav-settings", help: "Live TV settings", size: 32) { showSetup = true }
        }
        // Centred on the traffic lights and starting just after them.
        .padding(.leading, titlebar.leading)
        .padding(.trailing, DS.Space.s24)
        .frame(maxWidth: .infinity)
        .frame(height: titlebar.height)
        // Channels / Guide sits at the exact centre of the window, whatever
        // the widths of the groups on either side.
        .overlay {
            LiveTVSegmented(options: [(LiveTVScreen.channels, "Channels"), (.guide, "Guide")], selection: $store.screen)
        }
        .padding(.bottom, DS.Space.s8)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch store.loadState {
        case .failed(let message) where store.lineup.isEmpty:
            LiveTVMessageView(
                icon: store.rulesMissing ? "list.bullet.rectangle" : "antenna.radiowaves.left.and.right.slash",
                title: store.isConfigured ? (store.rulesMissing ? "Curated lineup not found" : "Channels didn't load") : "Set up Live TV",
                message: message,
                primary: store.isConfigured ? ("Try again", { store.loadCatalog(force: true) }) : ("Set up", { showSetup = true }),
                secondary: ("Settings", { showSetup = true })
            )
        case .loading where store.lineup.isEmpty, .idle where store.lineup.isEmpty:
            VStack(spacing: DS.Space.s12) {
                ProgressView()
                Text("Loading channels…").flixorFont(.callout).foregroundStyle(theme.textSecondary)
            }
        default:
            switch store.screen {
            case .channels: LiveTVChannelGrid(onPlay: play, showOrder: $showOrder)
            case .guide: LiveTVGuideView(onPlay: play)
            }
        }
    }

    private func play(_ channel: LiveChannel) {
        store.playing = channel
    }

    // MARK: Keys

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            nonisolated(unsafe) let unsafeEvent = event
            let consumed = MainActor.assumeIsolated { LiveTVKeyRouter.shared.handle(unsafeEvent) }
            return consumed ? nil : event
        }
        LiveTVKeyRouter.shared.browse = { event in handleBrowseKey(event) }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        LiveTVKeyRouter.shared.browse = nil
    }

    /// Esc steps back one level and never leaves Live TV on its own.
    private func handleBrowseKey(_ event: NSEvent) -> Bool {
        guard event.keyCode == 53 else { return false }
        if searchFocused || !store.query.isEmpty {
            store.query = ""
            searchFocused = false
            return true
        }
        if store.screen == .guide {
            store.screen = .channels
            return true
        }
        return false
    }
}

/// Position of the window's traffic lights in SwiftUI terms.
struct LiveTVTitlebarMetrics: Equatable {
    /// Leading inset that clears the buttons with a 12 pt gap.
    var leading: CGFloat = 84
    /// Row height whose centre matches the buttons' centre.
    var height: CGFloat = 52
}

/// Moves the window's traffic lights to the centre of a taller top bar while
/// Live TV is showing (the same idea as Electron's `trafficLightPosition`),
/// reports where they ended up, and restores AppKit's layout when Live TV goes
/// away or the player takes over. Re-applied on resize and full-screen changes,
/// because AppKit lays the title bar out again then.
struct LiveTVWindowButtonsReader: NSViewRepresentable {
    let barHeight: CGFloat
    let active: Bool
    let onChange: (LiveTVTitlebarMetrics) -> Void

    func makeNSView(context: Context) -> ReaderView { ReaderView(barHeight: barHeight, onChange: onChange) }

    func updateNSView(_ nsView: ReaderView, context: Context) {
        nsView.onChange = onChange
        nsView.active = active
        nsView.apply()
    }

    static func dismantleNSView(_ nsView: ReaderView, coordinator: ()) { nsView.restore() }

    final class ReaderView: NSView {
        let barHeight: CGFloat
        var active = true
        var onChange: (LiveTVTitlebarMetrics) -> Void
        private var last: LiveTVTitlebarMetrics?
        private var observers: [NSObjectProtocol] = []
        private var original: (container: NSRect, origins: [NSPoint])?
        private weak var observedWindow: NSWindow?

        init(barHeight: CGFloat, onChange: @escaping (LiveTVTitlebarMetrics) -> Void) {
            self.barHeight = barHeight
            self.onChange = onChange
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        deinit { observers.forEach(NotificationCenter.default.removeObserver) }

        private var buttons: [NSButton] {
            guard let window = observedWindow ?? window else { return [] }
            return [.closeButton, .miniaturizeButton, .zoomButton].compactMap { window.standardWindowButton($0) }
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil { restore() }
            super.viewWillMove(toWindow: newWindow)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            observedWindow = window
            guard let window else { return }
            for name in [NSWindow.didResizeNotification, NSWindow.didEnterFullScreenNotification,
                         NSWindow.didExitFullScreenNotification, NSWindow.didBecomeKeyNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    // After AppKit's own title bar layout for this event.
                    DispatchQueue.main.async { self?.apply() }
                })
            }
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        func apply() {
            guard let window = observedWindow ?? window, let content = window.contentView else { return }
            let fullScreen = window.styleMask.contains(.fullScreen)
            guard active, !fullScreen, let close = buttons.first, let container = close.superview?.superview else {
                restore()
                report(LiveTVTitlebarMetrics(leading: DS.Space.s24, height: barHeight))
                return
            }
            if original == nil { original = (container.frame, buttons.map(\.frame.origin)) }
            // Taller title bar container pinned to the top, buttons centred in it.
            let height = barHeight
            container.frame = NSRect(x: 0, y: window.frame.height - height, width: window.frame.width, height: height)
            let spacing: CGFloat = buttons.count > 1 ? buttons[1].frame.minX - buttons[0].frame.minX : 20
            let firstX = original?.origins.first?.x ?? 7
            for (index, button) in buttons.enumerated() {
                guard let superview = button.superview else { continue }
                // The button's superview fills the container; centre vertically in it.
                let y = (superview.bounds.height - button.frame.height) / 2
                button.setFrameOrigin(NSPoint(x: firstX + CGFloat(index) * spacing, y: y))
            }
            guard let zoom = buttons.last else { return }
            let frame = zoom.convert(zoom.bounds, to: nil)
            _ = content
            report(LiveTVTitlebarMetrics(leading: ceil(frame.maxX) + DS.Space.s12, height: height))
        }

        func restore() {
            guard let original, let close = buttons.first, let container = close.superview?.superview else { return }
            container.frame = original.container
            for (button, origin) in zip(buttons, original.origins) { button.setFrameOrigin(origin) }
            self.original = nil
            (observedWindow ?? window)?.contentView?.needsLayout = true
        }

        private func report(_ metrics: LiveTVTitlebarMetrics) {
            guard metrics != last else { return }
            last = metrics
            onChange(metrics)
        }
    }
}

/// Routes key presses to the player while it is on screen, else to browsing.
@MainActor
final class LiveTVKeyRouter {
    static let shared = LiveTVKeyRouter()
    var browse: ((NSEvent) -> Bool)?
    var player: ((NSEvent) -> Bool)?

    func handle(_ event: NSEvent) -> Bool {
        guard LiveTVStore.shared.isActive, let window = event.window, window.isKeyWindow,
              window.attachedSheet == nil, NSApp.modalWindow == nil else { return false }
        // ⌘L / ⌘⇧L leave Live TV from anywhere in it.
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "l" {
            LiveTVStore.shared.exit()
            return true
        }
        if let player, LiveTVStore.shared.playing != nil { return player(event) }
        return browse?(event) ?? false
    }
}

// MARK: - Sidebar

struct LiveTVSidebar: View {
    @ObservedObject private var store = LiveTVStore.shared
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                LiveTVSegmented(options: LiveTVMarket.allCases.map { ($0, $0 == .us ? "USA" : "India") },
                                selection: $store.market, fill: true)
                    .padding(.bottom, DS.Space.s16)

                row("Favorites", icon: "star", count: store.favorites.count, selected: store.section == .favorites) {
                    store.section = .favorites
                }
                row("Recent", icon: "clock.arrow.circlepath", count: store.recents.count, selected: store.section == .recent) {
                    store.section = .recent
                }

                header(store.market == .us ? "Channels" : "Indian channels")

                if store.market == .india {
                    HStack(spacing: DS.Space.s6) {
                        ForEach(LiveTVStore.indiaLanguages, id: \.self) { language in
                            LiveTVChip(title: language == "All" ? "All" : language, selected: store.language == language) {
                                store.language = language
                            }
                        }
                    }
                    .padding(.horizontal, DS.Space.s8)
                    .padding(.bottom, DS.Space.s8)
                }

                ForEach(store.market == .us ? LiveTVStore.usGenres : LiveTVStore.indiaGenres, id: \.self) { genre in
                    row(LiveTVStore.genreLabel(genre, market: store.market), icon: Self.icon(for: genre),
                        count: store.count(market: store.market, genre: genre),
                        selected: store.section == .channels && store.genre == genre) {
                        store.section = .channels
                        store.genre = genre
                    }
                }
            }
            .padding(.horizontal, DS.Space.s16)
            .padding(.top, DS.Space.s8)
            .padding(.bottom, DS.Space.s24)
        }
        .frame(width: 236)
    }

    static func icon(for genre: String) -> String {
        switch genre {
        case "All": return "square.grid.2x2"
        case "News": return "newspaper"
        case "Sports": return "sportscourt"
        case "Movies": return "film"
        case "Shows": return "tv"
        case "Family": return "figure.and.child.holdinghands"
        case "Local": return "mappin.and.ellipse"
        case "Premium": return "crown"
        case "Music": return "music.note"
        case "Factual": return "globe.americas"
        case "Devotional": return "sparkles"
        default: return "circle"
        }
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .flixorFont(.caption, weight: .semibold)
            .foregroundStyle(theme.textTertiary)
            .padding(.horizontal, DS.Space.s12)
            .padding(.top, DS.Space.s20)
            .padding(.bottom, DS.Space.s6)
    }

    private func row(_ title: String, icon: String, count: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        LiveTVSidebarRow(title: title, icon: icon, count: count, selected: selected, action: action)
    }
}

private struct LiveTVSidebarRow: View {
    let title: String
    let icon: String
    let count: Int
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s12) {
                Image(systemName: selected ? icon + (icon == "star" ? ".fill" : "") : icon)
                    .font(.flixorIcon(DS.Icon.sm, weight: .medium))
                    .foregroundStyle(selected ? theme.textPrimary : theme.textSecondary)
                    .frame(width: 20)
                Text(title)
                    .flixorFont(.body, weight: selected ? .semibold : .medium)
                    .foregroundStyle(selected || hovering ? theme.textPrimary : theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if count > 0 {
                    Text("\(count)").flixorFont(.caption).foregroundStyle(theme.textTertiary).monospacedDigit()
                }
            }
            .padding(.horizontal, DS.Space.s12)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                    .fill(selected ? Color.white.opacity(DS.Opacity.pressed) : hovering ? theme.hoverFill : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Shared components

/// Small red dot for "live".
struct LiveDot: View {
    var body: some View { Circle().fill(Color.flixorBrand).frame(width: 8, height: 8) }
}

struct LiveBadge: View {
    var body: some View {
        Text("LIVE")
            .flixorFont(.nano, weight: .heavy)
            .tracking(0.6)
            .foregroundStyle(.white)
            .padding(.horizontal, DS.Space.s6).padding(.vertical, 3)
            .background(Color.flixorBrand, in: RoundedRectangle(cornerRadius: DS.Radius.badge))
    }
}

/// Capsule segmented control in Flixor's style (selected = white fill).
struct LiveTVSegmented<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value
    var fill = false
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                let (value, title) = options[index]
                Button { selection = value } label: {
                    Text(title)
                        .flixorFont(.callout, weight: .semibold)
                        .foregroundStyle(selection == value ? Color.black : theme.textSecondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: !fill, vertical: false)
                        .padding(.horizontal, fill ? DS.Space.s6 : DS.Space.s16)
                        .frame(maxWidth: fill ? .infinity : nil)
                        .frame(height: 28)
                        .background(Capsule().fill(selection == value ? Color.white : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(DS.Opacity.hover)))
        .animation(DS.Motion.quick, value: selection)
    }
}

struct LiveTVChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        Button(action: action) {
            Text(title)
                .flixorFont(.footnote, weight: .semibold)
                .foregroundStyle(selected ? Color.black : theme.textSecondary)
                .padding(.horizontal, DS.Space.s12)
                .frame(height: 26)
                .background(Capsule().fill(selected ? Color.white : Color.white.opacity(DS.Opacity.hover)))
        }
        .buttonStyle(.plain)
    }
}

/// Capsule button with icon and title (secondary style).
struct LiveTVPillButton: View {
    var icon: String?
    let title: String
    var help: String = ""
    var prominent = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s6) {
                if let icon { Image(systemName: icon).font(.flixorIcon(DS.Icon.xs, weight: .bold)) }
                Text(title).flixorFont(.callout, weight: .semibold)
            }
            .foregroundStyle(prominent ? Color.black : .white)
            .padding(.horizontal, DS.Space.s14)
            .frame(height: 30)
            .background(Capsule().fill(prominent ? Color.white.opacity(hovering ? 0.9 : 1) : Color.white.opacity(hovering ? 0.16 : 0.10)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

struct LiveTVIconButton: View {
    let icon: String
    /// A NavIcons asset to draw instead of the SF Symbol.
    var asset: String? = nil
    var help: String = ""
    var size: CGFloat = 34
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if let asset { FlixorNavIcon(asset: asset, size: 18) } else {
                    Image(systemName: icon).font(.flixorIcon(DS.Icon.md, weight: .medium))
                }
            }
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.16 : 0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

struct LiveTVMessageView: View {
    let icon: String
    let title: String
    let message: String
    let primary: (String, () -> Void)
    var secondary: (String, () -> Void)?
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        VStack(spacing: DS.Space.s14) {
            Image(systemName: icon).font(.flixorIcon(DS.Icon.huge, weight: .light)).foregroundStyle(theme.textTertiary)
            Text(title).flixorFont(.title2, weight: .bold)
            Text(message).flixorFont(.body).foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 460)
            HStack(spacing: DS.Space.s10) {
                LiveTVPillButton(title: primary.0, prominent: true, action: primary.1)
                if let secondary { LiveTVPillButton(title: secondary.0, action: secondary.1) }
            }
            .padding(.top, DS.Space.s6)
        }
        .padding(DS.Space.s40)
    }
}

/// Channel logo on a neutral tile: xtream-web's logo when the guide server is
/// set up, else the provider icon, else the channel's initials.
struct LiveTVLogo: View {
    let channel: LiveChannel
    var width: CGFloat = 46
    var height: CGFloat = 30
    var plain = false
    @ObservedObject private var store = LiveTVStore.shared
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        ZStack {
            if !plain {
                RoundedRectangle(cornerRadius: DS.Radius.r6, style: .continuous).fill(Color.white.opacity(DS.Opacity.subtle))
            }
            if store.guideServer?.isComplete == true, let path = channel.logoPath {
                LiveTVRemoteImage(path: path, contentMode: .fit) { providerIcon }
                    .padding(height * 0.1)
            } else {
                providerIcon.padding(height * 0.1)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r6, style: .continuous))
    }

    @ViewBuilder
    private var providerIcon: some View {
        if let url = channel.logoURL.flatMap(URL.init(string:)), !(channel.logoURL ?? "").isEmpty {
            CachedAsyncImage(url: url, contentMode: .fit) { initials }
        } else {
            initials
        }
    }

    private var initials: some View {
        Text(Self.initials(channel.displayName))
            .font(.system(size: height * 0.34, weight: .bold))
            .foregroundStyle(theme.textSecondary)
    }

    static func initials(_ name: String) -> String {
        let words = name.split(separator: " ").filter { $0.first?.isLetter == true || $0.first?.isNumber == true }
        return String(words.prefix(3).compactMap(\.first)).uppercased()
    }
}

enum LiveTVFormat {
    static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.locale = Locale(identifier: "en_US")
        return f
    }()

    static func range(_ p: LiveProgram) -> String { "\(time.string(from: p.start)) – \(time.string(from: p.end))" }

    static func remaining(_ p: LiveProgram, now: Date) -> String {
        let minutes = max(0, Int(p.end.timeIntervalSince(now) / 60))
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min left" : "\(minutes) min left"
    }

    static func progress(_ p: LiveProgram, now: Date) -> Double {
        let total = p.end.timeIntervalSince(p.start)
        guard total > 0 else { return 0 }
        return min(1, max(0, now.timeIntervalSince(p.start) / total))
    }

    /// Short context line when there is no program: station, language or genre.
    static func context(_ c: LiveChannel) -> String {
        if let location = c.location { return "\(location.city), \(location.state)" }
        if c.market == .india { return [c.language, LiveTVStore.genreLabel(c.genre, market: .india)].compactMap { $0 }.joined(separator: " · ") }
        return c.premium ? "Premium" : c.genre
    }
}

struct LiveTVProgressBar: View {
    let value: Double
    var height: CGFloat = 3
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2))
                Capsule().fill(Color.flixorBrand).frame(width: max(height, geo.size.width * value))
            }
        }
        .frame(height: height)
    }
}
#endif
