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
    /// The include pattern used up its matching time, so the stream can't be judged.
    case timedOut

    var isMatch: Bool { self == .match }
}

/// Total time a regex include pattern may spend matching. A pattern that backtracks
/// badly can otherwise run for hours, and NSRegularExpression has no timeout.
final class StreamRuleTimeBudget: @unchecked Sendable {
    private let lock = NSLock()
    private var remainingSeconds: TimeInterval
    private var exhausted = false

    init(seconds: TimeInterval) {
        remainingSeconds = seconds
    }

    var remaining: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return exhausted ? 0 : remainingSeconds
    }

    var isExhausted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return exhausted
    }

    func spend(_ seconds: TimeInterval, overran: Bool) {
        lock.lock()
        defer { lock.unlock() }
        remainingSeconds -= seconds
        if overran || remainingSeconds <= 0 { exhausted = true }
    }
}

/// `StreamSelectionRules` compiled for matching.
struct StreamRuleMatcher {
    enum RuleError: Error {
        case invalidIncludePattern
        /// A repeat inside a repeat, like `(a+)+`: the classic pattern that hangs.
        case unsafeIncludePattern
        case invalidExcludeWords
    }

    let rules: StreamSelectionRules
    private let include: NSRegularExpression?
    private let exclude: NSRegularExpression?

    /// Longest text a rule is run against, so a costly pattern stays cheap on long descriptions.
    private static let maxTextLength = 1_000

    /// Spent by regex include patterns only; word lists are escaped and always fast.
    let timeBudget: StreamRuleTimeBudget

    init(rules: StreamSelectionRules, matchingBudget: TimeInterval = 1) throws {
        self.rules = rules
        timeBudget = StreamRuleTimeBudget(seconds: matchingBudget)

        if rules.includeIsRegex {
            let pattern = rules.include.trimmingCharacters(in: .whitespacesAndNewlines)
            if pattern.isEmpty {
                include = nil
            } else {
                guard !Self.hasNestedRepeat(pattern) else { throw RuleError.unsafeIncludePattern }
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

    /// True when a group containing an open-ended repeat is itself repeated. Can flag
    /// a few harmless patterns; the time budget covers whatever it misses.
    static func hasNestedRepeat(_ pattern: String) -> Bool {
        let chars = Array(pattern)
        var groupHasRepeat: [Bool] = []
        var closedGroupHadRepeat = false
        var inCharacterClass = false
        var index = 0

        while index < chars.count {
            let char = chars[index]
            index += 1

            if char == "\\" {
                index += 1
                closedGroupHadRepeat = false
                continue
            }
            if inCharacterClass {
                if char == "]" { inCharacterClass = false }
                continue
            }

            var isRepeat = char == "*" || char == "+"
            if char == "{", let close = chars[index...].firstIndex(of: "}") {
                // {3} repeats a fixed number of times; {3,} and {3,9} vary.
                isRepeat = chars[index..<close].contains(",")
                index = close + 1
                if !isRepeat { continue }
            }

            if isRepeat {
                if closedGroupHadRepeat { return true }
                if !groupHasRepeat.isEmpty { groupHasRepeat[groupHasRepeat.count - 1] = true }
                closedGroupHadRepeat = false
                continue
            }

            closedGroupHadRepeat = false
            switch char {
            case "[":
                inCharacterClass = true
            case "(":
                groupHasRepeat.append(false)
            case ")":
                let hadRepeat = groupHasRepeat.popLast() ?? false
                closedGroupHadRepeat = hadRepeat
                if hadRepeat, !groupHasRepeat.isEmpty { groupHasRepeat[groupHasRepeat.count - 1] = true }
            default:
                break
            }
        }
        return false
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
        if let include {
            guard let found = includeMatches(include, in: text, range: range) else { return .timedOut }
            if !found { return .missingInclude }
        }
        return .match
    }

    /// Nil when the time budget ran out. The progress callback is the only way to
    /// stop a running match, and it does fire during backtracking.
    private func includeMatches(_ regex: NSRegularExpression, in text: String, range: NSRange) -> Bool? {
        guard rules.includeIsRegex else { return regex.firstMatch(in: text, range: range) != nil }

        let allowed = timeBudget.remaining
        guard allowed > 0 else { return nil }
        let start = Date()
        let deadline = start.addingTimeInterval(allowed)
        var found = false
        var overran = false
        regex.enumerateMatches(in: text, options: [.reportProgress], range: range) { match, _, stop in
            if match != nil {
                found = true
                stop.pointee = true
            } else if Date() >= deadline {
                overran = true
                stop.pointee = true
            }
        }
        timeBudget.spend(Date().timeIntervalSince(start), overran: overran)
        return overran ? nil : found
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

    /// The include pattern took too long; automatic selection should give up.
    var rulesTimedOut: Bool { matcher?.timeBudget.isExhausted ?? false }

    /// `pick`, off the caller's actor so a costly pattern can't stall it.
    func pickOffActor(in results: [StremioAddonStreamResult]) async -> StremioPlayableStream? {
        await Task.detached(priority: .userInitiated) { self.pick(in: results) }.value
    }

    /// True once there's no reason to wait for more addons. Also runs off the caller's actor.
    func shouldStopWaiting(in results: [StremioAddonStreamResult], pending: Set<String>) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            self.earlyPick(in: results, pending: pending) != nil || self.rulesTimedOut
        }.value
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
