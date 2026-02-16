import SwiftUI

struct TVContentRatingBadge: View {
    let rating: String

    private var imageAssetName: String? {
        let lower = rating.lowercased().trimmingCharacters(in: .whitespaces)
        switch lower {
        case "g": return "g"
        case "pg": return "pg"
        case "pg-13", "pg13": return "pg13"
        case "r", "rated r": return "r_rated"
        case "tv-14", "tv14": return "tv14"
        case "tv-g", "tvg": return "tvg"
        case "tv-ma", "tvma": return "tvma"
        case "tv-pg", "tvpg": return "tvpg"
        case "unrated", "nr", "not rated": return "unrated"
        default: return nil
        }
    }

    var body: some View {
        if let assetName = imageAssetName {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(height: 14)
        } else {
            Text(rating)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
    }
}
