import SwiftUI
import FlixorKit
import Nuke

enum TVRowCardKind { case poster, landscape }

struct TVRowMenuAction: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let role: ButtonRole?
    let handler: () -> Void

    init(
        id: String,
        title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        handler: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.handler = handler
    }
}

struct TVRowTailAction {
    let title: String
    let systemImage: String
    let handler: () -> Void
}

struct TVCarouselRow: View {
    let title: String
    let items: [MediaItem]
    let kind: TVRowCardKind
    var focusNS: Namespace.ID? = nil
    var defaultFocus: Bool = false
    var preferredFocusItemId: String? = nil
    var sectionId: String = ""
    var landscapeFocusOutline: Bool = false
    var onSelect: ((MediaItem) -> Void)? = nil
    var screenID: TVScreenID? = nil
    var focusScreenKey: String? = nil
    var tailAction: TVRowTailAction? = nil
    var menuActions: ((MediaItem) -> [TVRowMenuAction])? = nil
    var onItemFocus: ((MediaItem) -> Void)? = nil
    var previewTrailerProvider: ((MediaItem) async -> TVTrailer?)? = nil

    @FocusState private var focusedID: String?
    @State private var expandedID: String?
    @State private var expandedTrailerItemID: String?
    @State private var expandedTrailer: TVTrailer?
    @State private var scrollProxy: ScrollViewProxy?
    @State private var expansionTask: Task<Void, Never>?
    @State private var lastFocusedIndex: Int?
    @EnvironmentObject private var profileSettings: TVProfileSettings
    @EnvironmentObject private var focusCoordinator: TVFocusCoordinator
    @Environment(\.tvThemePalette) private var theme
    @Environment(\.tvTypography) private var typography
    @Environment(\.tvCardVisualTokens) private var cardTokens

    private var posterScale: CGFloat {
        profileSettings.posterWidthMultiplier
    }

