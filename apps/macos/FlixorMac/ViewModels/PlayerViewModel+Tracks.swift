//
//  PlayerViewModel+Tracks.swift
//  FlixorMac
//
//  Audio/subtitle tracks, external (Stremio) subtitles, remembered track preferences, subtitle styling and sync
//

import Foundation

extension PlayerViewModel {
    // MARK: - Subtitle Styling

    func setSubtitleFontSize(_ size: Int) {
        subtitleFontSize = size
        UserDefaults.standard.set(size, forKey: "subtitleFontSize")
        mpvController?.setSubtitleFontSize(size)
    }

    func setSubtitleBorderSize(_ size: Double) {
        subtitleBorderSize = size
        UserDefaults.standard.set(size, forKey: "subtitleBorderSize")
        mpvController?.setSubtitleBorderSize(size)
    }

    func setSubtitleBackgroundOpacity(_ opacity: Double) {
        subtitleBackgroundOpacity = opacity
        UserDefaults.standard.set(opacity, forKey: "subtitleBackgroundOpacity")
        // Convert opacity (0-1) to hex alpha (00-FF) with black background
        let alpha = Int(opacity * 255)
        let hexColor = String(format: "000000%02X", alpha)
        mpvController?.setSubtitleBackgroundColor(hexColor)
    }

    func applySubtitleStyling() {
        guard let mpv = mpvController else { return }
        mpv.setSubtitleFontSize(subtitleFontSize)
        mpv.setSubtitleBorderSize(subtitleBorderSize)
        let alpha = Int(subtitleBackgroundOpacity * 255)
        let hexColor = String(format: "000000%02X", alpha)
        mpv.setSubtitleBackgroundColor(hexColor)
    }

    // MARK: - Audio/Subtitle Sync

    func setAudioDelay(_ seconds: Double) {
        audioDelay = seconds
        mpvController?.setAudioDelay(seconds)
        print("🔊 [Player] Audio delay set to \(seconds)s")
    }

    func setSubtitleDelay(_ seconds: Double) {
        subtitleDelay = seconds
        mpvController?.setSubtitleDelay(seconds)
        print("💬 [Player] Subtitle delay set to \(seconds)s")
    }

    func resetSyncOffsets() {
        setAudioDelay(0)
        setSubtitleDelay(0)
    }

    // MARK: - Track Management (MPV only)

    /// Load available audio and subtitle tracks (MPV only)
    func loadTracks() {
        guard let mpv = mpvController else {
            return
        }

        availableAudioTracks = mpv.getAudioTracks()
        let subtitleTracks = mpv.getSubtitleTracks()
        availableSubtitleTracks = subtitleTracks.filter { !$0.external }
        currentAudioTrackId = mpv.getCurrentAudioTrack()
        currentSubtitleTrackId = mpv.getCurrentSubtitleTrack()

        print("🎵 [Player] Loaded \(availableAudioTracks.count) audio tracks")
        print("💬 [Player] Loaded \(subtitleTracks.count) subtitle tracks")

        if sourceKind == .stream {
            print("💬 [Player] Stream subtitle options: internal=\(availableSubtitleTracks.count), external=\(availableExternalSubtitleOptions.count)")
            return
        }

        if subtitlesEnabled {
            print("💬 [Player] Subtitles enabled by preference, track: \(currentSubtitleTrackId ?? -1)")
        } else {
            // User prefers subtitles off - disable them
            mpv.disableSubtitles()
            currentSubtitleTrackId = nil
            print("💬 [Player] Subtitles disabled by preference")
        }
    }

    /// Set audio track (MPV only)
    /// - Parameter remember: Save the track's language for this title/show
    ///   ("Remember Track Selection"). Pass `false` for automatic selection.
    func setAudioTrack(_ trackId: Int, remember: Bool = true) {
        guard let mpv = mpvController else {
            return
        }

        mpv.setAudioTrack(trackId)
        currentAudioTrackId = trackId

        if remember, let lang = availableAudioTracks.first(where: { $0.id == trackId })?.lang, !lang.isEmpty {
            TrackPreferenceService.shared.saveAudioPreference(for: item.id, languageCode: lang)
            if let seriesId = item.grandparentRatingKey {
                TrackPreferenceService.shared.saveSeriesAudioPreference(for: seriesId, languageCode: lang)
            }
        }
    }

