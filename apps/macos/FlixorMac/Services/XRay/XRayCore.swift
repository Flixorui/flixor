//
//  XRayCore.swift
//  FlixorMac
//
//  X-Ray's timeline model and the parts of the analysis that are plain logic: shot
//  cuts from colour histograms, matching faces to the cast (with a second pass that
//  learns each actor's look in this film), when a name is sure enough to show, and
//  grouping shots into scenes.
//
//  No app dependencies, so the accuracy test tool can compile it on its own.
//

import Foundation

// MARK: - Model

struct XRayCastMember: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let character: String?
    let profilePath: String?
    let order: Int
}

/// One shot: from one cut to the next, with the people named in it.
struct XRayShot: Codable, Hashable {
    var start: Double
    var end: Double
    var people: [Int]
}

struct XRayScene: Hashable, Identifiable {
    var id: Double { start }
    var start: Double
    var end: Double
    /// Most screen time first.
    var people: [Int]
}

/// Everything X-Ray knows about one title, saved on this Mac.
struct XRayTimeline: Codable {
    static let currentVersion = 1
    var version = XRayTimeline.currentVersion
    var key: String
    var duration: Double
    var cast: [XRayCastMember]
    var shots: [XRayShot] = []
    /// Analysed stretches, sorted and merged: [[start, end], ...].
    var coverage: [[Double]] = []

    func isCovered(_ t: Double) -> Bool {
        coverage.contains { t >= $0[0] && t <= $0[1] }
    }

    /// End of the covered stretch containing `t`, or nil.
    func coveredEnd(at t: Double) -> Double? {
        coverage.first { t >= $0[0] - 0.01 && t <= $0[1] }?[1]
    }

    /// The first time at or after `t` that isn't analysed yet (nil when the rest is done).
    func firstUncovered(from t: Double) -> Double? {
        var cursor = max(0, t)
        for range in coverage where range[1] >= cursor {
            if range[0] > cursor + 1 { break }
            cursor = max(cursor, range[1])
        }
        return cursor < duration - 2 ? cursor : nil
    }

    mutating func addCoverage(_ start: Double, _ end: Double) {
        guard end > start else { return }
        var ranges = coverage + [[start, end]]
        ranges.sort { $0[0] < $1[0] }
        var merged: [[Double]] = []
        for r in ranges {
            if let last = merged.last, r[0] <= last[1] + 1.0 {
                merged[merged.count - 1][1] = max(last[1], r[1])
            } else {
                merged.append(r)
            }
        }
        coverage = merged
    }

    /// Replaces shots overlapping the new ones, keeping the list sorted.
    mutating func insert(_ new: [XRayShot]) {
        guard let first = new.first, let last = new.last else { return }
        shots.removeAll { $0.end > first.start + 0.01 && $0.start < last.end - 0.01 }
        shots.append(contentsOf: new)
        shots.sort { $0.start < $1.start }
    }

    func shot(at t: Double) -> XRayShot? {
        // Binary search: shots are sorted by start.
        var lo = 0, hi = shots.count - 1, found: XRayShot?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if shots[mid].start <= t { found = shots[mid]; lo = mid + 1 } else { hi = mid - 1 }
        }
        guard let found, t <= found.end + 0.5 else { return nil }
        return found
    }
}

// MARK: - Shot cuts

enum XRayHistogram {
    static let hueBins = 32, satBins = 32

    /// Hue/saturation histogram of an RGBA image (sampled on a coarse grid), ignoring
    /// near-black pixels.
    static func make(rgba: UnsafePointer<UInt8>, width: Int, height: Int, bytesPerRow: Int, step: Int = 6) -> [Float] {
        var bins = [Float](repeating: 0, count: hueBins * satBins)
        var y = 0
        while y < height {
            let row = rgba + y * bytesPerRow
            var x = 0
            while x < width {
                let p = row + x * 4
                let r = Float(p[0]) / 255, g = Float(p[1]) / 255, b = Float(p[2]) / 255
                let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
                // Near-black pixels don't count: letterbox bars baked into the picture
                // would otherwise make every frame look alike and hide the cuts.
                if mx < 0.07 { x += step; continue }
                var h: Float = 0
                if d > 0 {
                    if mx == r { h = (g - b) / d } else if mx == g { h = 2 + (b - r) / d } else { h = 4 + (r - g) / d }
                    h /= 6
                    if h < 0 { h += 1 }
                }
                let s = mx > 0 ? d / mx : 0
                let hi = min(hueBins - 1, Int(h * Float(hueBins)))
                let si = min(satBins - 1, Int(s * Float(satBins)))
                bins[hi * satBins + si] += 1
                x += step
            }
            y += step
        }
        return bins
    }

