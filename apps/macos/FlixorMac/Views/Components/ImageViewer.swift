//
//  ImageViewer.swift
//  FlixorMac
//
//  Full-window image viewer (screenshots, artwork, covers). It is drawn by
//  RootView above everything, including the floating back button and the
//  navigation bar, so its own × is the only way out shown. Keyboard: Esc
//  closes; ← / → (and Space) step through; Home / End jump to the ends.
//

import AppKit
import SwiftUI

struct ImageViewerItem: Equatable {
    let url: URL
    var thumbnail: URL? = nil
    var caption: String? = nil
}

@MainActor
final class ImageViewerPresenter: ObservableObject {
    static let shared = ImageViewerPresenter()

    @Published private(set) var items: [ImageViewerItem] = []
    @Published var index = 0
    var isPresented: Bool { !items.isEmpty }

    func show(_ items: [ImageViewerItem], at index: Int = 0) {
        guard !items.isEmpty else { return }
        self.index = min(max(0, index), items.count - 1)
        withAnimation(DS.Motion.quick) { self.items = items }
    }

    func close() {
        withAnimation(DS.Motion.quick) { items = [] }
    }

    func step(_ offset: Int) {
        guard !items.isEmpty else { return }
        let next = index + offset
        guard items.indices.contains(next) else { return }
        index = next
    }

    func jump(toLast last: Bool) {
        guard !items.isEmpty else { return }
        index = last ? items.count - 1 : 0
    }
}

struct ImageViewerOverlay: View {
    @ObservedObject var presenter: ImageViewerPresenter

    @Environment(\.flixorTheme) private var theme
    @State private var keyMonitor: Any?

    var body: some View {
        if presenter.isPresented {
            let items = presenter.items
            let index = presenter.index
            ZStack {
                Color.black
                    .ignoresSafeArea()
                    .onTapGesture { presenter.close() }

                VStack(spacing: DS.Space.s16) {
                    topBar(count: items.count, index: index)
                    image(items[index], neighbours: neighbours(items, index))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if let caption = items[index].caption, !caption.isEmpty {
                        Text(caption)
                            .flixorFont(.callout)
                            .foregroundStyle(Color.white.opacity(0.75))
                            .lineLimit(2)
                    }
                    if items.count > 1 {
                        thumbnailStrip(items, index: index)
                    }
                }
                .padding(.horizontal, DS.Space.s32)
                // Clear of the window's close / minimise / zoom buttons.
                .padding(.top, DS.Space.s40)
                .padding(.bottom, DS.Space.s20)

                if items.count > 1 {
                    HStack {
                        arrow("chevron.left", enabled: index > 0, help: "Previous (←)") { presenter.step(-1) }
                        Spacer()
                        arrow("chevron.right", enabled: index < items.count - 1, help: "Next (→)") { presenter.step(1) }
                    }
                    .padding(.horizontal, DS.Space.s16)
                }
            }
            .transition(.opacity)
            .onAppear(perform: installKeys)
            .onDisappear(perform: removeKeys)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Image \(index + 1) of \(items.count)")
        }
    }

    // MARK: Pieces

    /// Counter centred, × on the right.
    private func topBar(count: Int, index: Int) -> some View {
        ZStack {
            if count > 1 {
                Text("\(index + 1) / \(count)")
                    .flixorFont(.callout, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.8))
                    .padding(.horizontal, DS.Space.s12)
                    .frame(height: 32)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
            }
            HStack {
                Spacer()
                closeButton
            }
        }
    }

    private var closeButton: some View {
        HStack {
            Button { presenter.close() } label: {
                Image(systemName: "xmark")
                    .font(.flixorIcon(DS.Icon.sm, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.14)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: DS.Border.thin))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
            .accessibilityLabel("Close")
        }
    }

    private func image(_ item: ImageViewerItem, neighbours: [ImageViewerItem]) -> some View {
        ZStack {
            // Only the full image: a thumbnail placeholder stayed drawn behind
            // it and doubled the watermark.
            CachedAsyncImage(url: item.url, contentMode: .fit) {
                ProgressView().controlSize(.large)
            }
            .id(item.url)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r8, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 30)
            // Start loading the images either side so stepping is instant.
            ForEach(neighbours, id: \.url) { next in
                CachedAsyncImage(url: next.url) { Color.clear }
                    .frame(width: 1, height: 1)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
        }
    }

    private func neighbours(_ items: [ImageViewerItem], _ index: Int) -> [ImageViewerItem] {
        [index - 1, index + 1].filter { items.indices.contains($0) }.map { items[$0] }
    }

    private func thumbnailStrip(_ items: [ImageViewerItem], index: Int) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s8) {
                    ForEach(Array(items.enumerated()), id: \.offset) { offset, item in
                        Button { presenter.index = offset } label: {
                            CachedAsyncImage(url: item.thumbnail ?? item.url, contentMode: .fill) { Color.white.opacity(0.08) }
                                .frame(width: 96, height: 54)
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.r4, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: DS.Radius.r4, style: .continuous)
                                    .strokeBorder(Color.white.opacity(offset == index ? 0.95 : 0), lineWidth: 2))
                                .opacity(offset == index ? 1 : 0.55)
                        }
                        .buttonStyle(.plain)
                        .id(offset)
                    }
                }
                .padding(.vertical, DS.Space.s4)
                .frame(maxWidth: .infinity)
            }
            .frame(height: 64)
            .onChange(of: index) { value in
                withAnimation(DS.Motion.quick) { proxy.scrollTo(value, anchor: .center) }
            }
            .onAppear { proxy.scrollTo(index, anchor: .center) }
        }
    }

    private func arrow(_ symbol: String, enabled: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.flixorIcon(DS.Icon.md, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(0.14)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.25)
        .disabled(!enabled)
        .help(help)
    }

    // MARK: Keyboard

    private func installKeys() {
        removeKeys()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard presenter.isPresented else { return event }
            switch event.keyCode {
            case 53: presenter.close()                       // Esc
            case 123, 126: presenter.step(-1)                 // ← ↑
            case 124, 125, 49: presenter.step(1)              // → ↓ Space
            case 115: presenter.jump(toLast: false)           // Home
            case 119: presenter.jump(toLast: true)            // End
            default: return event
            }
            return nil
        }
    }

    private func removeKeys() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}
