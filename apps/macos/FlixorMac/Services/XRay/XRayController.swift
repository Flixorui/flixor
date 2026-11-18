//
//  XRayController.swift
//  FlixorMac
//
//  X-Ray for one playing title: loads the cast and their face references, keeps the
//  saved timeline, points the analyser at the part of the film that's needed next
//  (a few minutes ahead for streams, the whole film for Plex and local files), and
//  publishes who's in the current scene for the player's strip and panel.
//

import Foundation
import Combine

@MainActor
final class XRayController: ObservableObject {
    enum State: Equatable {
        case preparing
        case working
        case unavailable(String)
    }

    /// Streams stay this far ahead, played at `streamSpeed`, to limit the extra download.
    static let streamAhead: Double = 600
    static let streamSpeed: Double = 4

    let identity: XRayIdentity
    let wholeFile: Bool

    @Published private(set) var state: State = .preparing
    @Published private(set) var cast: [XRayCastMember] = []
    @Published private(set) var scenes: [XRayScene] = []
    @Published private(set) var currentScene: XRayScene?
    /// People in the current shot (shown first in the strip).
    @Published private(set) var shotPeople: [Int] = []
    /// Analysed stretches, for the seek bar.
    @Published private(set) var coverage: [[Double]] = []
    /// Where the analysed stretch containing the playhead ends (nil: not analysed yet).
    @Published private(set) var readyUntil: Double?

    private(set) var castById: [Int: XRayCastMember] = [:]
    private var timeline: XRayTimeline?
    private var analyzer: XRayAnalyzer?
    private var tickTimer: Timer?
    private var setupTask: Task<Void, Never>?
    private var cursor: Double?
    private var dirty = false
    private var lastSave = Date()
    private var screenTimes: [Int: Double] = [:]

    private weak var player: PlayerViewModel?

    init(identity: XRayIdentity, player: PlayerViewModel, wholeFile: Bool) {
        self.identity = identity
        self.player = player
        self.wholeFile = wholeFile
    }

    // MARK: Lifecycle

    func start(duration: Double) {
        setupTask = Task { [weak self] in
            guard let self else { return }
            let store = XRayStore.shared
            let saved = await store.loadTimeline(key: identity.key, duration: duration)
            let cast = saved?.cast.isEmpty == false ? saved!.cast : await store.cast(for: identity)
            guard !Task.isCancelled else { return }
            guard !cast.isEmpty else {
                state = .unavailable(String(localized: "No cast list for this title"))
                return
            }
            self.cast = cast
            castById = Dictionary(uniqueKeysWithValues: cast.map { ($0.id, $0) })
            timeline = saved ?? XRayTimeline(key: identity.key, duration: duration, cast: cast)
            refreshDerived()
            print("🎭 [XRay] \(identity.key): \(cast.count) cast, saved shots \(saved?.shots.count ?? 0)")

            let refs = await store.references(for: cast)
            guard !Task.isCancelled else { return }
            guard !refs.isEmpty else {
                state = .unavailable(String(localized: "No cast photos to match"))
                return
            }
            print("🎭 [XRay] face references for \(refs.count) of \(cast.count)")
            let analyzer = XRayAnalyzer(castRefs: refs, untimed: wholeFile) { [weak self] delivery in
                Task { @MainActor in self?.receive(delivery) }
            }
            self.analyzer = analyzer
            analyzer.start()
            state = .working
            tick()
            let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
            timer.tolerance = 0.3
            tickTimer = timer
        }
    }

    func stop() {
        setupTask?.cancel()
        tickTimer?.invalidate()
        tickTimer = nil
        analyzer?.stop()
        analyzer = nil
        saveIfNeeded(force: true)
    }

    // MARK: Steering the analyser

