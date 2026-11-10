//
//  LiveTVLineupBuilder.swift
//  FlixorMac
//
//  Personal build only (FLIXOR_LIVE_TV). A rule-for-rule port of xtream-web's
//  curated lineup: curation.ts (cleanName, genreFor, curate), feed-evidence.ts
//  (premiumName), local-stations.ts, parity.ts (matchLineup),
//  indian-lineup.ts and stream-sources.ts (attachSources, nextSource).
//  Keep it in step with those files; the comparison harness checks the output
//  against xtream-web on the same catalog snapshot.
//

#if FLIXOR_LIVE_TV
import Foundation

/// JavaScript RegExp semantics on top of NSRegularExpression: `\b` is the
/// ASCII word boundary JS uses, and `replace` without `global` replaces only
/// the first match.
struct JSRegex {
    private static var cache: [String: NSRegularExpression] = [:]
    private static let lock = NSLock()
    private static let asciiBoundary = "(?:(?<=[A-Za-z0-9_])(?![A-Za-z0-9_])|(?<![A-Za-z0-9_])(?=[A-Za-z0-9_]))"

    let regex: NSRegularExpression

    init(_ pattern: String, ignoreCase: Bool = false) {
        let key = (ignoreCase ? "i:" : "s:") + pattern
        JSRegex.lock.lock(); defer { JSRegex.lock.unlock() }
        if let cached = JSRegex.cache[key] { regex = cached; return }
        let translated = pattern.replacingOccurrences(of: "\\b", with: JSRegex.asciiBoundary)
        // Patterns are fixed literals; a bad one is a programming error.
        regex = try! NSRegularExpression(pattern: translated, options: ignoreCase ? [.caseInsensitive] : [])
        JSRegex.cache[key] = regex
    }

    func test(_ s: String) -> Bool {
        regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    func replace(_ s: String, with template: String, global: Bool = false) -> String {
        let range = NSRange(s.startIndex..., in: s)
        if global {
            return regex.stringByReplacingMatches(in: s, range: range, withTemplate: template)
        }
        guard let match = regex.firstMatch(in: s, range: range), let r = Range(match.range, in: s) else { return s }
        return s.replacingCharacters(in: r, with: regex.replacementString(for: match, in: s, offset: 0, template: template))
    }
}

/// JavaScript `String.prototype.trim` / `toUpperCase` / `localeCompare` equivalents.
enum JSString {
    static func trim(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
    static func upper(_ s: String) -> String { s.uppercased(with: Locale(identifier: "en_US_POSIX")) }
    private static let collationLocale = Locale(identifier: "en")
    static func localeCompare(_ a: String, _ b: String) -> Int {
        switch a.compare(b, options: [], range: nil, locale: collationLocale) {
        case .orderedAscending: return -1
        case .orderedDescending: return 1
        case .orderedSame: return 0
        }
    }
}

extension Array {
    /// Array.prototype.sort is stable; Swift's sort is not guaranteed to be.
    func jsStableSorted(_ compare: (Element, Element) -> Int) -> [Element] {
        enumerated().sorted { lhs, rhs in
            let c = compare(lhs.element, rhs.element)
            return c != 0 ? c < 0 : lhs.offset < rhs.offset
        }.map(\.element)
    }
}

struct LiveTVLineupBuilder {
    let rules: CuratedLineupRules
    private let logoIndex: [String: String]

    init(rules: CuratedLineupRules) {
        self.rules = rules
        var index: [String: String] = [:]
        for pair in rules.logos ?? [] where pair.count == 2 { index[Self.key(pair[0])] = pair[1] }
        logoIndex = index
    }

    // MARK: logos.ts

    func channelLogo(_ name: String) -> String? {
        let normalized = Self.key(name)
        if let path = logoIndex[normalized] { return path }
        return logoIndex[Self.key(rules.logoAliases?[normalized] ?? "")]
    }

    // MARK: curation.ts

