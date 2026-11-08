//
//  PlayerViewModel+SubtitleEngine.swift
//  FlixorMac
//
//  Subtitle engine: SDH filtering, subtitle cues + cue-based sync, and the
//  OpenSubtitles-hash lookup that asks subtitle addons for release-matched subtitles.
//

import Foundation

extension PlayerViewModel {
    // MARK: - SDH

    /// Strip hearing-impaired annotations ([MUSIC], (laughs), "JOHN:") from text
    /// subtitles via mpv `sub-filter-sdh`. Saved per profile; applies to cues
    /// decoded after the change.
    func setSubtitleFilterSDH(_ enabled: Bool) {
        subtitleFilterSDH = enabled
        UserDefaults.standard.subtitleFilterSDH = enabled
        mpvController?.setSubtitleFilterSDH(enabled)
    }

    // MARK: - Cues

    /// Max cues kept in `recentSubtitleCues`.
    private static let recentCueLimit = 50

    /// Reloads `subtitleCues` / `subtitleCueSource` for the selected subtitle track.
    /// External tracks (addon subtitles, sidecar files) are read and parsed off the
    /// main thread (SRT, WebVTT, ASS/SSA); embedded tracks fall back to cues
    /// observed while playing (`.observedOnly`). Called on track changes.
    func refreshSubtitleCues() {
        guard let mpv = mpvController else { return }
        let sid = mpv.getCurrentSubtitleTrack() ?? 0
        let track = sid > 0 ? mpv.getSubtitleTracks().first(where: { $0.id == sid }) : nil

        if subtitleCueTrackId != track?.id {
            // Cues shown by the previous track don't belong to this one
            recentSubtitleCues = []
            subtitleCueTrackId = track?.id
        }

        guard let track else {
            subtitleCueLoadTask?.cancel()
            subtitleCueFilePath = nil
            subtitleCues = []
            subtitleCueSource = .none
            return
        }

        guard track.external, let file = track.externalFilename, !file.isEmpty else {
            subtitleCueLoadTask?.cancel()
            subtitleCueFilePath = nil
            subtitleCues = []
            subtitleCueSource = .observedOnly
            return
        }

        if file == subtitleCueFilePath, !subtitleCues.isEmpty {
            subtitleCueSource = .fullFile
            return
        }
        subtitleCueFilePath = file
        subtitleCueLoadTask?.cancel()
        subtitleCueLoadTask = Task { [weak self] in
            let cues = await Self.loadCues(from: file)
            guard let self, !Task.isCancelled, self.subtitleCueFilePath == file else { return }
            self.subtitleCues = cues
            self.subtitleCueSource = cues.isEmpty ? .observedOnly : .fullFile
        }
    }

    /// Reads and parses a subtitle file (local path, file:// or http(s) URL) off the main actor.
    private nonisolated static func loadCues(from file: String) async -> [SubtitleCue] {
        let url: URL? = {
            if file.hasPrefix("http://") || file.hasPrefix("https://") || file.hasPrefix("file://") {
                return URL(string: file)
            }
            return URL(fileURLWithPath: file)
        }()
        guard let url else { return [] }
        let data: Data?
        if url.isFileURL {
            data = await Task.detached(priority: .utility) { try? Data(contentsOf: url) }.value
        } else {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            data = try? await URLSession.shared.data(for: request).0
        }
        guard let data, data.count < 20_000_000 else { return [] }
        return await Task.detached(priority: .utility) {
            guard let text = SubtitleCueParser.decode(data) else { return [] }
            return SubtitleCueParser.parse(text, formatHint: url.pathExtension)
        }.value
    }

