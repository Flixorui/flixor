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

// MARK: - More (⋯)

/// What the ⋯ menu needs to start a download. Built only for titles that can
/// be downloaded (movies and episodes with a Plex source).
struct DetailsDownloadRequest {
    let ratingKey: String
    let serverId: String
    let type: DownloadMediaType
    let title: String
    let year: Int?
    let thumb: String?
    let grandparentTitle: String?
    let grandparentRatingKey: String?
    let parentIndex: Int?
    let index: Int?

    var globalKey: String { "\(serverId):\(ratingKey)" }

    @MainActor func start() {
        DownloadManager.shared.queueDownload(
            ratingKey: ratingKey, serverId: serverId, type: type, title: title, year: year, thumb: thumb,
            grandparentTitle: grandparentTitle, grandparentRatingKey: grandparentRatingKey,
            parentIndex: parentIndex, index: index
        )
    }
}

/// While a download is queued, running, failed or done, the hero shows its
/// own button (with progress); otherwise "Download" lives in the ⋯ menu.
struct DetailsDownloadSlot: View {
    let request: DetailsDownloadRequest
    @ObservedObject private var downloads = DownloadManager.shared

    var body: some View {
        if downloads.isDownloaded(request.globalKey) || downloads.getProgress(request.globalKey) != nil {
            DetailsDownloadButton(
                ratingKey: request.ratingKey,
                serverId: request.serverId,
                type: request.type,
                title: request.title,
                year: request.year,
                thumb: request.thumb,
                grandparentTitle: request.grandparentTitle,
                grandparentRatingKey: request.grandparentRatingKey,
                parentIndex: request.parentIndex,
                index: request.index
            )
        }
    }
}

/// The hero's ⋯ button: watched state, Trakt rating and download, in one
/// native menu (Apple TV style), so the action row stays short.
struct DetailsMoreActionsButton: View {
    let model: DetailsTitleActionsModel?
    let title: String
    let download: DetailsDownloadRequest?

    @State private var menuAnchor = MenuAnchor()
    @State private var showRatingSheet = false
    @ObservedObject private var downloads = DownloadManager.shared

    private var canDownload: Bool {
        guard let download else { return false }
        return !downloads.isDownloaded(download.globalKey) && downloads.getProgress(download.globalKey) == nil
    }

    private var hasItems: Bool {
        (model?.kind != nil) || (model?.canRate ?? false) || canDownload
    }

    var body: some View {
        if hasItems {
            Button(action: showMenu) {
                DetailsCircleActionLabel(
                    systemImage: "ellipsis",
                    isBusy: (model?.isWorking ?? false) || (model?.isRatingWorking ?? false)
                )
            }
            .buttonStyle(.plain)
            .background(MenuAnchorReader(anchor: menuAnchor))
            .help("More")
            .accessibilityLabel("More actions")
            .sheet(isPresented: $showRatingSheet) {
                if let model {
                    DetailsRatingSheet(
                        title: title,
                        initialRating: model.userRating,
                        onSave: { value in
                            showRatingSheet = false
                            model.rate(value)
                        },
                        onRemove: {
                            showRatingSheet = false
                            model.removeRating()
                        },
                        onCancel: { showRatingSheet = false }
                    )
                }
            }
        }
    }

    private func showMenu() {
        guard let view = menuAnchor.view else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false

        if let model, let kind = model.kind {
            let watched = model.isWatched == true
            if let progress = model.progressText {
                let item = NSMenuItem(title: progress, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
            if kind.isCollection {
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
                    let seasons = NSMenu()
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
                        seasons.addItem(item)
                    }
                    let item = NSMenuItem(title: String(localized: "Seasons"), action: nil, keyEquivalent: "")
                    item.submenu = seasons
                    menu.addItem(item)
                }
            } else if watched {
                menu.addItem(MenuActionItem(title: String(localized: "Mark as Unwatched"), systemImage: "arrow.uturn.backward.circle") {
                    model.setWatched(false)
                })
            } else {
                menu.addItem(MenuActionItem(title: String(localized: "Mark as Watched"), systemImage: "checkmark.circle") {
                    model.setWatched(true)
                })
            }
        }

        if let model, model.canRate {
            if menu.numberOfItems > 0 { menu.addItem(.separator()) }
            let title = model.userRating.map { String(localized: "Change Trakt Rating (\($0)/10)…") } ?? String(localized: "Rate on Trakt…")
            menu.addItem(MenuActionItem(title: title, systemImage: model.userRating == nil ? "star" : "star.fill") {
                showRatingSheet = true
            })
        }

        if canDownload, let download {
            if menu.numberOfItems > 0 { menu.addItem(.separator()) }
            menu.addItem(MenuActionItem(title: String(localized: "Download"), systemImage: "arrow.down.to.line") {
                download.start()
            })
        }

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -DS.Space.s6), in: view)
    }
}