    private var posterSize: CGSize { .init(width: UX.posterWidth * posterScale, height: UX.posterHeight * posterScale) }
    private var landscapeSize: CGSize { .init(width: UX.landscapeWidth, height: UX.landscapeHeight) }
    private var expandedWidth: CGFloat { posterSize.height * (16.0/9.0) }
    private var tailFocusID: String? { tailAction == nil ? nil : "__tail__\(sectionId)" }
    private var resolvedFocusScreenKey: String? { focusScreenKey ?? screenID?.rawValue }
    private var resolvedPreferredFocusItemId: String? {
        preferredFocusItemId
            ?? resolvedFocusScreenKey.flatMap { focusCoordinator.lastFocusedItem(screen: $0, sectionID: sectionId) }
            ?? items.first?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(typography.section)
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, UX.gridH)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: UX.itemSpacing) {
                        ForEach(items, id: \.id) { item in
                            let isExpanded = kind == .poster && expandedID == item.id
                            let itemHeight = kind == .poster ? posterSize.height : landscapeSize.height
                            let itemWidth = (kind == .poster) ? (isExpanded ? expandedWidth : posterSize.width) : landscapeSize.width
                            let hasExpanded = kind == .poster && expandedID != nil
                            let neighborScale: CGFloat = (hasExpanded && !isExpanded) ? cardTokens.neighborScale : 1.0
                            let neighborOpacity: Double = (hasExpanded && !isExpanded) ? cardTokens.neighborDimOpacity : 1.0

                            // Stable focusable wrapper - never changes identity
                            ZStack {
                                if kind == .poster {
                                    TVPosterCard(item: item, isFocused: focusedID == item.id)
                                        .opacity(isExpanded ? 0 : 1)
                                        .animation(.easeOut(duration: 0.15), value: isExpanded)

                                    if isExpanded {
                                        TVLandscapeCard(
                                            item: item,
                                            showBadges: true,
                                            outlined: true,
                                            heightOverride: itemHeight,
                                            overrideURL: ImageService.shared.continueWatchingURL(for: item, width: 960, height: 540),
                                            previewTrailer: expandedTrailerItemID == item.id ? expandedTrailer : nil,
                                            previewTrailerMuted: profileSettings.focusedPosterTrailerMuted
                                        )
                                        .transition(.opacity)
                                    }
                                } else {
                                    TVLandscapeCard(
                                        item: item,
                                        showBadges: false,
                                        isFocused: focusedID == item.id,
                                        focusOutlineOnFocus: landscapeFocusOutline
                                    )
                                }
                            }
                            .frame(width: itemWidth, height: itemHeight, alignment: .bottom)
                            .id(item.id)
                            .focusable(true)
                            .focused($focusedID, equals: item.id)
                            .onTapGesture { onSelect?(item) }
                            .modifier(DefaultFocusModifier(
                                ns: focusNS,
                                enabled: defaultFocus && item.id == resolvedPreferredFocusItemId
                            ))
                            .scaleEffect(neighborScale, anchor: .bottom)
                            .opacity(neighborOpacity)
                            .animation(.easeOut(duration: 0.18), value: expandedID)
                            .contextMenu {
                                if let menuActions {
                                    ForEach(menuActions(item)) { action in
                                        Button(role: action.role) {
                                            action.handler()
                                        } label: {
                                            Label(action.title, systemImage: action.systemImage)
                                        }
                                    }
                                }
                            }
                        }

                        if let tailAction, let tailFocusID {
                            TVSeeAllCard(
                                title: tailAction.title,
                                systemImage: tailAction.systemImage,
                                isFocused: focusedID == tailFocusID,
                                kind: kind,
                                posterSize: posterSize,
                                landscapeSize: landscapeSize
                            )
                            .frame(
                                width: kind == .poster ? posterSize.width : landscapeSize.width,
                                height: kind == .poster ? posterSize.height : landscapeSize.height,
                                alignment: .bottom
                            )
                            .id(tailFocusID)
                            .focusable(true)
                            .focused($focusedID, equals: tailFocusID)
                            .onTapGesture {
                                tailAction.handler()
                            }
                        }
                    }
                    .padding(.horizontal, UX.gridH)
                    .frame(height: (kind == .poster ? posterSize.height : landscapeSize.height), alignment: .bottom)
                }
                .onAppear { scrollProxy = proxy }
                .onChange(of: focusedID) { newValue in
                    expansionTask?.cancel()

                    // Handle focus loss - collapse expansion
                    guard let id = newValue else {
                        TrailerPreviewDiagnostics.debug("Focus cleared row=\(sectionId); collapsing expanded preview")
                        withAnimation(.easeOut(duration: 0.2)) { expandedID = nil }
                        clearExpandedTrailer()
                        lastFocusedIndex = nil
                        return
                    }

                    if id == tailFocusID {
                        TrailerPreviewDiagnostics.debug("Tail action focused row=\(sectionId); collapsing expanded preview")
                        resolvedFocusScreenKey.map { focusCoordinator.remember(screen: $0, sectionID: sectionId, itemID: nil) }
                        if let sp = scrollProxy {
                            sp.scrollTo(id, anchor: .trailing)
                        }
                        withAnimation(.easeOut(duration: 0.18)) {
                            expandedID = nil
                        }
                        clearExpandedTrailer()
                        return
                    }

                    HomeHitchTracer.mark("RowFocusChanged", row: sectionId, extra: "item=\(id)")
                    HomeHitchTracer.measureRenderTime("RowFocusRender", row: sectionId)

                    guard let currentIndex = items.firstIndex(where: { $0.id == id }) else { return }
                    let item = items[currentIndex]
                    resolvedFocusScreenKey.map { focusCoordinator.remember(screen: $0, sectionID: sectionId, itemID: id) }
                    onItemFocus?(item)

                    if let sp = scrollProxy {
                        let shouldScroll: Bool
                        if id == items.first?.id {
                            shouldScroll = true
                        } else if let previousIndex = lastFocusedIndex {
                            shouldScroll = abs(currentIndex - previousIndex) > 2
                        } else {
                            shouldScroll = true
                        }

                        if shouldScroll {
                            let isFirstItem = id == items.first?.id
                            HomeHitchTracer.mark("RowHorizontalScroll", row: sectionId, extra: "item=\(id)")
                            sp.scrollTo(id, anchor: TVScrollAlignmentPolicy.home.horizontalAnchor(isFirstItem: isFirstItem))
                        }
                    }

                    lastFocusedIndex = currentIndex

                    guard kind == .poster, profileSettings.focusedPosterExpandEnabled else {
                        TrailerPreviewDiagnostics.debug("Expansion disabled row=\(sectionId) item=\(id)")
                        withAnimation(.easeOut(duration: 0.18)) {
                            expandedID = nil
                        }
                        clearExpandedTrailer()
                        return
                    }

                    if expandedID != nil, expandedID != id {
                        TrailerPreviewDiagnostics.debug("Collapsing previous expanded item row=\(sectionId) previous=\(expandedID ?? "nil") next=\(id)")
                        withAnimation(.easeOut(duration: 0.14)) {
                            expandedID = nil
                        }
                    }

                    if expandedTrailerItemID != id {
                        clearExpandedTrailer()
                    }

                    let expansionDelay = UInt64(max(0, profileSettings.focusedPosterExpandDelaySeconds) * 1_000_000_000)
                    TrailerPreviewDiagnostics.debug(
                        "Scheduling expansion row=\(sectionId) item=\(id) delaySeconds=\(profileSettings.focusedPosterExpandDelaySeconds)"
                    )

                    // Defer expansion slightly so rapid focus changes don't force reflow on every tick.
                    expansionTask = Task {
                        if expansionDelay > 0 {
                            try? await Task.sleep(nanoseconds: expansionDelay)
                        }
                        guard !Task.isCancelled else { return }
                        let span = HomeHitchTracer.begin("RowExpansionTask", row: sectionId)
                        withAnimation(.easeOut(duration: 0.18)) {
                            expandedID = id
                        }
                        TrailerPreviewDiagnostics.debug("Expansion applied row=\(sectionId) item=\(id)")
                        HomeHitchTracer.mark("RowExpansionApplied", row: sectionId, extra: "item=\(id)")
                        HomeHitchTracer.measureRenderTime("RowExpansionRender", row: sectionId)

                        if profileSettings.focusedPosterTrailerEnabled,
                           profileSettings.focusedPosterTrailerTarget == .expandedCard,
                           let previewTrailerProvider {
                            TrailerPreviewDiagnostics.debug("Trailer fetch start row=\(sectionId) item=\(id)")
                            let trailer = await previewTrailerProvider(item)
                            guard !Task.isCancelled else { return }
                            guard focusedID == id, expandedID == id else {
                                TrailerPreviewDiagnostics.debug("Trailer fetch discarded row=\(sectionId) item=\(id) because focus moved")
                                return
                            }
                            expandedTrailerItemID = id
                            expandedTrailer = trailer
                            if let trailer {
                                TrailerPreviewDiagnostics.debug(
                                    "Trailer fetch success row=\(sectionId) item=\(id) key=\(TrailerPreviewDiagnostics.summarizeKey(trailer.key))"
                                )
                            } else {
                                TrailerPreviewDiagnostics.debug("Trailer fetch produced no trailer row=\(sectionId) item=\(id)")
                            }
                        } else {
                            TrailerPreviewDiagnostics.debug("Trailer fetch skipped row=\(sectionId) item=\(id)")
                            clearExpandedTrailer()
                        }

                        span.end()
                    }

                    // Prefetch next items (±2) to keep scroll smooth
                    if let idx = items.firstIndex(where: { $0.id == id }) {
                        let window = items.dropFirst(max(0, idx-1)).prefix(4)
                        var urls: [URL] = window.compactMap { item in
                            if kind == .poster {
                                return ImageService.shared.thumbURL(for: item, width: 360, height: 540)
                            } else {
                                return ImageService.shared.continueWatchingURL(for: item, width: 960, height: 540)
                            }
                        }
                        // Pre-warm landscape image for focused poster expansion.
                        if kind == .poster, profileSettings.focusedPosterExpandEnabled,
                           let item = items.first(where: { $0.id == id }),
                           let landscapeURL = ImageService.shared.continueWatchingURL(for: item, width: 960, height: 540) {
                            urls.append(landscapeURL)
                        }
                        prefetchImages(urls)
                    }
                }
            }
            .frame(height: max((kind == .poster ? posterSize.height : landscapeSize.height), 340), alignment: .bottom)
            .padding(.bottom, kind == .poster ? 40 : 24)
            .focusSection()
            // Publish row focus state upwards (used for vertical snap)
            .preference(key: RowFocusKey.self, value: focusedID != nil ? sectionId : nil)
            // Publish focused item ID upwards (used for remembering scroll position)
            .preference(
                key: RowItemFocusKey.self,
                value: RowItemFocusValue(
                    rowId: focusedID != nil ? sectionId : nil,
                    itemId: items.contains(where: { $0.id == focusedID }) ? focusedID : nil
                )
            )
            .onAppear {
                if defaultFocus, focusedID == nil {
                    focusedID = resolvedPreferredFocusItemId
                }
            }
            .onDisappear {
                expansionTask?.cancel()
                TrailerPreviewDiagnostics.debug("Row disappeared row=\(sectionId); clearing expansion state")
                clearExpandedTrailer()
                expandedID = nil
            }
            .onChange(of: defaultFocus) { newValue in
                HomeHitchTracer.mark("RowDefaultFocusChanged", row: sectionId, extra: "value=\(newValue) currentFocus=\(focusedID ?? "nil")")
                // When this row becomes the default focus target, FORCE focus to preferred item.
                // Deferred to the next run loop turn so that the initial render pass
                // (focusedRowId change + vertical scroll) completes first, avoiding a
                // compounded ~10-12ms main-thread block.
                if newValue {
                    let targetItemId = resolvedPreferredFocusItemId
                    if let targetId = targetItemId {
                        if focusedID != targetId {
                            HomeHitchTracer.mark("RowDefaultFocusForced", row: sectionId, extra: "from=\(focusedID ?? "nil") to=\(targetId)")
                            DispatchQueue.main.async {
                                focusedID = targetId
                                HomeHitchTracer.measureRenderTime("RowForcedFocusRender", row: sectionId)
                            }
                        }
                    }
                }
            }
        }
    }

    private func clearExpandedTrailer() {
        expandedTrailerItemID = nil
        expandedTrailer = nil
    }
}

