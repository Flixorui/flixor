//
//  AppKitMenu.swift
//  FlixorMac
//
//  Native menus opened from our own SwiftUI buttons. SwiftUI's `Menu` on macOS
//  discards a custom label and draws a small accent-tinted icon instead.
//

import AppKit
import SwiftUI

final class MenuActionItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, systemImage: String? = nil, isEnabled: Bool = true, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        self.isEnabled = isEnabled
        image = systemImage.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func run() {
        handler()
    }
}

/// Holds the view a menu opens from.
final class MenuAnchor {
    weak var view: NSView?
}

struct MenuAnchorReader: NSViewRepresentable {
    let anchor: MenuAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }
}
