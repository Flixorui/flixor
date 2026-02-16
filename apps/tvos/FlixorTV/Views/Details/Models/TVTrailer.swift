import Foundation

struct TVTrailer: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let key: String
    let site: String
    let type: String
    let official: Bool?
    let publishedAt: String?

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
}
