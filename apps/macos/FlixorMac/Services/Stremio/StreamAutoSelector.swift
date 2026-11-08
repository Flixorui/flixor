//
//  StreamAutoSelector.swift
//  FlixorMac
//
//  Decides which addon stream to start automatically when Play is pressed.
//  Only streams the app can play are ever candidates (see `rankedPlayable`),
//  so torrents, NZBs and other unsupported types are never picked.
//

import Foundation

/// Why a stream did or did not pass the user's rules.
enum StreamRuleVerdict: Equatable {
    case match
    case missingInclude
    case excluded(String)
    case aboveResolutionLimit

    var isMatch: Bool { self == .match }
}

/// `StreamSelectionRules` compiled for matching.
struct StreamRuleMatcher {
    enum RuleError: Error {
        case invalidIncludePattern
        case invalidExcludeWords
    }

    let rules: StreamSelectionRules
    private let include: NSRegularExpression?
    private let exclude: NSRegularExpression?

    /// Longest text a rule is run against, so a costly pattern stays cheap on long descriptions.
    private static let maxTextLength = 1_000

    init(rules: StreamSelectionRules) throws {
        self.rules = rules

        if rules.includeIsRegex {
            let pattern = rules.include.trimmingCharacters(in: .whitespacesAndNewlines)
            if pattern.isEmpty {
                include = nil
            } else {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                    throw RuleError.invalidIncludePattern
                }
                include = regex
            }
        } else {
            include = try Self.wordsRegex(rules.include, error: .invalidIncludePattern)
        }
        exclude = try Self.wordsRegex(rules.exclude, error: .invalidExcludeWords)
    }

    /// Whole-word, case-insensitive match for `|` or `,` separated words. Letters and
    /// digits count as word characters, so "TS" matches "HD-TS" but not "HDTS" or "DTS".
    private static func wordsRegex(_ text: String, error: RuleError) throws -> NSRegularExpression? {
        let words = text
            .split(whereSeparator: { "|,\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }

        let alternatives = words.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        let pattern = "(?<![\\p{L}\\p{N}])(?:\(alternatives))(?![\\p{L}\\p{N}])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            throw error
        }
        return regex
    }

    func verdict(for stream: StremioPlayableStream) -> StreamRuleVerdict {
        verdict(text: Self.searchableText(for: stream), resolution: StremioSourceRanking.resolutionBucket(stream))
    }

    /// An unknown resolution passes the limit; ranking already puts it last.
    func verdict(text: String, resolution: Int?) -> StreamRuleVerdict {
        let text = String(text.prefix(Self.maxTextLength))
        let range = NSRange(text.startIndex..., in: text)

        if let exclude, let found = exclude.firstMatch(in: text, range: range),
           let foundRange = Range(found.range, in: text) {
            return .excluded(String(text[foundRange]))
        }
        if let limit = rules.maxResolution, let resolution, resolution > limit {
            return .aboveResolutionLimit
        }
        if let include, include.firstMatch(in: text, range: range) == nil {
            return .missingInclude
        }
        return .match
    }

    /// What rules are matched against. The URL is left out on purpose: tokens in it,
    /// or a `.ts` segment path, would trip words like "TS".
    private static func searchableText(for stream: StremioPlayableStream) -> String {
        [stream.addonName, stream.name, stream.title, stream.description, stream.quality, stream.behaviorHints?.filename]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}

/// Picks a stream from addon results. Pass `rules` for "Match my rules", nil for "Play best source".
struct StreamAutoSelector {
    private let matcher: StreamRuleMatcher?

    init(rules: StreamSelectionRules?) throws {
        matcher = try rules.map { try StreamRuleMatcher(rules: $0) }
    }

    /// The stream to play given everything that has arrived.
    func pick(in results: [StremioAddonStreamResult]) -> StremioPlayableStream? {
        let candidates = candidates(in: results)
        return preferredCandidate(in: candidates) ?? candidates.first
    }

    /// A stream good enough to stop waiting on the addons in `pending`, or nil to keep waiting.
    /// Agrees with `pick` on the same results. Rules: any match counts, once the preferred
    /// addon has answered. Best source: only a cached or debrid 4K stream, which the
    /// remaining addons could not meaningfully beat.
    func earlyPick(in results: [StremioAddonStreamResult], pending: Set<String>) -> StremioPlayableStream? {
        let candidates = candidates(in: results)
        guard let matcher else {
            guard let best = candidates.first, Self.isTopTier(best) else { return nil }
            return best
        }
        if let preferred = preferredCandidate(in: candidates) { return preferred }
        if let addon = matcher.rules.preferredAddonId, pending.contains(addon) { return nil }
        return candidates.first
    }

    /// Playable streams that pass the rules, best first.
    private func candidates(in results: [StremioAddonStreamResult]) -> [StremioPlayableStream] {
        let ranked = StremioSourceRanking.rankedPlayable(in: results)
        guard let matcher else { return ranked }
        return ranked.filter { matcher.verdict(for: $0).isMatch }
    }

    private func preferredCandidate(in candidates: [StremioPlayableStream]) -> StremioPlayableStream? {
        guard let addon = matcher?.rules.preferredAddonId else { return nil }
        return candidates.first { $0.addonInstallationId == addon }
    }

    private static func isTopTier(_ stream: StremioPlayableStream) -> Bool {
        (stream.behaviorHints?.cached == true || stream.isDebrid == true)
            && StremioSourceRanking.resolutionBucket(stream) == 2160
    }
}
