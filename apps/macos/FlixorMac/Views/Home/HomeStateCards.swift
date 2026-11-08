//
//  HomeStateCards.swift
//  FlixorMac
//
//  Inline state cards for the home page: offline, a failed row, and nothing
//  to show. They sit among the rows so the rest of the page stays usable; the
//  full-page ErrorView is kept for total failure only.
//

import SwiftUI

/// Icon, text and up to two actions on a quiet surface.
struct HomeStateCard: View {
    struct Action {
        let title: LocalizedStringKey
        let perform: () -> Void
    }

    let icon: String
    var iconTint: Color?
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var primary: Action?
    var secondary: Action?
    var isBusy: Bool = false

    @Environment(\.flixorTheme) private var theme

    var body: some View {
        HStack(spacing: DS.Space.cardPadding) {
            Image(systemName: icon)
                .font(.flixorIcon(DS.Icon.lg, weight: .medium))
                .foregroundStyle(iconTint ?? theme.textSecondary)
                .frame(width: DS.Icon.xxl, height: DS.Icon.xxl)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text(title)
                    .flixorFont(.body, weight: .semibold)
                    .foregroundStyle(theme.textPrimary)
                Text(message)
                    .flixorFont(.footnote)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: DS.Space.itemGap)

            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(Text("Retrying"))
            } else {
                if let secondary {
                    actionButton(secondary, prominent: false)
                }
                if let primary {
                    actionButton(primary, prominent: true)
                }
            }
        }
        .padding(DS.Space.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(theme.surfaceOverlay)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(theme.separator, lineWidth: DS.Border.thin)
        )
        .padding(.horizontal, DS.Space.s20)
    }

    private func actionButton(_ action: Action, prominent: Bool) -> some View {
        Button(action: action.perform) {
            Text(action.title)
                .flixorFont(.callout, weight: .semibold)
                .foregroundStyle(prominent ? theme.onAccent : theme.textPrimary)
                .padding(.horizontal, DS.Space.s14)
                .padding(.vertical, DS.Space.s6)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                        .fill(prominent ? theme.accent : theme.hoverFill)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(action.title))
    }
}

/// No network path. Replaces per-row errors while it shows.
struct HomeOfflineCard: View {
    let onRetry: () -> Void
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        HomeStateCard(
            icon: "wifi.slash",
            iconTint: theme.warning,
            title: "You're offline",
            message: "Check your network connection. Rows will refresh when you're back online.",
            primary: .init(title: "Retry", perform: onRetry)
        )
    }
}

/// One row (or Plex group) failed; names the source and offers a retry.
struct HomeRowErrorCard: View {
    let failure: HomeRowFailure
    var isRetrying: Bool = false
    let onRetry: () -> Void
    @Environment(\.flixorTheme) private var theme

    var body: some View {
        HomeStateCard(
            icon: "exclamationmark.triangle",
            iconTint: theme.warning,
            title: "Couldn't load \(failure.title)",
            message: "\(failure.source): \(failure.message)",
            primary: .init(title: "Retry", perform: onRetry),
            isBusy: isRetrying
        )
    }
}
