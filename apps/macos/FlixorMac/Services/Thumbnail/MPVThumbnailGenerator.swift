//
//  MPVThumbnailGenerator.swift
//  FlixorMac
//
//  Coordinates thumbnail generation using self-contained MPV instance
//

import Foundation
import AppKit
import Combine

/// Manages thumbnail generation for MPV player
class MPVThumbnailGenerator: ObservableObject {
    // MARK: - Properties

    private weak var mpvController: MPVPlayerController?
    private let cache = ThumbnailCache(maxSize: MPVThumbnailGenerator.bucketsPerTitle)
    private var debounceTimer: Timer?
    private let debounceInterval: TimeInterval = 0.05 // 50ms
    /// Created on the first hover request and destroyed after `idleTimeout` without
    /// requests, on `shutdown()`, or when this generator goes away. Work queue only.
    private var thumbnailPlayer: ThumbnailMPVPlayer?
    private var currentVideoURL: String?
    private static let idleTimeout: TimeInterval = 30
    // Work queue only.
    private var idleToken = 0
    private var failedLoadURL: String?
    private var failedLoadTime: CFAbsoluteTime = 0
    // Under generationLock.
    private var isShutDown = false
    /// The live thumbnail instance, so `shutdown()` can abort a wait from main.
    private var abortablePlayer: ThumbnailMPVPlayer?

    /// The seek bar is split into this many slots; one thumbnail per slot is made and cached.
    static let bucketsPerTitle = 120
    /// Thumbnails are made one at a time; a request that is no longer the newest is skipped.
    private let workQueue = DispatchQueue(label: "com.flixor.thumbnail.work", qos: .userInitiated)
    private let generationLock = NSLock()
    private var latestGeneration = 0
    /// Bumped when a different file loads; thumbnails made for the old one are discarded.
    private var fileGeneration = 0

    /// Observable property indicating if thumbnails are available
    @Published var isAvailable: Bool = false

    // MARK: - Initialization

    init(mpvController: MPVPlayerController) {
        self.mpvController = mpvController
        setupObservers()
    }

    deinit {
        // shutdown() normally ran already; never destroy mpv on the main thread.
        if let player = thumbnailPlayer {
            DispatchQueue.global(qos: .utility).async { player.shutdown() }
        }
    }

    // MARK: - Setup

    private func setupObservers() {
        // No-op: PlayerViewModel will call onVideoLoaded() directly
    }

    /// Called by PlayerViewModel when a video file is loaded. Only bookkeeping: the
    /// thumbnail instance opens the file on the first hover request, so it never
    /// competes with the player while the file starts.
    func onVideoLoaded(url: String) {
        print("📸 [ThumbnailGenerator] Video loaded")
        if url != currentVideoURL {
            // Slots of the old file must not answer for the new one.
            generationLock.lock()
            fileGeneration += 1
            latestGeneration += 1
            cache.clearAll()
            generationLock.unlock()
        }
        currentVideoURL = url
        isAvailable = true
    }