private struct TVSeeAllCard: View {
    let title: String
    let systemImage: String
    let isFocused: Bool
    let kind: TVRowCardKind
    let posterSize: CGSize
    let landscapeSize: CGSize

    @Environment(\.tvThemePalette) private var theme
    @Environment(\.tvTypography) private var typography
    @Environment(\.tvCardVisualTokens) private var cardTokens

    var body: some View {
        let radius = kind == .poster ? cardTokens.posterRadius : cardTokens.landscapeRadius

        VStack(alignment: .leading, spacing: 12) {
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: kind == .poster ? 36 : 30, weight: .semibold))
                .foregroundStyle(theme.accentStrong)

            Text(title)
                .font(kind == .poster ? typography.title : typography.section)
                .foregroundStyle(theme.textPrimary)

            Text("Open full grid")
                .font(typography.meta)
                .foregroundStyle(theme.textSecondary)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .leading
        )
        .padding(kind == .poster ? 22 : 24)
        .background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(theme.backgroundCard)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(isFocused ? theme.strokeFocused : theme.strokeDefault, lineWidth: isFocused ? cardTokens.focusedStrokeWidth : 1)
                )
        )
        .scaleEffect(isFocused ? cardTokens.focusedScale : 1.0)
        .shadow(
            color: .black.opacity(isFocused ? 0.42 : 0.18),
            radius: isFocused ? cardTokens.focusedShadowRadius : cardTokens.unfocusedShadowRadius,
            y: isFocused ? cardTokens.focusedShadowYOffset : cardTokens.unfocusedShadowYOffset
        )
        .animation(.easeOut(duration: UX.focusDur), value: isFocused)
        .frame(
            width: kind == .poster ? posterSize.width : landscapeSize.width,
            height: kind == .poster ? posterSize.height : landscapeSize.height
        )
    }
}

