//
//  PlayerViewModel+Controls.swift
//  FlixorMac
//
//  Playback controls: play/pause, seek, volume, speed, performance overlay, chapters
//

import Foundation

extension PlayerViewModel {
    // MARK: - Playback Controls

    func togglePlayPause() {
        let progress = duration > 0 ? (currentTime / duration) * 100 : 0

        guard let mpv = mpvController else { return }
        if isPlaying {
            mpv.pause()
            isPlaying = false
            stopProgressTracking()
            disableDisplaySleep()
            // Pause Trakt scrobble
            Task { await scrobbler.pauseScrobble(progress: progress) }
        } else {
            mpv.play()
            isPlaying = true
            startProgressTracking()
            enableDisplaySleep()
            // Resume Trakt scrobble
            Task { await scrobbler.resumeScrobble(progress: progress) }
        }

        // Update Now Playing info
        updateNowPlayingInfo()
    }

    func seek(to time: TimeInterval) {
        guard let mpv = mpvController else { return }
        mpv.seek(to: time)
        print("✅ [MPV] Seeked to \(time)s")
        // One report once seeking settles: held arrow keys seek many times a second.
        // Now Playing is updated on the playback-restart that ends the seek.
        seekProgressReportTask?.cancel()
        seekProgressReportTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.seekProgressReportTask = nil
            await self.reportProgress()
        }
    }

    func skip(seconds: TimeInterval) {
        let position = mpvController?.currentTimePosition ?? currentTime
        let newTime = max(0, min(duration, position + seconds))
        seek(to: newTime)
    }

    func setVolume(_ volume: Float) {
        self.volume = volume
        mpvController?.setVolume(Double(volume * 100)) // MPV uses 0-100 scale
    }

    func toggleMute() {
        isMuted.toggle()
        mpvController?.setMute(isMuted)
    }

    // MARK: - Playback Speed

    /// Speeds the player UI offers (0.25x to 2x).
    static let playbackSpeedRange: ClosedRange<Float> = 0.25...2.0
    /// Preset speeds for menus.
    static let playbackSpeedPresets: [Float] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    /// Speed used while hold-to-speed-up is active.
    static let speedBoostRate: Float = 2.0

    /// Sets the playback speed, clamped to `playbackSpeedRange`. Ends an active
    /// speed boost without restoring (the new speed wins).
    func setPlaybackSpeed(_ speed: Float) {
        let clamped = min(Self.playbackSpeedRange.upperBound, max(Self.playbackSpeedRange.lowerBound, speed))
        speedBeforeBoost = nil
        isSpeedBoostActive = false
        applySpeed(clamped)
        print("⚡ [Player] Playback speed set to \(clamped)x")
    }

    /// Steps the speed by `delta` (e.g. +0.25 / -0.25), clamped to the range.
    func stepPlaybackSpeed(by delta: Float) {
        let base = isSpeedBoostActive ? (speedBeforeBoost ?? playbackSpeed) : playbackSpeed
        setPlaybackSpeed(((base + delta) * 100).rounded() / 100)
    }

    /// Hold-to-speed-up: temporarily plays at 2x until `endSpeedBoost()`.
    /// Repeated calls while active are ignored.
    func beginSpeedBoost() {
        guard !isSpeedBoostActive, mpvController != nil else { return }
        speedBeforeBoost = playbackSpeed
        isSpeedBoostActive = true
        applySpeed(Self.speedBoostRate)
    }

    /// Ends hold-to-speed-up and restores the speed from before the boost.
    func endSpeedBoost() {
        guard isSpeedBoostActive else { return }
        let restore = speedBeforeBoost ?? 1.0
        speedBeforeBoost = nil
        isSpeedBoostActive = false
        applySpeed(restore)
    }

    private func applySpeed(_ speed: Float) {
        playbackSpeed = speed
        mpvController?.setSpeed(Double(speed))
        updateNowPlayingInfo()
    }

    // MARK: - Performance Overlay

    func togglePerformanceOverlay() {
        showPerformanceOverlay.toggle()

        if showPerformanceOverlay {
            startPerformanceStatsPolling()
        } else {
            stopPerformanceStatsPolling()
        }
    }

    private func startPerformanceStatsPolling() {
        // Initial fetch
        updatePerformanceStats()

        performanceStatsTimer?.invalidate()
        performanceStatsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updatePerformanceStats()
            }
        }
    }

    func stopPerformanceStatsPolling() {
        performanceStatsTimer?.invalidate()
        performanceStatsTimer = nil
    }

    private func updatePerformanceStats() {
        guard let mpv = mpvController else { return }
        mpv.fetchPerformanceStats { [weak self] stats in
            self?.performanceStats = stats
        }
    }

    // MARK: - Chapter Navigation

    func loadChapters() {
        guard let mpv = mpvController else { return }
        chapters = mpv.getChapters()
        currentChapterIndex = mpv.getCurrentChapter()
        print("📖 [Player] Loaded \(chapters.count) chapters")
    }

    func seekToChapter(_ index: Int) {
        guard let mpv = mpvController, index >= 0, index < chapters.count else { return }
        mpv.seekToChapter(index)
        currentChapterIndex = index
        print("📖 [Player] Seeking to chapter \(index + 1): \(chapters[index].displayName)")
    }

    func previousChapter() {
        guard let mpv = mpvController else { return }
        mpv.previousChapter()
        // Update current chapter index after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.currentChapterIndex = mpv.getCurrentChapter()
        }
    }

    func nextChapter() {
        guard let mpv = mpvController else { return }
        mpv.nextChapter()
        // Update current chapter index after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.currentChapterIndex = mpv.getCurrentChapter()
        }
    }
}
