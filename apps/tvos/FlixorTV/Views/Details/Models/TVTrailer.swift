import Foundation

struct TVTrailer: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let key: String
    let site: String
    let type: String
    let official: Bool?
    let publishedAt: String?
    let previewPlaybackURL: URL?

    var thumbnailURL: URL? {
        guard site.lowercased() == "youtube" else { return nil }
        return URL(string: "https://img.youtube.com/vi/\(key)/mqdefault.jpg")
    }

    var youtubeURL: URL? {
        guard site.lowercased() == "youtube" else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(key)")
    }

    var embedURL: URL? {
        guard site.lowercased() == "youtube" else { return nil }
        return URL(string: "https://www.youtube-nocookie.com/embed/\(key)?autoplay=1&rel=0&modestbranding=1&playsinline=1")
    }

    var inlinePlaybackURL: URL? {
        previewPlaybackURL ?? youtubeURL
    }

    var previewPlaybackExpiryDate: Date? {
        guard let previewPlaybackURL else { return nil }

        if let components = URLComponents(url: previewPlaybackURL, resolvingAgainstBaseURL: false),
           let expireValue = components.queryItems?.first(where: { $0.name == "expire" })?.value,
           let timestamp = TimeInterval(expireValue) {
            return Date(timeIntervalSince1970: timestamp)
        }

        let pathComponents = previewPlaybackURL.path.split(separator: "/")
        if let expireIndex = pathComponents.firstIndex(of: "expire"),
           pathComponents.indices.contains(pathComponents.index(after: expireIndex)),
           let timestamp = TimeInterval(pathComponents[pathComponents.index(after: expireIndex)]) {
            return Date(timeIntervalSince1970: timestamp)
        }

        return nil
    }

    func hasFreshPreviewPlaybackURL(
        now: Date = Date(),
        minimumRemainingLifetime: TimeInterval = 120
    ) -> Bool {
        guard previewPlaybackURL != nil else { return false }
        guard let previewPlaybackExpiryDate else { return true }
        return previewPlaybackExpiryDate.timeIntervalSince(now) > minimumRemainingLifetime
    }
}
