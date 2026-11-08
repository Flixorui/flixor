//
//  DetailsWatchActions.swift
//  FlixorMac
//
//  Hero action-row controls backed by DetailsTitleActionsModel: watched toggle
//  (movies/episodes), watched menu (shows/seasons, with per-season options) and
//  the Trakt "Rate" button.
//

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
        return Menu {
            if let progress = model.progressText {
                Text(progress)
            }
            Button {
                model.setWatched(true)
            } label: {
                Label(kind == .show ? "Mark Show as Watched" : "Mark Season as Watched", systemImage: "checkmark.circle")
            }
            .disabled(watched)

            Button {
                model.setWatched(false)
            } label: {
                Label(kind == .show ? "Mark Show as Unwatched" : "Mark Season as Unwatched", systemImage: "arrow.uturn.backward.circle")
            }
            .disabled(model.isWatched == false && !model.isInProgress)

            if !model.seasonOptions.isEmpty {
                Divider()
                ForEach(model.seasonOptions) { season in
                    Menu(season.title) {
                        Button("Mark as Watched") { model.setWatched(true, season: season) }
                        Button("Mark as Unwatched") { model.setWatched(false, season: season) }
                    }
                }
            }
        } label: {
            DetailsCircleActionLabel(
                systemImage: icon,
                tint: watched ? theme.accent : nil,
                isBusy: model.isWorking
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Watched status")
        .accessibilityLabel("Watched status")
        .accessibilityValue(stateDescription)
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
