import Foundation

struct PlayerTrack: Identifiable, Hashable {
    enum TrackType: String {
        case audio
        case subtitle = "sub"
        case video
    }

    let id: Int
    let ffIndex: Int?
    let type: TrackType
    let title: String?
    let language: String?
    let codec: String?
    let isDefault: Bool
    let isSelected: Bool

    var displayName: String {
        if let title, !title.isEmpty {
            return title
        }
        if let language, !language.isEmpty {
            return language.uppercased()
        }
        if let codec, !codec.isEmpty {
            return codec.uppercased()
        }
        return "Track \(id)"
    }
}
