//
//  PlayerViewModel+Tracks.swift
//  FlixorMac
//
//  Audio/subtitle tracks, external (Stremio) subtitles, remembered track preferences, subtitle styling and sync
//

import Foundation

extension PlayerViewModel {
    // MARK: - Subtitle Styling
    // Persisted per profile (UserDefaults subtitle* keys, shared with Settings) and
    // applied live. Affects text subtitles; styled ASS keeps its own styles and
    // bitmap subtitles (PGS/VobSub) can't be restyled.

    func setSubtitleFontSize(_ size: Int) {
        subtitleFontSize = size
        subtitleAppearance.fontSize = size
        ProfileSettings.shared.subtitleFontSize = size
        mpvController?.setSubtitleFontSize(size)
    }

    func setSubtitleBorderSize(_ size: Double) {
        subtitleBorderSize = size
        subtitleAppearance.borderSize = size
        ProfileSettings.shared.subtitleBorderSize = size
        mpvController?.setSubtitleBorderSize(size)
    }

    /// Background box opacity 0...1 (0 = no box).
    func setSubtitleBackgroundOpacity(_ opacity: Double) {
        let clamped = min(1, max(0, opacity))
        subtitleBackgroundOpacity = clamped
        subtitleAppearance.backgroundOpacity = clamped
        ProfileSettings.shared.subtitleBackgroundOpacity = clamped
        mpvController?.setSubtitleBackground(color: subtitleAppearance.backgroundColor, opacity: clamped)
    }

    /// Font family name ("" = default sans-serif).
    func setSubtitleFont(_ family: String) {
        subtitleAppearance.fontName = family
        UserDefaults.standard.subtitleFontName = family
        mpvController?.setSubtitleFont(family)
    }

    func setSubtitleBold(_ bold: Bool) {
        subtitleAppearance.bold = bold
        UserDefaults.standard.subtitleBold = bold
        mpvController?.setSubtitleBold(bold)
    }

    /// Vertical position, mpv `sub-pos` (0 = top ... 100 = bottom).
    func setSubtitlePosition(_ position: Int) {
        let clamped = min(150, max(0, position))
        subtitleAppearance.position = clamped
        UserDefaults.standard.subtitlePosition = clamped
        mpvController?.setSubtitlePosition(clamped)
    }

    /// Text colour as "#RRGGBB".
    func setSubtitleTextColor(_ hex: String) {
        subtitleAppearance.textColor = hex
        UserDefaults.standard.subtitleTextColor = hex
        mpvController?.setSubtitleColor(hex)
    }

    /// Outline colour as "#RRGGBB".
    func setSubtitleBorderColor(_ hex: String) {
        subtitleAppearance.borderColor = hex
        UserDefaults.standard.subtitleBorderColor = hex
        mpvController?.setSubtitleBorderColor(hex)
    }

    /// Background box colour as "#RRGGBB" (visible when the opacity is above 0).
    func setSubtitleBackgroundColor(_ hex: String) {
        subtitleAppearance.backgroundColor = hex
        UserDefaults.standard.subtitleBackgroundColor = hex
        mpvController?.setSubtitleBackground(color: hex, opacity: subtitleAppearance.backgroundOpacity)
    }

    /// Replaces the whole appearance (e.g. a preset or "reset"), saves and applies it.
    func setSubtitleAppearance(_ appearance: SubtitleAppearance) {
        let defaults = UserDefaults.standard
        defaults.subtitleFontName = appearance.fontName
        defaults.subtitleBold = appearance.bold
        defaults.subtitlePosition = appearance.position
        defaults.subtitleTextColor = appearance.textColor
        defaults.subtitleBorderColor = appearance.borderColor
        defaults.subtitleBackgroundColor = appearance.backgroundColor
        ProfileSettings.shared.subtitleFontSize = appearance.fontSize
        ProfileSettings.shared.subtitleBorderSize = appearance.borderSize
        ProfileSettings.shared.subtitleBackgroundOpacity = appearance.backgroundOpacity
        applySubtitleAppearanceFromDefaults()
    }

    /// Loads the profile's saved appearance into the published state and applies it to mpv.
    func applySubtitleAppearanceFromDefaults() {
        let appearance = SubtitleAppearance.fromDefaults()
        subtitleAppearance = appearance
        subtitleFontSize = appearance.fontSize
        subtitleBorderSize = appearance.borderSize
        subtitleBackgroundOpacity = appearance.backgroundOpacity
        mpvController?.applySubtitleAppearance(appearance)
    }

