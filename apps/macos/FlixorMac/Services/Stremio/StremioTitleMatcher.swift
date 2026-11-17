//
//  StremioTitleMatcher.swift
//  FlixorMac
//
//  Leaves out addon results whose file name is for another film or show: an
//  aggregator can return "Dune Part One" for Ramayana, or "Wonder Woman 1984"
//  for Wonder Woman. A result is kept when its file name contains one of the
//  title's names (TMDB title, original title, alternative titles, translations)
//  as whole words, and any year in it is within one of the release year. For an
//  episode, an SxxEyy in the name must be the episode asked for. A result with
//  no file name can't be checked and is kept.
//

import Foundation
import FlixorKit

struct StremioTitleMatcher: Sendable {
    enum Verdict { case match, unverified, mismatch }

    /// Normalised names, each " word word ", longest first.
    private let names: [String]
    private let squashedNames: [String]
    private let year: Int?
    private let season: Int?
    private let episode: Int?

    init(names: [String], year: Int?, season: Int? = nil, episode: Int? = nil) {
        let normalised = names.map(Self.normalise).filter { $0.count > 2 }
        var seen = Set<String>()
        self.names = normalised.filter { seen.insert($0).inserted }.sorted { $0.count > $1.count }
        self.squashedNames = self.names.map { $0.replacingOccurrences(of: " ", with: "") }.filter { $0.count >= 6 }
        self.year = year
        self.season = season
        self.episode = episode
    }

    func verdict(for stream: StremioPlayableStream) -> Verdict {
        guard let filename = stream.behaviorHints?.filename ?? Self.filenameLine(in: stream), !filename.isEmpty else {
            return .unverified
        }
        return verdict(filename: filename)
    }

    func verdict(filename: String) -> Verdict {
        let text = Self.normalise(Self.strippingSiteTags(filename))
        if !wrongEpisode(filename),
           let name = names.first(where: { text.contains($0) }) {
            // Years that are part of the title ("Blade Runner 2049") don't count.
            let rest = text.replacingOccurrences(of: name, with: " ")
            return yearFits(rest) ? .match : .mismatch
        }
        // "emd-wonderwoman.2160p.mkv": the name run together, with no year to check.
        let squashed = text.replacingOccurrences(of: " ", with: "")
        if !wrongEpisode(filename), Self.years(in: text).isEmpty,
           squashedNames.contains(where: { squashed.contains($0) }) {
            return .match
        }
        return .mismatch
    }

    /// Splits addon results into what matches (or can't be checked) and what is for another title.
    func split(_ results: [StremioAddonStreamResult]) -> (kept: [StremioAddonStreamResult], hidden: [StremioPlayableStream]) {
        var hidden: [StremioPlayableStream] = []
        let kept = results.map { result -> StremioAddonStreamResult in
            let streams = result.streams.filter { stream in
                guard stream.playable, verdict(for: stream) == .mismatch else { return true }
                hidden.append(stream)
                return false
            }
            return StremioAddonStreamResult(addonId: result.addonId, addonName: result.addonName,
                                            installationId: result.installationId, streams: streams, error: result.error)
        }
        return (kept, hidden)
    }

    // MARK: - Rules

    private func yearFits(_ text: String) -> Bool {
        guard let year, season == nil else { return true }
        let found = Self.years(in: text)
        return found.isEmpty || found.contains { abs($0 - year) <= 1 }
    }

    private func wrongEpisode(_ filename: String) -> Bool {
        guard let season, let episode else { return false }
        let pattern = #"(?i)\bS(\d{1,2})[ ._-]?E(\d{1,3})\b|\b(\d{1,2})x(\d{2,3})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: filename, range: NSRange(filename.startIndex..., in: filename)) else { return false }
        func group(_ i: Int) -> Int? {
            Range(match.range(at: i), in: filename).flatMap { Int(filename[$0]) }
        }
        let s = group(1) ?? group(3), e = group(2) ?? group(4)
        guard let s, let e else { return false }
        return s != season || e != episode
    }

