//
//  PlayerViewModel+XRay.swift
//  FlixorMac
//
//  Starts and stops X-Ray (who's in each scene) with the playing file. Only with AI
//  Features and X-Ray switched on, and never for full discs or Plex transcodes.
//

import Foundation

extension PlayerViewModel {
    /// Called when a file has loaded. Keeps X-Ray if it's the same title, else restarts it.
    func startXRayIfNeeded() {
        guard AISettings.shared.isXRayActive, mpvController != nil else {
            print("🎭 [XRay] off (AI \(AISettings.shared.isEnabled), X-Ray \(AISettings.shared.xrayEnabled))")
            stopXRay()
            return
        }
        // A full disc (30-90 GB) or a transcode session can't take a second reader.
        if sourceKind == .stream, isDiscSource(uri: streamPlaybackItem?.uri) {
            print("🎭 [XRay] off for a full disc")
            stopXRay(); return
        }
        if sourceKind == .plex, isTranscoding || currentURLIsHLS {
            print("🎭 [XRay] off for a Plex transcode")
            stopXRay(); return
        }

        let itemId = item.id
        xrayIdentityTask?.cancel()
        xrayIdentityTask = Task { [weak self] in
            guard let self, let identity = await self.xrayIdentity() else {
                print("🎭 [XRay] no TMDB match for this title")
                return
            }
            guard !Task.isCancelled, self.item.id == itemId else { return }
            print("🎭 [XRay] title \(identity.key)")
            if let current = self.xray, current.identity == identity { return }
            // Only the old controller: stopXRay() would cancel this task too.
            self.xray?.stop()
            self.xray = nil
            // Durations arrive just after the file loads.
            var waited = 0
            while self.duration <= 0, waited < 40, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                waited += 1
            }
            guard !Task.isCancelled, self.duration > 0 else {
                print("🎭 [XRay] no duration yet; not started")
                return
            }
            let controller = XRayController(identity: identity, player: self, wholeFile: self.sourceKind != .stream)
            self.xray = controller
            controller.start(duration: self.duration)
        }
    }

    func stopXRay() {
        xrayIdentityTask?.cancel()
        xrayIdentityTask = nil
        xray?.stop()
        xray = nil
    }

    /// AI or X-Ray was switched on or off in Settings while playing.
    func refreshXRayForSettings() {
        if AISettings.shared.isXRayActive {
            if xray == nil, !isLoading { startXRayIfNeeded() }
        } else {
            stopXRay()
        }
    }

    private func xrayIdentity() async -> XRayIdentity? {
        let resolver = MediaIdentityResolver.shared
        if let stream = streamPlaybackItem {
            if let series = StreamSeriesRef(item: stream) {
                var tmdb = series.tmdbId
                if tmdb == nil, let imdb = series.imdbId { tmdb = await resolver.tmdbId(imdbId: imdb, isShow: true) }
                guard let tmdb else { return nil }
                return XRayIdentity(tmdbId: tmdb, isMovie: false, season: series.season, episode: series.episode)
            }
            guard stream.mediaType == .movie else { return nil }
            let baseId = stream.contentKey.hasPrefix("movie:") ? String(stream.contentKey.dropFirst(6)) : ""
            var tmdb = stream.tmdbId ?? (baseId.hasPrefix("tmdb:") ? Int(baseId.dropFirst(5)) : nil)
            let imdb = stream.imdbId ?? (baseId.hasPrefix("tt") ? baseId : nil)
            if tmdb == nil, let imdb { tmdb = await resolver.tmdbId(imdbId: imdb, isShow: false) }
            guard let tmdb else { return nil }
            return XRayIdentity(tmdbId: tmdb, isMovie: true, season: nil, episode: nil)
        }
        guard let found = await resolver.tmdbIdentity(for: item) else { return nil }
        if found.mediaType == .movie {
            return XRayIdentity(tmdbId: found.id, isMovie: true, season: nil, episode: nil)
        }
        return XRayIdentity(tmdbId: found.id, isMovie: false, season: item.parentIndex, episode: item.index)
    }
}