    /// Set subtitle track (MPV only)
    func setSubtitleTrack(_ trackId: Int, remember: Bool = true) {
        guard let mpv = mpvController else {
            return
        }

        mpv.setSubtitleTrack(trackId)
        currentSubtitleTrackId = trackId

        if remember, let lang = availableSubtitleTracks.first(where: { $0.id == trackId })?.lang, !lang.isEmpty {
            saveSubtitleLanguagePreference(lang)
        }
        subtitlesEnabled = true  // Remember that user wants subtitles
        print("💬 [Player] Subtitle track set to \(trackId), preference saved: enabled")
    }

    /// Disable subtitles (MPV only)
    func disableSubtitles() {
        guard let mpv = mpvController else {
            return
        }

        mpv.disableSubtitles()
        currentSubtitleTrackId = nil
        selectedExternalSubtitleId = nil
        subtitlesEnabled = false  // Remember that user wants subtitles off
        saveSubtitleLanguagePreference("none")
        print("💬 [Player] Subtitles disabled, preference saved: disabled")
    }

    private func saveSubtitleLanguagePreference(_ languageCode: String) {
        TrackPreferenceService.shared.saveSubtitlePreference(for: item.id, languageCode: languageCode)
        if let seriesId = item.grandparentRatingKey {
            TrackPreferenceService.shared.saveSeriesSubtitlePreference(for: seriesId, languageCode: languageCode)
        }
    }

    /// Applies the audio/subtitle language the user last picked for this title,
    /// or for its show. Only per-title and per-show choices are used; a global
    /// "most used" language would leak one choice into unrelated titles.
    /// - Returns: Which track types were set from a remembered choice.
    @discardableResult
    func applyRememberedTrackPreferences() -> (audio: Bool, subtitle: Bool) {
        guard let mpv = mpvController else { return (false, false) }
        let service = TrackPreferenceService.shared
        var applied: (audio: Bool, subtitle: Bool) = (false, false)

        let audioTracks = availableAudioTracks.compactMap { track in track.lang.map { (index: track.id, languageCode: $0) } }
        if let trackId = service.recommendedAudioTrackIndex(
            tracks: audioTracks, mediaId: item.id, seriesId: item.grandparentRatingKey, includeGlobal: false
        ) {
            if trackId != currentAudioTrackId { setAudioTrack(trackId, remember: false) }
            applied.audio = true
        }

        let subtitleTracks = availableSubtitleTracks.compactMap { track in track.lang.map { (index: track.id, languageCode: $0) } }
        if let trackId = service.recommendedSubtitleTrackIndex(
            tracks: subtitleTracks, mediaId: item.id, seriesId: item.grandparentRatingKey, includeGlobal: false
        ) {
            if trackId == -1 {
                mpv.disableSubtitles()
                currentSubtitleTrackId = nil
            } else if trackId != currentSubtitleTrackId {
                mpv.setSubtitleTrack(trackId)
                currentSubtitleTrackId = trackId
            }
            applied.subtitle = true
        }

        if applied.audio || applied.subtitle {
            print("🎵 [Player] Applied remembered tracks (audio: \(applied.audio), subtitles: \(applied.subtitle))")
        }
        return applied
    }

    func loadExternalSubtitle(_ subtitle: StremioSubtitleCandidate) {
        guard sourceKind == .stream else { return }
        Task {
            do {
                try await self.attachExternalSubtitle(subtitle)
            } catch {
                AppLogger.shared.error("[Stremio] Failed to load external subtitle", data: [
                    "subtitleId": subtitle.id,
                    "url": subtitle.url,
                    "error": error.localizedDescription,
                ])
            }
        }
    }

