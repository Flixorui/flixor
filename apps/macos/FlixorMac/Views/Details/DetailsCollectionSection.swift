//
//  DetailsCollectionSection.swift
//  FlixorMac
//
//  "Part of <Collection>": the other movies of a TMDB collection (franchise)
//  in release order, with the movie being viewed highlighted.
//

import SwiftUI
import FlixorKit

// MARK: - Model

@MainActor
final class DetailsCollectionModel: ObservableObject {
    /// The movie's collection when it has at least two parts.
    @Published private(set) var collection: TMDBCollectionDetails?

    private var loadedMovieId: Int?

    /// Loads the collection for a TMDB movie id (nil clears it). Repeated calls
    /// with the same id are ignored.
    func load(movieId: Int?) async {
        guard movieId != loadedMovieId else { return }
        loadedMovieId = movieId
        collection = nil
        guard let movieId else { return }

        do {
            let result = try await FlixorCore.shared.tmdb.getCollection(forMovieId: movieId)
            guard loadedMovieId == movieId, !Task.isCancelled else { return }
            collection = (result?.parts.count ?? 0) > 1 ? result : nil
        } catch {
            // No collection row on failure; allow a retry on the next appearance.
            if loadedMovieId == movieId { loadedMovieId = nil }
        }
    }
}

// MARK: - View

struct DetailsCollectionSection: View {
    let collection: TMDBCollectionDetails
    /// TMDB id of the movie being viewed (highlighted, not tappable).
    let currentMovieId: Int?
    let onSelect: (MediaItem) -> Void

    @Environment(\.flixorTheme) private var theme
    @Environment(\.windowMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s16) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                Text("Part of \(collection.name ?? "a Collection")")
                    .flixorFont(.title2)
                    .foregroundStyle(theme.textPrimary)
                Text("\(collection.parts.count) movies, in release order")
                    .flixorFont(.footnote)
                    .foregroundStyle(theme.textTertiary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: DS.Space.s16) {
                    ForEach(Array(collection.parts.enumerated()), id: \.element.id) { index, part in
                        CollectionPartCard(
                            part: part,
                            position: index + 1,
                            isCurrent: part.id == currentMovieId,
                            width: metrics.posterWidth(base: 150),
                            onTap: {
                                guard part.id != currentMovieId else { return }
                                onSelect(Self.mediaItem(for: part))
                            }
                        )
                    }
                }
                .padding(.vertical, DS.Space.s6)
                .padding(.trailing, DS.Space.s60)
            }
        }
    }

    /// Same id format as the Suggested rows ("tmdb:movie:<id>").
    static func mediaItem(for part: TMDBMedia) -> MediaItem {
        MediaItem(
            id: "tmdb:movie:\(part.id)",
            title: part.title ?? part.name ?? "",
            type: "movie",
            thumb: part.posterPath.map { "https://image.tmdb.org/t/p/w500\($0)" },
            art: part.backdropPath.map { "https://image.tmdb.org/t/p/w780\($0)" },
            year: part.releaseDate.flatMap { Int($0.prefix(4)) },
            rating: nil,
            duration: nil,
            viewOffset: nil,
            summary: part.overview,
            grandparentTitle: nil,
            grandparentThumb: nil,
            grandparentArt: nil,
            grandparentRatingKey: nil,
            parentIndex: nil,
            index: nil,
            parentRatingKey: nil,
            parentTitle: nil,
            leafCount: nil,
            viewedLeafCount: nil
        )
    }
}

private struct CollectionPartCard: View {
    let part: TMDBMedia
    let position: Int
    let isCurrent: Bool
    let width: CGFloat
    let onTap: () -> Void

    @Environment(\.flixorTheme) private var theme
    @State private var isHovered = false

    private var title: String { part.title ?? part.name ?? "Untitled" }
    private var year: String? {
        guard let date = part.releaseDate, date.count >= 4 else { return nil }
        return String(date.prefix(4))
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: DS.Space.controlGap) {
                ZStack(alignment: .topLeading) {
                    poster
                        .frame(width: width, height: width * DS.Layout.posterAspect)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.poster, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.poster, style: .continuous)
                                .strokeBorder(
                                    isCurrent ? theme.accent : Color.white.opacity(isHovered ? DS.Opacity.tertiary : DS.Opacity.pressed),
                                    lineWidth: isCurrent ? DS.Border.focus + 1 : DS.Border.thin
                                )
                        )

                    Text(isCurrent ? "VIEWING" : "\(position)")
                        .flixorFont(.nano)
                        .foregroundStyle(isCurrent ? theme.onAccent : theme.textPrimary)
                        .padding(.horizontal, DS.Space.s6)
                        .padding(.vertical, DS.Space.s4)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.badge, style: .continuous)
                                .fill(isCurrent ? theme.accent : theme.scrim(DS.Opacity.scrimMedium))
                        )
                        .padding(DS.Space.s8)
                }
                .scaleEffect(isHovered && !isCurrent ? 1.03 : 1)
                .flixorShadow(isHovered ? .card : .raised)

                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    Text(title)
                        .flixorFont(.callout, weight: .semibold)
                        .foregroundStyle(isCurrent ? theme.textPrimary : theme.textPrimary.opacity(DS.Opacity.strong))
                        .lineLimit(2)
                    Text(year ?? "TBA")
                        .flixorFont(.caption)
                        .foregroundStyle(theme.textTertiary)
                }
                .frame(width: width, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DS.Motion.quick) { isHovered = hovering }
        }
        .accessibilityLabel(Text(isCurrent ? "\(title), currently viewing" : "\(title)\(year.map { ", \($0)" } ?? ""). Open details"))
    }

    @ViewBuilder private var poster: some View {
        if let path = part.posterPath, let url = URL(string: "https://image.tmdb.org/t/p/w342\(path)") {
            CachedAsyncImage(url: url, aspectRatio: 2.0 / 3.0, contentMode: .fill)
        } else {
            ZStack {
                theme.surfaceElevated
                Image(systemName: "film")
                    .font(.flixorIcon(DS.Icon.xl))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }
}