    private func tick() {
        guard let player, var timeline, let analyzer else { return }
        if timeline.duration <= 0, player.duration > 0 { timeline.duration = player.duration; self.timeline = timeline }
        let playhead = player.currentTime
        updateCurrent(at: playhead)

        let controller = player.mpvController
        let canLoad = controller?.allowsBackgroundNetworkLoads ?? false
        var target = timeline.firstUncovered(from: playhead)
        if target == nil, wholeFile { target = timeline.firstUncovered(from: 0) }
        var run = canLoad && target != nil
        if let t = target, !wholeFile, t - playhead > Self.streamAhead { run = false }
        var seek: Double?
        if run, let t = target {
            // Already working there: let it carry on. Elsewhere (a seek, a finished stretch): move.
            if let c = cursor, c >= t - 3, c <= t + 20 {} else { seek = t; cursor = t }
        }
        analyzer.update(options: controller?.currentLoadOptions, run: run, seekTo: seek, speed: Self.streamSpeed)
        saveIfNeeded()
    }

    private func receive(_ delivery: XRayAnalyzer.Delivery) {
        guard var timeline else { return }
        if let failed = delivery.failed {
            print("⚠️ [XRay] stopped: \(failed)")
            if timeline.shots.isEmpty { state = .unavailable(String(localized: "X-Ray couldn't read this file")) }
            return
        }
        if !delivery.shots.isEmpty { timeline.insert(delivery.shots) }
        if let (s, e) = delivery.covered {
            timeline.addCoverage(s, e)
            cursor = e
        }
        if delivery.reachedEnd {
            if let c = cursor { timeline.addCoverage(c, timeline.duration) }
            cursor = nil
        }
        self.timeline = timeline
        dirty = true
        refreshDerived()
        if let player { updateCurrent(at: player.currentTime) }
    }

    private func refreshDerived() {
        guard let timeline else { return }
        scenes = XRayScenes.group(timeline.shots)
        coverage = timeline.coverage
        var times: [Int: Double] = [:]
        for shot in timeline.shots {
            for p in shot.people { times[p, default: 0] += shot.end - shot.start }
        }
        screenTimes = times
    }

    private func updateCurrent(at t: Double) {
        let scene = scene(at: t)
        if scene != currentScene { currentScene = scene }
        let people = timeline?.shot(at: t)?.people ?? []
        if people != shotPeople { shotPeople = people }
        let until = timeline?.coveredEnd(at: t)
        if until.map({ Int($0) }) != readyUntil.map({ Int($0) }) { readyUntil = until }
    }

    private func saveIfNeeded(force: Bool = false) {
        guard dirty, let timeline, force || Date().timeIntervalSince(lastSave) > 30 else { return }
        dirty = false
        lastSave = Date()
        Task { await XRayStore.shared.save(timeline) }
    }

    // MARK: Questions from the UI

    func scene(at t: Double) -> XRayScene? {
        scenes.last { $0.start <= t + 0.25 && t <= $0.end + 1 }
    }

    /// People in the current scene, those in the current shot first.
    var scenePeople: [XRayCastMember] {
        guard let scene = currentScene else { return [] }
        let order = shotPeople + scene.people.filter { !shotPeople.contains($0) }
        return order.compactMap { castById[$0] }
    }

    func people(in scene: XRayScene) -> [XRayCastMember] {
        scene.people.compactMap { castById[$0] }
    }

    /// Names for the seek-bar preview at `t`.
    func names(at t: Double) -> String? {
        guard let scene = scene(at: t), !scene.people.isEmpty else { return nil }
        let names = scene.people.prefix(3).compactMap { castById[$0]?.name }
        let more = scene.people.count - names.count
        return names.joined(separator: ", ") + (more > 0 ? " +\(more)" : "")
    }

    /// Everyone seen so far, most screen time first.
    var seenCast: [(member: XRayCastMember, seconds: Double)] {
        screenTimes.compactMap { id, s in castById[id].map { ($0, s) } }.sorted { $0.seconds > $1.seconds }
    }

    func nextScene(with person: Int, after t: Double) -> XRayScene? {
        scenes.first { $0.start > t + 1 && $0.people.contains(person) }
    }

    func sceneNumber(_ scene: XRayScene) -> Int? {
        scenes.firstIndex(of: scene).map { $0 + 1 }
    }

    var isWholeFileDone: Bool {
        guard let timeline else { return false }
        return timeline.firstUncovered(from: 0) == nil
    }

    var isPlayheadCovered: Bool { readyUntil != nil }
}
