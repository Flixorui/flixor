//
//  PlayerViewModel+Markers.swift
//  FlixorMac
//
//  Intro/credits markers, auto-skip, next episode lookup, countdown and episode navigation
//

import Foundation

extension PlayerViewModel {
    func fetchMarkers(ratingKey: String) async {
        print("🎯 [Player] fetchMarkers() CALLED for ratingKey: \(ratingKey)")
        do {
            print("🌐 [Player] Calling api.getPlexMarkers...")
            let plexMarkers = try await api.getPlexMarkers(ratingKey: ratingKey)
            print("✅ [Player] Got \(plexMarkers.count) raw markers from API")

            // Debug: Print raw marker data
            for (index, m) in plexMarkers.enumerated() {
                print("   [Raw \(index)] type=\(m.type ?? "nil"), start=\(m.startTimeOffset ?? -1), end=\(m.endTimeOffset ?? -1)")
            }

            // Map to PlayerMarker (ensure id and ms fields present)
            let mapped: [PlayerMarker] = plexMarkers.compactMap { m in
                guard let type = m.type?.lowercased(),
                      let s = m.startTimeOffset, let e = m.endTimeOffset else { return nil }
                // Only care about intro/credits
                guard type == "intro" || type == "credits" else { return nil }
                // Convert Int id to String (Plex API returns Int)
                let id = m.id.map { String($0) } ?? "\(type)-\(s)-\(e)"
                return PlayerMarker(id: id, type: type, startTimeOffset: s, endTimeOffset: e)
            }
            self.plexMarkersSnapshot = mapped
            // Same as `markers = mapped` unless community segments were already loaded.
            rebuildMarkersFromSources()
            let creditsMarker = mapped.first { $0.type == "credits" }
            let introMarker = mapped.first { $0.type == "intro" }
            print("🎬 [Player] Markers loaded: \(mapped.count) total")
            if let intro = introMarker {
                print("   📍 INTRO: \(intro.startTimeOffset)ms - \(intro.endTimeOffset)ms (\(TimeInterval(intro.startTimeOffset)/1000.0)s - \(TimeInterval(intro.endTimeOffset)/1000.0)s)")
            }
            if let credits = creditsMarker {
                print("   📍 CREDITS: \(credits.startTimeOffset)ms - \(credits.endTimeOffset)ms (\(TimeInterval(credits.startTimeOffset)/1000.0)s - \(TimeInterval(credits.endTimeOffset)/1000.0)s)")
            }
            if mapped.isEmpty {
                print("   ⚠️ No intro/credits markers found for this content")
            }
        } catch {
            print("❌ [Player] Failed to fetch markers: \(error)")
            print("❌ [Player] Error details: \(String(describing: error))")
            self.plexMarkersSnapshot = []
            rebuildMarkersFromSources()
        }
        // Plex items lacking intro or credits markers: look up community segments in the background.
        loadCommunitySkipSegmentsForPlexIfNeeded(ratingKey: ratingKey)
    }

    func fetchNextEpisode(parentRatingKey: String, currentRatingKey: String) async {
        do {
            // Fetch all episodes in the season
            struct EpisodeResponse: Decodable {
                let Metadata: [EpisodeMetadata]?
            }
            let response: EpisodeResponse = try await api.get("/api/plex/dir/library/metadata/\(parentRatingKey)/children")
            let episodes = response.Metadata ?? []
            self.seasonEpisodes = episodes

            // Find next episode
            if let currentIndex = episodes.firstIndex(where: { $0.ratingKey == currentRatingKey }),
               currentIndex + 1 < episodes.count {
                self.nextEpisode = episodes[currentIndex + 1]
                print("📺 [Player] Next episode: \(self.nextEpisode?.title ?? "nil")")
            } else {
                self.nextEpisode = nil
                print("📺 [Player] No next episode")
            }
        } catch {
            print("⚠️ [Player] Failed to fetch next episode: \(error)")
            self.nextEpisode = nil
        }
    }