    static func cleanName(_ raw: String) -> String {
        var s = JSRegex("^(?:US|AT&T|PRIME|TUBI|TV|RK)\\s*[:|]\\s*", ignoreCase: true).replace(raw, with: "")
        s = JSRegex("[ᴿᴬᵂᴴᴰᵁ⁶⁰ᶠᵖˢᵉᵛᶜ⁴ᴷ]+").replace(s, with: "", global: true)
        s = JSRegex("\\s*\\b(?:FHD|UHD|HD|SD|4K|8K|RAW|HEVC|H265|H264)\\b\\s*", ignoreCase: true).replace(s, with: " ", global: true)
        s = JSRegex("\\s+").replace(s, with: " ", global: true)
        return JSString.trim(s)
    }

    static func genreFor(category: String, name: String) -> String {
        if JSRegex("^(HSN|QVC)\\b", ignoreCase: true).test(name) { return "Shows" }
        if JSRegex("SPORT|ESPN|NFL|NBA|MLB|NHL|GOLF|TENNIS|FS[12]|ACC NETWORK|SEC NETWORK|NBC SN|PICKLEBALL", ignoreCase: true).test(name) { return "Sports" }
        if JSRegex("NEWS", ignoreCase: true).test(category) { return "News" }
        if JSRegex("SPORT|ESPN|NFL|NBA|MLB|NHL|GOLF|TENNIS|FS[12]|ACC NETWORK|SEC NETWORK", ignoreCase: true).test(category + " " + name) { return "Sports" }
        if JSRegex("MOVIE", ignoreCase: true).test(category) || JSRegex("^(HBO|CINEMAX|SHOWTIME|STARZ|EPIX|MGM)", ignoreCase: true).test(name) { return "Movies" }
        if JSRegex("KIDS|CARTOON|FAMILY", ignoreCase: true).test(category) { return "Family" }
        if JSRegex("US\\| (?:NBC|ABC|CBS|FOX|CW|MIAMI)\\b").test(category) { return "Local" }
        return "Shows"
    }

    // MARK: feed-evidence.ts

    static func premiumName(_ raw: String) -> String {
        var s = raw
        s = JSRegex("^HBO 2\\b", ignoreCase: true).replace(s, with: "HBO Hits")
        s = JSRegex("^HBO SIGNATURE\\b", ignoreCase: true).replace(s, with: "HBO Drama")
        s = JSRegex("^HBO ZONE\\b", ignoreCase: true).replace(s, with: "HBO Movies")
        s = JSRegex("^(?:CINEMAX )?MOREMAX\\b", ignoreCase: true).replace(s, with: "Cinemax Hits")
        s = JSRegex("\\s+HDAR$", ignoreCase: true).replace(s, with: "")
        s = JSRegex("^CINEMAX 5 STAR ?MAX\\b", ignoreCase: true).replace(s, with: "Cinemax Classics")
        s = JSRegex("^5STARMAX\\b", ignoreCase: true).replace(s, with: "Cinemax Classics")
        s = JSRegex("^ACTIONMAX\\b", ignoreCase: true).replace(s, with: "Cinemax Action")
        s = JSRegex("^STARZ BLACK\\b", ignoreCase: true).replace(s, with: "STARZ in Black")
        s = JSRegex("FAMILYZONE", ignoreCase: true).replace(s, with: "Family Zone")
        return s
    }

    // MARK: local-stations.ts

    func stationLocation(_ name: String) -> StationLocation? {
        rules.stations.first { JSRegex("\\b\(NSRegularExpression.escapedPattern(for: $0.callsign))\\b", ignoreCase: true).test(name) }
    }

