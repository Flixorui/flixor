//
//  AskFlixorPanel.swift
//  FlixorMac
//
//  Ask Flixor's window: a floating chat window over the app that can be moved
//  by its header, resized from any edge or corner, set to a preset size,
//  minimised to a pill, or snapped to the left or right edge, where it docks
//  and the page narrows beside it. Size, position and mode are kept per profile.
//

import SwiftUI
import AppKit
import FlixorKit

private let askTint = Color(hex: 0xA78BFA)

// MARK: - Window state

@MainActor
final class AskWindowStore: ObservableObject {
    enum Mode: String { case floating, dockedLeft, dockedRight }

    @Published var isOpen = false
    @Published var isMinimised = false
    @Published var mode: Mode = .floating
    /// Floating frame, in the layer's coordinates (top-left origin).
    @Published var frame: CGRect = .zero
    @Published var dockWidth: CGFloat = 420
    /// While dragging near an edge: where it would dock.
    @Published var snapPreview: Mode?

    static let minSize = CGSize(width: 340, height: 420)
    static let dockRange: ClosedRange<CGFloat> = 320...560
    static let margin: CGFloat = 22
    /// Keeps the window clear of the title bar and traffic lights.
    static let topInset: CGFloat = 44

    private(set) var container: CGSize = .zero
    private var profileKey = ""

    enum Preset: String, CaseIterable, Identifiable {
        case standard, compact, wide, tall
        var id: String { rawValue }
        var label: String {
            switch self {
            case .standard: return String(localized: "Default")
            case .compact: return String(localized: "Compact")
            case .wide: return String(localized: "Wide")
            case .tall: return String(localized: "Tall")
            }
        }
        var sizeLabel: String {
            switch self {
            case .standard: return "440 × 600"
            case .compact: return "340 × 430"
            case .wide: return "640 × 480"
            case .tall: return String(localized: "440 × full height")
            }
        }
    }

    /// Space the docked window takes from the page, per side.
    var leadingInset: CGFloat { isOpen && !isMinimised && mode == .dockedLeft ? dockWidth : 0 }
    var trailingInset: CGFloat { isOpen && !isMinimised && mode == .dockedRight ? dockWidth : 0 }

    func updateContainer(_ size: CGSize) {
        guard size != container, size.width > 0 else { return }
        container = size
        loadForProfile()
        if frame == .zero { apply(.standard) } else { frame = clamped(frame) }
    }

    func loadForProfile() {
        let key = UserDefaults.standard.profileKey("askWindow")
        guard key != profileKey else { return }
        profileKey = key
        let saved = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        mode = Mode(rawValue: saved["mode"] as? String ?? "") ?? .floating
        dockWidth = (saved["dock"] as? Double).map { CGFloat($0) } ?? 420
        if let x = saved["x"] as? Double, let y = saved["y"] as? Double, let w = saved["w"] as? Double, let h = saved["h"] as? Double {
            frame = clamped(CGRect(x: x, y: y, width: w, height: h))
        } else {
            frame = .zero
        }
    }

    func save() {
        guard !profileKey.isEmpty else { return }
        UserDefaults.standard.set([
            "mode": mode.rawValue, "dock": Double(dockWidth),
            "x": Double(frame.minX), "y": Double(frame.minY), "w": Double(frame.width), "h": Double(frame.height),
        ], forKey: profileKey)
    }

    func apply(_ preset: Preset) {
        let size: CGSize
        switch preset {
        case .standard: size = CGSize(width: 440, height: 600)
        case .compact: size = CGSize(width: 340, height: 430)
        case .wide: size = CGSize(width: 640, height: 480)
        case .tall: size = CGSize(width: 440, height: container.height - Self.topInset - Self.margin)
        }
        mode = .floating
        let origin = CGPoint(x: container.width - size.width - Self.margin,
                             y: preset == .tall ? Self.topInset : container.height - size.height - Self.margin)
        frame = clamped(CGRect(origin: origin, size: size))
        save()
    }

    func reset() {
        dockWidth = 420
        apply(.standard)
    }

    func dock(_ side: Mode) {
        mode = side
        save()
    }

    /// Keeps the window inside the layer and at least the minimum size.
    func clamped(_ rect: CGRect) -> CGRect {
        guard container.width > 0 else { return rect }
        let maxW = max(Self.minSize.width, container.width - 2 * 8)
        let maxH = max(Self.minSize.height, container.height - Self.topInset - 8)
        var r = rect
        r.size.width = min(max(r.width, Self.minSize.width), maxW)
        r.size.height = min(max(r.height, Self.minSize.height), maxH)
        r.origin.x = min(max(r.minX, 8), container.width - r.width - 8)
        r.origin.y = min(max(r.minY, Self.topInset), container.height - r.height - 8)
        return r
    }
}

// MARK: - Layer (launcher, pill, window)

/// Everything Ask Flixor draws over the app. Put it over the main content.
struct AskFlixorLayer: View {
    @ObservedObject var model: AskFlixorModel
    @ObservedObject var store: AskWindowStore
    let contextItem: MediaItem?