    /// Pearson correlation, as OpenCV's HISTCMP_CORREL.
    static func correlation(_ a: [Float], _ b: [Float]) -> Float {
        let n = Float(a.count)
        let ma = a.reduce(0, +) / n, mb = b.reduce(0, +) / n
        var num: Float = 0, da: Float = 0, db: Float = 0
        for i in 0..<a.count {
            let x = a[i] - ma, y = b[i] - mb
            num += x * y; da += x * x; db += y * y
        }
        let den = sqrt(da * db)
        return den > 0 ? num / den : 1
    }

    /// Below this the two frames are taken to be different shots.
    static let cutThreshold: Float = 0.55
}

// MARK: - Matching

/// Who a face is, against the film's cast photos plus faces already found in this film.
final class XRayMatcher {
    struct Match {
        let person: Int?
        let guess: Int
        let score: Float
        let margin: Float
        let pass: Int
    }

    static let match: Float = 0.40, margin: Float = 0.04
    /// The second pass (in-film faces as extra references) is stricter.
    static let match2: Float = 0.45, margin2: Float = 0.06
    /// A face this sure becomes an in-film reference; a name this sure shows from one frame.
    static let strong: Float = 0.48
    static let maxInFilmRefs = 24
    /// The second pass and learning only use faces at least this big (pixels at 960
    /// wide), and never in a crowd: small crowd faces look alike enough to borrow a name.
    static let minSecondPassSide: Double = 80
    static let crowdSize = 6

    private(set) var castRefs: [Int: [[Float]]]
    private(set) var filmRefs: [Int: [[Float]]] = [:]

    init(castRefs: [Int: [[Float]]]) {
        self.castRefs = castRefs.filter { !$0.value.isEmpty }
    }

    var hasReferences: Bool { castRefs.count >= 1 }

    /// `allowSecondPass`: the face is big enough and not in a crowd.
    func match(_ e: [Float], allowSecondPass: Bool = true) -> Match? {
        guard let first = best(e, includeFilm: false) else { return nil }
        if first.score >= Self.match, first.score - first.second >= Self.margin {
            return Match(person: first.person, guess: first.person, score: first.score, margin: first.score - first.second, pass: 1)
        }
        if allowSecondPass, !filmRefs.isEmpty, let second = best(e, includeFilm: true),
           second.score >= Self.match2, second.score - second.second >= Self.margin2 {
            return Match(person: second.person, guess: second.person, score: second.score, margin: second.score - second.second, pass: 2)
        }
        return Match(person: nil, guess: first.person, score: first.score, margin: first.score - first.second, pass: 0)
    }

    /// Adds a confidently named face as a reference for that actor in this film.
    /// Returns true when it was added.
    @discardableResult
    func learn(_ e: [Float], person: Int, score: Float) -> Bool {
        guard score >= Self.strong else { return false }
        var list = filmRefs[person] ?? []
        guard list.count < Self.maxInFilmRefs else { return false }
        // Skip near-duplicates (the same shot again): they add nothing.
        if list.contains(where: { XRayMath.dot($0, e) > 0.9 }) { return false }
        list.append(e)
        filmRefs[person] = list
        return true
    }

    private func best(_ e: [Float], includeFilm: Bool) -> (person: Int, score: Float, second: Float)? {
        var top: (Int, Float) = (-1, -2), second: Float = -2
        for (person, refs) in castRefs {
            var s: Float = -2
            for r in refs { s = max(s, XRayMath.dot(r, e)) }
            if includeFilm, let extra = filmRefs[person] {
                for r in extra { s = max(s, XRayMath.dot(r, e)) }
            }
            if s > top.1 { second = top.1; top = (person, s) } else if s > second { second = s }
        }
        guard top.0 >= 0 else { return nil }
        return (top.0, top.1, max(second, -1))
    }
}

// MARK: - Shots from samples

/// Builds shots from frames sampled in time order (about 2 a second).
final class XRayShotBuilder {
    struct Face {
        let time: Double
        let embedding: [Float]
        let secondPassOK: Bool
        var match: XRayMatcher.Match
    }

    struct OpenShot {
        var start: Double
        var end: Double
        var faces: [Face] = []
    }

    /// A gap longer than this between samples (a seek) ends the shot.
    static let maxGap: Double = 2.0

    let matcher: XRayMatcher
    private var lastHistogram: [Float]?
    private var lastTime: Double?
    private var open: OpenShot?
    /// Finished shots whose faces may still be renamed by the second pass.
    private(set) var recent: [OpenShot] = []
    private let recentLimit = 400

    init(matcher: XRayMatcher) {
        self.matcher = matcher
    }