    func applyStreamTrackAutoSelectionIfNeeded(skipAudio: Bool = false, skipSubtitles: Bool = false) async {
        guard sourceKind == .stream else { return }

        if !skipAudio,
           !UserDefaults.standard.preferredAudioLanguage.isEmpty,
           let audioMatch = preferredAudioTrack() {
            setAudioTrack(audioMatch.id, remember: false)
        }

        guard !skipSubtitles, UserDefaults.standard.enableSubtitleAutoSelect else { return }

        let internalMatch = preferredInternalSubtitleTrack()
        let externalMatch = preferredExternalSubtitleCandidate()
        let preference = UserDefaults.standard.subtitleSourcePreference

        switch preference {
        case .internal:
            if let internalMatch {
                setSubtitleTrack(internalMatch.id, remember: false)
            } else if let externalMatch {
                do { try await attachExternalSubtitle(externalMatch) } catch {}
            }
        case .external:
            if let externalMatch {
                do { try await attachExternalSubtitle(externalMatch) } catch {}
            } else if let internalMatch {
                setSubtitleTrack(internalMatch.id, remember: false)
            }
        case .any:
            if let internalMatch {
                setSubtitleTrack(internalMatch.id, remember: false)
            } else if let externalMatch {
                do { try await attachExternalSubtitle(externalMatch) } catch {}
            }
        }
    }

    private func preferredAudioTrack() -> MPVTrack? {
        let preferredLanguage = UserDefaults.standard.preferredAudioLanguage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !preferredLanguage.isEmpty else { return nil }
        return availableAudioTracks.first { track in
            (track.lang ?? "").lowercased().hasPrefix(preferredLanguage)
        }
    }

    private func preferredInternalSubtitleTrack() -> MPVTrack? {
        let preferredLanguage = UserDefaults.standard.preferredSubtitleLanguage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !preferredLanguage.isEmpty else { return availableSubtitleTracks.first }
        return availableSubtitleTracks.first { track in
            (track.lang ?? "").lowercased().hasPrefix(preferredLanguage) ||
            track.displayName.lowercased().contains(preferredLanguage)
        }
    }

    private func preferredExternalSubtitleCandidate() -> StremioSubtitleCandidate? {
        let preferredLanguage = UserDefaults.standard.preferredSubtitleLanguage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !preferredLanguage.isEmpty else { return availableExternalSubtitleOptions.first }
        return availableExternalSubtitleOptions.first { subtitle in
            subtitle.lang.lowercased().hasPrefix(preferredLanguage)
        }
    }

    private func attachExternalSubtitle(_ subtitle: StremioSubtitleCandidate) async throws {
        guard let mpv = mpvController else { throw NSError(domain: "PlayerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "MPV controller unavailable"]) }
        guard let remoteURL = URL(string: subtitle.url) else {
            throw NSError(domain: "PlayerError", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid subtitle URL"])
        }

        let (data, _) = try await URLSession.shared.data(from: remoteURL)
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("FlixorMac-StremioSubs", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true, attributes: nil)

        let fileExtension: String = {
            if let format = subtitle.format, !format.isEmpty {
                return format
            }
            return remoteURL.pathExtension.isEmpty ? "srt" : remoteURL.pathExtension
        }()
        let localURL = tempDirectory.appendingPathComponent("\(subtitle.id).\(fileExtension)")
        try data.write(to: localURL, options: .atomic)

        cleanupExternalSubtitleFiles()
        externalSubtitleTempFiles = [localURL]
        mpv.clearExternalSubtitleTracks()
        mpv.addExternalSubtitleFile(path: localURL.path, title: subtitle.addonName ?? subtitle.lang.uppercased(), language: subtitle.lang, select: true)
        selectedExternalSubtitleId = subtitle.id
        subtitlesEnabled = true

        try? await Task.sleep(nanoseconds: 200_000_000)
        loadTracks()

        AppLogger.shared.info("[Stremio] External subtitle loaded", data: [
            "subtitleId": subtitle.id,
            "language": subtitle.lang,
            "path": localURL.path,
        ])
    }

    func cleanupExternalSubtitleFiles() {
        externalSubtitleTempFiles.forEach { url in
            try? FileManager.default.removeItem(at: url)
        }
        externalSubtitleTempFiles.removeAll()
        mpvController?.clearExternalSubtitleTracks()
    }
}