    @State private var dragStart: CGRect?
    @State private var dockDragStart: CGFloat?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.clear
                if let side = store.snapPreview {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(askTint.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(askTint.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                        .frame(width: store.dockWidth, height: geo.size.height - AskWindowStore.topInset - 10)
                        .offset(x: side == .dockedLeft ? 6 : geo.size.width - store.dockWidth - 6, y: AskWindowStore.topInset)
                        .allowsHitTesting(false)
                }
                if store.isOpen && !store.isMinimised {
                    window(in: geo.size)
                }
                if !store.isOpen || store.isMinimised {
                    launcher
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(DS.Space.s24)
                }
            }
            .coordinateSpace(name: "askLayer")
            // Same rule as Settings: the accent colour only marks what's on.
            // Menus, buttons, the text caret and spinners stay neutral.
            .tint(SettingsChrome.neutralTint)
            .onAppear { store.updateContainer(geo.size) }
            .onChange(of: geo.size) { store.updateContainer($0) }
        }
        .onChange(of: store.isOpen) { _ in model.isVisible = store.isOpen && !store.isMinimised }
        .onChange(of: store.isMinimised) { _ in model.isVisible = store.isOpen && !store.isMinimised }
        .onAppear { model.isVisible = store.isOpen && !store.isMinimised }
    }

    @ViewBuilder
    private var launcher: some View {
        if store.isMinimised {
            Button { withAnimation(DS.Motion.standard) { store.isMinimised = false } } label: {
                HStack(spacing: DS.Space.s8) {
                    Image(systemName: "sparkles")
                    Text("Ask Flixor").font(.flixor(.callout, weight: .bold))
                    if model.unread > 0 {
                        Text(model.unread == 1 ? String(localized: "1 new") : String(localized: "\(model.unread) new"))
                            .font(.flixor(.micro, weight: .bold))
                            .foregroundStyle(Color(hex: 0x5B21B6))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(.white))
                    } else if model.isSending {
                        ProgressView().controlSize(.small).tint(.white)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, DS.Space.s14)
                .frame(height: 40)
                .background(Capsule().fill(LinearGradient(colors: [Color(hex: 0x7C3AED), Color(hex: 0x9F67FF)], startPoint: .leading, endPoint: .trailing)))
                .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .help("Show Ask Flixor (⌘J)")
        } else {
            AskFlixorLauncher { withAnimation(DS.Motion.standard) { store.isOpen = true } }
        }
    }

    @ViewBuilder
    private func window(in size: CGSize) -> some View {
        switch store.mode {
        case .floating:
            chat(width: store.frame.width, docked: false)
                .frame(width: store.frame.width, height: store.frame.height)
                .background(AskWindowBackground(cornerRadius: 16))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                .shadow(color: .black.opacity(0.6), radius: 28, y: 14)
                .overlay(resizeHandles)
                .offset(x: store.frame.minX, y: store.frame.minY)
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .bottomTrailing)))
        case .dockedLeft, .dockedRight:
            let leading = store.mode == .dockedLeft
            chat(width: store.dockWidth, docked: true)
                .frame(width: store.dockWidth, height: size.height)
                .background(AskWindowBackground(cornerRadius: 0))
                .overlay(alignment: leading ? .trailing : .leading) {
                    Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1)
                }
                .overlay(alignment: leading ? .trailing : .leading) { dockResizeHandle(leading: leading) }
                .offset(x: leading ? 0 : size.width - store.dockWidth)
                .ignoresSafeArea(edges: .top)
        }
    }

    private func chat(width: CGFloat, docked: Bool) -> some View {
        AskChatView(
            model: model,
            store: store,
            width: width,
            contextItem: contextItem,
            headerDrag: headerDrag(docked: docked)
        )
    }

    // MARK: Moving

    private func headerDrag(docked: Bool) -> AnyGesture<DragGesture.Value> {
        AnyGesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .named("askLayer"))
                .onChanged { value in
                    if docked {
                        // Pull it away from the edge to float it again.
                        guard abs(value.translation.width) > 40 else { return }
                        let size = CGSize(width: max(store.frame.width, AskWindowStore.minSize.width), height: max(store.frame.height, 520))
                        store.mode = .floating
                        store.frame = store.clamped(CGRect(x: value.location.x - size.width / 2, y: value.location.y - 16, width: size.width, height: size.height))
                        dragStart = store.frame
                        return
                    }
                    if dragStart == nil { dragStart = store.frame }
                    guard let start = dragStart else { return }
                    store.frame = store.clamped(start.offsetBy(dx: value.translation.width, dy: value.translation.height))
                    let x = value.location.x
                    store.snapPreview = x < 28 ? .dockedLeft : (x > store.container.width - 28 ? .dockedRight : nil)
                }
                .onEnded { _ in
                    if let side = store.snapPreview {
                        withAnimation(DS.Motion.standard) { store.dock(side) }
                    }
                    store.snapPreview = nil
                    dragStart = nil
                    store.save()
                }
        )
    }

    // MARK: Resizing

    private var resizeHandles: some View {
        ZStack {
            ForEach(AskResizeEdge.allCases, id: \.self) { edge in
                // Hit area only along its edge or corner; the frame around it just places it.
                edge.hitArea
                    .frame(maxWidth: edge.size.width, maxHeight: edge.size.height)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { edge.cursor.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .named("askLayer"))
                            .onChanged { value in
                                if dragStart == nil { dragStart = store.frame }
                                guard let start = dragStart else { return }
                                store.frame = store.clamped(edge.resize(start, by: value.translation))
                            }
                            .onEnded { _ in dragStart = nil; store.save() }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge.alignment)
                    .allowsHitTesting(true)
            }
        }
    }

    private func dockResizeHandle(leading: Bool) -> some View {
        Color.clear
            .frame(width: 8)
            .contentShape(Rectangle())
            .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dockDragStart == nil { dockDragStart = store.dockWidth }
                        let delta = leading ? value.translation.width : -value.translation.width
                        let width = (dockDragStart ?? store.dockWidth) + delta
                        store.dockWidth = min(max(width, AskWindowStore.dockRange.lowerBound), AskWindowStore.dockRange.upperBound)
                    }
                    .onEnded { _ in dockDragStart = nil; store.save() }
            )
    }
}

