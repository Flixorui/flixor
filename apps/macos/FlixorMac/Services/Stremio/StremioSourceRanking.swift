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
        score += qualityScore(resolutionBucket(stream))
        score += min((stream.size ?? 0) / 1_000_000, 9_999)

        if let groupIndex = addonOrder.firstIndex(where: { $0 == stream.addonInstallationId }) {
            score += max(0, 1_000 - groupIndex)
        }

        score += max(0, 500 - stream.streamIndex)
        return score
    }

    /// Uses the resolution bucket because many addons send no `quality` field.
    static func qualityScore(_ bucket: Int?) -> Int {
        switch bucket {
        case 2160: return 20_000
        case 1080: return 15_000
        case 720: return 10_000
        case 480: return 5_000
        default: return 0
        }
    }

    /// Playable streams in the order the addon listed them.
    static func listedPlayable(in result: StremioAddonStreamResult) -> [StremioPlayableStream] {
        result.streams.filter { $0.playable && $0.url != nil }
    }

    /// The results of the first addon, in the order given, with anything playable.
    static func firstAddonWithPlayable(in results: [StremioAddonStreamResult]) -> [StremioAddonStreamResult] {
        results.first { !listedPlayable(in: $0).isEmpty }.map { [$0] } ?? []
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

    /// The candidate most like `reference`; the earliest wins a tie. A binge group is often
    /// as broad as "WEB-DL", so a match on it can still be a very different release.
    private static func closest(
        to reference: StremioPlayableStream,
        in candidates: [StremioPlayableStream]
    ) -> StremioPlayableStream? {
        var best: StremioPlayableStream?
        var bestValue = Int.min
        for candidate in candidates {
            let value = similarity(candidate, to: reference)
            if value > bestValue {
                best = candidate
                bestValue = value
            }
        }
        return best
    }

    /// Resolution counts most, then release group, then shared words in the file name
    /// and in the description, which is where aggregators name the provider.
    static func similarity(_ stream: StremioPlayableStream, to reference: StremioPlayableStream) -> Int {
        var value = 0
        if let bucket = resolutionBucket(reference), bucket == resolutionBucket(stream) { value += 1_000 }
        if let group = releaseGroup(reference), group == releaseGroup(stream) { value += 500 }
        value += 10 * fileWords(stream).intersection(fileWords(reference)).count
        value += 20 * descriptionWords(stream).intersection(descriptionWords(reference)).count
        return value
    }

    /// The `GROUP` in `Show.S01E01.1080p.WEB-DL-GROUP.mkv`.
    static func releaseGroup(_ stream: StremioPlayableStream) -> String? {
        guard let filename = stream.behaviorHints?.filename,
              let range = filename.range(of: "-[A-Za-z0-9]+(\\.[a-zA-Z0-9]{2,4})?$", options: .regularExpression) else {
            return nil
        }
        return filename[range].dropFirst().split(separator: ".").first?.lowercased()
    }

    private static func words(_ text: String?) -> [String] {
        (text ?? "").lowercased()
            .split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
            .map(String.init)
            .filter { $0.count > 1 }
    }

    /// File name words, without the season and episode that always differ.
    private static func fileWords(_ stream: StremioPlayableStream) -> Set<String> {
        Set(words(stream.behaviorHints?.filename).filter {
            $0.range(of: "^(s[0-9]+e[0-9]+|s[0-9]+|e[0-9]+)$", options: .regularExpression) == nil
        })
    }

    /// Letters only, because sizes and bitrates differ from episode to episode.
    private static func descriptionWords(_ stream: StremioPlayableStream) -> Set<String> {
        Set(words(stream.description).filter { $0.allSatisfy(\.isLetter) })
    }

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

    /// A full Blu-ray disc (BDMV folder, ISO, BD25/50) rather than an encode or remux.
    /// The debrid service serves the disc's main .m2ts, tens of GB that often start
    /// slowly, so the player waits longer before calling it dead. A false positive
    /// only means a longer wait.
    static func isDiscRelease(_ stream: StremioPlayableStream) -> Bool {
        // Not the description when there is a file name: aggregators write "AVC" there for every release.
        let parts = stream.behaviorHints?.filename.map { [$0] }
            ?? [stream.name, stream.title, stream.description].compactMap { $0 }
        return isDiscRelease(text: parts.joined(separator: "\n"))
    }

    static func isDiscRelease(text: String) -> Bool {
        // "_" counts as a word character for \b, and release names use it as a separator.
        let text = text.replacingOccurrences(of: "_", with: " ")
        func matches(_ pattern: String) -> Bool {
            text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        // A Matroska or MP4 file is an encode or remux, whatever its name says.
        if matches(#"\.(mkv|mp4|avi|m4v|webm)\s*$"#) { return false }
        if matches(#"\b(BDMV|BR-?DISK|BD(25|50|66|100))\b|\.(iso|m2ts)\b|\bISO\b"#) { return true }
        if matches(#"\bCOMPLETE[ ._-]+(UHD[ ._-]+)?BLU-?RAY\b|\bBlu-?ray[ ._-]+dis[ck]\b|\bFull[ ._-]+Blu-?ray\b"#) { return true }
        // "1080p.BluRay.AVC.TrueHD-FGT": the disc's own codec named, no encoder.
        return matches(#"\bBlu-?ray\b"#)
            && matches(#"\b(AVC|VC-?1|MPEG-?2|MVC)\b"#)
            && !matches(#"\b(x26[45]|h\.?26[45]|REMUX|BDRip|BRRip|WEB-?DL|WEBRip)\b"#)
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
    /// apply. Streams whose URL is in `excludingURLs` are never returned. With
    /// `followAddonOrder`, once the addon in use has nothing, the next addon in order wins.
    static func bestMatch(
        for reference: StremioPlayableStream?,
        in results: [StremioAddonStreamResult],
        excludingURLs: Set<String> = [],
        tiers: MatchTiers = .all,
        followAddonOrder: Bool = UserDefaults.standard.stremioPlayAction == .addonOrder
    ) -> (stream: StremioPlayableStream, tier: MatchTier)? {
        let candidates = followAddonOrder ? results.flatMap(listedPlayable) : rankedPlayable(in: results)
        let ranked = candidates.filter { !excludingURLs.contains($0.url ?? "") }
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
        for (tier, matches) in checks where tiers.contains(tier.option) && !(followAddonOrder && tier == .quality) {
            let matching = ranked.filter(matches)
            if let stream = tier == .bestRanked ? matching.first : closest(to: reference, in: matching) {
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

        /// The addon in use supplied it, so no other addon can do better.
        var isSameAddon: Bool {
            self == .bingeGroup || self == .addonAndQuality || self == .addon
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
        /// Next episode stays on the source in use. Many addons send no binge group,
        /// so same addon and resolution have to count too.
        static let nextEpisode: MatchTiers = .all
    }
}
