import SwiftUI
import FlixorKit
import Nuke

enum TVHeroChromeStyle {
    case appleMinimal
    case dualArrows
    case focusOnly
}

struct TVHeroCarouselView: View {
    let items: [MediaItem]
    var focusNS: Namespace.ID? = nil
    var defaultFocus: Bool = false
    var chrome: TVHeroChromeStyle = .appleMinimal
    @Binding var currentIndex: Int

    @State private var autoAdvanceTask: Task<Void, Never>?
    @State private var isBillboardFocused = false
    @State private var hasReceivedInitialFocus = false

    private let autoAdvanceSeconds: UInt64 = 20

    private var activeItem: MediaItem? {
        guard !items.isEmpty else { return nil }
        let clamped = min(max(currentIndex, 0), items.count - 1)
        return items[clamped]
    }

    var body: some View {
        ZStack {
            if let item = activeItem {
                TVBillboardView(
                    item: item,
                    focusNS: focusNS,
                    // Only set default focus on first load, not when carousel advances
                    defaultFocus: defaultFocus && !hasReceivedInitialFocus,
                    layout: .fullBleed
                )
                    .transition(.opacity)
            }

            if items.count > 1 {
                heroChrome
            }
        }
        .frame(height: UX.heroFullBleedHeight)
        .frame(maxWidth: .infinity)
        .ignoresSafeArea(.container, edges: [.top, .horizontal])
        .animation(.easeInOut(duration: 0.35), value: currentIndex)
        .onAppear {
            clampIndex()
            prefetchAdjacentHeroImages()
            restartAutoAdvance()
        }
        .onDisappear {
            autoAdvanceTask?.cancel()
            autoAdvanceTask = nil
        }
        .onChange(of: items.map(\.id)) { _ in
            clampIndex()
            prefetchAdjacentHeroImages()
            restartAutoAdvance()
        }
        .onChange(of: currentIndex) { _ in
            prefetchAdjacentHeroImages()
            restartAutoAdvance()
        }
        .onChange(of: isBillboardFocused) { _ in
            restartAutoAdvance()
        }
        .onPreferenceChange(BillboardFocusKey.self) { hasFocus in
            isBillboardFocused = hasFocus
            if hasFocus && !hasReceivedInitialFocus {
                hasReceivedInitialFocus = true
            }
        }
    }

    @ViewBuilder
    private var heroChrome: some View {
        switch chrome {
        case .appleMinimal:
            appleMinimalChrome
        case .dualArrows:
            dualArrowChrome
        case .focusOnly:
            EmptyView()
        }
    }

    private var appleMinimalChrome: some View {
        VStack {
            Spacer()
            pageIndicators
                .padding(.bottom, UX.heroDotsBottomInset)
        }
        .allowsHitTesting(false)
    }

    private var dualArrowChrome: some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                heroArrowButton(systemName: "chevron.left", action: previous)

                pageIndicators

                heroArrowButton(systemName: "chevron.right", action: next)
            }
            .padding(.bottom, 34)
        }
    }

    private var pageIndicators: some View {
        HStack(spacing: 8) {
            ForEach(Array(items.indices), id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index == currentIndex ? Color.white : Color.white.opacity(0.45))
                    .frame(width: index == currentIndex ? 24 : 8, height: 8)
                    .animation(.easeOut(duration: 0.2), value: currentIndex)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule(style: .continuous).fill(Color.black.opacity(0.4)))
    }

    private func heroArrowButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 52, height: 52)
                .background(Circle().fill(Color.white.opacity(0.95)))
        }
        .buttonStyle(.plain)
    }

    private func next() {
        guard !items.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            currentIndex = (currentIndex + 1) % items.count
        }
    }

    private func previous() {
        guard !items.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            currentIndex = (currentIndex - 1 + items.count) % items.count
        }
    }

    private func clampIndex() {
        guard !items.isEmpty else {
            currentIndex = 0
            return
        }
        if currentIndex < 0 {
            currentIndex = 0
        } else if currentIndex >= items.count {
            currentIndex = items.count - 1
        }
    }

    private func restartAutoAdvance() {
        autoAdvanceTask?.cancel()
        autoAdvanceTask = nil
        guard items.count > 1 else { return }
        guard !isBillboardFocused else { return }
        autoAdvanceTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: autoAdvanceSeconds * 1_000_000_000)
                guard !Task.isCancelled else { return }
                next()
            }
        }
    }

    private func prefetchAdjacentHeroImages() {
        guard !items.isEmpty else { return }

        let clamped = min(max(currentIndex, 0), items.count - 1)
        let previous = (clamped - 1 + items.count) % items.count
        let next = (clamped + 1) % items.count

        let urls = [previous, next].compactMap { idx in
            ImageService.shared.artURL(for: items[idx], width: 2200, height: 1240)
        }
        TVHeroImagePrefetch.shared.startPrefetching(with: urls)
    }
}

private enum TVHeroImagePrefetch {
    static let shared = ImagePrefetcher(pipeline: ImagePipeline.shared)
}
