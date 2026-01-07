//
//  RatingsDisplay.swift
//  FlixorMac
//
//  Display multi-source ratings from MDBList
//

import SwiftUI

struct RatingsDisplay: View {
    let ratings: MDBListRatings?

    var body: some View {
        if let ratings = ratings, ratings.hasAnyRating {
            HStack(spacing: 10) {
                if let imdb = ratings.imdb {
                    RatingBadge(provider: "imdb", score: imdb)
                }
                if let tmdb = ratings.tmdb {
                    RatingBadge(provider: "tmdb", score: tmdb)
                }
                if let trakt = ratings.trakt {
                    RatingBadge(provider: "trakt", score: trakt)
                }
                if let letterboxd = ratings.letterboxd {
                    RatingBadge(provider: "letterboxd", score: letterboxd)
                }
                if let tomatoes = ratings.tomatoes {
                    RatingBadge(provider: "tomatoes", score: tomatoes)
                }
                if let audience = ratings.audience {
                    RatingBadge(provider: "audience", score: audience)
                }
                if let metacritic = ratings.metacritic {
                    RatingBadge(provider: "metacritic", score: metacritic)
                }
            }
        }
    }
}

struct RatingBadge: View {
    let provider: String
    let score: Double

    private var providerInfo: RatingProvider? {
        RATING_PROVIDERS[provider]
    }

    private var displayScore: String {
        // Letterboxd uses 5-point scale, others use 100 or 10
        if provider == "letterboxd" {
            return String(format: "%.1f", score)
        } else if score > 10 {
            // Percentage score (Rotten Tomatoes, Metacritic)
            return "\(Int(score))%"
        } else {
            // 10-point scale (IMDb, TMDB, Trakt)
            return String(format: "%.1f", score)
        }
    }

    private var iconName: String {
        switch provider {
        case "imdb": return "star.fill"
        case "tmdb": return "film.fill"
        case "trakt": return "chart.bar.fill"
        case "letterboxd": return "square.grid.2x2.fill"
        case "tomatoes": return "leaf.fill"
        case "audience": return "person.2.fill"
        case "metacritic": return "m.circle.fill"
        default: return "star.fill"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 12))
                .foregroundStyle(providerInfo?.color ?? .gray)

            Text(displayScore)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            (providerInfo?.color ?? .gray).opacity(0.15),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .help(providerInfo?.name ?? provider.capitalized)
    }
}

// MARK: - Async Ratings Loader

struct RatingsLoaderView: View {
    let imdbId: String?
    let mediaType: String

    @State private var ratings: MDBListRatings?
    @State private var isLoading = false

    @AppStorage("mdblistEnabled") private var mdblistEnabled: Bool = false

    private var shouldShow: Bool {
        return MDBListService.shared.isReady() && imdbId != nil
    }

    var body: some View {
        Group {
            if shouldShow {
                if isLoading {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading ratings...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    RatingsDisplay(ratings: ratings)
                }
            }
        }
        .task {
            await loadRatings()
        }
    }

    @MainActor
    private func loadRatings() async {
        guard shouldShow, let imdbId = imdbId else { return }

        isLoading = true
        defer { isLoading = false }

        let type = mediaType == "movie" ? "movie" : "show"
        ratings = await MDBListService.shared.fetchRatings(imdbId: imdbId, mediaType: type)
    }
}