    func updateCurrentMarker() {
        refreshCommunityMarkersIfNeeded()
        guard !markers.isEmpty else {
            if currentMarker != nil {
                print("⚠️ [Player] Clearing marker - no markers available")
                currentMarker = nil
                cancelAutoSkip()
            }
            return
        }

        let currentMs = Int(currentTime * 1000)

        // Skippable types: intro, credits (Plex + community), recap, preview (community).
        let newMarker = markers.first { marker in
            marker.isSkippable &&
            currentMs >= marker.startTimeOffset && currentMs <= marker.endTimeOffset
        }

        // Only update if changed to avoid unnecessary UI updates
        if newMarker?.id != currentMarker?.id {
            if let marker = newMarker {
                print("🎬 [Player] ✅ Marker ACTIVE: \(marker.type) at \(currentMs)ms (range: \(marker.startTimeOffset)-\(marker.endTimeOffset))")
                // Trigger auto-skip if enabled and not already triggered for this marker
                triggerAutoSkipIfEnabled(for: marker)
            } else if currentMarker != nil {
                print("🎬 [Player] ❌ Marker ended at \(currentMs)ms")
                cancelAutoSkip()
            }
            currentMarker = newMarker
        }
    }

    // MARK: - Auto-Skip

    private func triggerAutoSkipIfEnabled(for marker: PlayerMarker) {
        guard !autoSkipTriggeredMarkers.contains(marker.id) else {
            print("⏭️ [Player] Marker \(marker.id) already triggered, skipping auto-skip")
            return
        }

        let defaults = UserDefaults.standard
        let skipIntro = defaults.skipIntroAutomatically
        let skipCredits = defaults.skipCreditsAutomatically
        let skipRecap = defaults.skipRecapAutomatically
        let shouldAutoSkip = (marker.type == "intro" && skipIntro) ||
                             (marker.type == "credits" && skipCredits) ||
                             (marker.type == SkipSegmentType.recap.markerType && skipRecap)

        print("⏭️ [Player] Auto-skip check: type=\(marker.type), skipIntro=\(skipIntro), skipCredits=\(skipCredits), shouldAutoSkip=\(shouldAutoSkip)")

        guard shouldAutoSkip else { return }

        let delay = defaults.autoSkipDelay
        print("⏭️ [Player] Starting auto-skip countdown for \(marker.type): \(delay)s")

        // Start countdown
        autoSkipCountdown = delay
        autoSkipTimer?.invalidate()

        // Countdown timer (fires every second)
        autoSkipTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            Task { @MainActor in
                guard let countdown = self.autoSkipCountdown, countdown > 0 else {
                    timer.invalidate()
                    return
                }

                if countdown == 1 {
                    // Time to skip
                    self.performAutoSkip(marker)
                } else {
                    self.autoSkipCountdown = countdown - 1
                }
            }
        }
    }

    private func performAutoSkip(_ marker: PlayerMarker) {
        // Verify we're still in the marker region
        guard currentMarker?.id == marker.id else {
            cancelAutoSkip()
            return
        }

        autoSkipTriggeredMarkers.insert(marker.id)
        cancelAutoSkip()
        skipMarker()
        print("⏭️ [Player] Auto-skipped \(marker.type)")
    }

    func cancelAutoSkip() {
        autoSkipTimer?.invalidate()
        autoSkipTimer = nil
        autoSkipCountdown = nil
    }

    /// Cancel auto-skip when user manually skips or interacts
    func userCancelledAutoSkip() {
        if let marker = currentMarker {
            autoSkipTriggeredMarkers.insert(marker.id)
        }
        cancelAutoSkip()
    }

    /// Find credits chapter by name (fallback when no Plex marker exists)
    private func findCreditsChapter() -> MPVChapter? {
        let creditsKeywords = ["credits", "end credits", "ending credits"]

        return chapters.first { chapter in
            guard let title = chapter.title?.lowercased() else { return false }
            return creditsKeywords.contains { title.contains($0) }
        }
    }

    /// Markers, chapters, duration or the next episode changed: rebuild the trigger
    /// point and check again on the next position update.
    func invalidateNextEpisodeTrigger() {
        nextEpisodeTrigger = nil
        lastNextEpisodeCheckTime = nil
    }

    /// Priority: 1. Credits marker, 2. Credits chapter, 3. Time-based fallback.
    private func makeNextEpisodeTrigger(fallbackSeconds: TimeInterval) -> NextEpisodeTriggerPoint {
        let creditsMarker = markers.first { $0.type == "credits" }
        let bufferSeconds: TimeInterval = 3.0  // Show overlay 3 seconds before trigger point
        let triggerStart: TimeInterval
        let triggerSource: String

        if let marker = creditsMarker, let scene = markers.first(where: {
            $0.segmentType == .postCredits && $0.startTimeOffset >= marker.startTimeOffset
        }) {
            // Community data knows a post-credits scene: don't cut it off, trigger after it.
            triggerStart = max(0, TimeInterval(scene.endTimeOffset) / 1000.0 - bufferSeconds)
            triggerSource = "POST-CREDITS scene end (3s early) at \(triggerStart)s"
        } else if let marker = creditsMarker {
            // Priority 1: Use credits marker (convert ms to seconds, minus buffer)
            triggerStart = max(0, TimeInterval(marker.startTimeOffset) / 1000.0 - bufferSeconds)
            triggerSource = "CREDITS marker (3s early) at \(triggerStart)s"
        } else if let chapter = findCreditsChapter() {
            // Priority 2: Use credits chapter start time (minus buffer)
            triggerStart = max(0, chapter.time - bufferSeconds)
            triggerSource = "CREDITS chapter '\(chapter.title ?? "Credits")' (3s early) at \(triggerStart)s"
        } else {
            // Priority 3: Use fallback (X seconds before end)
            triggerStart = max(0, duration - fallbackSeconds)
            triggerSource = "FALLBACK (\(Int(fallbackSeconds))s before end) at \(triggerStart)s"
        }
        return NextEpisodeTriggerPoint(start: triggerStart, source: triggerSource, fallbackSeconds: fallbackSeconds)
    }

    func updateNextEpisodeCountdown() {
        if item.type != "episode" {
            if nextEpisodeCountdown != nil { nextEpisodeCountdown = nil }
            return
        }
        if nextEpisode == nil {
            if nextEpisodeCountdown != nil { nextEpisodeCountdown = nil }
            return
        }
        if duration <= 0 {
            if nextEpisodeCountdown != nil { nextEpisodeCountdown = nil }
            return
        }
        // About once a second of playback; a seek or a changed input checks at once.
        if let last = lastNextEpisodeCheckTime, abs(currentTime - last) < 1.0 { return }
        lastNextEpisodeCheckTime = currentTime

        let defaults = UserDefaults.standard
        // "Auto-Play Next" off: no automatic countdown. The Next Episode
        // button in the controls stays available for manual use.
        if !defaults.autoPlayNext {
            if nextEpisodeCountdown != nil || nextEpisodeCountdownTimer != nil { cancelCountdown() }
            return
        }

        let fallbackSeconds = TimeInterval(defaults.creditsCountdownFallback)
        let trigger: NextEpisodeTriggerPoint
        if let cached = nextEpisodeTrigger, cached.fallbackSeconds == fallbackSeconds {
            trigger = cached
        } else {
            trigger = makeNextEpisodeTrigger(fallbackSeconds: fallbackSeconds)
            nextEpisodeTrigger = trigger
        }
        let triggerStart = trigger.start

        // Addon streams: look up the next episode's source a minute ahead.
        if sourceKind == .stream && currentTime >= triggerStart - 60 {
            prefetchNextEpisodeSourceIfNeeded()
        }

        if currentTime >= triggerStart {
            // Start 5-second countdown timer if not already running. Not after the
            // user cancelled it, once the player closed, or during a source lookup.
            if nextEpisodeCountdown == nil && nextEpisodeCountdownTimer == nil,
               !nextEpisodeCountdownDismissed, !isResolvingNextEpisode,
               mpvController?.isShutDown == false {
                print("🎬 [Countdown] TRIGGERED via \(trigger.source)! Starting 5s countdown")
                startNextEpisodeCountdown()
            }
        } else {
            // Seeked back before the trigger point: the countdown may run again later.
            nextEpisodeCountdownDismissed = false
            if nextEpisodeCountdown != nil {
                cancelCountdown()
            }
        }
    }

    func skipMarker() {
        guard let marker = currentMarker else { return }
        // Mark as triggered so it won't auto-skip again if user seeks back
        autoSkipTriggeredMarkers.insert(marker.id)
        cancelAutoSkip()
        let skipToTime = TimeInterval(marker.endTimeOffset) / 1000.0 + 1.0
        seek(to: skipToTime)
        print("⏭️ [Player] Skipped \(marker.type) to \(skipToTime)s")
    }

    // MARK: - Next Episode

    func playNext() {
        guard let next = nextEpisode else { return }
        if sourceKind == .stream {
            playNextStreamEpisode()
            return
        }

        // EOF, the countdown and the Next button can all land here: navigate once,
        // and never from a player that has already closed.
        guard !didNavigateToEpisode, mpvController?.isShutDown == false else { return }
        didNavigateToEpisode = true

        // Create MediaItem from next episode, preserving mediaIndex for version consistency
        let nextItem = MediaItem(
            id: "plex:\(next.ratingKey)",
            title: next.title,
            type: "episode",
            thumb: next.thumb,
            art: nil,
            year: nil,
            rating: nil,
            duration: nil,
            viewOffset: nil,
            summary: next.summary,
            grandparentTitle: item.grandparentTitle,
            grandparentThumb: item.grandparentThumb,
            grandparentArt: item.grandparentArt,
            grandparentRatingKey: item.grandparentRatingKey,
            parentIndex: next.parentIndex,
            index: next.index,
            parentRatingKey: nil,
            parentTitle: nil,
            leafCount: nil,
            viewedLeafCount: nil,
            mediaIndex: item.mediaIndex  // Preserve version selection
        )

        print("▶️ [Player] Play next: \(next.title) (mediaIndex: \(item.mediaIndex ?? 0))")

        // Stop current playback
        stopPlayback()

        // Call navigation callback
        onPlayNext?(.plex(nextItem))
    }

    /// Play a specific episode from the season (e.g., from episode selector)
    func playEpisode(_ episode: EpisodeMetadata) {
        if sourceKind == .stream {
            guard let season = episode.parentIndex, let number = episode.index else { return }
            playStreamEpisode(season: season, episode: number, episodeTitle: episode.title)
            return
        }
        guard !didNavigateToEpisode, mpvController?.isShutDown == false else { return }
        didNavigateToEpisode = true

        let episodeItem = MediaItem(
            id: "plex:\(episode.ratingKey)",
            title: episode.title,
            type: "episode",
            thumb: episode.thumb,
            art: nil,
            year: nil,
            rating: nil,
            duration: nil,
            viewOffset: nil,
            summary: episode.summary,
            grandparentTitle: item.grandparentTitle,
            grandparentThumb: item.grandparentThumb,
            grandparentArt: item.grandparentArt,
            grandparentRatingKey: item.grandparentRatingKey,
            parentIndex: episode.parentIndex,
            index: episode.index,
            parentRatingKey: nil,
            parentTitle: nil,
            leafCount: nil,
            viewedLeafCount: nil,
            mediaIndex: item.mediaIndex  // Preserve version selection
        )

        print("▶️ [Player] Play episode: S\(episode.parentIndex ?? 0)E\(episode.index ?? 0) \(episode.title) (mediaIndex: \(item.mediaIndex ?? 0))")

        // Stop current playback
        stopPlayback()

        // Call navigation callback
        onPlayNext?(.plex(episodeItem))
    }

    func cancelCountdown() {
        nextEpisodeCountdownTimer?.invalidate()
        nextEpisodeCountdownTimer = nil
        nextEpisodeCountdown = nil
    }

    /// The user cancelled the countdown: it must not start again for this item.
    func userCancelledCountdown() {
        nextEpisodeCountdownDismissed = true
        cancelCountdown()
    }

    private func startNextEpisodeCountdown() {
        nextEpisodeCountdown = 5
        nextEpisodeCountdownTimer?.invalidate()
        nextEpisodeCountdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            Task { @MainActor in
                guard let countdown = self.nextEpisodeCountdown, countdown > 0 else {
                    timer.invalidate()
                    self.nextEpisodeCountdownTimer = nil
                    return
                }
                let newCount = countdown - 1
                self.nextEpisodeCountdown = newCount
                if newCount == 0 {
                    timer.invalidate()
                    self.nextEpisodeCountdownTimer = nil
                    self.playNext()
                }
            }
        }
    }
}