// Preference to propagate which row currently holds focus
struct RowFocusKey: PreferenceKey {
    static var defaultValue: String? = nil
    static func reduce(value: inout String?, nextValue: () -> String?) {
        let next = nextValue()
        if let next { value = next }
    }
}

// Preference to propagate which specific item is focused in which row
struct RowItemFocusValue: Equatable {
    let rowId: String?
    let itemId: String?
}

struct RowItemFocusKey: PreferenceKey {
    static var defaultValue = RowItemFocusValue(rowId: nil, itemId: nil)
    static func reduce(value: inout RowItemFocusValue, nextValue: () -> RowItemFocusValue) {
        let next = nextValue()
        if next.rowId != nil { value = next }
    }
}

private struct DefaultFocusModifier: ViewModifier {
    let ns: Namespace.ID?
    let enabled: Bool
    func body(content: Content) -> some View {
        if let ns, enabled {
            content.prefersDefaultFocus(true, in: ns)
        } else {
            content
        }
    }
}

private enum TVRowImagePrefetch {
    static let shared = ImagePrefetcher(pipeline: ImagePipeline.shared)
}

private func prefetchImages(_ urls: [URL]) {
    TVRowImagePrefetch.shared.startPrefetching(with: urls)
}

// MARK: - Hitch investigation tracer