private enum AskResizeEdge: CaseIterable {
    case top, bottom, left, right, topLeft, topRight, bottomLeft, bottomRight

    var size: CGSize {
        switch self {
        case .top, .bottom: return CGSize(width: CGFloat.infinity, height: 6)
        case .left, .right: return CGSize(width: 6, height: CGFloat.infinity)
        default: return CGSize(width: 14, height: 14)
        }
    }

    @ViewBuilder var hitArea: some View { Color.clear }

    var alignment: Alignment {
        switch self {
        case .top: return .top
        case .bottom: return .bottom
        case .left: return .leading
        case .right: return .trailing
        case .topLeft: return .topLeading
        case .topRight: return .topTrailing
        case .bottomLeft: return .bottomLeading
        case .bottomRight: return .bottomTrailing
        }
    }

    var cursor: NSCursor {
        switch self {
        case .top, .bottom: return .resizeUpDown
        case .left, .right: return .resizeLeftRight
        default: return .crosshair
        }
    }

    func resize(_ start: CGRect, by t: CGSize) -> CGRect {
        var r = start
        let minW = AskWindowStore.minSize.width, minH = AskWindowStore.minSize.height
        if [.left, .topLeft, .bottomLeft].contains(self) {
            let w = max(minW, start.width - t.width)
            r.origin.x = start.maxX - w
            r.size.width = w
        }
        if [.right, .topRight, .bottomRight].contains(self) { r.size.width = max(minW, start.width + t.width) }
        if [.top, .topLeft, .topRight].contains(self) {
            let h = max(minH, start.height - t.height)
            r.origin.y = start.maxY - h
            r.size.height = h
        }
        if [.bottom, .bottomLeft, .bottomRight].contains(self) { r.size.height = max(minH, start.height + t.height) }
        return r
    }
}

