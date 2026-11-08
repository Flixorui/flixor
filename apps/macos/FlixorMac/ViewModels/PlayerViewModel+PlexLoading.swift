//
//  PlayerViewModel+PlexLoading.swift
//  FlixorMac
//
//  Plex playback loading: direct play, DASH/HLS transcode, quality changes, retries and failure handling
//

import Foundation

extension PlayerViewModel {
    /// Generate Plex HTTP headers for MPV streaming
    private var plexStreamHeaders: [String: String] {
        var headers: [String: String] = [
            "X-Plex-Client-Identifier": "FlixorMac",
            "X-Plex-Product": "Flixor",
            "X-Plex-Version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            "X-Plex-Platform": "macOS",
            "X-Plex-Client-Profile-Name": "Generic",
            "Accept": "application/json",
            "Accept-Charset": "utf-8"
        ]
        if let token = plexToken {
            headers["X-Plex-Token"] = token
        }
        return headers
    }

    /// Handles a failed load or a mid-playback error without treating it as
    /// "finished watching". Plex retry/HLS fallback only applies to Plex sources.
    func handlePlaybackFailure(early: Bool) {
        switch sourceKind {
        case .plex where early:
            print("❌ [Player] Plex playback failed to load - likely connection error")
            // If direct play URL failed (404, expired token, etc.), try to refresh it
            if currentURLIsHLS == false {
                if directPlayRetryCount < maxDirectPlayRetries {
                    directPlayRetryCount += 1
                    print("🔄 [Player] Attempting to refresh direct play URL (attempt \(directPlayRetryCount)/\(maxDirectPlayRetries))")
                    fileStartTime = nil
                    Task {
                        let success = await self.retryDirectPlay()
                        if !success {
                            print("↩️ [Player] Direct play retry failed; falling back to HLS")
                            self.directPlayRetryCount = 0
                            await self.retryWithHLS()
                        }
                    }
                } else {
                    print("⚠️ [Player] Max direct play retries (\(maxDirectPlayRetries)) reached; falling back to HLS")
                    directPlayRetryCount = 0
                    fileStartTime = nil
                    Task {
                        await self.retryWithHLS()
                    }
                }
            } else {
                // Already using HLS, can't retry further
                failPlayback("Failed to load video. Please check your network connection and try again.")
            }
        case .plex:
            Task { await self.reportProgress() }
            failPlayback("Playback was interrupted. Check your connection and try again.")
        case .stream:
            print("❌ [Player] Stream source failed (early: \(early))")
            if !early { Task { await self.reportProgress() } }
            failPlayback(early
                ? "This source couldn't be loaded. Go back and pick another source."
                : "The stream was interrupted. Try again or pick another source.")
        case .offline:
            failPlayback("This download couldn't be played. The file may be incomplete or damaged.")
        }
    }

    private func failPlayback(_ message: String) {
        error = message
        isLoading = false
        isPlaying = false
        fileStartTime = nil
    }

    func fetchServerResumeOffset() async {
        guard sourceKind == .plex else { return }
        // Try to get latest playstate from backend metadata if not included
        let rk = item.id.replacingOccurrences(of: "plex:", with: "")
        guard !rk.isEmpty else { return }
        do {
            struct Meta: Decodable { let viewOffset: Int? }
            let meta: Meta = try await api.get("/api/plex/metadata/\(rk)")
            if let ms = meta.viewOffset, ms > 2000 {
                serverResumeSeconds = TimeInterval(ms) / 1000.0
                print("🕑 [Player] Server resume offset: \(ms) ms")
            }
        } catch {
            print("⚠️ [Player] Failed to fetch server resume offset: \(error)")
        }
    }

