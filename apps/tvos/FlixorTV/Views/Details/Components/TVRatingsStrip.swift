import SwiftUI

struct TVRatingsStrip: View {
    let ratings: TVDetailsViewModel.ExternalRatings

    var body: some View {
        HStack(spacing: 8) {
            if let imdbScore = ratings.imdb?.score {
                RatingsPill {
                    HStack(spacing: 6) {
                        Text("IMDb")
                            .font(.system(size: 12, weight: .black))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.yellow)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        Text(String(format: "%.1f", imdbScore))
                            .font(.system(size: 14, weight: .semibold))
                        if let votes = ratings.imdb?.votes, votes > 0 {
                            Text(votesDisplay(votes))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
            }
            if let critic = ratings.rottenTomatoes?.critic {
                RatingsPill {
                    HStack(spacing: 6) {
                        Image(systemName: "leaf.fill")
                            .foregroundStyle(scoreColor(critic))
                        Text("\(critic)% Critics")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(scoreColor(critic))
                    }
                }
            }
            if let audience = ratings.rottenTomatoes?.audience {
                RatingsPill {
                    HStack(spacing: 6) {
                        Image(systemName: "person.3.fill")
                            .foregroundStyle(scoreColor(audience))
                        Text("\(audience)% Audience")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(scoreColor(audience))
                    }
                }
            }
        }
    }

    private func votesDisplay(_ v: Int) -> String {
        switch v {
        case 1_000_000...: return String(format: "%.1fM", Double(v)/1_000_000)
        case 10_000...: return String(format: "%.1fk", Double(v)/1_000)
        case 1_000...: return String(format: "%.1fk", Double(v)/1_000)
        default: return NumberFormatter.localizedString(from: NSNumber(value: v), number: .decimal)
        }
    }

    private func scoreColor(_ s: Int) -> Color {
        if s >= 85 { return Color(red: 0.42, green: 0.87, blue: 0.44) }
        if s >= 60 { return Color(red: 0.97, green: 0.82, blue: 0.35) }
        return Color(red: 0.94, green: 0.32, blue: 0.28)
    }
}

private struct RatingsPill<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.18)))
    }
}

