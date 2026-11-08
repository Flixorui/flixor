//
//  DetailsBadges.swift
//  FlixorMac
//
//  Small badge and rating components used by the details screen
//

import SwiftUI
import FlixorKit

// MARK: - Technical Badge Component
struct TechnicalBadge: View {
    let text: String
    var isHighlighted: Bool = false

    /// Maps badge text to image asset name
    private var imageAssetName: String? {
        let lower = text.lowercased()
        if lower == "4k" || lower == "uhd" || lower == "2160p" {
            return "4K"
        }
        if lower == "hd" || lower == "1080p" || lower == "1080i" || lower == "fhd" {
            return "hd"
        }
        if lower == "720p" || lower == "hd ready" {
            return "hd" // Use HD icon for 720p as well
        }
        // HDR formats - check more specific first
        if lower.contains("hdr10+") || lower.contains("hdr10 plus") {
            return "hdr10+"
        }
        if lower.contains("dolby vision") || lower == "dv" || lower.contains("dovi") {
            return "dolbyVision"
        }
        if lower.contains("hdr10") || lower.contains("hdr 10") || lower == "hdr" || lower.contains("hdr (") {
            return "hdr"
        }
        if lower.contains("dolby atmos") || lower.contains("atmos") || lower.contains("truehd") {
            return "dolbyatmos"
        }
        if lower == "cc" || lower.contains("closed caption") {
            return "cc"
        }
        if lower == "sdh" || lower.contains("deaf") || lower.contains("hard of hearing") {
            return "sdh"
        }
        if lower == "ad" || lower.contains("audio desc") {
            return "ad"
        }
        return nil
    }

    var body: some View {
        if let assetName = imageAssetName {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(height: 12)
        } else {
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Color.white.opacity(0.15)
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}

// MARK: - Content Rating Badge Component
struct ContentRatingBadge: View {
    let rating: String

    /// Maps content rating to image asset name
    private var imageAssetName: String? {
        let lower = rating.lowercased().trimmingCharacters(in: .whitespaces)
        switch lower {
        case "g":
            return "g"
        case "pg-13", "pg13":
            return "pg13"
        case "r", "rated r":
            return "r_rated"
        case "pg":
            return "pg"
        case "tv-14", "tv14":
            return "tv14"
        case "tv-g", "tvg":
            return "tvg"
        case "tv-ma", "tvma":
            return "tvma"
        case "tv-pg", "tvpg":
            return "tvpg"
        case "unrated", "nr", "not rated":
            return "unrated"
        default:
            return nil
        }
    }

    var body: some View {
        if let assetName = imageAssetName {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(height: 12)
        } else {
            Text(rating)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}

struct RatingsStrip: View {
    let ratings: DetailsViewModel.ExternalRatings

    var body: some View {
        HStack(spacing: 12) {
            if let imdbScore = ratings.imdb?.score {
                HStack(spacing: 4) {
                    IMDbMark()
                    Text(String(format: "%.1f", imdbScore))
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            if let critic = ratings.rottenTomatoes?.critic {
                HStack(spacing: 4) {
                    TomatoIcon(score: critic)
                    Text("\(critic)%")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            if let audience = ratings.rottenTomatoes?.audience {
                HStack(spacing: 4) {
                    PopcornIcon(score: audience)
                    Text("\(audience)%")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
        }
    }

    private func formattedVotes(_ votes: Int) -> String? {
        guard votes > 0 else { return nil }
        switch votes {
        case 1_000_000...:
            return String(format: "%.1fM", Double(votes) / 1_000_000)
        case 10_000...:
            return String(format: "%.1fk", Double(votes) / 1_000)
        case 1_000...:
            return String(format: "%.1fk", Double(votes) / 1_000)
        default:
            return NumberFormatter.localizedString(from: NSNumber(value: votes), number: .decimal)
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 85 { return Color(red: 0.42, green: 0.87, blue: 0.44) }
        if score >= 60 { return Color(red: 0.97, green: 0.82, blue: 0.35) }
        return Color(red: 0.94, green: 0.32, blue: 0.28)
    }
}

private struct RatingsPill<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.18))
            )
    }
}

struct IMDbMark: View {
    var body: some View {
        Image("imdb")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: 16)
    }
}

struct TomatoIcon: View {
    let score: Int

    var body: some View {
        Image(score >= 60 ? "tomato-fresh" : "tomato-rotten")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 18, height: 18)
    }
}

struct PopcornIcon: View {
    let score: Int

    var body: some View {
        Image(score >= 60 ? "popcorn-full" : "popcorn-fallen")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 18, height: 18)
    }
}

// MARK: - Badge helper

private struct HeroMetaPill: View {
    enum Style {
        case `default`
        case highlighted  // For HDR/DV - purple background
        case source       // For Plex - subtle white
        case warning      // For "No local source" - red background
    }

    let text: String
    var style: Style = .default

    private var palette: (background: Color, foreground: Color, border: Color?) {
        switch style {
        case .highlighted:
            // Purple for HDR/DV badges
            return (Color(red: 0.6, green: 0.35, blue: 0.71).opacity(0.85), Color.white, nil)
        case .source:
            // Subtle white for Plex source
            return (Color.white.opacity(0.18), Color.white, Color.white.opacity(0.25))
        case .warning:
            // Red for no local source
            return (Color.red.opacity(0.7), Color.white, nil)
        case .default:
            return (Color.white.opacity(0.12), Color.white, Color.white.opacity(0.2))
        }
    }

    var body: some View {
        let colors = palette
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(colors.background)
            )
            .overlay(
                Group {
                    if let border = colors.border {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(border, lineWidth: 1)
                    }
                }
            )
            .foregroundStyle(colors.foreground)
    }
}

// MARK: - Metadata Badge Component
private struct MetadataBadge: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.75))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

private struct Badge: View { let text: String; var body: some View { Text(text).font(.caption).padding(.horizontal, 8).padding(.vertical, 4).background(Color.white.opacity(0.12)).cornerRadius(6) } }
