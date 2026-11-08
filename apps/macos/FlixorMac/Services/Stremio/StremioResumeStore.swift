//
//  StremioResumeStore.swift
//  FlixorMac
//
//  Local resume state for generic stream playback.
//

import Foundation

actor StremioResumeStore {
    static let shared = StremioResumeStore()

    private let storage = StremioStorage.shared

    func get(contentKey: String) async -> ResumeState? {
        let index = await storage.resumeStateIndex()
        return index[contentKey]
    }

    func save(_ state: ResumeState) async {
        var index = await storage.resumeStateIndex()
        index[state.contentKey] = state
        await storage.setResumeStateIndex(index)
    }

    func remove(contentKey: String) async {
        var index = await storage.resumeStateIndex()
        index.removeValue(forKey: contentKey)
        await storage.setResumeStateIndex(index)
    }

    /// Removes resume points for a title. Content keys are `movie:<baseId>` or
    /// `series:<baseId>:<season>:<episode>` (see `StremioContentResolver.buildContentKey`),
    /// where baseId is an IMDb id or `tmdb:<id>`, so both forms are matched.
    /// - Parameters:
    ///   - season: nil = every episode of the series.
    ///   - episode: nil = every episode of `season`.
    /// - Returns: the removed content keys.
    @discardableResult
    func removeAll(
        isMovie: Bool,
        tmdbId: Int?,
        imdbId: String?,
        season: Int? = nil,
        episode: Int? = nil
    ) async -> [String] {
        var baseIds: [String] = []
        if let imdbId, !imdbId.isEmpty { baseIds.append(imdbId) }
        if let tmdbId { baseIds.append("tmdb:\(tmdbId)") }
        guard !baseIds.isEmpty else { return [] }

        var index = await storage.resumeStateIndex()
        let matching = index.keys.filter { key in
            let lowered = key.lowercased()
            return baseIds.contains { base in
                let base = base.lowercased()
                if isMovie { return lowered == "movie:\(base)" }
                if let season, let episode { return lowered == "series:\(base):\(season):\(episode)" }
                if let season { return lowered.hasPrefix("series:\(base):\(season):") }
                return lowered.hasPrefix("series:\(base):")
            }
        }
        guard !matching.isEmpty else { return [] }
        for key in matching { index.removeValue(forKey: key) }
        await storage.setResumeStateIndex(index)
        return Array(matching)
    }
}