/// Frosted, slightly violet glass.
private struct AskWindowBackground: View {
    let cornerRadius: CGFloat
    var body: some View {
        ZStack {
            VisualEffectBlur()
            LinearGradient(colors: [Color(hex: 0x1C1A22).opacity(0.86), Color(hex: 0x100F14).opacity(0.94)], startPoint: .top, endPoint: .bottom)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .withinWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Chat

struct AskChatView: View {
    @ObservedObject var model: AskFlixorModel
    @ObservedObject var store: AskWindowStore
    let width: CGFloat
    let contextItem: MediaItem?
    let headerDrag: AnyGesture<DragGesture.Value>

    @ObservedObject private var settings = AISettings.shared
    @EnvironmentObject private var router: NavigationRouter
    @EnvironmentObject private var mainViewState: MainViewState
    @Environment(\.flixorTheme) private var theme
    @State private var draft = ""
    @State private var showsHistory = false
    @State private var dismissedContextId: String?
    @FocusState private var inputFocused: Bool

    private var isCompact: Bool { width < 420 }
    private var activeContext: MediaItem? {
        guard let contextItem, contextItem.id != dismissedContextId else { return nil }
        return contextItem
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if showsHistory {
                historyList
            } else {
                if let context = activeContext { contextChip(context) }
                if model.messages.isEmpty && !model.isSending {
                    emptyState
                } else {
                    conversation
                }
                composer
            }
        }
        .onAppear { inputFocused = true }
        .onExitCommand { withAnimation(DS.Motion.standard) { store.isOpen = false } }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: DS.Space.s6) {
            HStack(spacing: DS.Space.s8) {
                Image(systemName: "line.3.horizontal")
                    .font(.flixor(.micro, weight: .bold))
                    .foregroundStyle(theme.textTertiary)
                Image(systemName: "sparkles").foregroundStyle(askTint)
                Text(showsHistory ? "Conversations" : "Ask Flixor")
                    .font(.flixor(.callout, weight: .bold))
                    .lineLimit(1)
                    .fixedSize()
                if !isCompact && !showsHistory { enginePill }
                Spacer(minLength: DS.Space.s8)
            }
            .contentShape(Rectangle())
            .gesture(headerDrag)
            .help("Drag to move")

            if isCompact {
                moreMenu
            } else {
                headerButton(showsHistory ? "chevron.left" : "clock", help: showsHistory ? "Back" : "History") { showsHistory.toggle() }
                headerButton("square.and.pencil", help: "New chat") { model.newConversation(); showsHistory = false }
                sizeMenu
            }
            headerButton("minus", help: "Minimise") { withAnimation(DS.Motion.standard) { store.isMinimised = true } }
            headerButton("xmark", help: "Close (⌘J)") { withAnimation(DS.Motion.standard) { store.isOpen = false } }
        }
        .padding(.leading, DS.Space.s12)
        .padding(.trailing, DS.Space.s8)
        .padding(.top, store.mode == .floating ? DS.Space.s10 : 40)
        .padding(.bottom, DS.Space.s8)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
    }

    private func headerButton(_ symbol: String, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.flixor(.footnote, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(AskHoverButtonStyle())
        .help(help)
    }

    private var engineName: String {
        switch settings.engine {
        case .apple: return String(localized: "Apple Intelligence")
        case .anthropic: return AskModelNames.friendly(settings.model(for: .anthropic, quick: false))
        case .openAI: return AskModelNames.friendly(settings.openAIModel)
        }
    }

    private var enginePill: some View {
        Menu {
            engineChoices
        } label: {
            (Text("● ").foregroundColor(theme.success) + Text(engineName).foregroundColor(Color.white.opacity(0.85)))
                .font(.flixor(.caption))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .tint(Color.white.opacity(0.85))
        .fixedSize()
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Capsule().fill(Color.white.opacity(0.07)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1).allowsHitTesting(false))
        .help("Engine")
    }

    @ViewBuilder
    private var engineChoices: some View {
        ForEach(AIEngineKind.allCases) { kind in
            Button {
                settings.engine = kind
            } label: {
                if settings.engine == kind { Label(kind.label, systemImage: "checkmark") } else { Text(kind.label) }
            }
            .disabled(kind != .apple && !settings.hasKey(for: kind))
        }
        Divider()
        Button("AI Settings…") { openSettings() }
    }

    private var sizeMenu: some View {
        Menu {
            sizeChoices
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.flixor(.caption, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 26, height: 26)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(theme.textSecondary)
        .fixedSize()
        .help("Size and position")
    }

    @ViewBuilder
    private var sizeChoices: some View {
        ForEach(AskWindowStore.Preset.allCases) { preset in
            Button("\(preset.label)  ·  \(preset.sizeLabel)") { withAnimation(DS.Motion.standard) { store.apply(preset) } }
        }
        Divider()
        Button("Dock to Right Edge") { withAnimation(DS.Motion.standard) { store.dock(.dockedRight) } }
        Button("Dock to Left Edge") { withAnimation(DS.Motion.standard) { store.dock(.dockedLeft) } }
        if store.mode != .floating {
            Button("Float") { withAnimation(DS.Motion.standard) { store.mode = .floating; store.save() } }
        }
        Divider()
        Button("Reset Size and Position") { withAnimation(DS.Motion.standard) { store.reset() } }
    }

    private var moreMenu: some View {
        Menu {
            Menu("Engine") { engineChoices }
            Button(showsHistory ? "Back to Chat" : "History") { showsHistory.toggle() }
            Button("New Chat") { model.newConversation(); showsHistory = false }
            Menu("Size") { sizeChoices }
        } label: {
            Image(systemName: "ellipsis")
                .font(.flixor(.footnote, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 26, height: 26)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(theme.textSecondary)
        .fixedSize()
    }

    // MARK: Context

    private func contextChip(_ item: MediaItem) -> some View {
        HStack(spacing: DS.Space.s8) {
            CachedAsyncImage(url: item.thumb.flatMap(URL.init(string:)), maxPixelSize: 80)
                .aspectRatio(contentMode: .fill)
                .frame(width: 20, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.06)))
            (Text("Looking at ").foregroundColor(Color(hex: 0xD8D0FF))
                + Text(item.type == "episode" ? (item.grandparentTitle ?? item.title) : item.title).bold().foregroundColor(.white)
                + Text(item.year.map { " (\(String($0)))" } ?? "").foregroundColor(theme.textSecondary))
                .font(.flixor(.footnote))
                .lineLimit(1)
            Spacer(minLength: 4)
            Button { dismissedContextId = item.id } label: {
                Image(systemName: "xmark").font(.flixor(.nano, weight: .bold)).foregroundStyle(theme.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Ask without this title")
        }
        .padding(.horizontal, DS.Space.s8)
        .padding(.vertical, DS.Space.s6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(askTint.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(askTint.opacity(0.22), lineWidth: 1))
        .padding(.horizontal, DS.Space.s12)
        .padding(.top, DS.Space.s8)
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DS.Space.s12) {
            Spacer(minLength: 0)
            Text("What are you in the mood for?").font(.flixor(.title3, weight: .bold))
            Text("Answers come from your watchlist, history, Plex library and TMDB. Every title is a card you can open.")
                .font(.flixor(.footnote))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(AskFlixorModel.suggestions, id: \.0) { suggestion in
                    Button { model.send(suggestion.0, context: nil) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.0).font(.flixor(.footnote, weight: .medium)).multilineTextAlignment(.leading)
                            Text(suggestion.1).font(.flixor(.micro)).foregroundStyle(theme.textTertiary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
                        .padding(DS.Space.s10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05)))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(DS.Space.s14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    // MARK: Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.Space.s14) {
                    ForEach(model.messages) { message in
                        AskMessageView(
                            message: message,
                            width: width,
                            isLast: message.id == model.messages.last?.id,
                            onFollowUp: { model.send($0, context: activeContext) },
                            onRetry: { model.retry() },
                            onUseApple: { settings.engine = .apple; model.retry() },
                            onOpenSettings: openSettings,
                            open: open
                        )
                        .id(message.id)
                    }
                    if model.isSending {
                        AskLiveView(steps: model.liveSteps, text: model.liveText).id("live")
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, DS.Space.s12)
                .padding(.vertical, DS.Space.s10)
            }
            .onChange(of: model.messages.count) { _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: model.liveText) { _ in proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: model.liveSteps.count) { _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    // MARK: Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            TextField(model.messages.isEmpty ? "Ask about movies, shows, your library…" : "Ask a follow-up…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.flixor(.callout))
                .lineLimit(1...6)
                .focused($inputFocused)
                .onSubmit(send)
            HStack(spacing: DS.Space.s8) {
                Text(isCompact ? "⏎ send" : "⏎ send · ⌥⏎ new line · esc close")
                    .font(.flixor(.micro))
                    .foregroundStyle(theme.textTertiary)
                Spacer()
                if model.isSending {
                    Button { model.stop() } label: {
                        Image(systemName: "stop.fill")
                            .font(.flixor(.nano, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color.white.opacity(0.16)))
                    }
                    .buttonStyle(.plain)
                    .help("Stop")
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up")
                            .font(.flixor(.footnote, weight: .heavy))
                            .foregroundStyle(.black)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.white.opacity(0.35) : .white))
                    }
                    .buttonStyle(.plain)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Send")
                }
            }
        }
        .padding(.leading, DS.Space.s12)
        .padding(.trailing, DS.Space.s8)
        .padding(.vertical, DS.Space.s8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(inputFocused ? 0.22 : 0.14), lineWidth: 1))
        .padding(DS.Space.s10)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !model.isSending else { return }
        draft = ""
        model.send(text, context: activeContext)
    }

    // MARK: History

    private var historyList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if model.conversations.isEmpty {
                    Text("No saved conversations yet.")
                        .font(.flixor(.footnote))
                        .foregroundStyle(theme.textSecondary)
                        .padding(DS.Space.s14)
                }
                ForEach(groupedConversations, id: \.0) { group in
                    Text(group.0.uppercased())
                        .font(.flixor(.micro, weight: .bold))
                        .kerning(0.5)
                        .foregroundStyle(theme.textTertiary)
                        .padding(.horizontal, DS.Space.s10)
                        .padding(.top, DS.Space.s10)
                        .padding(.bottom, DS.Space.s2)
                    ForEach(group.1) { conversation in
                        Button {
                            model.open(conversation)
                            showsHistory = false
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(conversation.title).font(.flixor(.footnote, weight: .semibold)).lineLimit(1)
                                Text(historySubtitle(conversation)).font(.flixor(.caption)).foregroundStyle(theme.textTertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, DS.Space.s10)
                            .padding(.vertical, DS.Space.s8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(AskHoverButtonStyle(cornerRadius: 9))
                        .contextMenu {
                            Button("Delete Conversation", role: .destructive) { model.delete(conversation) }
                        }
                    }
                }
            }
            .padding(DS.Space.s8)
        }
        .frame(maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            Text("Kept on this Mac for this profile.")
                .font(.flixor(.caption))
                .foregroundStyle(theme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Space.s12)
                .background(Color.black.opacity(0.2))
        }
    }

    private var groupedConversations: [(String, [AskConversation])] {
        let calendar = Calendar.current
        var today: [AskConversation] = [], yesterday: [AskConversation] = [], earlier: [AskConversation] = []
        for c in model.conversations {
            if calendar.isDateInToday(c.updatedAt) { today.append(c) }
            else if calendar.isDateInYesterday(c.updatedAt) { yesterday.append(c) }
            else { earlier.append(c) }
        }
        return [(String(localized: "Today"), today), (String(localized: "Yesterday"), yesterday), (String(localized: "Earlier"), earlier)]
            .filter { !$0.1.isEmpty }
    }

    private func historySubtitle(_ c: AskConversation) -> String {
        let questions = c.messages.filter { $0.role == .user }.count
        let count = questions == 1 ? String(localized: "1 question") : String(localized: "\(questions) questions")
        let time = Calendar.current.isDateInToday(c.updatedAt)
            ? DateFormatter.localizedString(from: c.updatedAt, dateStyle: .none, timeStyle: .short)
            : DateFormatter.localizedString(from: c.updatedAt, dateStyle: .medium, timeStyle: .none)
        return "\(count) · \(time)"
    }

    // MARK: Opening things

    private func open(_ target: AskOpenTarget) {
        let tab = mainViewState.selectedTab
        switch target {
        case .title(let item):
            router.push(DetailsNavigationItem(item: item), on: tab)
        case .person(let person):
            router.push(PersonRoute(tmdbId: String(person.id), name: person.name, profilePath: person.profilePath), on: tab)
        case .entity(let entity):
            switch entity.kind {
            case .company, .network:
                router.push(EntityBrowseRoute(kind: entity.kind == .company ? .company : .network,
                                              id: entity.tmdbId, name: entity.name, logoPath: entity.logoPath), on: tab)
            case .collection:
                if let first = entity.firstPart {
                    router.push(DetailsNavigationItem(item: first), on: tab)
                    return
                }
                Task { @MainActor in
                    let tmdb = FlixorCore.shared.tmdb
                    guard let details = try? await tmdb.getCollection(id: entity.tmdbId),
                          let first = details.sortedByRelease().parts.first else { return }
                    let item = MediaItem(
                        id: "tmdb:movie:\(first.id)", title: first.title ?? first.name ?? entity.name, type: "movie",
                        thumb: TMDBImageURL.url(first.posterPath, size: .w500)?.absoluteString,
                        art: TMDBImageURL.url(first.backdropPath, size: .w780)?.absoluteString,
                        year: first.releaseDate.flatMap { Int($0.prefix(4)) }, rating: nil, duration: nil, viewOffset: nil, summary: nil,
                        grandparentTitle: nil, grandparentThumb: nil, grandparentArt: nil, grandparentRatingKey: nil,
                        parentIndex: nil, index: nil, parentRatingKey: nil, parentTitle: nil, leafCount: nil, viewedLeafCount: nil
                    )
                    router.push(DetailsNavigationItem(item: item), on: tab)
                }
            }
        }
    }

    private func openSettings() {
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}

enum AskOpenTarget {
    case title(MediaItem)
    case person(AskPersonCard)
    case entity(AskEntityCard)
}

enum AskModelNames {
    /// "gpt-6.1-sol" → "GPT-6.1 Sol", "claude-opus-5-5" → "Claude Opus 5.5".
    static func friendly(_ id: String) -> String {
        guard !id.isEmpty else { return String(localized: "Choose a model") }
        let parts = id.split(separator: "-").map(String.init)
        var words: [String] = []
        var i = 0
        while i < parts.count {
            let part = parts[i]
            if part.lowercased() == "gpt" { words.append("GPT"); i += 1; continue }
            // Version numbers written with dashes: 5-5 → 5.5
            if Int(part) != nil, i + 1 < parts.count, Int(parts[i + 1]) != nil, parts[i + 1].count <= 2 {
                words.append("\(part).\(parts[i + 1])"); i += 2; continue
            }
            words.append(part.prefix(1).uppercased() + part.dropFirst())
            i += 1
        }
        // "GPT 6.1" reads as "GPT-6.1"
        return words.joined(separator: " ").replacingOccurrences(of: "GPT ", with: "GPT-")
    }
}

private struct AskHoverButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 7
    func makeBody(configuration: Configuration) -> some View {
        AskHoverBody(configuration: configuration, cornerRadius: cornerRadius)
    }
    private struct AskHoverBody: View {
        let configuration: Configuration
        let cornerRadius: CGFloat
        @State private var hovered = false
        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.12 : (hovered ? 0.07 : 0))))
                .onHover { hovered = $0 }
        }
    }
}