    /// Called on every file-loaded: subtitle appearance + SDH filter, then the
    /// rest of the per-file engine state (aspect, speed sync, subtitle cues/hash).
    func applySubtitleStyling() {
        applySubtitleAppearanceFromDefaults()
        // Off is mpv's default: leave it alone so a custom MPV config entry still applies
        if subtitleFilterSDH { mpvController?.setSubtitleFilterSDH(true) }
        applyEngineStateForLoadedFile()
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

        defer { refreshSubtitleCues() }

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
            if let seriesId = trackPreferenceSeriesId {
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
        if remember {
            subtitlesEnabled = true  // Remember that user wants subtitles
        }
        refreshSubtitleCues()
        print("💬 [Player] Subtitle track set to \(trackId) (remember: \(remember))")
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
        refreshSubtitleCues()
        print("💬 [Player] Subtitles disabled, preference saved: disabled")
    }

    private func saveSubtitleLanguagePreference(_ languageCode: String) {
        TrackPreferenceService.shared.saveSubtitlePreference(for: item.id, languageCode: languageCode)
        if let seriesId = trackPreferenceSeriesId {
            TrackPreferenceService.shared.saveSeriesSubtitlePreference(for: seriesId, languageCode: languageCode)
        }
    }

    /// Show-level id for remembered tracks: the Plex show, or the addon series
    /// (stream episodes have no grandparent rating key).
    var trackPreferenceSeriesId: String? {
        if let key = item.grandparentRatingKey { return key }
        return streamPlaybackItem.flatMap { StreamSeriesRef(item: $0)?.baseId }
    }

    /// True once the user has turned subtitles off. Never having chosen is not
    /// "off": automatic selection is on by default and must still work then.
    var subtitlesTurnedOff: Bool {
        UserDefaults.standard.object(forKey: "playerSubtitlesEnabled") != nil && !subtitlesEnabled
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
            tracks: audioTracks, mediaId: item.id, seriesId: trackPreferenceSeriesId, includeGlobal: false
        ) {
            if trackId != currentAudioTrackId { setAudioTrack(trackId, remember: false) }
            applied.audio = true
        }

        let subtitleTracks = availableSubtitleTracks.compactMap { track in track.lang.map { (index: track.id, languageCode: $0) } }
        if let trackId = service.recommendedSubtitleTrackIndex(
            tracks: subtitleTracks, mediaId: item.id, seriesId: trackPreferenceSeriesId, includeGlobal: false
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

        // Plex: preferred languages fill in what wasn't remembered.
        // (Addon streams do this in applyStreamTrackAutoSelectionIfNeeded.)
        if sourceKind == .plex {
            applyPlexTrackPreferences(skipAudio: applied.audio, skipSubtitles: applied.subtitle)
        }
        refreshSubtitleCues()
        return applied
    }

    // MARK: - Preferred languages

    /// The preferred audio language with "Original language" resolved to the
    /// title's original language (TMDB). Nil when unset or unresolvable.
    func resolvedPreferredAudioLanguage() async -> String? {
        let preference = UserDefaults.standard.preferredAudioLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !preference.isEmpty else { return nil }
        if preference.lowercased() == PlaybackLanguagePreference.original {
            // Bounded: switching audio long after playback started would be jarring
            let item = self.item
            let stream = streamPlaybackItem
            let lookup = Task { await OriginalLanguageResolver.shared.originalLanguage(for: item, stream: stream) }
            let timeout = Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if !Task.isCancelled { lookup.cancel() }
            }
            defer { timeout.cancel() }
            return await lookup.value
        }
        return preference
    }

