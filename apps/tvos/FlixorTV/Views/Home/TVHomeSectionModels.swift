import Foundation
import FlixorKit
import OSLog

enum TrailerPreviewDiagnostics {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "xyz.flixor.tv",
        category: "TrailerPreview"
    )

    static func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
        #if DEBUG
        print("🎞️ [TrailerPreview] \(message)")
        #endif
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        #if DEBUG
        print("❌ [TrailerPreview] \(message)")
        #endif
    }

    static func summarizeKey(_ key: String) -> String {
        guard key.count > 5 else { return key }
        return "\(key.prefix(3))...\(key.suffix(2))"
    }

    static func summarizeURL(_ url: URL?) -> String {
        guard let url else { return "nil" }
        if let host = url.host {
            return "\(host)\(url.path)"
        }
        return url.absoluteString
    }
}

enum TrailerPreviewFeatureFlags {
    private static let defaultsKey = "tvos.debug.useNuvioTrailerResolver"

    static var useNuvioResolver: Bool {
        if let override = UserDefaults.standard.object(forKey: defaultsKey) as? Bool {
            return override
        }
        return true
    }
}

enum TVBrowseContext: Hashable {
    case continueWatching
    case onDeck
    case watchlist
    case recentlyAdded(libraryKey: String)
    case collection(id: String)
    case tmdbPopular
    case tmdbTrending
    case traktList(id: String)
    case custom(id: String)
}

struct TVHomeSectionDescriptor: Identifiable, Hashable {
    let id: String
    let title: String
    let items: [MediaItem]
    let supportsSeeAll: Bool
    let browseContext: TVBrowseContext?
    let heroEligible: Bool
    let preferredRowKind: TVRowCardKind?
    let usesContinueWatchingStyle: Bool

    init(
        id: String,
        title: String,
        items: [MediaItem],
        supportsSeeAll: Bool = false,
        browseContext: TVBrowseContext? = nil,
        heroEligible: Bool = true,
        preferredRowKind: TVRowCardKind? = nil,
        usesContinueWatchingStyle: Bool = false
    ) {
        self.id = id
        self.title = title
        self.items = items
        self.supportsSeeAll = supportsSeeAll
        self.browseContext = browseContext
        self.heroEligible = heroEligible
        self.preferredRowKind = preferredRowKind
        self.usesContinueWatchingStyle = usesContinueWatchingStyle
    }
}

struct TVHomeFocusedPreview: Equatable {
    let itemID: String
    let title: String
    let summary: String?
    let logoURL: String?
    let backdropURL: String?
    let trailerURL: URL?
    let trailerAudioURL: URL?
    let sourceSectionID: String
}