// MARK: - Messages

private struct AskMessageView: View {
    let message: AskMessage
    let width: CGFloat
    let isLast: Bool
    let onFollowUp: (String) -> Void
    let onRetry: () -> Void
    let onUseApple: () -> Void
    let onOpenSettings: () -> Void
    let open: (AskOpenTarget) -> Void

    @State private var hovered = false
    @State private var showsSteps = false
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        if message.role == .user {
            VStack(alignment: .trailing, spacing: 3) {
                if let context = message.contextTitle {
                    Text("About \(context)").font(.flixor(.micro)).foregroundStyle(theme.textTertiary)
                }
                Text(message.text)
                    .font(.flixor(.callout))
                    .padding(.horizontal, DS.Space.s12)
                    .padding(.vertical, 7)
                    .background(UnevenBubble().fill(Color(hex: 0x2C2B33)))
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 40)
        } else {
            HStack(alignment: .top, spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(message.isError
                              ? AnyShapeStyle(Color(hex: 0x3A3A40))
                              : AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x7C3AED), askTint], startPoint: .topLeading, endPoint: .bottomTrailing)))
                    Text(message.isError ? "!" : "✦").font(.flixor(.caption, weight: .bold)).foregroundStyle(.white)
                }
                .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: DS.Space.s8) {
                    if !message.steps.isEmpty { stepsLine }
                    if message.isError {
                        Text(message.text).font(.flixor(.callout)).foregroundStyle(Color(hex: 0xFFD27A))
                        AskFlow(spacing: 6) {
                            AskActionChip(title: "↻ Try again", action: onRetry)
                            if AISettings.shared.engine != .apple && AppleEngine.availability == nil {
                                AskActionChip(title: "Use Apple Intelligence", tinted: true, action: onUseApple)
                            }
                            AskActionChip(title: "Open AI Settings", action: onOpenSettings)
                        }
                    } else {
                        if !message.text.isEmpty {
                            Text(markdown(message.text))
                                .font(.flixor(.callout))
                                .lineSpacing(2)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if message.wasStopped {
                            Text("Stopped").font(.flixor(.caption)).foregroundStyle(theme.textTertiary)
                        }
                        if !message.entities.isEmpty {
                            AskFlow(spacing: 6) {
                                ForEach(message.entities) { entity in AskEntityChip(entity: entity) { open(.entity(entity)) } }
                            }
                        }
                        if !message.people.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: DS.Space.s10) {
                                    ForEach(message.people) { person in AskPersonChip(person: person) { open(.person(person)) } }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        if !message.cards.isEmpty { cards }
                        if isLast && !message.followUps.isEmpty {
                            AskFlow(spacing: 6) {
                                ForEach(message.followUps, id: \.self) { question in
                                    AskActionChip(title: question, tinted: true) { onFollowUp(question) }
                                }
                            }
                            .padding(.top, 2)
                        }
                        HStack(spacing: 2) {
                            AskSmallAction(symbol: "doc.on.doc", title: "Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(message.text, forType: .string)
                            }
                            if isLast { AskSmallAction(symbol: "arrow.clockwise", title: "Retry", action: onRetry) }
                        }
                        .opacity(hovered ? 1 : 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
        }
    }

    private var stepsLine: some View {
        VStack(alignment: .leading, spacing: 3) {
            Button { withAnimation(DS.Motion.quick) { showsSteps.toggle() } } label: {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark").font(.flixor(.nano, weight: .bold)).foregroundStyle(theme.success)
                    Text(stepsSummary).font(.flixor(.caption)).foregroundStyle(theme.textTertiary).lineLimit(1)
                    Image(systemName: showsSteps ? "chevron.down" : "chevron.right").font(.flixor(.nano, weight: .bold)).foregroundStyle(theme.textTertiary)
                }
            }
            .buttonStyle(.plain)
            if showsSteps {
                ForEach(message.steps) { step in
                    Text("· \(step.label)").font(.flixor(.caption)).foregroundStyle(theme.textTertiary)
                }
                if !message.used.isEmpty {
                    Text("Used: " + message.used.joined(separator: " · ")).font(.flixor(.caption)).foregroundStyle(theme.textTertiary)
                }
            }
        }
    }

    private var stepsSummary: String {
        let first = message.steps.first?.label ?? ""
        let count = message.steps.count
        return count == 1 ? first : String(localized: "\(first) · \(count) steps")
    }

    @ViewBuilder
    private var cards: some View {
        if width >= 560 && message.cards.count >= 2 {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 150), spacing: 10, alignment: .top)], alignment: .leading, spacing: 12) {
                ForEach(message.cards) { card in AskPosterTile(card: card) { open(.title(card.item)) } }
            }
        } else if message.cards.count >= 4 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(message.cards) { card in AskPosterTile(card: card) { open(.title(card.item)) }.frame(width: 96) }
                }
                .padding(.vertical, 2)
            }
        } else {
            VStack(spacing: 6) {
                ForEach(message.cards) { card in AskCardRow(card: card) { open(.title(card.item)) } }
            }
        }
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

