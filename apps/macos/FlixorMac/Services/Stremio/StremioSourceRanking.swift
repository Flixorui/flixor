//
//  StremioSourceRanking.swift
//  FlixorMac
//
//  Source ranking shared by the sources picker (auto-play best source) and the
//  player (next-episode source, dead-link recovery), plus "same source" matching.
//

import Foundation

enum StremioSourceRanking {
    /// Score used to pick the best source. `addonOrder` is the installation ids in
    /// the user's addon priority order (earlier = preferred).
    static func score(for stream: StremioPlayableStream, addonOrder: [String]) -> Int {
        var score = 0
        if stream.playable { score += 1_000_000 }
        if stream.behaviorHints?.cached == true { score += 100_000 }
        if stream.isDebrid == true { score += 50_000 }
        score += qualityScore(stream.quality)
        score += min((stream.size ?? 0) / 1_000_000, 9_999)

        if let groupIndex = addonOrder.firstIndex(where: { $0 == stream.addonInstallationId }) {
            score += max(0, 1_000 - groupIndex)
        }

        score += max(0, 500 - stream.streamIndex)
        return score
    }

    static func qualityScore(_ quality: String?) -> Int {
        guard let quality = quality?.lowercased() else { return 0 }
        if quality.contains("2160") || quality.contains("4k") { return 20_000 }
        if quality.contains("1080") { return 15_000 }
        if quality.contains("720") { return 10_000 }
        if quality.contains("480") { return 5_000 }
        return 0
    }

    /// Playable streams, best first.
    static func rankedPlayable(in results: [StremioAddonStreamResult]) -> [StremioPlayableStream] {
        let order = results.map(\.installationId)
        return results.flatMap(\.streams)
            .filter { $0.playable && $0.url != nil }
            .map { ($0, score(for: $0, addonOrder: order)) }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    // MARK: - Matching

    /// Resolution bucket (2160/1080/720/480) from the quality field, or from the
    /// name/title text addons usually put it in. Nil when unknown.
    static func resolutionBucket(_ stream: StremioPlayableStream) -> Int? {
        resolutionBucket(text: [stream.quality, stream.name, stream.title, stream.behaviorHints?.filename]
            .compactMap { $0 }
            .joined(separator: " "))
    }

    static func resolutionBucket(text: String) -> Int? {
        let text = text.lowercased()
        if text.contains("2160") || text.contains("4k") || text.contains("uhd") { return 2160 }
        if text.contains("1080") { return 1080 }
        if text.contains("720") { return 720 }
        if text.contains("480") { return 480 }
        return nil
    }

    static func isSameAddon(_ lhs: StremioPlayableStream, _ rhs: StremioPlayableStream) -> Bool {
        if let l = lhs.addonInstallationId, let r = rhs.addonInstallationId { return l == r }
        if let l = lhs.addonId, let r = rhs.addonId { return l == r }
        return false
    }

    /// Stremio `behaviorHints.bingeGroup`: same non-empty group = same release
    /// line (provider, quality, release group), meant for auto-picking the next episode.
    static func isSameBingeGroup(_ lhs: StremioPlayableStream, _ rhs: StremioPlayableStream) -> Bool {
        guard let l = lhs.behaviorHints?.bingeGroup, !l.isEmpty,
              let r = rhs.behaviorHints?.bingeGroup else { return false }
        return l == r
    }

    /// Picks the source closest to `reference` from `results`, in this order:
    /// same addon + same binge group; same addon + same resolution; same addon;
    /// any addon with the same resolution; best ranked. `tiers` limits which steps
    /// apply. Streams whose URL is in `excludingURLs` are never returned.
    static func bestMatch(
        for reference: StremioPlayableStream?,
        in results: [StremioAddonStreamResult],
        excludingURLs: Set<String> = [],
        tiers: MatchTiers = .all
    ) -> (stream: StremioPlayableStream, tier: MatchTier)? {
        let ranked = rankedPlayable(in: results).filter { !excludingURLs.contains($0.url ?? "") }
        guard !ranked.isEmpty else { return nil }
        guard let reference else {
            return tiers.contains(.bestRanked) ? (ranked[0], .bestRanked) : nil
        }

        let bucket = resolutionBucket(reference)
        let checks: [(MatchTier, (StremioPlayableStream) -> Bool)] = [
            (.bingeGroup, { isSameAddon($0, reference) && isSameBingeGroup($0, reference) }),
            (.addonAndQuality, { bucket != nil && isSameAddon($0, reference) && resolutionBucket($0) == bucket }),
            (.addon, { isSameAddon($0, reference) }),
            (.quality, { bucket != nil && resolutionBucket($0) == bucket }),
            (.bestRanked, { _ in true }),
        ]
        for (tier, matches) in checks where tiers.contains(tier.option) {
            if let stream = ranked.first(where: matches) {
                return (stream, tier)
            }
        }
        return nil
    }

    enum MatchTier: String {
        case bingeGroup, addonAndQuality, addon, quality, bestRanked

        var option: MatchTiers {
            switch self {
            case .bingeGroup: return .bingeGroup
            case .addonAndQuality: return .addonAndQuality
            case .addon: return .addon
            case .quality: return .quality
            case .bestRanked: return .bestRanked
            }
        }
    }

    struct MatchTiers: OptionSet {
        let rawValue: Int
        static let bingeGroup = MatchTiers(rawValue: 1 << 0)
        static let addonAndQuality = MatchTiers(rawValue: 1 << 1)
        static let addon = MatchTiers(rawValue: 1 << 2)
        static let quality = MatchTiers(rawValue: 1 << 3)
        static let bestRanked = MatchTiers(rawValue: 1 << 4)
        static let all: MatchTiers = [.bingeGroup, .addonAndQuality, .addon, .quality, .bestRanked]
        /// Next episode per the Stremio binge rules: same addon + binge group, else best ranked.
        static let nextEpisode: MatchTiers = [.bingeGroup, .bestRanked]
    }
}
