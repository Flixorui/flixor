//
//  DetailsFloatingHeader.swift
//  FlixorMac
//
//  Compact translucent header pinned to the top of the details page once the
//  hero has scrolled out of view: logo (or title), Play and My List.
//

import SwiftUI

struct DetailsFloatingHeader: View {
    @ObservedObject var vm: DetailsViewModel
    /// Nil when there is nothing to play from the header (e.g. a season page).
    let onPlay: (() -> Void)?
    /// "Play" plays from Plex; otherwise it opens addon sources.
    let playsFromPlex: Bool
    let horizontalPadding: CGFloat

    @Environment(\.flixorTheme) private var theme

    private static let height: CGFloat = 60
    private static let logoHeight: CGFloat = 32

    var body: some View {
        HStack(spacing: DS.Space.s16) {
            titleView
                .frame(maxWidth: 360, alignment: .leading)

            Spacer(minLength: DS.Space.s16)

            if let onPlay {
                Button(action: onPlay) {
                    HStack(spacing: DS.Space.s6) {
                        Image(systemName: "play.fill")
                            .font(.flixorIcon(DS.Icon.xs, weight: .semibold))
                        Text("Play")
                            .font(.flixor(.callout, weight: .semibold))
                    }
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, DS.Space.s16)
                    .padding(.vertical, DS.Space.s8)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(playsFromPlex ? "Play" : "Play with addons")
                .accessibilityLabel(playsFromPlex ? "Play" : "Play with addons")
            }

            if let watchlistId = vm.heroWatchlistCanonicalId {
                WatchlistButton(
                    canonicalId: watchlistId,
                    mediaType: vm.heroWatchlistMediaType,
                    plexRatingKey: vm.plexRatingKey,
                    plexGuid: vm.plexGuid,
                    tmdbId: vm.tmdbId,
                    imdbId: nil,
                    title: vm.title,
                    year: vm.year.flatMap { Int($0) },
                    posterURL: vm.posterURL?.absoluteString,
                    style: .icon
                )
            }
        }
        .padding(.horizontal, horizontalPadding)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .background(theme.scrim(DS.Opacity.scrimLight))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.separator)
                .frame(height: DS.Border.hairline)
        }
        .flixorShadow(.raised)
    }

    @ViewBuilder private var titleView: some View {
        if let logo = vm.logoURL {
            CachedAsyncImage(url: logo, contentMode: .fit) {
                titleText
            }
            .frame(height: Self.logoHeight, alignment: .leading)
            .accessibilityLabel(vm.title)
        } else {
            titleText
        }
    }

    private var titleText: some View {
        Text(vm.title)
            .flixorFont(.headline, weight: .bold)
            .foregroundStyle(theme.textPrimary)
            .lineLimit(1)
    }
}
