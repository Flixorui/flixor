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
        Task { @MainActor [weak self] in
            await self?.reportProgress()
            self?.updateNowPlayingInfo()
        }
    }

    func skip(seconds: TimeInterval) {
        let newTime = max(0, min(duration, currentTime + seconds))
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

    func setPlaybackSpeed(_ speed: Float) {
        playbackSpeed = speed
        mpvController?.setSpeed(Double(speed))
        print("⚡ [Player] Playback speed set to \(speed)x")
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

        // Poll every 500ms
        performanceStatsTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
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
        performanceStats = mpv.getPerformanceStats()
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
