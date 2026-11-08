//
//  SubtitleCueParser.swift
//  FlixorMac
//
//  Parses SRT, WebVTT and ASS/SSA subtitle files into timed cues for the
//  cue-based subtitle sync UI.
//

import Foundation

/// One subtitle cue. `start`/`end` are in the SUBTITLE's own timeline (file
/// timestamps, before `sub-delay`); it is shown on screen at `start + subtitleDelay`.
struct SubtitleCue: Identifiable, Hashable {
    let id: String
    let start: TimeInterval
    let end: TimeInterval
    /// Plain text (tags removed, lines joined with "\n").
    let text: String

    init(start: TimeInterval, end: TimeInterval, text: String) {
        self.start = start
        self.end = max(end, start)
        self.text = text
        self.id = "\(Int((start * 1000).rounded()))-\(text.hashValue)"
    }
}

/// Where the player's cue list comes from.
enum SubtitleCueSource: Equatable {
    /// No subtitle selected, or the track's cues can't be read.
    case none
    /// The whole subtitle file was parsed: `subtitleCues` has every cue (past and upcoming).
    case fullFile
    /// Embedded/streamed track: mpv does not expose its cue list, so only cues
    /// already shown (`recentSubtitleCues`) are known; upcoming cues are unavailable.
    case observedOnly
}

enum SubtitleCueParser {
    /// Parses subtitle text; the format is detected from the content
    /// (`formatHint` such as "srt", "vtt", "ass" is only a tie-breaker).
    /// Returns cues sorted by start time; empty when nothing could be parsed.
    static func parse(_ content: String, formatHint: String? = nil) -> [SubtitleCue] {
        let text = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
        let hint = formatHint?.lowercased() ?? ""
        let cues: [SubtitleCue]
        if text.contains("[Events]") || hint == "ass" || hint == "ssa" {
            cues = parseASS(text)
        } else {
            // SRT and WebVTT share the "start --> end" timing line
            cues = parseTimedBlocks(text)
        }
        return cues.sorted { $0.start < $1.start }
    }

    /// Decodes subtitle file data (UTF-8, falling back to Windows-1252 / Latin-1).
    static func decode(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        if let utf16 = String(data: data, encoding: .utf16), data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            return utf16
        }
        return String(data: data, encoding: .windowsCP1252) ?? String(data: data, encoding: .isoLatin1)
    }

    // MARK: - SRT / WebVTT

    private static func parseTimedBlocks(_ text: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        let lines = text.components(separatedBy: "\n")
        var index = 0
        while index < lines.count {
            let line = lines[index]
            guard line.contains("-->") else { index += 1; continue }
            let parts = line.components(separatedBy: "-->")
            guard parts.count >= 2,
                  let start = parseTimestamp(parts[0]),
                  // VTT may append cue settings after the end time ("00:01.000 align:start")
                  let end = parseTimestamp(parts[1].trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first ?? "") else {
                index += 1
                continue
            }
            index += 1
            var body: [String] = []
            while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                // A missing blank line before the next cue: stop at its timing line
                if lines[index].contains("-->") { break }
                body.append(lines[index])
                index += 1
            }
            // Drop a trailing SRT counter that belongs to the next cue
            if let last = body.last, Int(last.trimmingCharacters(in: .whitespaces)) != nil,
               index < lines.count, lines[index].contains("-->") {
                body.removeLast()
            }
            let cleaned = cleanMarkup(body.joined(separator: "\n"))
            if !cleaned.isEmpty {
                cues.append(SubtitleCue(start: start, end: end, text: cleaned))
            }
        }
        return cues
    }

    /// "01:02:03,456", "01:02:03.456", "02:03.456" (VTT), "1:02:03.45"
    static func parseTimestamp(_ raw: String) -> TimeInterval? {
        let value = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let parts = value.split(separator: ":").map(String.init)
        guard (2...3).contains(parts.count) else { return nil }
        var seconds: Double = 0
        for part in parts.dropLast() {
            guard let number = Int(part) else { return nil }
            seconds = seconds * 60 + Double(number)
        }
        guard let last = Double(parts[parts.count - 1]) else { return nil }
        return seconds * 60 + last
    }

    // MARK: - ASS / SSA

    private static func parseASS(_ text: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        var inEvents = false
        var format: [String] = []
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inEvents = line.lowercased() == "[events]"
                continue
            }
            guard inEvents else { continue }
            if line.lowercased().hasPrefix("format:") {
                format = line.dropFirst("format:".count).split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespaces).lowercased()
                }
                continue
            }
            guard line.lowercased().hasPrefix("dialogue:") else { continue }
            let fields = format.isEmpty
                ? ["layer", "start", "end", "style", "name", "marginl", "marginr", "marginv", "effect", "text"]
                : format
            guard let startIndex = fields.firstIndex(of: "start"),
                  let endIndex = fields.firstIndex(of: "end"),
                  let textIndex = fields.firstIndex(of: "text") else { continue }
            // Text is the last field and may itself contain commas
            let values = line.dropFirst("dialogue:".count)
                .split(separator: ",", maxSplits: fields.count - 1, omittingEmptySubsequences: false)
                .map { String($0) }
            guard values.count == fields.count,
                  let start = parseTimestamp(values[startIndex]),
                  let end = parseTimestamp(values[endIndex]) else { continue }
            let body = values[textIndex]
                .replacingOccurrences(of: "{[^}]*}", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\N", with: "\n")
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\h", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                cues.append(SubtitleCue(start: start, end: end, text: body))
            }
        }
        return cues
    }

    // MARK: - Helpers

    /// Removes HTML-like tags (<i>, <font>, VTT <c.x>, <00:01.000>) and ASS override blocks.
    static func cleanMarkup(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "{\\\\[^}]*}", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
