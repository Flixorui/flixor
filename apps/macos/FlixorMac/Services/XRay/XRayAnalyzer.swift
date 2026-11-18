//
//  XRayAnalyzer.swift
//  FlixorMac
//
//  The worker behind X-Ray: on its own low-priority thread it drives the hidden player,
//  samples two frames a second, finds and matches faces, and sends finished shots back
//  to XRayController on the main thread. The controller decides where it works and
//  when it rests (`update`).
//

import Foundation

final class XRayAnalyzer {
    struct Delivery {
        var shots: [XRayShot] = []
        /// The stretch analysed since the last seek, so far.
        var covered: (Double, Double)?
        var reachedEnd = false
        var failed: String?
    }

    /// Seconds between analysed frames.
    static let sampleInterval: Double = 0.5

    private let lock = NSLock()
    private var options: MPVNetworkLoadOptions?
    private var shouldRun = false
    private var pendingSeek: Double?
    private var speed: Double = 4
    private var stopped = false
    private var source: XRayFrameSource?

    private let untimed: Bool
    private let matcher: XRayMatcher
    private let deliver: (Delivery) -> Void

    /// `deliver` is called on the worker thread, in order.
    init(castRefs: [Int: [[Float]]], untimed: Bool, deliver: @escaping (Delivery) -> Void) {
        self.matcher = XRayMatcher(castRefs: castRefs)
        self.untimed = untimed
        self.deliver = deliver
    }

    func start() {
        let thread = Thread { [self] in run() }
        thread.name = "com.flixor.xray"
        thread.qualityOfService = .utility
        thread.start()
    }

    /// Where and whether to work. Any thread.
    func update(options: MPVNetworkLoadOptions?, run: Bool, seekTo: Double?, speed: Double) {
        lock.lock()
        self.options = options
        shouldRun = run
        if let seekTo { pendingSeek = seekTo }
        self.speed = speed
        lock.unlock()
    }

    /// Ends the thread soon; the hidden player is destroyed there.
    func stop() {
        lock.lock()
        stopped = true
        let running = source
        lock.unlock()
        running?.abort()
    }

    // MARK: Worker thread

    private func run() {
        guard let engine = XRayFaceEngine.bundled() else {
            send(Delivery(failed: "face model missing"))
            return
        }
        let source = XRayFrameSource(untimed: untimed)
        lock.lock()
        self.source = source
        let stoppedEarly = stopped
        lock.unlock()
        defer { source.shutdown() }
        guard !stoppedEarly else { return }
        guard source.isReady else {
            send(Delivery(failed: "hidden player failed"))
            return
        }

        let builder = XRayShotBuilder(matcher: matcher)
        var pending: [XRayShot] = []
        var segmentStart: Double?, lastSample: Double?
        var nextSample = -Double.infinity
        var isPlaying = false
        var appliedSpeed = -1.0
        var loadFailures = 0
        var retryAfter = Date.distantPast
        var lastDelivery = Date(), lastRematch = Date()
        var atEnd = false

        func flushAndDeliver(reachedEnd: Bool = false) {
            pending += builder.flush()
            var d = Delivery(shots: pending, reachedEnd: reachedEnd)
            if let s = segmentStart, let e = lastSample { d.covered = (s, e + Self.sampleInterval) }
            pending = []
            send(d)
            lastDelivery = Date()
        }

        while true {
            lock.lock()
            let isStopped = stopped
            let opts = options, run = shouldRun, seek = pendingSeek, wantedSpeed = speed
            pendingSeek = nil
            lock.unlock()
            if isStopped { break }

            guard let opts else { Thread.sleep(forTimeInterval: 0.25); continue }
            if source.loadedURL != opts.url {
                guard Date() >= retryAfter else { Thread.sleep(forTimeInterval: 0.25); continue }
                guard source.load(opts) else {
                    loadFailures += 1
                    // A source refusing a second connection isn't hammered.
                    if loadFailures >= 4 {
                        send(Delivery(failed: "couldn't open a second connection to this file"))
                        break
                    }
                    retryAfter = Date().addingTimeInterval([5.0, 15, 60][min(loadFailures - 1, 2)])
                    continue
                }
                loadFailures = 0
                isPlaying = false
                appliedSpeed = -1
                atEnd = false
            }

            if let seek {
                flushAndDeliver()
                source.seek(to: seek)
                segmentStart = nil
                lastSample = nil
                nextSample = -Double.infinity
                atEnd = false
            }

            guard run, !atEnd else {
                if isPlaying { source.setPaused(true); isPlaying = false }
                if !pending.isEmpty || segmentStart != nil, Date().timeIntervalSince(lastDelivery) > 1 {
                    var d = Delivery(shots: pending)
                    if let s = segmentStart, let e = lastSample { d.covered = (s, e + Self.sampleInterval) }
                    pending = []
                    send(d)
                    lastDelivery = Date()
                }
                Thread.sleep(forTimeInterval: 0.2)
                continue
            }
            if !untimed, appliedSpeed != wantedSpeed { source.setSpeed(wantedSpeed); appliedSpeed = wantedSpeed }
            if !isPlaying { source.setPaused(false); isPlaying = true }

            switch source.pump(timeout: 0.1, wants: { $0 >= nextSample }) {
            case .frame(let frame):
                autoreleasepool {
                    nextSample = frame.time + Self.sampleInterval
                    let histogram = frame.pixels.withUnsafeBufferPointer {
                        XRayHistogram.make(rgba: $0.baseAddress!, width: frame.width, height: frame.height, bytesPerRow: frame.width * 4)
                    }
                    let faces = engine.faces(in: frame.image)
                    pending += builder.add(time: frame.time, histogram: histogram, faces: faces)
                    if segmentStart == nil { segmentStart = frame.time }
                    lastSample = frame.time
                }
            case .ended:
                atEnd = true
                isPlaying = false
                flushAndDeliver(reachedEnd: true)
            case .skipped, .idle:
                break
            }

            if Date().timeIntervalSince(lastRematch) > 20 {
                pending += builder.rematchRecent()
                lastRematch = Date()
            }
            if Date().timeIntervalSince(lastDelivery) > 1.5 {
                var d = Delivery(shots: pending)
                if let s = segmentStart, let e = lastSample { d.covered = (s, e + Self.sampleInterval) }
                pending = []
                send(d)
                lastDelivery = Date()
            }
        }
        flushAndDeliver()
    }

    private func send(_ delivery: Delivery) {
        deliver(delivery)
    }
}