    func loadStreamURL() async {
        isLoading = true
        error = nil
        directPlayRetryCount = 0  // Reset retry counter for new stream

        do {
            // Validate this is a Plex item
            guard item.id.hasPrefix("plex:") else {
                throw NSError(
                    domain: "PlayerError",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Cannot play non-Plex content. Item must be in your Plex library.\n\nID: \(item.id)"]
                )
            }

            // Validate item type - only movies, episodes, and clips have playable media
            guard ["movie", "episode", "clip"].contains(item.type) else {
                throw NSError(
                    domain: "PlayerError",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Cannot play \(item.type) type. Only movies and episodes can be played.\n\nPlease select an episode from the show."]
                )
            }

            // Extract ratingKey from item.id
            let ratingKey = item.id.replacingOccurrences(of: "plex:", with: "")

            guard !ratingKey.isEmpty else {
                throw NSError(domain: "PlayerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid item ID: \(item.id)"])
            }

            print("📺 [Player] Fetching stream URL for ratingKey: \(ratingKey)")
            print("📺 [Player] Item title: \(item.title) (type: \(item.type))")

            // Fetch markers (intro/credits)
            print("📺 [Player] About to call fetchMarkers...")
            await fetchMarkers(ratingKey: ratingKey)
            print("📺 [Player] fetchMarkers returned, markers count: \(markers.count)")

            // Fetch next episode if this is an episode - get parentRatingKey from metadata
            if item.type == "episode" {
                do {
                    struct EpMetadata: Decodable {
                        let parentRatingKey: String?
                    }
                    let meta: EpMetadata = try await api.get("/api/plex/metadata/\(ratingKey)")
                    if let parentKey = meta.parentRatingKey {
                        await fetchNextEpisode(parentRatingKey: parentKey, currentRatingKey: ratingKey)
                    }
                } catch {
                    print("⚠️ [Player] Failed to get parent rating key: \(error)")
                }
            }

            // Get Plex server connection details (like mobile app)
            let servers = try await api.getPlexServers()
            guard let activeServer = servers.first(where: { $0.isActive == true }) else {
                throw NSError(domain: "PlayerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No active Plex server configured"])
            }

            print("📺 [Player] Using server: \(activeServer.name)")

            let connectionsResponse = try await api.getPlexConnections(serverId: activeServer.id)
            let connections = connectionsResponse.connections

