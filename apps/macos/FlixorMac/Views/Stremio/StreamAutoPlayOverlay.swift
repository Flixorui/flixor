//
//  StreamAutoPlayOverlay.swift
//  FlixorMac
//
//  The "Finding a source…" card and the "Choose Source…" button next to Play.
//

import Combine
import SwiftUI

struct StreamAutoPlayOverlay: View {
    @ObservedObject var controller: StreamAutoPlayController
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        ZStack {
            if let title = controller.findingTitle {
                theme.scrim()
                    .ignoresSafeArea()
                    .transition(.opacity)
                card(title: title)
                    .transition(.opacity)
                    // Leaving the page (back, another tab) ends the search.
                    .onDisappear { controller.cancel() }
                    .inPageModal(onDismiss: { controller.cancel() })
            }
        }
        .animation(DS.Motion.standard, value: controller.findingTitle)
    }

    private func card(title: String) -> some View {
        VStack(spacing: DS.Space.itemGap) {
            ProgressView()
                .progressViewStyle(.circular)
                .accessibilityHidden(true)

            VStack(spacing: DS.Space.s4) {
                Text("Finding a source…")
                    .flixorFont(.headline, weight: .semibold)
                    .foregroundStyle(theme.textPrimary)
                Text(title)
                    .flixorFont(.callout)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }

            HStack(spacing: DS.Space.controlGap) {
                Button("Choose Source…") { controller.chooseSourceInstead() }
                    .accessibilityLabel("Stop looking and choose a source")
                Button("Cancel") { controller.cancel() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Cancel finding a source")
            }
        }
        .padding(DS.Space.sheetPadding)
        .frame(minWidth: 280)
        .background(theme.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.Radius.dialog, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

/// Opens the sources page next to Play. Only shown when Play would otherwise pick by itself.
struct StremioChooseSourceButton: View {
    let action: () -> Void
    @StateObject private var playAction = StremioPlayActionObserver()
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        if playAction.value.isAutomatic {
            Button(action: action) {
                Image(systemName: "list.bullet")
                    .font(.flixorIcon(DS.Icon.lg, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(DS.Opacity.selected), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Choose Source… (or hold Option when pressing Play)")
            .accessibilityLabel("Choose source")
        }
    }
}

/// Follows the current profile's Play setting so the page updates after Settings changes it.
@MainActor
private final class StremioPlayActionObserver: ObservableObject {
    @Published private(set) var value = UserDefaults.standard.stremioPlayAction

    init() {
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .map { _ in UserDefaults.standard.stremioPlayAction }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .assign(to: &$value)
    }
}