import QuartzCore
import os.signpost

enum HomeHitchTracer {
    private static let log = OSLog(subsystem: "com.flixor.tv.hitch", category: .pointsOfInterest)
    private static var visitedRows: Set<String> = []

    static func isRevisit(_ row: String) -> Bool { visitedRows.contains(row) }
    static func recordVisit(_ row: String) { visitedRows.insert(row) }

    static func begin(_ name: String, row: String, extra: String = "") -> Span {
        let revisit = isRevisit(row)
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "HomeHitch", signpostID: id,
                    "%{public}s row=%{public}s revisit=%{public}d %{public}s",
                    name, row, revisit ? 1 : 0, extra)
        let start = CACurrentMediaTime()
        let label = "[\(name)] row=\(row) revisit=\(revisit) \(extra)"
        #if DEBUG
        print("[HITCH] BEGIN \(label) t=\(ms(start))")
        #endif
        return Span(log: log, id: id, label: label, start: start)
    }

    static func mark(_ name: String, row: String, extra: String = "") {
        let revisit = isRevisit(row)
        os_signpost(.event, log: log, name: "HomeHitch",
                    "%{public}s row=%{public}s revisit=%{public}d %{public}s",
                    name, row, revisit ? 1 : 0, extra)
        #if DEBUG
        print("[HITCH] EVENT [\(name)] row=\(row) revisit=\(revisit) \(extra) t=\(ms(CACurrentMediaTime()))")
        #endif
    }

    /// Measure how long SwiftUI blocks the main thread AFTER a state change.
    /// Call this right after mutating @State/@Published. The closure queued via
    /// DispatchQueue.main.async won't run until SwiftUI finishes its synchronous
    /// layout/render pass, so the delta captures the platform render cost.
    static func measureRenderTime(_ label: String, row: String) {
        let preRender = CACurrentMediaTime()
        let revisit = isRevisit(row)
        DispatchQueue.main.async {
            let elapsed = (CACurrentMediaTime() - preRender) * 1000
            os_signpost(.event, log: log, name: "HomeHitch",
                        "RENDER %{public}s row=%{public}s revisit=%{public}d elapsed=%.2fms",
                        label, row, revisit ? 1 : 0, elapsed)
            #if DEBUG
            print("[HITCH] RENDER [\(label)] row=\(row) revisit=\(revisit) renderTime=\(String(format: "%.2f", elapsed))ms")
            #endif
        }
    }

    struct Span {
        let log: OSLog
        let id: OSSignpostID
        let label: String
        let start: Double
        func end() {
            let elapsed = (CACurrentMediaTime() - start) * 1000
            os_signpost(.end, log: log, name: "HomeHitch", signpostID: id)
            #if DEBUG
            print("[HITCH] END   \(label) elapsed=\(String(format: "%.2f", elapsed))ms")
            #endif
        }
    }

    private static let epoch = CACurrentMediaTime()
    private static func ms(_ t: Double) -> String {
        String(format: "%.2f", (t - epoch) * 1000)
    }
}
