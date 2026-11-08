//
//  LanguageMatcher.swift
//  FlixorMac
//
//  Matches audio/subtitle tracks against a preferred language, understanding
//  ISO 639-1/-2 codes (en, eng; de, ger, deu), regional variants (pt-BR vs pt,
//  es-419 vs es, fr-CA) and Chinese scripts (zh-Hans vs zh-Hant), including
//  hints in track titles ("Portuguese (Brazil)", "Latino", "Traditional").
//

import Foundation

/// A normalized language: ISO 639-1 base (when known) plus an optional variant
/// group ("br", "pt", "419", "es", "hans", "hant", "ca", or a lowercased region).
struct LanguageTag: Equatable, Hashable {
    let base: String
    let variant: String?

    /// BCP-47-ish identifier, e.g. "pt-BR", "es-419", "zh-Hans", "en".
    var identifier: String {
        guard let variant else { return base }
        switch variant {
        case "hans": return "\(base)-Hans"
        case "hant": return "\(base)-Hant"
        case "419": return "\(base)-419"
        default: return "\(base)-\(variant.uppercased())"
        }
    }
}

enum LanguageMatcher {
    // MARK: - Parsing

    /// Parses a language code ("pt-BR", "pt_br", "por", "pob", "es-419", "zh-Hant", "chi")
    /// into a normalized tag. Returns nil for empty/unknown placeholders ("und", "unknown").
    static func parse(_ code: String?) -> LanguageTag? {
        guard var raw = code?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !raw.isEmpty else {
            return nil
        }
        raw = raw.replacingOccurrences(of: "_", with: "-")
        if ["und", "unknown", "zxx", "mis", "mul", "none", "n/a"].contains(raw) { return nil }

        // Whole-code aliases that carry a variant (OpenSubtitles & common release tags)
        if let alias = variantAliases[raw] { return alias }

        let parts = raw.split(separator: "-").map(String.init)
        guard let first = parts.first, let base = normalizeBase(first) else { return nil }
        let variant = parts.dropFirst().lazy.compactMap { normalizeVariant($0, base: base) }.first
        return LanguageTag(base: base, variant: variant)
    }

    /// Tag for a track from its language code, falling back to / refined by its title.
    static func tag(lang: String?, title: String?) -> LanguageTag? {
        let titleText = title?.lowercased() ?? ""
        var tag = parse(lang)
        if tag == nil, !titleText.isEmpty {
            tag = baseFromLanguageName(in: titleText).map { LanguageTag(base: $0, variant: nil) }
        }
        guard let found = tag else { return nil }
        if found.variant == nil, let hinted = variantHint(in: titleText, base: found.base) {
            return LanguageTag(base: found.base, variant: hinted)
        }
        return found
    }

    // MARK: - Matching

    /// How well a track matches a preference (higher is better), nil when the
    /// languages differ.
    /// - 3: same variant, or neither side has one (or the track has the base's "home" variant)
    /// - 2: one side has no variant
    /// - 1: same language, different variant (pt-PT for a pt-BR preference)
    static func score(track: LanguageTag, preference: LanguageTag) -> Int? {
        guard track.base == preference.base else { return nil }
        switch (preference.variant, track.variant) {
        case let (p?, t?): return p == t ? 3 : 1
        case (_?, nil): return 2
        case (nil, nil): return 3
        case let (nil, t?): return t == homeVariant[track.base] ? 3 : 2
        }
    }

    /// Index of the best-matching item for `preference`, or nil when none matches.
    /// Ties keep the earlier item, except that forced (signs-only) items are only
    /// chosen when nothing else matches and "default"-flagged items win ties.
    static func bestMatch<T>(
        in items: [T],
        preference: String,
        lang: (T) -> String?,
        title: (T) -> String?,
        isForced: (T) -> Bool = { _ in false },
        isDefault: (T) -> Bool = { _ in false }
    ) -> Int? {
        guard let preferred = parse(preference) else { return nil }
        var best: (index: Int, rank: Int)?
        for (index, item) in items.enumerated() {
            guard let tag = tag(lang: lang(item), title: title(item)),
                  let score = score(track: tag, preference: preferred) else { continue }
            let rank = score * 4 + (isForced(item) ? 0 : 2) + (isDefault(item) ? 1 : 0)
            if best == nil || rank > best!.rank { best = (index, rank) }
        }
        return best?.index
    }

    /// True when `code` and `other` are the same language (variants ignored).
    static func sameLanguage(_ code: String?, _ other: String?) -> Bool {
        guard let a = parse(code), let b = parse(other) else { return false }
        return a.base == b.base
    }

    /// English display name for a code ("pt-BR" -> "Portuguese (Brazil)").
    static func displayName(for code: String) -> String {
        guard let tag = parse(code) else { return code }
        let english = Locale(identifier: "en_US")
        return english.localizedString(forIdentifier: tag.identifier.replacingOccurrences(of: "-", with: "_"))
            ?? english.localizedString(forLanguageCode: tag.base)
            ?? code
    }

    // MARK: - Normalization tables

    /// The variant that a plain code implies (plain "pt" usually means European Portuguese).
    private static let homeVariant: [String: String] = ["pt": "pt", "es": "es", "fr": "fr", "zh": "hans"]

    /// Codes that carry a variant on their own (OpenSubtitles and common release tags).
    private static let variantAliases: [String: LanguageTag] = [
        "pob": LanguageTag(base: "pt", variant: "br"), "pb": LanguageTag(base: "pt", variant: "br"),
        "ptbr": LanguageTag(base: "pt", variant: "br"),
        "chs": LanguageTag(base: "zh", variant: "hans"), "zhs": LanguageTag(base: "zh", variant: "hans"),
        "cht": LanguageTag(base: "zh", variant: "hant"), "zht": LanguageTag(base: "zh", variant: "hant"),
    ]

