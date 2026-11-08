//
//  SearchPeopleRow.swift
//  FlixorMac
//
//  "People" row in search results (TMDB person search) and the inline
//  per-source status rows (still loading / failed with retry).
//

import SwiftUI
import FlixorKit

struct SearchPeopleRow: View {
    let people: [TMDBPersonSummary]
    let onTap: (TMDBPersonSummary) -> Void

    @Environment(\.windowMetrics) private var metrics

    private var diameter: CGFloat { metrics.posterWidth(base: 120) }

    var body: some View {
        CarouselRow(
            title: String(localized: "People"),
            items: people,
            itemWidth: diameter,
            spacing: DS.Space.s16,
            rowHeight: diameter + DS.Space.s64
        ) { person in
            SearchPersonCard(person: person, diameter: diameter) {
                onTap(person)
            }
        }
    }
}

struct SearchPersonCard: View {
    let person: TMDBPersonSummary
    let diameter: CGFloat
    let onTap: () -> Void

    @Environment(\.flixorTheme) private var theme
    @State private var isHovered = false

    private var imageURL: URL? {
        guard let path = person.profilePath, !path.isEmpty else { return nil }
        return ImageService.shared.proxyImageURL(url: "https://image.tmdb.org/t/p/h632\(path)")
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: DS.Space.s8) {
                ZStack {
                    Circle().fill(theme.surfaceElevated)
                    if let imageURL {
                        CachedAsyncImage(url: imageURL, contentMode: .fill) {
                            placeholder
                        }
                        .frame(width: diameter, height: diameter)
                    } else {
                        placeholder
                    }
                }
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())
                .overlay(
                    Circle().strokeBorder(
                        isHovered ? theme.focusRing : theme.separator,
                        lineWidth: isHovered ? DS.Border.focus : DS.Border.thin
                    )
                )
                .scaleEffect(isHovered ? 1.04 : 1)
                .flixorShadow(isHovered ? .floating : .card)

                VStack(spacing: DS.Space.s2) {
                    Text(person.name)
                        .flixorFont(.callout, weight: .semibold)
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    if let department = person.knownForDepartment, !department.isEmpty {
                        Text(department)
                            .flixorFont(.caption)
                            .foregroundStyle(theme.textTertiary)
                            .lineLimit(1)
                    }
                }
                .frame(width: diameter)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DS.Motion.quick) { isHovered = hovering }
        }
        .accessibilityLabel(Text(accessibilityText))
    }

    private var placeholder: some View {
        ZStack {
            theme.surfaceElevated
            Image(systemName: "person.fill")
                .font(.flixorIcon(DS.Icon.xxl))
                .foregroundStyle(theme.textTertiary)
        }
    }

    private var accessibilityText: String {
        if let department = person.knownForDepartment, !department.isEmpty {
            return "\(person.name), \(department)"
        }
        return person.name
    }
}

// MARK: - Section status rows

/// Inline row for a source that failed, with a retry button.
struct SearchSectionErrorRow: View {
    let message: String
    let onRetry: () -> Void

    @Environment(\.flixorTheme) private var theme

    var body: some View {
        HStack(spacing: DS.Space.controlGap) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.flixorIcon(DS.Icon.sm))
                .foregroundStyle(theme.warning)
            Text(message)
                .flixorFont(.callout)
                .foregroundStyle(theme.textSecondary)
            Button(action: onRetry) {
                Text("Retry")
                    .flixorFont(.callout, weight: .semibold)
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, DS.Space.s10)
                    .padding(.vertical, DS.Space.s4)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                            .fill(theme.hoverFill)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Retry: \(message)"))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, SearchLayout.gutter)
    }
}

/// Inline row for sources still loading after others returned results.
struct SearchSectionLoadingRow: View {
    let message: String

    @Environment(\.flixorTheme) private var theme

    var body: some View {
        HStack(spacing: DS.Space.controlGap) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .flixorFont(.callout)
                .foregroundStyle(theme.textTertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, SearchLayout.gutter)
    }
}