            // Prefer current/preferred connection, then local, then first available
            guard let selectedConnection = connections.first(where: { $0.isCurrent == true })
                    ?? connections.first(where: { $0.isPreferred == true })
                    ?? connections.first(where: { $0.local == true })
                    ?? connections.first else {
                throw NSError(domain: "PlayerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No Plex server connection available"])
            }

            let baseUrl = selectedConnection.uri.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            print("📺 [Player] Server URL: \(baseUrl)")

            // Store for cleanup
            self.plexBaseUrl = baseUrl

            // Get Plex access token
            let authServers = try await api.getPlexAuthServers()
            guard let serverWithToken = authServers.first(where: {
                $0.clientIdentifier == activeServer.id ||
                $0.clientIdentifier == activeServer.machineIdentifier
            }), let token = serverWithToken.token as String? else {
                throw NSError(domain: "PlayerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not get Plex access token"])
            }

            // Store for cleanup
            self.plexToken = token

            print("📺 [Player] Got access token")

            // First try: Direct Play via Plex part URL if available (only if quality is Original)
            struct MetaMedia: Decodable {
                struct Part: Decodable { let key: String? }
                let Part: [Part]?
                let container: String?
                let videoCodec: String?
                let audioCodec: String?
                let width: Int?
                let height: Int?
            }
            struct MetaResponse: Decodable { let Media: [MetaMedia]? }
            var directURL: URL? = nil

            // Always fetch metadata to get source resolution (for quality filtering)
            do {
                // Bypass cache to get fresh part keys (they can change when Plex rescans)
                let meta: MetaResponse = try await api.get("/api/plex/metadata/\(ratingKey)", bypassCache: true)
                // Use mediaIndex from item if specified, otherwise use first version
                let mediaArray = meta.Media ?? []
                let selectedIndex = item.mediaIndex ?? 0
                let m = selectedIndex < mediaArray.count ? mediaArray[selectedIndex] : mediaArray.first
                print("📺 [Player] Using media version \(selectedIndex + 1) of \(mediaArray.count)")

                // Store source resolution for quality filtering
                if let width = m?.width {
                    self.sourceWidth = width
                    print("📺 [Player] Source resolution: \(width)x\(m?.height ?? 0)")
                }
                if let height = m?.height {
                    self.sourceHeight = height
                }

                // Skip Direct Play if user selected a specific quality (transcoding required)
                if selectedQuality == .original {
                    // MPV can handle MKV/HEVC/TrueHD directly: allow all formats
                    print("✅ [Player] MPV backend: Allowing direct play for all codecs")

                    if let key = m?.Part?.first?.key, !key.isEmpty {
                        let direct = "\(baseUrl)\(key)?X-Plex-Token=\(token)"
                        directURL = URL(string: direct)
                        if directURL != nil { print("🎯 [Player] Attempting Direct Play: \(direct)") }
                    }
                } else {
                    print("🎚️ [Player] Quality set to \(selectedQuality.rawValue) - transcoding required, skipping Direct Play")
                }
            } catch {
                print("⚠️ [Player] Could not fetch metadata: \(error)")
            }

            var startURL: URL
            var isDirectPlay = false
            if let d = directURL {
                self.streamURL = d
                startURL = d
                isDirectPlay = true
            } else {
                // Fallback: backend HLS endpoint with selected quality
                print("📺 [Player] Requesting stream URL from backend (HLS, quality: \(selectedQuality.rawValue))")
                struct StreamResponse: Codable { let url: String }
                let response: StreamResponse = try await api.get(
                    "/api/plex/stream/\(ratingKey)",
                    queryItems: buildTranscodeQueryItems(quality: selectedQuality)
                )
                print("📺 [Player] Received stream URL: \(response.url)")
                guard let u = URL(string: response.url) else {
                    throw NSError(domain: "PlayerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid stream URL"])
                }
                startURL = u
                self.currentURLIsHLS = true
                self.isTranscoding = selectedQuality.requiresTranscoding
            }

            // Handle transcoding URLs
            // DASH: Use start.mpd URL directly (like web player)
            // Direct Play: Use URL as-is
            if !isDirectPlay && startURL.absoluteString.contains("start.mpd") {
                // DASH transcode: Use start.mpd directly (MPV/DASH.js handles it)
                print("📺 [Player] Using DASH transcode URL directly")

                // Extract session ID for cleanup
                if let sessionParam = URLComponents(string: startURL.absoluteString)?.queryItems?.first(where: { $0.name == "session" })?.value {
                    self.sessionId = sessionParam
                }

                self.streamURL = startURL
                print("✅ [Player] DASH URL: \(startURL.absoluteString)")

            } else {
                // Direct Play
                self.streamURL = startURL
                print("✅ [Player] Stream URL ready: \(startURL.absoluteString)")
            }

            // Initialize player
            guard let finalURL = self.streamURL else {
                throw NSError(domain: "PlayerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Stream URL not set"])
            }

            // Load file in MPV
            guard let mpvController = self.mpvController else {
                throw NSError(domain: "PlayerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "MPV controller not initialized"])
            }

            // Wait for MPV to be initialized (view must be in window first)
            var waitCount = 0
            let maxWaitCount = 50 // 5 seconds max
            while !mpvController.isInitialized && waitCount < maxWaitCount {
                print("⏳ [MPV] Waiting for initialization... (\(waitCount)/\(maxWaitCount))")
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                waitCount += 1
            }

            guard mpvController.isInitialized else {
                throw NSError(domain: "PlayerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "MPV failed to initialize (timeout)"])
            }

            print("🎬 [MPV] Loading file: \(finalURL.absoluteString)")
            mpvController.loadFile(finalURL.absoluteString, headers: plexStreamHeaders, verifyTLS: false)

            // MPV will handle playback automatically
            // Property and event callbacks will update our @Published properties

            // Start progress tracking
            startProgressTracking()

        } catch {
            print("❌ [Player] Failed to load stream: \(error)")

            // If transcoding failed, reset to Original quality
            if selectedQuality != .original && isTranscoding {
                print("⚠️ [Player] Transcoding failed - resetting to Original quality")
                selectedQuality = .original
                isTranscoding = false

                // Retry with Direct Play
                print("🔄 [Player] Retrying with Direct Play...")
                self.error = nil
                await loadStreamURL()
                return
            }

            self.error = "Failed to load video stream: \(error.localizedDescription)"
            self.isLoading = false
        }
    }

    func changeQuality(_ newQuality: PlaybackQuality) {
        guard sourceKind == .plex else { return }
        print("🎚️ [Player] Changing quality: \(selectedQuality.rawValue) → \(newQuality.rawValue)")

        // No change needed
        guard newQuality != selectedQuality else {
            print("   Already at \(newQuality.rawValue)")
            return
        }

        isChangingQuality = true

        let savedTime = currentTime > 2 ? currentTime : 0

        selectedQuality = newQuality
        isTranscoding = newQuality.requiresTranscoding

        Task {
            defer {
                // Always reset changing quality flag
                isChangingQuality = false
            }

            // Stop current playback
            stopProgressTracking()

            // Reload stream with new quality
            await loadStreamURL()

            // DASH supports seeking to any position (unlike HLS)
            // MPV and DASH.js handle adaptive segment loading automatically
            if savedTime > 2 {
                // Wait for stream to initialize
                let waitTime: UInt64 = isTranscoding ? 3_000_000_000 : 500_000_000 // 3s for DASH, 0.5s for Direct Play
                try? await Task.sleep(nanoseconds: waitTime)

                seek(to: savedTime)
                print("⏩ [Player] Restored position: \(Int(savedTime))s")
            }
        }
    }

    // MARK: - Stream URL Building

    /// Build query items for DASH transcoding based on selected quality
    /// Backend expects "quality" and "resolution" params, which it converts to Plex params
    private func buildTranscodeQueryItems(quality: PlaybackQuality) -> [URLQueryItem] {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "protocol", value: "dash"),  // Use DASH only (better seek support than HLS)
            URLQueryItem(name: "directPlay", value: "0"),
            URLQueryItem(name: "directStream", value: "0")
        ]

        // Backend expects "quality" (not "maxVideoBitrate") and "resolution" (not "videoResolution")
        // The backend converts these to the proper Plex API params
        if let bitrate = quality.bitrate {
            queryItems.append(URLQueryItem(name: "quality", value: String(bitrate)))
        }

        if let resolution = quality.resolution {
            queryItems.append(URLQueryItem(name: "resolution", value: resolution))
        }

        return queryItems
    }

    // MARK: - Cleanup

    func stopTranscodeSession() async {
        guard let sessionId = sessionId,
              let baseUrl = plexBaseUrl,
              let token = plexToken else {
            return
        }

        do {
            let stopUrl = "\(baseUrl)/video/:/transcode/universal/stop?session=\(sessionId)&X-Plex-Token=\(token)"
            guard let url = URL(string: stopUrl) else { return }

            print("🛑 [Player] Stopping transcode session: \(sessionId)")
            _ = try await URLSession.shared.data(from: url)
            print("✅ [Player] Transcode session stopped")
        } catch {
            print("⚠️ [Player] Failed to stop transcode session: \(error)")
        }
    }

    // MARK: - Retry

    /// Retry direct play with fresh metadata and token (handles URL expiration)
    private func retryDirectPlay() async -> Bool {
        print("🔄 [Player] Retrying direct play with fresh metadata and token")

        do {
            // 1. Get ratingKey
            let ratingKey = item.id.replacingOccurrences(of: "plex:", with: "")
            guard !ratingKey.isEmpty else {
                print("❌ [Player] Invalid ratingKey")
                return false
            }

            // 2. Re-fetch metadata to get fresh part key
            struct MetaMedia: Decodable {
                struct Part: Decodable { let key: String? }
                let Part: [Part]?
                let container: String?
                let videoCodec: String?
                let audioCodec: String?
            }
            struct MetaResponse: Decodable { let Media: [MetaMedia]? }
            // CRITICAL: Bypass all caching to get truly fresh part key
            let meta: MetaResponse = try await api.get("/api/plex/metadata/\(ratingKey)", bypassCache: true)

            guard let partKey = meta.Media?.first?.Part?.first?.key, !partKey.isEmpty else {
                print("❌ [Player] No part key in fresh metadata")
                return false
            }

            // Check if part key changed (indicates Plex rescanned library)
            if let oldURL = self.streamURL?.absoluteString, oldURL.contains("/library/parts/") {
                let oldPartKey = oldURL.components(separatedBy: "?").first?.components(separatedBy: "/library/parts").last ?? ""
                let newPartKey = partKey.replacingOccurrences(of: "/library/parts", with: "")
                if !oldPartKey.isEmpty && oldPartKey != newPartKey {
                    print("🔄 [Player] Part key changed: \(oldPartKey) → \(newPartKey)")
                    print("   (Plex rescanned library and reassigned file IDs)")
                }
            }

            print("✅ [Player] Fresh part key: \(partKey)")

            // 3. Re-fetch server connection and token
            let servers = try await api.getPlexServers()
            guard let activeServer = servers.first(where: { $0.isActive == true }) else {
                print("❌ [Player] No active server")
                return false
            }

            let connectionsResponse = try await api.getPlexConnections(serverId: activeServer.id)
            guard let connection = connectionsResponse.connections.first(where: { $0.isCurrent == true })
                                  ?? connectionsResponse.connections.first(where: { $0.isPreferred == true })
                                  ?? connectionsResponse.connections.first(where: { $0.local == true })
                                  ?? connectionsResponse.connections.first else {
                print("❌ [Player] No server connection")
                return false
            }

            let baseUrl = connection.uri.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

            let authServers = try await api.getPlexAuthServers()
            guard let serverWithToken = authServers.first(where: {
                $0.clientIdentifier == activeServer.id ||
                $0.clientIdentifier == activeServer.machineIdentifier
            }), let token = serverWithToken.token as String? else {
                print("❌ [Player] No fresh token")
                return false
            }

            print("✅ [Player] Fresh token obtained")

            // 4. Build new direct play URL
            let newDirectURL = "\(baseUrl)\(partKey)?X-Plex-Token=\(token)"
            guard let url = URL(string: newDirectURL) else {
                print("❌ [Player] Invalid URL")
                return false
            }

            print("✅ [Player] New direct play URL: \(newDirectURL)")

            // 5. Update state
            self.streamURL = url
            self.currentURLIsHLS = false
            self.plexBaseUrl = baseUrl
            self.plexToken = token

            // 6. Reload in MPV
            let savedPosition = currentTime > 2 ? currentTime : 0

            guard let mpvController = self.mpvController else {
                print("❌ [Player] MPV controller not available")
                return false
            }

            print("🎬 [MPV] Reloading file with fresh URL")
            self.fileStartTime = nil // Reset to detect new loading errors
            mpvController.loadFile(url.absoluteString, headers: plexStreamHeaders, verifyTLS: false)

            // Seek will happen after file-loaded event via applyInitialSeekIfNeeded
            // But we need to preserve the position
            if savedPosition > 2 {
                // Wait for file to load, then seek
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                if self.duration > 0 && savedPosition < self.duration {
                    self.seek(to: savedPosition)
                    print("⏩ [Player] Restored position: \(Int(savedPosition))s")
                }
            }

            print("✅ [Player] Successfully retried direct play with fresh URL")
            return true

        } catch {
            print("❌ [Player] Failed to retry direct play: \(error)")
            return false
        }
    }

    /// Retry with HLS transcoding as fallback (for MPV backend)
    private func retryWithHLS() async {
        print("↩️ [Player] Falling back to HLS transcoding (quality: \(selectedQuality.rawValue))")

        do {
            let ratingKey = item.id.replacingOccurrences(of: "plex:", with: "")
            struct StreamResponse: Codable { let url: String }
            let response: StreamResponse = try await api.get(
                "/api/plex/stream/\(ratingKey)",
                queryItems: buildTranscodeQueryItems(quality: selectedQuality)
            )
            guard let url = URL(string: response.url) else {
                throw NSError(domain: "PlayerError", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid HLS URL"])
            }

            self.streamURL = url
            self.currentURLIsHLS = true
            self.isTranscoding = selectedQuality.requiresTranscoding

            // Handle session URL if needed (start.m3u8)
            var finalURL = url
            if url.absoluteString.contains("start.m3u8") {
                print("📺 [Player] Starting HLS transcode session")

                // Extract session ID
                if let sessionParam = URLComponents(string: url.absoluteString)?.queryItems?.first(where: { $0.name == "session" })?.value {
                    self.sessionId = sessionParam
                }

                // Start the session
                let (_, startResponse) = try await URLSession.shared.data(from: url)
                if let httpResponse = startResponse as? HTTPURLResponse {
                    print("📺 [Player] Start response: \(httpResponse.statusCode)")
                }

                // Wait for transcoder (MPV needs more time)
                let delaySeconds = 5
                print("⏳ [Player] Waiting \(delaySeconds)s for transcoder...")
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds) * 1_000_000_000)

                // Build session URL
                if let sessionId = self.sessionId,
                   let baseUrlString = url.absoluteString.components(separatedBy: "/video/").first,
                   let token = URLComponents(string: url.absoluteString)?.queryItems?.first(where: { $0.name == "X-Plex-Token" })?.value {
                    let sessionURL = "\(baseUrlString)/video/:/transcode/universal/session/\(sessionId)/base/index.m3u8?X-Plex-Token=\(token)"
                    if let sessionUrl = URL(string: sessionURL) {
                        finalURL = sessionUrl
                        self.streamURL = sessionUrl
                        print("✅ [Player] Using session URL: \(sessionURL)")
                    }
                }
            }

            let savedPosition = currentTime > 2 ? currentTime : 0

            guard let mpvController = self.mpvController else {
                throw NSError(domain: "PlayerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "MPV controller not available"])
            }

            print("🎬 [MPV] Loading HLS stream")
            self.fileStartTime = nil
            mpvController.loadFile(finalURL.absoluteString, headers: plexStreamHeaders, verifyTLS: false)

            // Restore position after file loads
            if savedPosition > 2 {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds for HLS
                if self.duration > 0 && savedPosition < self.duration {
                    self.seek(to: savedPosition)
                    print("⏩ [Player] Restored position: \(Int(savedPosition))s")
                }
            }

            self.isLoading = false
            print("✅ [Player] HLS fallback successful")

        } catch {
            print("❌ [Player] HLS fallback failed: \(error)")
            self.error = "Failed to load video: \(error.localizedDescription)"
            self.isLoading = false
            self.isPlaying = false
        }
    }
}