    /// Stops thumbnail work and destroys the thumbnail instance (and its connection)
    /// off the main thread. Called when playback stops or the player closes.
    func shutdown() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        generationLock.lock()
        isShutDown = true
        latestGeneration += 1
        let running = abortablePlayer
        generationLock.unlock()
        // A load or seek in progress gives up instead of holding the queue.
        running?.abort()
        isAvailable = false
        // Strong: the instance must be destroyed here, on the work queue.
        workQueue.async { [self] in
            destroyThumbnailPlayer()
        }
    }

    // MARK: - Public Methods

    /// Generate a thumbnail at a specific timestamp
    /// - Parameters:
    ///   - time: Time in seconds
    ///   - completion: Called with the generated image or nil on failure
    func generateThumbnail(at time: Double, completion: @escaping (NSImage?) -> Void) {
        let time = bucketTime(for: time)
        // Check cache first (instant)
        if let cached = cache.get(at: time) {
            debounceTimer?.invalidate()
            debounceTimer = nil
            completion(cached)
            return
        }

        // Debounce requests to avoid overwhelming the system
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
            self?.requestThumbnail(at: time, latestOnly: true, completion: completion)
        }
    }

    /// Middle of the seek-bar slot `time` falls in, so nearby hover positions share
    /// one thumbnail. Ten-second slots until the duration is known.
    private func bucketTime(for time: Double) -> Double {
        let duration = mpvController?.currentDuration ?? 0
        let size = duration > 0 ? max(1, duration / Double(Self.bucketsPerTitle)) : 10
        var bucket = (floor(max(0, time) / size) + 0.5) * size
        if duration > 0 { bucket = min(bucket, max(0, duration - 1)) }
        return (bucket * 10).rounded() / 10
    }

    /// Pre-fetch thumbnails around a specific time
    /// - Parameter centerTime: Center timestamp in seconds
    /// - Parameter range: Time range in seconds (default: 5 seconds)
    func prefetchThumbnails(around centerTime: Double, range: Double = 5.0) {
        // Pre-fetch thumbnails at 1-second intervals
        let startTime = max(0, centerTime - range)
        let endTime = centerTime + range
        var currentTime = startTime

        while currentTime <= endTime {
            // Skip if already cached
            if cache.get(at: currentTime) == nil {
                requestThumbnail(at: currentTime, latestOnly: false) { _ in
                    // Silent completion
                }
            }
            currentTime += 1.0
        }

        print("🔮 [ThumbnailGenerator] Prefetching thumbnails from \(startTime)s to \(endTime)s")
    }

    /// Clear all cached thumbnails
    func clearCache() {
        cache.clearAll()
    }

    // MARK: - Private Methods

    /// The thumbnail instance with the player's current file open, creating it and
    /// opening the file when needed. Nil while the player is starting or buffering
    /// (no competing download then), after shutdown, or when the file fails to open.
    /// Work queue only.
    private func preparedPlayer() -> ThumbnailMPVPlayer? {
        generationLock.lock()
        let shutDown = isShutDown
        generationLock.unlock()
        guard !shutDown, let controller = mpvController,
              controller.allowsBackgroundNetworkLoads,
              let options = controller.currentLoadOptions else { return nil }

        if let player = thumbnailPlayer, player.loadedURL == options.url {
            return player
        }
        // A source that refused the second connection isn't retried for a while.
        if failedLoadURL == options.url, CFAbsoluteTimeGetCurrent() - failedLoadTime < Self.idleTimeout {
            return nil
        }
        let player = thumbnailPlayer ?? ThumbnailMPVPlayer()
        thumbnailPlayer = player
        generationLock.lock()
        abortablePlayer = player
        let shutDownNow = isShutDown
        generationLock.unlock()
        if shutDownNow { player.abort() }
        guard player.loadVideo(options: options) else {
            failedLoadURL = options.url
            failedLoadTime = CFAbsoluteTimeGetCurrent()
            return nil
        }
        failedLoadURL = nil
        return player
    }

    /// Destroys the thumbnail instance once no request came for `idleTimeout`. Work queue only.
    private func scheduleIdleTeardown() {
        idleToken += 1
        let token = idleToken
        workQueue.asyncAfter(deadline: .now() + Self.idleTimeout) { [weak self] in
            guard let self, self.idleToken == token, self.thumbnailPlayer != nil else { return }
            print("📸 [ThumbnailGenerator] Idle: closing thumbnail instance")
            self.destroyThumbnailPlayer()
        }
    }

    /// Work queue only.
    private func destroyThumbnailPlayer() {
        idleToken += 1
        generationLock.lock()
        abortablePlayer = nil
        generationLock.unlock()
        thumbnailPlayer?.shutdown()
        thumbnailPlayer = nil
    }

    private var currentGeneration: Int {
        generationLock.lock()
        defer { generationLock.unlock() }
        return latestGeneration
    }

    private func requestThumbnail(at time: Double, latestOnly: Bool, completion: @escaping (NSImage?) -> Void) {
        guard isAvailable, currentVideoURL != nil else {
            print("⚠️ [ThumbnailGenerator] Thumbnails not available yet")
            DispatchQueue.main.async {
                completion(nil)
            }
            return
        }

        generationLock.lock()
        if latestOnly { latestGeneration += 1 }
        let generation = latestGeneration
        let requestFileGeneration = fileGeneration
        generationLock.unlock()

        // One at a time, off the main thread
        workQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }

            // A newer hover request replaced this one: its caller no longer waits for it.
            if latestOnly, self.currentGeneration != generation {
                return
            }
            if let cached = self.cache.get(at: time) {
                DispatchQueue.main.async {
                    completion(cached)
                }
                return
            }

            // Idle time counts from the end of the last piece of work.
            defer { self.scheduleIdleTeardown() }
            // Use our self-contained thumbnail player
            guard let player = self.preparedPlayer(), let image = player.generateThumbnail(at: time) else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }

            // Cache the thumbnail, unless another file loaded while it was made.
            // Checked and queued under the lock so a clear can't land in between.
            self.generationLock.lock()
            let sameFile = self.fileGeneration == requestFileGeneration
            if sameFile { self.cache.set(image: image, at: time) }
            self.generationLock.unlock()
            guard sameFile else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }

            // Return on main thread
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }
}
