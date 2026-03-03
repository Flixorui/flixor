import Foundation

struct TVFocusMemory: Equatable {
    var lastSectionID: String?
    var lastItemIDsBySection: [String: String] = [:]
}