/// The answer being written: lookups as they happen, then the text as it streams.
private struct AskLiveView: View {
    let steps: [AskStep]
    let text: String
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x7C3AED), askTint], startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("✦").font(.flixor(.caption, weight: .bold)).foregroundStyle(.white)
            }
            .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 5) {
                if steps.isEmpty && text.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Thinking…").font(.flixor(.footnote)).foregroundStyle(theme.textSecondary)
                    }
                }
                ForEach(steps) { step in
                    HStack(spacing: 6) {
                        if step.done {
                            Image(systemName: "checkmark").font(.flixor(.nano, weight: .bold)).foregroundStyle(theme.success).frame(width: 12)
                        } else {
                            ProgressView().controlSize(.mini).frame(width: 12)
                        }
                        Text(step.label).font(.flixor(.footnote)).foregroundStyle(step.done ? theme.textSecondary : .white)
                    }
                }
                if !text.isEmpty {
                    (Text(text) + Text(" ▍").foregroundColor(askTint))
                        .font(.flixor(.callout))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct UnevenBubble: Shape {
    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 16, small: CGFloat = 4
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - small))
        p.addArc(center: CGPoint(x: rect.maxX - small, y: rect.maxY - small), radius: small, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        return p
    }
}

private struct AskActionChip: View {
    let title: String
    var tinted = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.flixor(.footnote, weight: .semibold))
                .multilineTextAlignment(.leading)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(tinted ? askTint.opacity(hovered ? 0.2 : 0.12) : Color.white.opacity(hovered ? 0.1 : 0.06)))
                .overlay(Capsule().strokeBorder(tinted ? askTint.opacity(0.35) : Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

private struct AskSmallAction: View {
    let symbol: String
    let title: LocalizedStringKey
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.flixor(.caption))
                .foregroundStyle(Color.white.opacity(0.5))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
        }
        .buttonStyle(AskHoverButtonStyle(cornerRadius: 5))
    }
}

