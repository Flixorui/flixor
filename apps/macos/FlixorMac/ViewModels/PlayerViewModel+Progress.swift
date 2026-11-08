//
//  PlayerViewModel+Progress.swift
//  FlixorMac
//
//  Resume seek, progress reporting, Plex/Trakt scrobble, Stremio resume store and playback end
//

import Foundation

extension PlayerViewModel {
    func applyInitialSeekIfNeeded() {
        guard !initialSeekApplied else { return }
        guard duration > 0 else {
            // Duration not available yet, will be called again when duration is set
            return
        }

        initialSeekApplied = true

        var seconds = forcedResumeSeconds ?? TimeInterval(item.viewOffset ?? 0) / 1000.0
        forcedResumeSeconds = nil
        if seconds <= 2, let s = serverResumeSeconds { seconds = s }

        // If viewOffset is at or past the duration, definitely restart from beginning
        if seconds >= duration {
            print("🔄 [Player] Content fully watched (offset=\(Int(seconds))s >= duration=\(Int(duration))s) - restarting from beginning")
            seconds = 0
        }
        // If content is almost finished (within last 30s or >95% watched), restart from beginning
        else if duration > 0 {
            let progress = seconds / duration
            let secondsRemaining = duration - seconds
            if progress > 0.95 || secondsRemaining < 30 {
                print("🔄 [Player] Content almost finished (progress: \(Int(progress * 100))%, \(Int(secondsRemaining))s remaining) - restarting from beginning")
                seconds = 0
            }
        }

        // Only seek if we have a meaningful offset
        if seconds > 2 {
            seek(to: seconds)
            print("⏩ [Player] Resuming playback at \(Int(seconds))s")
        } else if seconds == 0 && (item.viewOffset ?? 0) > 0 {
            // Explicitly seeking to 0 after restarting fully watched content
            seek(to: 0)
            print("▶️ [Player] Starting from beginning")
        }
    }

    // MARK: - Progress Tracking

    func startProgressTracking() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.reportProgress()
                self?.updateTraktProgress()
            }
        }
    }

    func stopProgressTracking() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    // MARK: - Trakt Scrobbling

    func startTraktScrobble() {
        guard !scrobbleStarted else { return }
        scrobbleStarted = true

        let initialProgress = duration > 0 ? (currentTime / duration) * 100 : 0
        Task {
            if let streamPlaybackItem {
                await scrobbler.startScrobble(for: streamPlaybackItem, initialProgress: initialProgress)
            } else {
                await scrobbler.startScrobble(for: item, initialProgress: initialProgress)
            }
        }
    }

    private func updateTraktProgress() {
        guard duration > 0 else { return }
        let progress = (currentTime / duration) * 100
        scrobbler.updateProgress(progress)
    }

    // MARK: - Plex Progress Reporting

    func reportProgress() async {
        guard currentTime > 0, duration > 0 else { return }

        // Only report if progress changed significantly (more than 5 seconds)
        guard abs(currentTime - lastReportedProgress) > 5 else { return }

        lastReportedProgress = currentTime

        let progressPercent = Int((currentTime / duration) * 100)
        print("📊 [Player] Progress: \(Int(currentTime))s / \(Int(duration))s (\(progressPercent)%)")

        if let streamPlaybackItem {
            await saveStreamProgress(streamPlaybackItem, progressPercent: progressPercent)
            return
        }

        do {
            let ratingKey = item.id.replacingOccurrences(of: "plex:", with: "")
            struct ProgressRequest: Encodable {
                let ratingKey: String
                let time: Int
                let duration: Int
                let state: String
            }
            let request = ProgressRequest(
                ratingKey: ratingKey,
                time: Int(currentTime * 1000),
                duration: Int(duration * 1000),
                state: isPlaying ? "playing" : "paused"
            )
            let _: EmptyResponse = try await api.post("/api/plex/progress", body: request)
        } catch {
            print("⚠️ [Player] Failed to report progress: \(error)")
        }
    }

    /// Persists resume position plus a local watch-history entry for stream playback.
    /// The history entry is what makes Continue Watching work without Plex or Trakt.
    private func saveStreamProgress(
        _ streamItem: StreamPlaybackItem,
        progressPercent: Int,
        isFinal: Bool = false
    ) async {
        let positionMs = Int(currentTime * 1000)
        let durationMs = Int(duration * 1000)

        if progressPercent >= 90 {
            await resumeStore.remove(contentKey: streamItem.contentKey)
        } else {
            await resumeStore.save(
                ResumeState(
                    contentKey: streamItem.contentKey,
                    positionMs: positionMs,
                    durationMs: durationMs,
                    updatedAt: Date()
                )
            )
        }

        // recordProgress handles the completion threshold itself, so it also clears
        // finished titles out of the row.
        await LocalLibraryStore.shared.recordProgress(
            for: streamItem,
            positionMs: positionMs,
            durationMs: durationMs,
            force: isFinal
        )
    }

    func reportStopped() async {
        guard duration > 0 else { return }
        if let streamPlaybackItem {
            let progressPercent = Int((currentTime / duration) * 100)
            await saveStreamProgress(streamPlaybackItem, progressPercent: progressPercent, isFinal: true)
            return
        }
        do {
            let ratingKey = item.id.replacingOccurrences(of: "plex:", with: "")
            struct ProgressRequest: Encodable {
                let ratingKey: String
                let time: Int
                let duration: Int
                let state: String
            }
            let request = ProgressRequest(
                ratingKey: ratingKey,
                time: Int(currentTime * 1000),
                duration: Int(duration * 1000),
                state: "stopped"
            )
            let _: EmptyResponse = try await api.post("/api/plex/progress", body: request)
        } catch {
            print("⚠️ [Player] Failed to report stopped: \(error)")
        }
    }

    func handlePlaybackEnd() {
        isPlaying = false
        stopProgressTracking()
        disableDisplaySleep()

        if let streamPlaybackItem {
            Task {
                await resumeStore.remove(contentKey: streamPlaybackItem.contentKey)
                await scrobbler.stopScrobble(progress: 100)
            }
            // Auto-play the next episode of a series stream (same rules as Plex).
            if item.type == "episode" && nextEpisode != nil && UserDefaults.standard.autoPlayNext && !isResolvingNextEpisode {
                print("▶️ [Player] Auto-playing next stream episode...")
                playNextStreamEpisode()
            }
            return
        }

        // Mark as watched
        Task {
            do {
                let ratingKey = item.id.replacingOccurrences(of: "plex:", with: "")
                struct ScrobbleRequest: Encodable {
                    let ratingKey: String
                }
                let _: EmptyResponse = try await api.post("/api/plex/scrobble", body: ScrobbleRequest(ratingKey: ratingKey))
                print("✅ [Player] Marked as watched")
            } catch {
                print("⚠️ [Player] Failed to mark as watched: \(error)")
            }

            // Auto-play next episode if available and enabled in Player settings
            if item.type == "episode" && nextEpisode != nil && UserDefaults.standard.autoPlayNext {
                print("▶️ [Player] Auto-playing next episode...")
                // Small delay to ensure scrobble completes
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                await MainActor.run {
                    playNext()
                }
            }
        }
    }
}