    /// Records a cue mpv just showed (embedded tracks expose no cue list).
    func recordShownSubtitleCue(_ shown: MPVShownSubtitleCue) {
        // mpv's sub-start may be in the subtitle timeline or already shifted by
        // sub-delay (depends on the mpv version). The cue appeared "now", so the
        // value closer to the playback time tells which one it is.
        let delay = shown.subDelay
        let inPlaybackTimeline = delay != 0
            && abs(shown.start - shown.playbackTime) < abs(shown.start + delay - shown.playbackTime)
        let start = inPlaybackTimeline ? shown.start - delay : shown.start
        let end = shown.end.map { inPlaybackTimeline ? $0 - delay : $0 } ?? start + 2
        let text = SubtitleCueParser.cleanMarkup(shown.text)
        guard !text.isEmpty else { return }

        if let last = recentSubtitleCues.last, last.text == text, abs(last.start - start) < 0.05 { return }
        var cues = recentSubtitleCues.filter { !(abs($0.start - start) < 0.05 && $0.text == text) }
        cues.append(SubtitleCue(start: start, end: end, text: text))
        cues.sort { $0.start < $1.start }
        recentSubtitleCues = Array(cues.suffix(Self.recentCueLimit))
    }

    /// Position in the subtitle's own timeline that is on screen now.
    var subtitleTimelinePosition: TimeInterval {
        currentTime - subtitleDelay
    }

    /// Cues around the current playback position for the sync UI: up to `before`
    /// cues that started before now and `after` upcoming cues, in time order.
    /// With `.observedOnly` (embedded tracks) only already-shown cues are returned.
    func nearbySubtitleCues(before: Int = 5, after: Int = 5) -> [SubtitleCue] {
        let position = subtitleTimelinePosition
        switch subtitleCueSource {
        case .fullFile:
            let split = firstCueIndex(startingAfter: position)
            let lower = max(0, split - before)
            let upper = min(subtitleCues.count, split + after)
            return Array(subtitleCues[lower..<upper])
        case .observedOnly:
            return Array(recentSubtitleCues.filter { $0.start <= position + 0.5 }.suffix(before))
        case .none:
            return []
        }
    }

    /// The cue on screen now, if known.
    var activeSubtitleCue: SubtitleCue? {
        let position = subtitleTimelinePosition
        let pool = subtitleCueSource == .fullFile ? subtitleCues : recentSubtitleCues
        return pool.last { $0.start <= position && position < $0.end }
    }

    /// Cue-based sync: sets `sub-delay` so the cue starting at `cueStart` (subtitle
    /// timeline, i.e. `SubtitleCue.start`) appears at the current playback position.
    /// Pick the line that is being spoken right now.
    func syncSubtitle(cueStart: TimeInterval) {
        let delay = min(3600, max(-3600, currentTime - cueStart))
        setSubtitleDelay((delay * 1000).rounded() / 1000)
    }

    /// Convenience for `syncSubtitle(cueStart: cue.start)`.
    func syncSubtitle(to cue: SubtitleCue) {
        syncSubtitle(cueStart: cue.start)
    }

    /// Index of the first cue whose start is after `position` (binary search).
    private func firstCueIndex(startingAfter position: TimeInterval) -> Int {
        var low = 0
        var high = subtitleCues.count
        while low < high {
            let mid = (low + high) / 2
            if subtitleCues[mid].start <= position { low = mid + 1 } else { high = mid }
        }
        return low
    }

    // MARK: - OpenSubtitles hash lookup