    /// ISO 639-2/B (bibliographic) and other codes Foundation may not map.
    private static let baseAliases: [String: String] = [
        "alb": "sq", "arm": "hy", "baq": "eu", "bur": "my", "chi": "zh", "cze": "cs", "dut": "nl",
        "fre": "fr", "geo": "ka", "ger": "de", "gre": "el", "ice": "is", "mac": "mk", "mao": "mi",
        "may": "ms", "per": "fa", "rum": "ro", "slo": "sk", "tib": "bo", "wel": "cy",
        "iw": "he", "in": "id", "ji": "yi", "jp": "ja", "gr": "el", "cn": "zh", "kr": "ko",
        "scc": "sr", "scr": "hr", "nob": "no", "nb": "no", "nno": "no", "nn": "no",
        "fil": "tl", "cmn": "zh", "yue": "zh", "spa": "es", "por": "pt",
    ]

    private static func normalizeBase(_ code: String) -> String? {
        if let alias = baseAliases[code] { return alias }
        guard code.count >= 2, code.count <= 3, code.allSatisfy(\.isLetter) else { return nil }
        if code.count == 2 { return code }
        if let alpha2 = Locale.LanguageCode(code).identifier(.alpha2) { return alpha2.lowercased() }
        return code
    }

    private static let latinAmericanRegions: Set<String> = [
        "419", "mx", "ar", "co", "cl", "pe", "ve", "us", "la", "lat", "latam", "uy", "py", "bo", "ec",
        "gt", "cu", "do", "hn", "ni", "pa", "pr", "sv", "cr",
    ]

    private static func normalizeVariant(_ part: String, base: String) -> String? {
        let p = part.lowercased()
        switch base {
        case "es":
            if latinAmericanRegions.contains(p) { return "419" }
            if p == "es" { return "es" }
        case "pt":
            if p == "br" { return "br" }
            if p == "pt" { return "pt" }
        case "zh":
            if ["hans", "cn", "sg", "chs", "my"].contains(p) { return "hans" }
            if ["hant", "tw", "hk", "mo", "cht"].contains(p) { return "hant" }
        default:
            break
        }
        // Generic region (fr-CA, en-GB) or script; ignore numeric/odd subtags
        if p.count == 2, p.allSatisfy(\.isLetter) { return p }
        return nil
    }

    private static func containsWord(_ text: String, _ word: String) -> Bool {
        text.range(of: "\\b\(NSRegularExpression.escapedPattern(for: word))\\b", options: .regularExpression) != nil
    }

    /// Variant hinted by a track title (e.g. "Spanish (Latin America)").
    private static func variantHint(in title: String, base: String) -> String? {
        guard !title.isEmpty else { return nil }
        switch base {
        case "pt":
            if title.contains("brazil") || title.contains("brasil") || containsWord(title, "br") || title.contains("pt-br") { return "br" }
            if title.contains("portugal") || title.contains("european") || title.contains("europeu") { return "pt" }
        case "es":
            if title.contains("latin") || title.contains("latam") || containsWord(title, "lat")
                || title.contains("mexic") || title.contains("américa") || title.contains("america") { return "419" }
            if title.contains("spain") || title.contains("españa") || title.contains("castil") || title.contains("european") { return "es" }
        case "zh":
            if title.contains("simplified") || title.contains("简") || containsWord(title, "chs") || containsWord(title, "gb") { return "hans" }
            if title.contains("traditional") || title.contains("繁") || containsWord(title, "cht") || title.contains("big5") { return "hant" }
        case "fr":
            if title.contains("canad") || title.contains("québ") || title.contains("quebec") { return "ca" }
            if title.contains("france") || title.contains("european") { return "fr" }
        default:
            break
        }
        return nil
    }

    /// Common languages whose English or native name may appear in a title without a code.
    private static let nameLookup: [(names: [String], base: String)] = [
        (["english"], "en"), (["spanish", "español", "espanol", "castellano", "latino"], "es"),
        (["portuguese", "português", "portugues"], "pt"), (["french", "français", "francais"], "fr"),
        (["german", "deutsch"], "de"), (["italian", "italiano"], "it"), (["japanese", "日本語"], "ja"),
        (["korean", "한국어"], "ko"), (["chinese", "mandarin", "cantonese", "中文"], "zh"),
        (["russian", "русский"], "ru"), (["arabic", "العربية"], "ar"), (["hindi", "हिन्दी"], "hi"),
        (["dutch", "nederlands"], "nl"), (["swedish", "svenska"], "sv"), (["norwegian", "norsk"], "no"),
        (["danish", "dansk"], "da"), (["finnish", "suomi"], "fi"), (["polish", "polski"], "pl"),
        (["turkish", "türkçe"], "tr"), (["hebrew", "עברית"], "he"), (["thai", "ไทย"], "th"),
        (["vietnamese", "tiếng việt"], "vi"), (["indonesian"], "id"), (["czech", "čeština"], "cs"),
        (["greek", "ελληνικά"], "el"), (["hungarian", "magyar"], "hu"), (["romanian", "română"], "ro"),
        (["ukrainian", "українська"], "uk"),
    ]

    private static func baseFromLanguageName(in title: String) -> String? {
        nameLookup.first { entry in entry.names.contains { title.contains($0) } }?.base
    }
}