    func curate(raw: [XtreamRawStream], categories: [XtreamRawCategory]) -> [LiveChannel] {
        var us: [String: String] = [:]
        for c in categories where JSRegex("^US\\s*\\|", ignoreCase: true).test(c.categoryName) {
            us[c.categoryId] = c.categoryName
        }
        let eligible = raw.filter { c in
            us[c.categoryId] != nil
                && !JSRegex("^\\s*#").test(c.name)
                && c.adultFlag != 1
                && JSRegex("^\\d+$").test(c.streamId)
        }
        var names: [String: Int] = [:]
        for c in eligible { names[Self.cleanName(c.name), default: 0] += 1 }

        let channels: [LiveChannel] = eligible.map { c in
            let category = us[c.categoryId]!
            let evidence = rules.feedEvidence[c.streamId]
            let name = (evidence?.name).flatMap { $0.isEmpty ? nil : $0 } ?? Self.premiumName(Self.cleanName(c.name))
            let location = stationLocation(name) ?? stationLocation(c.name)
            let feed: String
            if let zone = evidence?.zone, !zone.isEmpty {
                feed = "\(zone) (schedule + video match)"
            } else if JSRegex("\\bWEST\\b", ignoreCase: true).test(name) {
                feed = "West (provider label)"
            } else if JSRegex("\\bEAST\\b", ignoreCase: true).test(name) {
                feed = "East (provider label)"
            } else {
                feed = "Unverified"
            }
            return LiveChannel(
                id: c.streamId,
                name: name,
                originalName: c.name,
                category: Self.cleanName(JSRegex("^US\\|\\s*").replace(category, with: "")),
                categoryId: c.categoryId,
                genre: location != nil ? "Local" : Self.genreFor(category: category, name: name),
                epgId: c.epgChannelId ?? "",
                quality: JSRegex("4K|ᵁᴴᴰ").test(c.name) ? "4K" : JSRegex("HD|ᴴᴰ").test(c.name) ? "HD" : "",
                feed: feed,
                core: JSRegex("US\\| (ENTERTAINMENT|NEWS|MOVIES|KIDS|SPORT)\\s").test(category),
                location: location,
                evidence: evidence,
                variants: names[name] ?? 1,
                logoURL: c.streamIcon,
                logoPath: channelLogo(name) ?? "/api/image/\(c.streamId)\(evidence?.status == "schedule-match" ? "?identity=curated" : "")"
            )
        }
        func rank(_ c: LiveChannel) -> Double {
            let i = rules.priority.firstIndex(of: c.name) ?? -1
            return (c.core ? 0 : 10000) + Double(i < 0 ? 100 : i) + (c.quality == "HD" ? 0 : 0.1)
        }
        return channels.jsStableSorted { a, b in
            let r = rank(a) - rank(b)
            if r != 0 { return r < 0 ? -1 : 1 }
            let n = JSString.localeCompare(a.name, b.name)
            if n != 0 { return n }
            return JSString.localeCompare(a.id, b.id)
        }
    }

    // MARK: parity.ts

    static func key(_ s: String) -> String {
        JSRegex("[^A-Z0-9]").replace(JSString.upper(s), with: "", global: true)
    }

    func matchLineup(_ channels: [LiveChannel]) -> [LiveChannel] {
        let keyed = channels.map { (channel: $0, key: Self.key($0.name)) }
        var lineup: [LiveChannel] = []
        for name in rules.referenceLineup {
            let nameKey = Self.key(name)
            let exact = keyed.filter { $0.key == nameKey }.map(\.channel)
            let aliasKeys = Set((rules.aliases[name] ?? []).map(Self.key))
            let alternative = keyed.filter { aliasKeys.contains($0.key) }.map(\.channel)
            var local: [LiveChannel] = []
            if let callsign = rules.callsigns[name], !callsign.isEmpty {
                let re = JSRegex("\\b" + callsign + "\\b", ignoreCase: true)
                local = channels.filter { re.test($0.name) }
            }
            var seen = Set<String>()
            var candidates: [LiveChannel] = []
            for c in exact + alternative + local where seen.insert(c.id).inserted { candidates.append(c) }
            candidates = candidates.jsStableSorted { a, b in
                let core = (b.core ? 1 : 0) - (a.core ? 1 : 0)
                if core != 0 { return core }
                return (b.quality == "HD" ? 1 : 0) - (a.quality == "HD" ? 1 : 0)
            }
            if let first = candidates.first, var channel = channels.first(where: { $0.id == first.id }) {
                channel.referenceName = name
                channel.logoPath = channelLogo(name) ?? channel.logoPath
                lineup.append(channel)
            }
        }

        let premiumPattern = JSRegex("^(HBO|STARZ|SHOWTIME|SHOXBET|CINEMAX|MOREMAX|MOVIEMAX|OUTERMAX|ACTIONMAX|THRILLERMAX|5 STARMAX|PARAMOUNT\\+ WITH SHOWTIME)\\b", ignoreCase: true)
        let premium = channels.filter { premiumPattern.test($0.name) }.jsStableSorted { a, b in
            let s = (b.evidence?.status == "schedule-match" ? 1 : 0) - (a.evidence?.status == "schedule-match" ? 1 : 0)
            if s != 0 { return s }
            return (b.core ? 1 : 0) - (a.core ? 1 : 0)
        }
        let coastSuffix = JSRegex("\\s+(East|West)$", ignoreCase: true)
        let verifiedBases = Set(premium.filter { $0.evidence?.status == "schedule-match" }
            .map { Self.key(coastSuffix.replace($0.name, with: "")) })
        let coastWord = JSRegex("\\b(East|West)\\b", ignoreCase: true)
        let excluded = JSRegex("HBO (?:MAX|BOXING)|ORIGINAL|THRILLERMAX|MOVIEMAX|OUTERMAX", ignoreCase: true)
        var groupedKeys = Set<String>()
        for c in premium {
            // Keep unidentified duplicates in the audit without assigning them a coast.
            if c.evidence == nil && !coastWord.test(c.name) && verifiedBases.contains(Self.key(c.name)) { continue }
            if c.evidence?.status == "mismatch" || excluded.test(c.name) { continue }
            if groupedKeys.insert(Self.key(c.name)).inserted {
                var p = c
                p.premium = true
                lineup.append(p)
            }
        }
        return lineup
    }