    /// Preferred audio/subtitle languages for Plex playback, applied after
    /// remembered per-title choices (which win). Subtitles follow the existing
    /// on/off preference: they are only switched when subtitles are on.
    private func applyPlexTrackPreferences(skipAudio: Bool, skipSubtitles: Bool) {
        if !skipSubtitles, subtitlesEnabled, UserDefaults.standard.enableSubtitleAutoSelect,
           !UserDefaults.standard.preferredSubtitleLanguage.trimmingCharacters(in: .whitespaces).isEmpty,
           let match = preferredInternalSubtitleTrack(), match.id != currentSubtitleTrackId {
            setSubtitleTrack(match.id, remember: false)
            print("💬 [Player] Preferred subtitle language -> track \(match.id) (\(match.lang ?? "?"))")
        }

        guard !skipAudio, !UserDefaults.standard.preferredAudioLanguage.isEmpty else { return }
        let audioAtStart = currentAudioTrackId
        languageSelectionTask?.cancel()
        languageSelectionTask = Task { [weak self] in
            guard let self, let language = await self.resolvedPreferredAudioLanguage(), !Task.isCancelled else { return }
            // Don't override a choice the user made while the language was resolving
            guard self.currentAudioTrackId == audioAtStart,
                  let match = self.preferredAudioTrack(language: language),
                  match.id != self.currentAudioTrackId else { return }
            self.setAudioTrack(match.id, remember: false)
            print("🎵 [Player] Preferred audio language \(language) -> track \(match.id)")
        }
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

        if !skipAudio {
            let audioAtStart = currentAudioTrackId
            if let language = await resolvedPreferredAudioLanguage(),
               currentAudioTrackId == audioAtStart,
               let audioMatch = preferredAudioTrack(language: language),
               audioMatch.id != currentAudioTrackId {
                setAudioTrack(audioMatch.id, remember: false)
            }
        }

        guard !skipSubtitles else { return }

        // "Subtitles off" wins over automatic selection, same as Plex.
        if subtitlesTurnedOff {
            mpvController?.disableSubtitles()
            currentSubtitleTrackId = nil
            refreshSubtitleCues()
            return
        }

        guard UserDefaults.standard.enableSubtitleAutoSelect else { return }

        let internalMatch = preferredInternalSubtitleTrack()
        let externalMatch = preferredExternalSubtitleCandidate()
        let preference = UserDefaults.standard.subtitleSourcePreference

        switch preference {
        case .internal:
            if let internalMatch {
                setSubtitleTrack(internalMatch.id, remember: false)
            } else if let externalMatch {
                do { try await attachExternalSubtitle(externalMatch, remember: false) } catch {}
            }
        case .external:
            if let externalMatch {
                do { try await attachExternalSubtitle(externalMatch, remember: false) } catch {}
            } else if let internalMatch {
                setSubtitleTrack(internalMatch.id, remember: false)
            }
        case .any:
            if let internalMatch {
                setSubtitleTrack(internalMatch.id, remember: false)
            } else if let externalMatch {
                do { try await attachExternalSubtitle(externalMatch, remember: false) } catch {}
            }
        }
    }

    /// Best audio track for a language code (region variants and ISO 639-1/-2 aware).
    func preferredAudioTrack(language: String) -> MPVTrack? {
        LanguageMatcher.bestMatch(
            in: availableAudioTracks,
            preference: language,
            lang: { $0.lang },
            title: { $0.title },
            isDefault: { $0.isDefault }
        ).map { availableAudioTracks[$0] }
    }

    /// Best embedded subtitle track for the preferred subtitle language; forced
    /// (signs-only) tracks only when nothing else matches. With no preference
    /// set, the first track (previous behaviour).
    func preferredInternalSubtitleTrack() -> MPVTrack? {
        let preferredLanguage = UserDefaults.standard.preferredSubtitleLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !preferredLanguage.isEmpty else { return availableSubtitleTracks.first }
        return LanguageMatcher.bestMatch(
            in: availableSubtitleTracks,
            preference: preferredLanguage,
            lang: { $0.lang },
            title: { $0.title },
            isForced: { $0.forced || ($0.title?.lowercased().contains("forced") ?? false) },
            isDefault: { $0.isDefault }
        ).map { availableSubtitleTracks[$0] }
    }

    /// Best addon subtitle for the preferred subtitle language (first one when unset).
    func preferredExternalSubtitleCandidate(in candidates: [StremioSubtitleCandidate]? = nil) -> StremioSubtitleCandidate? {
        let options = candidates ?? availableExternalSubtitleOptions
        let preferredLanguage = UserDefaults.standard.preferredSubtitleLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !preferredLanguage.isEmpty else { return options.first }
        return LanguageMatcher.bestMatch(
            in: options,
            preference: preferredLanguage,
            lang: { $0.lang },
            title: { _ in nil }
        ).map { options[$0] }
    }

    /// - Parameter remember: Save this as the user's choice. Pass `false` for automatic selection.
    func attachExternalSubtitle(_ subtitle: StremioSubtitleCandidate, remember: Bool = true) async throws {
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
        if remember {
            subtitlesEnabled = true
            // Also replaces a remembered "off", which now carries across the series.
            saveSubtitleLanguagePreference(subtitle.lang)
        }

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