// MARK: - Cards and chips

private struct AskCardRow: View {
    let card: AskTitleCard
    let onOpen: () -> Void
    @State private var isHovered = false
    @Environment(\.flixorTheme) private var theme

    private var owned: Bool { card.subtitle.contains(String(localized: "On your Plex")) }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: DS.Space.s10) {
                CachedAsyncImage(url: card.posterURL, maxPixelSize: 120)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 38, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.rank.map { "\($0) · \(card.item.title)" } ?? card.item.title)
                        .font(.flixor(.callout, weight: .semibold)).lineLimit(1)
                    Text(card.subtitle)
                        .font(.flixor(.caption))
                        .foregroundStyle(owned ? theme.success : theme.textSecondary)
                        .lineLimit(1)
                    if let note = card.note {
                        Text(note).font(.flixor(.footnote)).foregroundStyle(Color.white.opacity(0.85)).lineLimit(2)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.flixor(.caption, weight: .semibold)).foregroundStyle(theme.textTertiary)
            }
            .padding(DS.Space.s6)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(isHovered ? 0.08 : 0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Open \(card.item.title)")
    }
}

private struct AskPosterTile: View {
    let card: AskTitleCard
    let onOpen: () -> Void
    @State private var isHovered = false
    @Environment(\.flixorTheme) private var theme