    // MARK: indian-lineup.ts

    func indianLineup(raw: [XtreamRawStream]) -> [LiveChannel] {
        var byId: [String: XtreamRawStream] = [:]
        for c in raw { byId[c.streamId] = c }
        return rules.indianFeeds.compactMap { o in
            guard let c = byId[o.id], c.adultFlag != 1 else { return nil }
            let genreLabel = o.genre == "Movies" ? "Movies" : o.genre == "Shows" ? "Entertainment" : o.genre == "Family" ? "Kids" : o.genre
            let verified = o.regionVerified ?? false
            return LiveChannel(
                id: o.id,
                name: o.name,
                originalName: c.name,
                category: "India · \(o.language) · \(genreLabel)",
                categoryId: c.categoryId,
                genre: o.genre,
                epgId: c.epgChannelId ?? "",
                quality: o.quality,
                feed: verified ? "India · video / regional evidence observed" : "Regional edition unconfirmed",
                core: true,
                market: .india,
                language: o.language,
                evidence: FeedEvidence(
                    name: o.name, status: "video-match",
                    note: "\(o.note) Identity checked against sampled video; not an official schedule match. Language is the channel category, not a verified audio-track guarantee.",
                    checkedAt: o.checkedAt),
                variants: 1,
                logoURL: c.streamIcon,
                logoPath: "/api/image/\(o.id)"
            )
        }
    }

    // MARK: stream-sources.ts

    func compatibleSources(_ channel: LiveChannel, available: Set<String>) -> [VerifiedSource] {
        let entries = rules.verifiedSources
        guard let primary = entries.first(where: { $0.channelId == channel.id }) ?? entries.first(where: { $0.id == channel.id }) else { return [] }
        return entries.filter { s in
            (primary.channelId == nil || primary.channelId == "" || s.channelId == primary.channelId)
                && available.contains(s.id)
                && s.channel == primary.channel && s.region == primary.region
                && s.language == primary.language && s.coast == primary.coast
        }.jsStableSorted { a, b in
            (b.id == channel.id ? 1 : 0) - (a.id == channel.id ? 1 : 0)
        }
    }

    func attachSources(_ channels: [LiveChannel], available: Set<String>) -> [LiveChannel] {
        channels.map { c in
            var copy = c
            copy.sources = compatibleSources(c, available: available)
            copy.variants = copy.sources.isEmpty ? 1 : copy.sources.count
            return copy
        }
    }

    static func nextSource(_ ids: [String], failed: Set<String>) -> String? {
        ids.first { !failed.contains($0) }
    }

    // MARK: provider.ts getCatalog (lineup part)

    /// `attachSources([...us.lineup, ...india], available)`.
    func lineup(raw: [XtreamRawStream], categories: [XtreamRawCategory]) -> [LiveChannel] {
        let curated = curate(raw: raw, categories: categories)
        let india = indianLineup(raw: raw)
        let us = matchLineup(curated)
        let available = Set(raw.map(\.streamId))
        return attachSources(us + india, available: available)
    }
}
#endif
