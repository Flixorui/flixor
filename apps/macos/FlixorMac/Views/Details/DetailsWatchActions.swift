//
//  DetailsWatchActions.swift
//  FlixorMac
//
//  Hero action-row controls backed by DetailsTitleActionsModel: watched toggle
//  (movies/episodes), watched menu (shows/seasons, with per-season options) and
//  the Trakt "Rate" button.
//

import AppKit
import SwiftUI

// MARK: - Shared circle label

/// 44pt translucent circle used by the hero's secondary actions (matches
/// WatchlistButton / RequestButton `.circle`).
struct DetailsCircleActionLabel: View {
    let systemImage: String
    var tint: Color? = nil
    var isBusy: Bool = false
    var badgeText: String? = nil

    @Environment(\.flixorTheme) private var theme
    @State private var isHovered = false

    var body: some View {
        ZStack {
            if isBusy {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            } else {
                Image(systemName: systemImage)
                    .font(.flixorIcon(DS.Icon.lg, weight: .medium))
                    .foregroundStyle(tint ?? theme.textPrimary)
            }
        }
        .frame(width: 44, height: 44)
        .background(Color.white.opacity(isHovered ? 0.28 : 0.2))
        .clipShape(Circle())
        .overlay(alignment: .topTrailing) {
            if let badgeText, !isBusy {
                Text(badgeText)
                    .font(.flixor(.nano, weight: .bold))
                    .foregroundStyle(theme.onAccent)
                    .padding(.horizontal, DS.Space.s4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(theme.accent))
                    .offset(x: DS.Space.s4, y: -DS.Space.s2)
            }
        }
        .contentShape(Circle())
        .onHover { isHovered = $0 }
        .animation(DS.Motion.quick, value: isHovered)
    }
}

// MARK: - Watched

struct DetailsWatchedControl: View {
    @ObservedObject var model: DetailsTitleActionsModel

    @Environment(\.flixorTheme) private var theme
    @State private var menuAnchor = MenuAnchor()

    private var watched: Bool { model.isWatched == true }

    private var icon: String {
        if watched { return "checkmark.circle.fill" }
        if model.isInProgress { return "circle.lefthalf.filled" }
        return "checkmark.circle"
    }

    private var stateDescription: String {
        if watched { return String(localized: "Watched") }
        if let progress = model.progressText { return progress }
        return model.isWatched == nil ? String(localized: "Watch state unknown") : String(localized: "Not watched")
    }

    var body: some View {
        Group {
            if let kind = model.kind {
                if kind.isCollection {
                    collectionMenu(kind: kind)
                } else {
                    toggleButton
                }
            }
        }
        .disabled(model.isWorking)
    }

    private var toggleButton: some View {
        Button {
            model.setWatched(!watched)
        } label: {
            DetailsCircleActionLabel(
                systemImage: icon,
                tint: watched ? theme.accent : nil,
                isBusy: model.isWorking
            )
        }
        .buttonStyle(.plain)
        .help(watched ? "Mark as unwatched" : "Mark as watched")
        .accessibilityLabel(watched ? "Mark as unwatched" : "Mark as watched")
        .accessibilityValue(stateDescription)
    }

    private func collectionMenu(kind: DetailsTitleActionsModel.TitleKind) -> some View {
        Button {
            showCollectionMenu(kind: kind)
        } label: {
            DetailsCircleActionLabel(
                systemImage: icon,
                tint: watched ? theme.accent : nil,
                isBusy: model.isWorking
            )
        }
        .buttonStyle(.plain)
        .background(MenuAnchorReader(anchor: menuAnchor))
        .help("Watched status")
        .accessibilityLabel("Watched status")
        .accessibilityValue(stateDescription)
    }

    /// A native menu opened from our own button: SwiftUI's `Menu` on macOS discards
    /// a custom label and draws a small accent-tinted icon instead.
    private func showCollectionMenu(kind: DetailsTitleActionsModel.TitleKind) {
        guard let view = menuAnchor.view else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false

        if let progress = model.progressText {
            let item = NSMenuItem(title: progress, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(MenuActionItem(
            title: kind == .show ? String(localized: "Mark Show as Watched") : String(localized: "Mark Season as Watched"),
            systemImage: "checkmark.circle",
            isEnabled: !watched
        ) { model.setWatched(true) })

        menu.addItem(MenuActionItem(
            title: kind == .show ? String(localized: "Mark Show as Unwatched") : String(localized: "Mark Season as Unwatched"),
            systemImage: "arrow.uturn.backward.circle",
            isEnabled: model.isWatched != false || model.isInProgress
        ) { model.setWatched(false) })

        if !model.seasonOptions.isEmpty {
            menu.addItem(.separator())
            for season in model.seasonOptions {
                let submenu = NSMenu()
                submenu.addItem(MenuActionItem(title: String(localized: "Mark as Watched")) {
                    model.setWatched(true, season: season)
                })
                submenu.addItem(MenuActionItem(title: String(localized: "Mark as Unwatched")) {
                    model.setWatched(false, season: season)
                })
                let item = NSMenuItem(title: season.title, action: nil, keyEquivalent: "")
                item.submenu = submenu
                menu.addItem(item)
            }
        }

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -DS.Space.s6), in: view)
    }
}

private final class MenuActionItem: NSMenuItem {
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
private final class MenuAnchor {
    weak var view: NSView?
}

private struct MenuAnchorReader: NSViewRepresentable {
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

// MARK: - Rate

struct DetailsRateControl: View {
    @ObservedObject var model: DetailsTitleActionsModel
    let title: String

    @Environment(\.flixorTheme) private var theme
    @State private var showSheet = false

    var body: some View {
        if model.canRate {
            Button {
                showSheet = true
            } label: {
                DetailsCircleActionLabel(
                    systemImage: model.userRating == nil ? "star" : "star.fill",
                    tint: model.userRating == nil ? nil : theme.warning,
                    isBusy: model.isRatingWorking,
                    badgeText: model.userRating.map { String($0) }
                )
            }
            .buttonStyle(.plain)
            .disabled(model.isRatingWorking)
            .help(model.userRating.map { "Your Trakt rating: \($0)/10" } ?? "Rate on Trakt")
            .accessibilityLabel("Rate")
            .accessibilityValue(model.userRating.map { "\($0) out of 10" } ?? "Not rated")
            .sheet(isPresented: $showSheet) {
                DetailsRatingSheet(
                    title: title,
                    initialRating: model.userRating,
                    onSave: { value in
                        showSheet = false
                        model.rate(value)
                    },
                    onRemove: {
                        showSheet = false
                        model.removeRating()
                    },
                    onCancel: { showSheet = false }
                )
            }
        }
    }
}