    private var plexBadge: String? {
        guard card.subtitle.contains(String(localized: "On your Plex")) else { return nil }
        let quality = card.subtitle.components(separatedBy: " · ").last ?? ""
        return quality.contains("p") || quality.contains("4K") ? "PLEX \(quality.uppercased())" : "PLEX"
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 4) {
                ZStack(alignment: .topLeading) {
                    Color.white.opacity(0.06)
                    CachedAsyncImage(url: card.posterURL, maxPixelSize: 300).aspectRatio(contentMode: .fill)
                }
                .aspectRatio(2 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if let rank = card.rank {
                        Text("\(rank)").font(.flixor(.caption, weight: .heavy))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.65)))
                            .padding(6)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if let badge = plexBadge {
                        Text(badge).font(.flixor(.nano, weight: .bold)).foregroundStyle(theme.success)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.7)))
                            .padding(6)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(isHovered ? 0.45 : 0.08), lineWidth: 1))
                Text(card.item.title).font(.flixor(.footnote, weight: .semibold)).lineLimit(1)
                Text(card.note ?? card.item.year.map(String.init) ?? "")
                    .font(.flixor(.caption)).foregroundStyle(theme.textSecondary).lineLimit(2)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Open \(card.item.title)")
    }
}

/// A cast or crew member: round photo, name, and character or job.
private struct AskPersonChip: View {
    let person: AskPersonCard
    let onOpen: () -> Void
    @State private var isHovered = false
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: DS.Space.s6) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.08))
                    if person.profileURL != nil {
                        CachedAsyncImage(url: person.profileURL, maxPixelSize: 160)
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Text(person.name.split(separator: " ").compactMap(\.first).prefix(2).map(String.init).joined())
                            .font(.flixor(.bodyLarge, weight: .semibold))
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(isHovered ? 0.5 : 0.12), lineWidth: 1))
                VStack(spacing: 1) {
                    Text(person.name)
                        .font(.flixor(.caption, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    if !person.subtitle.isEmpty {
                        Text(person.subtitle)
                            .font(.flixor(.micro))
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(width: 76)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Open \(person.name)")
        .accessibilityLabel(Text(person.subtitle.isEmpty ? person.name : "\(person.name), \(person.subtitle)"))
    }
}

/// A studio, network or film series: small logo (or poster), name and kind.
private struct AskEntityChip: View {
    let entity: AskEntityCard
    let onOpen: () -> Void
    @State private var isHovered = false
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: DS.Space.s8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(entity.kind == .collection ? Color.white.opacity(0.08) : Color.white.opacity(0.9))
                    if entity.logoURL != nil {
                        CachedAsyncImage(url: entity.logoURL, contentMode: entity.kind == .collection ? .fill : .fit)
                            .padding(entity.kind == .collection ? 0 : 3)
                    } else {
                        Image(systemName: entity.kind == .collection ? "film.stack" : "building.2")
                            .font(.flixor(.caption))
                            .foregroundStyle(entity.kind == .collection ? theme.textSecondary : Color.black.opacity(0.6))
                    }
                }
                .frame(width: entity.kind == .collection ? 22 : 34, height: entity.kind == .collection ? 32 : 22)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    Text(entity.name).font(.flixor(.footnote, weight: .semibold)).lineLimit(1)
                    Text(entity.label).font(.flixor(.micro)).foregroundStyle(theme.textSecondary)
                }
                Image(systemName: "chevron.right").font(.flixor(.nano, weight: .bold)).foregroundStyle(theme.textTertiary)
            }
            .padding(.leading, DS.Space.s6)
            .padding(.trailing, DS.Space.s10)
            .padding(.vertical, DS.Space.s4)
            .background(Capsule().fill(Color.white.opacity(isHovered ? 0.1 : 0.06)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Open \(entity.name)")
        .accessibilityLabel(Text("\(entity.name), \(entity.label)"))
    }
}

/// Wraps chips onto as many lines as they need.
private struct AskFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// The ✦ button in the window corner that opens Ask Flixor.
struct AskFlixorLauncher: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "sparkles")
                .font(.flixor(.title3, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Circle().fill(Color(hex: 0x7C3AED).opacity(isHovered ? 1 : 0.85)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Ask Flixor (⌘J)")
        .accessibilityLabel(Text("Ask Flixor"))
    }
}