    /// Adds one sampled frame. Returns shots that just finished.
    func add(time: Double, histogram: [Float], faces: [XRayDetectedFace]) -> [XRayShot] {
        var finished: [XRayShot] = []
        let isCut: Bool = {
            guard let lastHistogram, let lastTime else { return true }
            if time - lastTime > Self.maxGap || time < lastTime { return true }
            return XRayHistogram.correlation(lastHistogram, histogram) < XRayHistogram.cutThreshold
        }()
        if isCut, let shot = open {
            finished.append(close(shot))
            open = nil
        }
        if open == nil { open = OpenShot(start: time, end: time) }
        open?.end = time + 0.5
        let crowd = faces.count >= XRayMatcher.crowdSize
        for f in faces {
            let ok = !crowd && Double(min(f.box.width, f.box.height)) >= XRayMatcher.minSecondPassSide
            guard let m = matcher.match(f.embedding, allowSecondPass: ok) else { continue }
            if ok, let person = m.person, m.pass == 1 { matcher.learn(f.embedding, person: person, score: m.score) }
            open?.faces.append(Face(time: time, embedding: f.embedding, secondPassOK: ok, match: m))
        }
        lastHistogram = histogram
        lastTime = time
        return finished
    }

    /// Ends the open shot (a seek, the end of a stretch).
    func flush() -> [XRayShot] {
        lastHistogram = nil
        lastTime = nil
        guard let shot = open else { return [] }
        open = nil
        return [close(shot)]
    }

    /// Re-matches unnamed faces of recent shots now that the matcher knows more faces
    /// from this film. Returns the shots whose people changed.
    func rematchRecent() -> [XRayShot] {
        var changed: [XRayShot] = []
        for i in recent.indices {
            var any = false
            for j in recent[i].faces.indices where recent[i].faces[j].match.person == nil && recent[i].faces[j].secondPassOK {
                if let m = matcher.match(recent[i].faces[j].embedding), m.person != nil {
                    recent[i].faces[j].match = m
                    any = true
                }
            }
            if any {
                changed.append(XRayShot(start: recent[i].start, end: recent[i].end, people: Self.people(in: recent[i])))
            }
        }
        return changed
    }

    private func close(_ shot: OpenShot) -> XRayShot {
        recent.append(shot)
        if recent.count > recentLimit { recent.removeFirst(recent.count - recentLimit) }
        return XRayShot(start: shot.start, end: shot.end, people: Self.people(in: shot))
    }

    /// People sure enough to show: named in two frames of the shot, or once very surely.
    /// One stray match (a coat taken for a face) doesn't make it.
    static func people(in shot: OpenShot) -> [Int] {
        var frames: [Int: Set<Double>] = [:], best: [Int: Float] = [:]
        for f in shot.faces {
            guard let p = f.match.person else { continue }
            frames[p, default: []].insert(f.time)
            best[p] = max(best[p] ?? -1, f.match.score)
        }
        return frames.keys
            .filter { (frames[$0]?.count ?? 0) >= 2 || (best[$0] ?? 0) >= XRayMatcher.strong }
            .sorted { (best[$0] ?? 0) > (best[$1] ?? 0) }
    }
}

// MARK: - Scenes

enum XRayScenes {
    /// Groups shots into scenes: a scene goes on while the same people keep coming back,
    /// and ends at a gap in the analysis or when new people take over after a while.
    static func group(_ shots: [XRayShot]) -> [XRayScene] {
        var scenes: [XRayScene] = []
        var start = 0.0, end = 0.0
        var screen: [Int: Double] = [:], lastSeen: [Int: Double] = [:]
        var lastFaceTime: Double?
        var hasScene = false

        func finish() {
            guard hasScene else { return }
            let people = screen.keys.sorted { (screen[$0] ?? 0) > (screen[$1] ?? 0) }
            scenes.append(XRayScene(start: start, end: end, people: people))
        }

        for shot in shots {
            var split = !hasScene || shot.start - end > XRayShotBuilder.maxGap + 0.5
            if !split, !shot.people.isEmpty {
                let returning = shot.people.contains { (lastSeen[$0].map { shot.start - $0 } ?? .infinity) < 120 }
                let quietFor = lastFaceTime.map { shot.start - $0 } ?? (shot.start - start)
                if !returning && (end - start >= 30 || quietFor >= 45) { split = true }
            }
            if split {
                finish()
                start = shot.start
                screen = [:]
                lastSeen = [:]
                lastFaceTime = nil
                hasScene = true
            }
            end = max(end, shot.end)
            if split { end = shot.end }
            for p in shot.people {
                screen[p, default: 0] += shot.end - shot.start
                lastSeen[p] = shot.end
            }
            if !shot.people.isEmpty { lastFaceTime = shot.end }
        }
        finish()
        return scenes
    }
}