    /// For addon streams: once playback started, compute the OpenSubtitles hash
    /// (or take it from the stream's behaviorHints) and ask subtitle addons again
    /// with videoHash/videoSize/filename. New (release-matched) results are added
    /// to `availableExternalSubtitleOptions`. Runs in the background; skipped
    /// silently when the server doesn't support range requests.
    func startSubtitleHashLookupIfNeeded() {
        guard sourceKind == .stream,
              let playback = streamPlaybackItem,
              UserDefaults.standard.stremioSubtitleAddonsEnabled,
              subtitleHashLookupURL != playback.uri,
              let identity = Self.subtitleIdentity(for: playback) else { return }
        subtitleHashLookupURL = playback.uri
        subtitleHashTask?.cancel()

        let hints = availableStremioSources.first(where: { $0.id == currentStremioSourceId })?.behaviorHints
        let headers = Dictionary(playback.headers.map { ($0.name, $0.value) }, uniquingKeysWith: { first, _ in first })
        let uri = playback.uri

        subtitleHashTask = Task { [weak self] in
            var hash = hints?.videoHash
            var size = hints?.videoSize.map(Int64.init)
            if hash == nil || size == nil, let url = URL(string: uri) {
                guard let computed = await OpenSubtitlesHasher.hash(url: url, headers: headers) else {
                    AppLogger.shared.info("[Subtitles] Video hash unavailable (no range support or request failed)")
                    return
                }
                hash = computed.hash
                size = computed.size
            }
            guard !Task.isCancelled, let hash, let size else { return }

            let filename = hints?.filename ?? URL(string: uri).flatMap { url -> String? in
                let name = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
                return url.pathExtension.isEmpty ? nil : name
            }
            let extra = StremioService.SubtitleRequestExtra(videoHash: hash, videoSize: size, filename: filename)
            let fetched = await StremioService.shared.getSubtitles(identity: identity, extra: extra)
            guard !Task.isCancelled else { return }
            self?.mergeHashMatchedSubtitles(fetched, forStreamURL: uri)
        }
    }

    private func mergeHashMatchedSubtitles(_ fetched: [StremioSubtitleCandidate], forStreamURL uri: String) {
        guard streamPlaybackItem?.uri == uri else { return }
        let known = Set(availableExternalSubtitleOptions.map(\.url))
        let added = fetched.filter { !known.contains($0.url) }
        AppLogger.shared.info("[Subtitles] Hash lookup finished", data: ["results": fetched.count, "new": added.count])
        guard !added.isEmpty else { return }
        // Hash-matched results first: they are synced to this exact release
        availableExternalSubtitleOptions = added + availableExternalSubtitleOptions

        // Fill a gap only: auto-select on, nothing shown, and no remembered "off" for this title
        let service = TrackPreferenceService.shared
        let rememberedOff = service.getSubtitlePreference(for: item.id) == "none"
            || (trackPreferenceSeriesId.flatMap { service.getSeriesSubtitlePreference(for: $0) } == "none")
        guard UserDefaults.standard.enableSubtitleAutoSelect,
              !subtitlesTurnedOff,
              !rememberedOff,
              selectedExternalSubtitleId == nil,
              (currentSubtitleTrackId ?? 0) <= 0,
              !UserDefaults.standard.preferredSubtitleLanguage.trimmingCharacters(in: .whitespaces).isEmpty,
              let match = preferredExternalSubtitleCandidate(in: added) else { return }
        Task { [weak self] in
            try? await self?.attachExternalSubtitle(match, remember: false)
        }
    }

    /// Rebuilds the addon content identity from a stream's content key
    /// ("movie:<id>" or "series:<id>:<season>:<episode>").
    static func subtitleIdentity(for playback: StreamPlaybackItem) -> StremioContentIdentity? {
        let key = playback.contentKey
        if key.hasPrefix("movie:") {
            let baseId = String(key.dropFirst("movie:".count))
            guard !baseId.isEmpty else { return nil }
            return StremioContentIdentity(
                requestType: StremioRequestType.movie.rawValue, baseId: baseId, requestId: baseId,
                imdbId: playback.imdbId, tmdbId: playback.tmdbId, seasonNumber: nil, episodeNumber: nil, source: "player"
            )
        }
        guard key.hasPrefix("series:") else { return nil }
        var parts = key.dropFirst("series:".count).split(separator: ":").map(String.init)
        guard parts.count >= 3, let episode = Int(parts.removeLast()), let season = Int(parts.removeLast()) else { return nil }
        let baseId = parts.joined(separator: ":")
        return StremioContentIdentity(
            requestType: StremioRequestType.series.rawValue, baseId: baseId, requestId: "\(baseId):\(season):\(episode)",
            imdbId: playback.imdbId, tmdbId: playback.tmdbId, seasonNumber: season, episodeNumber: episode, source: "player"
        )
    }
}