    private static func years(in text: String) -> [Int] {
        text.split(separator: " ").compactMap { word in
            guard word.count == 4, let value = Int(word), (1900...2099).contains(value) else { return nil }
            return value
        }
    }

    // MARK: - Text

    /// Lowercase, accents folded, "&" as "and", anything but letters and digits as one space,
    /// padded with spaces so " name " only matches whole words.
    static func normalise(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
            .replacingOccurrences(of: "&", with: " and ")
        var out = ""
        var lastWasSpace = true
        for character in folded {
            if character.isLetter || character.isNumber {
                out.append(character)
                lastWasSpace = false
            } else if !lastWasSpace {
                out.append(" ")
                lastWasSpace = true
            }
        }
        return " " + out.trimmingCharacters(in: .whitespaces) + " "
    }

    /// Drops "www.site.tld - " in front and [bracketed] / {braced} tags.
    private static func strippingSiteTags(_ filename: String) -> String {
        filename
            .replacingOccurrences(of: #"^\s*(www\.)?[A-Za-z0-9-]+\.[A-Za-z]{2,10}\s+-\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[[^\]]*\]|\{[^}]*\}"#, with: " ", options: .regularExpression)
    }

    /// A line of the stream's text that looks like a file name, for addons that send no hint.
    private static func filenameLine(in stream: StremioPlayableStream) -> String? {
        [stream.title, stream.description].compactMap { $0 }
            .flatMap { $0.split(separator: "\n") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.range(of: #"\.(mkv|mp4|avi|m4v|ts|m2ts|iso|webm)$"#, options: [.regularExpression, .caseInsensitive]) != nil }
    }
}

/// Builds and caches title matchers from TMDB, keyed by title.
actor StremioTitleMatcherStore {
    static let shared = StremioTitleMatcherStore()

    private var cache: [String: StremioTitleMatcher] = [:]

    /// A matcher for the title `identity` asks for, or nil when its names can't be
    /// found (then nothing is left out). `fallbackTitle` is used if TMDB has nothing.
    func matcher(for identity: StremioContentIdentity, fallbackTitle: String?) async -> StremioTitleMatcher? {
        let isSeries = identity.requestType == StremioRequestType.series.rawValue
        let key = "\(identity.requestType):\(identity.baseId)"
        let base: StremioTitleMatcher?
        if let cached = cache[key] {
            base = cached
        } else {
            base = await lookUp(identity: identity, isSeries: isSeries, fallbackTitle: fallbackTitle)
            if let base { cache[key] = base }
        }
        guard let base, isSeries else { return base }
        return base.forEpisode(season: identity.seasonNumber, episode: identity.episodeNumber)
    }

    private func lookUp(identity: StremioContentIdentity, isSeries: Bool, fallbackTitle: String?) async -> StremioTitleMatcher? {
        let tmdb = await FlixorCore.shared.tmdb
        let mediaType = isSeries ? "tv" : "movie"
        var tmdbId = identity.tmdbId
        if tmdbId == nil, let imdb = identity.imdbId ?? (identity.baseId.hasPrefix("tt") ? identity.baseId : nil),
           let found = try? await tmdb.findByExternalId(imdb) {
            tmdbId = (isSeries ? found.tvResults.first : found.movieResults.first)?.id
        }
        if let tmdbId, let names = try? await tmdb.getTitleNames(mediaType: mediaType, id: tmdbId), !names.allNames.isEmpty {
            // Shows span years; only movies check the year.
            return StremioTitleMatcher(names: names.allNames, year: isSeries ? nil : names.year)
        }
        guard let fallbackTitle, !fallbackTitle.isEmpty else { return nil }
        return StremioTitleMatcher(names: [fallbackTitle], year: nil)
    }
}

extension StremioTitleMatcher {
    fileprivate init(copying other: StremioTitleMatcher, season: Int?, episode: Int?) {
        self.names = other.names
        self.squashedNames = other.squashedNames
        self.year = other.year
        self.season = season
        self.episode = episode
    }

    func forEpisode(season: Int?, episode: Int?) -> StremioTitleMatcher {
        StremioTitleMatcher(copying: self, season: season, episode: episode)
    }
}
