//
//  KSPlayerView.swift
//  Flixor
//
//  Created by KSPlayer integration
//

import Foundation
import KSPlayer
import React
import AVKit

@objc(KSPlayerView)
class KSPlayerView: UIView {
    private var playerView: IOSVideoPlayerView!
    private var currentSource: NSDictionary?
    private var isPaused = false
    private var currentVolume: Float = 1.0
    private var pendingTextTrackId: Int?
    private var lastSelectedTextTrackId: Int?
    private var lastSubtitleDebugTime: TimeInterval = 0
    private var lastSubtitlePartsLogTime: TimeInterval = 0
    private var lastSubtitleReselectTime: TimeInterval = 0
    private var lastSubtitleSelectionName: String?
    private var lastSubtitleRender: SubtitleRender?
    private let nativeLogFileName = "ksplayer_native.log"
    weak var viewManager: KSPlayerViewManager?

    // Store constraint references for dynamic updates
    private var subtitleBottomConstraint: NSLayoutConstraint?
    private var subtitleLabelBottomConstraint: NSLayoutConstraint?

    // AirPlay properties (removed duplicate declarations)

    // Event blocks for Fabric
    @objc var onLoad: RCTDirectEventBlock?
    @objc var onProgress: RCTDirectEventBlock?
    @objc var onBuffering: RCTDirectEventBlock?
    @objc var onEnd: RCTDirectEventBlock?
    @objc var onError: RCTDirectEventBlock?
    @objc var onBufferingProgress: RCTDirectEventBlock?

    // Property setters that React Native will call
    @objc var source: NSDictionary? {
        didSet {
            if let source = source {
                setSource(source)
            }
        }
    }

    @objc var paused: Bool = false {
        didSet {
            setPaused(paused)
        }
    }

    @objc var volume: NSNumber = 1.0 {
        didSet {
            setVolume(volume.floatValue)
        }
    }

    @objc var rate: NSNumber = 1.0 {
        didSet {
            setPlaybackRate(rate.floatValue)
        }
    }

    @objc var audioTrack: NSNumber = -1 {
        didSet {
            setAudioTrack(audioTrack.intValue)
        }
    }

    @objc var textTrack: NSNumber = -1 {
        didSet {
            setTextTrack(textTrack.intValue)
        }
    }

    // AirPlay properties
    @objc var allowsExternalPlayback: Bool = true {
        didSet {
            setAllowsExternalPlayback(allowsExternalPlayback)
        }
    }

    @objc var usesExternalPlaybackWhileExternalScreenIsActive: Bool = true {
        didSet {
            setUsesExternalPlaybackWhileExternalScreenIsActive(usesExternalPlaybackWhileExternalScreenIsActive)
        }
    }

    @objc var subtitleBottomOffset: NSNumber = 60 {
        didSet {
            print("KSPlayerView: [PROP SETTER] subtitleBottomOffset setter called with value: \(subtitleBottomOffset.floatValue)")
            updateSubtitlePositioning()
        }
    }

    @objc var subtitleFontSize: NSNumber = 16 {
        didSet {
            let size = CGFloat(truncating: subtitleFontSize)
            print("KSPlayerView: [PROP SETTER] subtitleFontSize setter called with value: \(size)")
            updateSubtitleFont(size: size)
        }
    }

    @objc var resizeMode: NSString = "contain" {
        didSet {
            print("KSPlayerView: [PROP SETTER] resizeMode setter called with value: \(resizeMode)")
            applyVideoGravity()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupPlayerView()
        setupCustomSubtitlePositioning()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupPlayerView()
        setupCustomSubtitlePositioning()
    }

    private func setupPlayerView() {
        playerView = IOSVideoPlayerView()
        playerView.translatesAutoresizingMaskIntoConstraints = false
        // Hide native controls - we use custom React Native controls
        playerView.isUserInteractionEnabled = false
        // Hide KSPlayer's built-in overlay/controls
        playerView.controllerView.isHidden = true
        playerView.contentOverlayView.isHidden = true
        playerView.controllerView.alpha = 0
        playerView.contentOverlayView.alpha = 0
        playerView.controllerView.gestureRecognizers?.forEach { $0.isEnabled = false }
        addSubview(playerView)

        NSLayoutConstraint.activate([
            playerView.topAnchor.constraint(equalTo: topAnchor),
            playerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            playerView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Subtitle views will be set up in setupCustomSubtitlePositioning() -> adjustSubtitlePositioning()
        // Don't modify them here to avoid conflicting states
        print("KSPlayerView: [SETUP] Player view created, subtitle positioning will be set up separately")

        // Set up player delegates and callbacks
        setupPlayerCallbacks()
        logToFile("KSPlayerView setupPlayerView complete")
    }

    private func setupCustomSubtitlePositioning() {
        // Wait for the player view to be fully set up before modifying subtitle positioning
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.adjustSubtitlePositioning()
        }
    }

    private func adjustSubtitlePositioning() {
        // Remove existing constraints for subtitle positioning
        playerView.subtitleBackView.removeFromSuperview()
        playerView.subtitleLabel.removeFromSuperview()

        // Add subtitle views to main container (self) instead of playerView
        // to make them independent of video transformations
        self.addSubview(playerView.subtitleBackView)
        self.addSubview(playerView.subtitleLabel)

        // Ensure subtitles are always on top of video
        self.bringSubviewToFront(playerView.subtitleBackView)
        self.bringSubviewToFront(playerView.subtitleLabel)

        // Set up new constraints for better mobile visibility
        playerView.subtitleBackView.translatesAutoresizingMaskIntoConstraints = false
        playerView.subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        // Configure subtitleBackView for PGS/image subtitles
        // This is a UIImageView that displays bitmap subtitles
        playerView.subtitleBackView.contentMode = .scaleAspectFit
        playerView.subtitleBackView.clipsToBounds = false
        // Set content hugging/compression priorities for intrinsic size
        playerView.subtitleBackView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        playerView.subtitleBackView.setContentHuggingPriority(.defaultLow, for: .vertical)
        playerView.subtitleBackView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        playerView.subtitleBackView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        // Store the bottom constraint references for dynamic updates
        // Constrain to main container (self) instead of playerView
        subtitleBottomConstraint = playerView.subtitleBackView.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -CGFloat(subtitleBottomOffset.floatValue))
        subtitleLabelBottomConstraint = playerView.subtitleLabel.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -CGFloat(subtitleBottomOffset.floatValue))

        NSLayoutConstraint.activate([
            // Position subtitleBackView (for PGS/image subtitles)
            subtitleBottomConstraint!,
            playerView.subtitleBackView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            playerView.subtitleBackView.widthAnchor.constraint(lessThanOrEqualTo: self.widthAnchor, multiplier: 0.95),
            // Allow larger height for PGS subtitles (up to 25% of screen height)
            playerView.subtitleBackView.heightAnchor.constraint(lessThanOrEqualTo: self.heightAnchor, multiplier: 0.25),

            // Position subtitleLabel (for text subtitles) - same position as backView
            subtitleLabelBottomConstraint!,
            playerView.subtitleLabel.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            playerView.subtitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: self.leadingAnchor, constant: 20),
            playerView.subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: self.trailingAnchor, constant: -20),
        ])

        // Ensure subtitle views are initially hidden
        playerView.subtitleBackView.isHidden = true
        playerView.subtitleLabel.isHidden = true

        print("KSPlayerView: Custom subtitle positioning applied - positioned \(subtitleBottomOffset.floatValue)pts from bottom for mobile visibility")
        print("KSPlayerView: subtitleBackView contentMode: \(playerView.subtitleBackView.contentMode.rawValue) (scaleAspectFit=1)")
    }

    private func updateSubtitlePositioning() {
        // Update subtitle positioning when offset changes
        print("KSPlayerView: [OFFSET UPDATE] subtitleBottomOffset changed to: \(subtitleBottomOffset.floatValue)")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("KSPlayerView: [OFFSET UPDATE] Applying new positioning with offset: \(self.subtitleBottomOffset.floatValue)")

            let newOffset = -CGFloat(self.subtitleBottomOffset.floatValue)

            // Update both subtitle view constraints
            if let backViewConstraint = self.subtitleBottomConstraint,
               let labelConstraint = self.subtitleLabelBottomConstraint {
                backViewConstraint.constant = newOffset
                labelConstraint.constant = newOffset
                print("KSPlayerView: [OFFSET UPDATE] Updated both constraint constants to: \(newOffset)")
            } else {
                // Fallback: recreate positioning if constraint references are missing
                print("KSPlayerView: [OFFSET UPDATE] Constraint references missing, recreating positioning")
                self.adjustSubtitlePositioning()
            }
        }
    }

    private func applyVideoGravity() {
        print("KSPlayerView: [VIDEO GRAVITY] Applying resizeMode: \(resizeMode)")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let contentMode: UIViewContentMode
            switch self.resizeMode.lowercased {
            case "cover":
                contentMode = .scaleAspectFill
            case "stretch":
                contentMode = .scaleToFill
            case "contain":
                contentMode = .scaleAspectFit
            default:
                contentMode = .scaleAspectFit
            }

            // Set contentMode on the player itself, not the view
            self.playerView.playerLayer?.player.contentMode = contentMode
            print("KSPlayerView: [VIDEO GRAVITY] Set player contentMode to: \(contentMode)")
        }
    }

    private func setupPlayerCallbacks() {
        // Configure KSOptions (use static defaults where required)
        KSOptions.isAutoPlay = false
        #if targetEnvironment(simulator)
        // Simulator: disable hardware decode and MEPlayer to avoid VT/Vulkan issues
        KSOptions.hardwareDecode = false
        KSOptions.asynchronousDecompression = false
        KSOptions.secondPlayerType = nil
        #else
        // PERFORMANCE OPTIMIZATION: Enable asynchronous decompression globally
        // This ensures the global default is correct for all player instances
        KSOptions.asynchronousDecompression = true
        // Ensure hardware decode is enabled globally
        KSOptions.hardwareDecode = true
        #endif
        print("KSPlayerView: [PERF] Global settings: asyncDecomp=\(KSOptions.asynchronousDecompression), hwDecode=\(KSOptions.hardwareDecode)")

        // Subtitle defaults for consistent rendering
        SubtitleModel.textFontSize = 20.0
        SubtitleModel.textBold = false
    }

    private func nativeLogFilePath() -> String {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let logURL = documentsDirectory?.appendingPathComponent(nativeLogFileName)
        return logURL?.path ?? "unknown"
    }

    private func logToFile(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        guard let logURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(nativeLogFileName) else { return }

        if FileManager.default.fileExists(atPath: logURL.path) {
            if let handle = try? FileHandle(forWritingTo: logURL) {
                defer { try? handle.close() }
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            }
        } else {
            try? data.write(to: logURL, options: .atomic)
        }
    }

    private struct SubtitleRender {
        let start: TimeInterval
        let end: TimeInterval
        let text: NSAttributedString?
        let image: UIImage?
    }

    private func updateSubtitleFont(size: CGFloat) {
        // Update KSPlayer subtitle font size via SubtitleModel
        SubtitleModel.textFontSize = size
        // Also directly apply to current label for immediate effect
        playerView.subtitleLabel.font = SubtitleModel.textFont
        // Re-render current subtitle parts to apply font
        if let currentTime = playerView.playerLayer?.player.currentPlaybackTime {
            _ = playerView.srtControl.subtitle(currentTime: currentTime)
        }
        print("KSPlayerView: [FONT UPDATE] Applied subtitle font size: \(size)")
    }

    func setSource(_ source: NSDictionary) {
        currentSource = source

        guard let uri = source["uri"] as? String else {
            print("KSPlayerView: No URI provided")
            sendEvent("onError", ["error": "No URI provided in source"])
            return
        }

        // Validate URL before proceeding
        guard let url = URL(string: uri), url.scheme != nil else {
            print("KSPlayerView: Invalid URL format: \(uri)")
            sendEvent("onError", ["error": "Invalid URL format: \(uri)"])
            return
        }

        var headers: [String: String] = [:]
        if let headersDict = source["headers"] as? [String: String] {
            headers = headersDict
        }

        // Choose player pipeline based on format
        let isMKV = uri.lowercased().contains(".mkv")
        let isHLS = uri.lowercased().contains(".m3u8")
        print("KSPlayerView: [FORMAT DETECTION] URI: \(uri.prefix(100))... isMKV=\(isMKV), isHLS=\(isHLS)")

        #if targetEnvironment(simulator)
        if isMKV || isHLS {
            // MKV/HLS MEPlayer not supported on Simulator (VT/Vulkan issues)
            sendEvent("onError", ["error": "MKV/HLS playback with hardware acceleration is not supported in the iOS Simulator. Test on a real device."])
        }
        #else
        // PERFORMANCE OPTIMIZATION: Use KSMEPlayer (FFmpeg) for ALL content
        // KSMEPlayer provides hardware decode via VideoToolbox with full control over
        // buffering, threading, and async decompression - critical for smooth playback
        // KSAVPlayer (AVPlayer) doesn't use our performance optimizations
        // Force KSMEPlayer for everything to ensure consistent smooth playback
        KSOptions.firstPlayerType = KSMEPlayer.self
        KSOptions.secondPlayerType = KSAVPlayer.self  // Fallback to AVPlayer if FFmpeg fails
        print("KSPlayerView: [PLAYER CONFIG] Using KSMEPlayer as primary for all content (isMKV=\(isMKV), isHLS=\(isHLS))")
        #endif

        // Create KSPlayerResource with validated URL
        let resource = KSPlayerResource(url: url, options: createOptions(with: headers), name: "Video")

        print("KSPlayerView: Setting source: \(uri)")
        print("KSPlayerView: URL scheme: \(url.scheme ?? "unknown"), host: \(url.host ?? "unknown")")

        playerView.set(resource: resource)

        // Set up delegate after setting the resource
        if let playerLayer = playerView.playerLayer {
            playerLayer.delegate = self
            print("KSPlayerView: Delegate set successfully on playerLayer")

            // Apply video gravity after player is set up
            applyVideoGravity()
        } else {
            print("KSPlayerView: ERROR - playerLayer is nil, cannot set delegate")
        }

        // Apply current state
        if isPaused {
            playerView.pause()
        } else {
            playerView.play()
        }

        setVolume(currentVolume)

        // Ensure AirPlay is properly configured after setting source
        DispatchQueue.main.async {
            self.setAllowsExternalPlayback(self.allowsExternalPlayback)
            self.setUsesExternalPlaybackWhileExternalScreenIsActive(self.usesExternalPlaybackWhileExternalScreenIsActive)
        }
    }

    private func createOptions(with headers: [String: String]) -> KSOptions {
        // Use custom HighPerformanceOptions subclass for frame buffer optimization
        let options = HighPerformanceOptions()
        // Disable native player remote control center integration; use RN controls
        options.registerRemoteControll = false

        // Disable auto-selection of embedded subtitles - let React Native control subtitle selection
        options.autoSelectEmbedSubtitle = false

        // Allow selecting image-based subtitles (PGS/DVB). KSMEPlayer requires this to enable image subtitle tracks.
        options.isSeekImageSubtitle = true

        // PERFORMANCE OPTIMIZATION: Buffer durations for smooth high bitrate playback
        // preferredForwardBufferDuration = 5.0s: Increased to give decoder more headroom before playback starts
        // This prevents frame drops by ensuring sufficient decoded frames are available
        options.preferredForwardBufferDuration = 5.0
        // maxBufferDuration = 300.0s: Increased to allow the player to cache more content ahead of time (5 minutes)
        options.maxBufferDuration = 300.0

        // Enable "second open" to relax startup/seek buffering thresholds (already enabled)
        options.isSecondOpen = true

        // PERFORMANCE OPTIMIZATION: Fast stream analysis for high bitrate content
        // Reduces startup latency significantly for large high-bitrate streams
        options.probesize = 50_000_000  // 50MB for faster format detection
        options.maxAnalyzeDuration = 5_000_000  // 5 seconds in microseconds for faster stream structure analysis

        // PERFORMANCE OPTIMIZATION: Decoder thread optimization
        // Use all available CPU cores for parallel decoding
        options.decoderOptions["threads"] = "0"  // Use all CPU cores instead of "auto"
        // refcounted_frames already set to "1" in KSOptions init for memory efficiency

        // PERFORMANCE OPTIMIZATION: Hardware decode explicitly enabled
        // Ensure VideoToolbox hardware acceleration is always preferred for non-simulator
        #if targetEnvironment(simulator)
        options.hardwareDecode = false
        options.asynchronousDecompression = false
        #else
        options.hardwareDecode = true  // Explicitly enable hardware decode
        // PERFORMANCE OPTIMIZATION: Asynchronous decompression (CRITICAL)
        // Offloads VideoToolbox decompression to background threads, preventing main thread stalls
        options.asynchronousDecompression = true

        // PERFORMANCE OPTIMIZATION: Async decode for smooth playback
        // Ensures video and audio decoding happens on background threads, preventing frame drops
        options.syncDecodeVideo = false
        options.syncDecodeAudio = false

        // PERFORMANCE OPTIMIZATION: Enable video adaptability for smoother playback
        // Allows the player to adapt video quality dynamically if needed
        options.videoAdaptable = true
        #endif

        // HDR handling: Let KSPlayer automatically detect content's native dynamic range
        // Setting destinationDynamicRange to nil allows KSPlayer to use the content's actual HDR/SDR mode
        // This prevents forcing HDR tone mapping on SDR content (which causes oversaturation)
        // KSPlayer will automatically detect HDR10/Dolby Vision/HLG from the video format description
        options.destinationDynamicRange = nil

        // Configure audio for proper dialogue mixing using FFmpeg's pan filter
        // This approach uses standard audio engineering practices for multi-channel downmixing

        // Use conservative center channel mixing that preserves spatial audio
        // c0 (Left) = 70% original left + 30% center (dialogue) + 20% rear left
        // c1 (Right) = 70% original right + 30% center (dialogue) + 20% rear right
        // This creates natural dialogue presence without the "playing on both ears" effect
        options.audioFilters.append("pan=stereo|c0=0.7*c0+0.3*c2+0.2*c4|c1=0.7*c1+0.3*c2+0.2*c5")

        // Alternative: Use FFmpeg's surround filter for more sophisticated downmixing
        // This provides better spatial audio processing and natural dialogue mixing
        // options.audioFilters.append("surround=ang=45")

        if !headers.isEmpty {
            // Clean and validate headers before adding
            var cleanHeaders: [String: String] = [:]
            for (key, value) in headers {
                // Remove any null or empty values
                if !value.isEmpty && value != "null" {
                    cleanHeaders[key] = value
                }
            }

            if !cleanHeaders.isEmpty {
                options.appendHeader(cleanHeaders)
                print("KSPlayerView: Added headers: \(cleanHeaders.keys.joined(separator: ", "))")

                if let referer = cleanHeaders["Referer"] ?? cleanHeaders["referer"] {
                    options.referer = referer
                    print("KSPlayerView: Set referer: \(referer)")
                }
            }
        }

        print("KSPlayerView: [PERF] High-performance options configured: asyncDecomp=\(options.asynchronousDecompression), hwDecode=\(options.hardwareDecode), buffer=\(options.preferredForwardBufferDuration)s/\(options.maxBufferDuration)s, HDR=\(options.destinationDynamicRange?.description ?? "auto")")

        return options
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        if paused {
            playerView.pause()
        } else {
            playerView.play()
        }
    }

    func setVolume(_ volume: Float) {
        currentVolume = volume
        playerView.playerLayer?.player.playbackVolume = volume
    }

    func setPlaybackRate(_ rate: Float) {
        playerView.playerLayer?.player.playbackRate = rate
        print("KSPlayerView: Set playback rate to \(rate)x")
    }

    func seek(to time: TimeInterval) {
        guard let playerLayer = playerView.playerLayer,
              playerLayer.player.isReadyToPlay,
              playerLayer.player.seekable else {
            print("KSPlayerView: Cannot seek - player not ready or not seekable")
            return
        }

        // Capture the current paused state before seeking
        let wasPaused = isPaused
        print("KSPlayerView: Seeking to \(time), paused state before seek: \(wasPaused)")

        playerView.seek(time: time) { [weak self] success in
            guard let self = self else { return }

            if success {
                print("KSPlayerView: Seek successful to \(time)")

                // Restore the paused state after seeking
                // KSPlayer's seek may resume playback, so we need to re-apply the paused state
                if wasPaused {
                    DispatchQueue.main.async {
                        self.playerView.pause()
                        print("KSPlayerView: Restored paused state after seek")
                    }
                }
            } else {
                print("KSPlayerView: Seek failed to \(time)")
            }
        }
    }

    func setAudioTrack(_ trackId: Int) {
        if let player = playerView.playerLayer?.player {
            let audioTracks = player.tracks(mediaType: .audio)
            print("KSPlayerView: Available audio tracks count: \(audioTracks.count)")
            print("KSPlayerView: Requested track ID: \(trackId)")

            // Debug: Print all track information
            for (index, track) in audioTracks.enumerated() {
                print("KSPlayerView: Track \(index) - ID: \(track.trackID), Name: '\(track.name)', Language: '\(track.language ?? "nil")', isEnabled: \(track.isEnabled)")
            }

            // First try to find track by trackID (proper way)
            var selectedTrack: MediaPlayerTrack? = nil
            var trackIndex: Int = -1

            // Try to find by exact trackID match
            if let track = audioTracks.first(where: { Int($0.trackID) == trackId }) {
                selectedTrack = track
                trackIndex = audioTracks.firstIndex(where: { $0.trackID == track.trackID }) ?? -1
                print("KSPlayerView: Found track by trackID \(trackId) at index \(trackIndex)")
            }
            // Fallback: treat trackId as array index
            else if trackId >= 0 && trackId < audioTracks.count {
                selectedTrack = audioTracks[trackId]
                trackIndex = trackId
                print("KSPlayerView: Found track by array index \(trackId) (fallback)")
            }

            if let track = selectedTrack {
                print("KSPlayerView: Selecting track \(trackId) (index: \(trackIndex)): '\(track.name)' (ID: \(track.trackID))")

                // Use KSPlayer's select method which properly handles track selection
                player.select(track: track)

                print("KSPlayerView: Successfully selected audio track \(trackId)")

                // Verify the selection worked
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let tracksAfter = player.tracks(mediaType: .audio)
                    for (index, track) in tracksAfter.enumerated() {
                        print("KSPlayerView: After selection - Track \(index) (ID: \(track.trackID)) isEnabled: \(track.isEnabled)")
                    }
                }

                // Configure audio downmixing for multi-channel tracks
                configureAudioDownmixing(for: track)
            } else if trackId == -1 {
                // Disable all audio tracks (mute)
                for track in audioTracks { track.isEnabled = false }
                print("KSPlayerView: Disabled all audio tracks")
            } else {
                print("KSPlayerView: Track \(trackId) not found. Available track IDs: \(audioTracks.map { Int($0.trackID) }), array indices: 0..\(audioTracks.count - 1)")
            }
        } else {
            print("KSPlayerView: No player available for audio track selection")
        }
    }

    private func configureAudioDownmixing(for track: MediaPlayerTrack) {
        // Check if this is a multi-channel audio track that needs downmixing
        // This is a simplified check - in practice, you might want to check the actual channel layout
        let trackName = track.name.lowercased()
        let isMultiChannel = trackName.contains("5.1") || trackName.contains("7.1") ||
                            trackName.contains("truehd") || trackName.contains("dts") ||
                            trackName.contains("dolby") || trackName.contains("atmos")

        if isMultiChannel {
            print("KSPlayerView: Detected multi-channel audio track '\(track.name)', ensuring proper dialogue mixing")
            print("KSPlayerView: Using FFmpeg pan filter for natural stereo downmixing")
        } else {
            print("KSPlayerView: Stereo or mono audio track '\(track.name)', no additional downmixing needed")
        }
    }

    func setTextTrack(_ trackId: Int) {
        NSLog("KSPlayerView: [SET TEXT TRACK] trackId: \(trackId)")
        lastSelectedTextTrackId = trackId
        lastSubtitleSelectionName = nil
        logToFile("setTextTrack trackId=\(trackId)")

        // Handle immediate disable request
        if trackId == -1 {
            pendingTextTrackId = nil
            playerView.srtControl.selectedSubtitleInfo = nil
            playerView.subtitleLabel.isHidden = true
            playerView.subtitleBackView.isHidden = true
            playerView.subtitleLabel.attributedText = nil
            playerView.subtitleBackView.image = nil
            NSLog("KSPlayerView: [SET TEXT TRACK] Subtitles disabled")
            return
        }

        guard let player = playerView.playerLayer?.player else {
            pendingTextTrackId = trackId
            NSLog("KSPlayerView: [SET TEXT TRACK] No player available, queued trackId \(trackId)")
            logToFile("setTextTrack queued (no player) trackId=\(trackId)")
            return
        }

        let textTracks = player.tracks(mediaType: .subtitle)
        let subtitleInfos = playerView.srtControl.subtitleInfos

        NSLog("KSPlayerView: [SET TEXT TRACK] Player tracks: \(textTracks.count), SubtitleInfos: \(subtitleInfos.count)")
        logToFile("setTextTrack tracks=\(textTracks.count) subtitleInfos=\(subtitleInfos.count)")
        if subtitleInfos.isEmpty {
            pendingTextTrackId = trackId
            NSLog("KSPlayerView: [SET TEXT TRACK] SubtitleInfos not ready, queued trackId \(trackId)")
            logToFile("setTextTrack queued (subtitleInfos empty) trackId=\(trackId)")
        }

        // Find the track by ID or index
        var selectedTrack: MediaPlayerTrack? = nil
        var trackIndex: Int = -1

        // Try to find by exact trackID match
        if let track = textTracks.first(where: { Int($0.trackID) == trackId }) {
            selectedTrack = track
            trackIndex = textTracks.firstIndex(where: { $0.trackID == track.trackID }) ?? -1
        }
        // Fallback: treat trackId as array index
        else if trackId >= 0 && trackId < textTracks.count {
            selectedTrack = textTracks[trackId]
            trackIndex = trackId
        }

        guard let track = selectedTrack else {
            NSLog("KSPlayerView: [SET TEXT TRACK] Track \(trackId) not found")
            return
        }

        NSLog("KSPlayerView: [SET TEXT TRACK] Selected track index=\(trackIndex), name='\(track.name)', isImageSubtitle=\(track.isImageSubtitle)")

        // Select the track in the player
        player.select(track: track)

        // Find matching SubtitleInfo - this is CRITICAL for rendering
        // Try multiple strategies in order of reliability
        var matchingSubtitleInfo: SubtitleInfo? = nil

        // Log available SubtitleInfos for debugging
        for (idx, info) in subtitleInfos.enumerated() {
            NSLog("KSPlayerView: [SET TEXT TRACK] SubtitleInfo[\(idx)]: name='\(info.name)', subtitleID='\(info.subtitleID)'")
        }

        // Strategy 1: Direct index match (most reliable)
        if trackIndex >= 0 && trackIndex < subtitleInfos.count {
            matchingSubtitleInfo = subtitleInfos[trackIndex]
            NSLog("KSPlayerView: [SET TEXT TRACK] Matched by direct index: \(trackIndex)")
        }

        // Strategy 2: Match by subtitleID == trackIndex as string
        if matchingSubtitleInfo == nil {
            matchingSubtitleInfo = subtitleInfos.first(where: { $0.subtitleID == String(trackIndex) })
            if matchingSubtitleInfo != nil {
                NSLog("KSPlayerView: [SET TEXT TRACK] Matched by subtitleID='\(trackIndex)'")
            }
        }

        // Strategy 3: Match by subtitleID == trackID as string
        if matchingSubtitleInfo == nil {
            matchingSubtitleInfo = subtitleInfos.first(where: { $0.subtitleID == String(track.trackID) })
            if matchingSubtitleInfo != nil {
                NSLog("KSPlayerView: [SET TEXT TRACK] Matched by subtitleID='\(track.trackID)'")
            }
        }

        // Strategy 4: Match by name
        if matchingSubtitleInfo == nil {
            matchingSubtitleInfo = subtitleInfos.first(where: { $0.name.lowercased() == track.name.lowercased() })
            if matchingSubtitleInfo != nil {
                NSLog("KSPlayerView: [SET TEXT TRACK] Matched by name: '\(track.name)'")
            }
        }

        // Strategy 5: First available (last resort)
        if matchingSubtitleInfo == nil && !subtitleInfos.isEmpty {
            matchingSubtitleInfo = subtitleInfos.first
            NSLog("KSPlayerView: [SET TEXT TRACK] Using first available SubtitleInfo as fallback")
        }

        // Set the selected subtitle
        if let info = matchingSubtitleInfo {
            playerView.srtControl.selectedSubtitleInfo = info
            pendingTextTrackId = nil
            lastSubtitleSelectionName = info.name
            NSLog("KSPlayerView: [SET TEXT TRACK] SUCCESS - selectedSubtitleInfo set to: '\(info.name)'")
            logToFile("setTextTrack selectedSubtitleInfo=\(info.name)")

            // Debug: Verify selection was set
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                if let currentSelection = self?.playerView.srtControl.selectedSubtitleInfo {
                    NSLog("KSPlayerView: [SET TEXT TRACK] VERIFY - selectedSubtitleInfo is: '\(currentSelection.name)'")
                } else {
                    NSLog("KSPlayerView: [SET TEXT TRACK] VERIFY - selectedSubtitleInfo is NIL (something cleared it!)")
                }
            }
        } else {
            NSLog("KSPlayerView: [SET TEXT TRACK] ERROR - No SubtitleInfo found, subtitles may not render")
            logToFile("setTextTrack failed to match SubtitleInfo")
        }
    }

    // Get available tracks for React Native
    func getAvailableTracks() -> [String: Any] {
        guard let player = playerView.playerLayer?.player else {
            return ["audioTracks": [], "textTracks": []]
        }

        let audioTracks = player.tracks(mediaType: .audio).enumerated().map { index, track in
            return [
                "id": Int(track.trackID), // Use actual track ID, not array index
                "index": index, // Keep index for backward compatibility
                "name": track.name,
                "language": track.language ?? "Unknown",
                "languageCode": track.languageCode ?? "",
                "isEnabled": track.isEnabled,
                "bitRate": track.bitRate,
                "bitDepth": track.bitDepth
            ]
        }

        let textTracks = player.tracks(mediaType: .subtitle).enumerated().map { index, track in
            // Create a better display name for subtitles
            var displayName = track.name
            if displayName.isEmpty || displayName == "Unknown" {
                if let language = track.language, !language.isEmpty && language != "Unknown" {
                    displayName = language
                } else if let languageCode = track.languageCode, !languageCode.isEmpty {
                    displayName = languageCode.uppercased()
                } else {
                    displayName = "Subtitle \(index + 1)"
                }
            }

            // Add language info if not already in the name
            if let language = track.language, !language.isEmpty && language != "Unknown" && !displayName.lowercased().contains(language.lowercased()) {
                displayName += " (\(language))"
            }

            return [
                "id": Int(track.trackID), // Use actual track ID, not array index
                "index": index, // Keep index for backward compatibility
                "name": displayName,
                "language": track.language ?? "Unknown",
                "languageCode": track.languageCode ?? "",
                "isEnabled": track.isEnabled,
                "isImageSubtitle": track.isImageSubtitle
            ]
        }

        return [
            "audioTracks": audioTracks,
            "textTracks": textTracks
        ]
    }

    // AirPlay methods
    func setAllowsExternalPlayback(_ allows: Bool) {
        print("[KSPlayerView] Setting allowsExternalPlayback: \(allows)")
        playerView.playerLayer?.player.allowsExternalPlayback = allows
    }

    func setUsesExternalPlaybackWhileExternalScreenIsActive(_ uses: Bool) {
        print("[KSPlayerView] Setting usesExternalPlaybackWhileExternalScreenIsActive: \(uses)")
        playerView.playerLayer?.player.usesExternalPlaybackWhileExternalScreenIsActive = uses
    }

    func showAirPlayPicker() {
        print("[KSPlayerView] showAirPlayPicker called")

        DispatchQueue.main.async {
            // Create a temporary route picker view for triggering AirPlay
            let routePickerView = AVRoutePickerView()
            routePickerView.tintColor = .white
            routePickerView.alpha = 0.01 // Nearly invisible but still interactive

            // Find the current view controller
            guard let viewController = self.findHostViewController() else {
                print("[KSPlayerView] Could not find view controller for AirPlay picker")
                return
            }

            // Add to the view controller's view temporarily
            viewController.view.addSubview(routePickerView)

            // Position it off-screen but still in the view hierarchy
            routePickerView.frame = CGRect(x: -100, y: -100, width: 44, height: 44)

            // Force layout
            viewController.view.setNeedsLayout()
            viewController.view.layoutIfNeeded()

            // Wait a bit for the view to be ready, then trigger
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // Find and trigger the AirPlay button
                self.triggerAirPlayButton(routePickerView)

                // Clean up after a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    routePickerView.removeFromSuperview()
                    print("[KSPlayerView] Cleaned up temporary AirPlay picker")
                }
            }
        }
    }

    private func triggerAirPlayButton(_ routePickerView: AVRoutePickerView) {
        // Recursively find the button in the route picker view
        func findButton(in view: UIView) -> UIButton? {
            if let button = view as? UIButton {
                return button
            }
            for subview in view.subviews {
                if let button = findButton(in: subview) {
                    return button
                }
            }
            return nil
        }

        if let button = findButton(in: routePickerView) {
            print("[KSPlayerView] Found AirPlay button, triggering tap")
            button.sendActions(for: .touchUpInside)
        } else {
            print("[KSPlayerView] Could not find AirPlay button in route picker")
        }
    }

    func getAirPlayState() -> [String: Any] {
        guard let player = playerView.playerLayer?.player else {
            return [
                "allowsExternalPlayback": false,
                "usesExternalPlaybackWhileExternalScreenIsActive": false,
                "isExternalPlaybackActive": false
            ]
        }

        return [
            "allowsExternalPlayback": player.allowsExternalPlayback,
            "usesExternalPlaybackWhileExternalScreenIsActive": player.usesExternalPlaybackWhileExternalScreenIsActive,
            "isExternalPlaybackActive": player.isExternalPlaybackActive
        ]
    }

    // Get current player state for React Native
    func getCurrentState() -> [String: Any] {
        guard let player = playerView.playerLayer?.player else {
            return [:]
        }

        return [
            "currentTime": player.currentPlaybackTime,
            "duration": player.duration,
            "buffered": player.playableTime,
            "isPlaying": !isPaused,
            "volume": currentVolume
        ]
    }

    // MARK: - Performance Optimization Helpers

    // MARK: - HDR Detection

    /// Detects HDR information from video tracks
    /// Returns a dictionary with hdrType, colorSpace, colorPrimaries, and colorTransfer
    private func detectHDRInfo(player: MediaPlayerProtocol) -> [String: String] {
        var hdrInfo: [String: String] = [:]

        // Get video tracks
        let videoTracks = player.tracks(mediaType: .video)
        print("KSPlayerView: [HDR] Found \(videoTracks.count) video tracks")

        for (index, track) in videoTracks.enumerated() {
            print("KSPlayerView: [HDR] Video track \(index): ID=\(track.trackID), name='\(track.name)', bitDepth=\(track.bitDepth)")

            // Check the track's dynamicRange property (from KSPlayer)
            let dynamicRange = track.dynamicRange
            print("KSPlayerView: [HDR] Track dynamicRange: \(String(describing: dynamicRange))")

            switch dynamicRange {
            case .some(.dolbyVision):
                hdrInfo["hdrType"] = "Dolby Vision"
                hdrInfo["colorSpace"] = "BT.2020"
                hdrInfo["colorTransfer"] = "PQ/HLG"
                print("KSPlayerView: [HDR] Detected Dolby Vision from track")
            case .some(.hdr10):
                hdrInfo["hdrType"] = "HDR10"
                hdrInfo["colorSpace"] = "BT.2020"
                hdrInfo["colorTransfer"] = "PQ (SMPTE2084)"
                print("KSPlayerView: [HDR] Detected HDR10 from track")
            case .some(.hlg):
                hdrInfo["hdrType"] = "HLG"
                hdrInfo["colorSpace"] = "BT.2020"
                hdrInfo["colorTransfer"] = "HLG"
                print("KSPlayerView: [HDR] Detected HLG from track")
            case .some(.sdr), .none:
                print("KSPlayerView: [HDR] Track is SDR or unknown")
                // Check bit depth as fallback
                if track.bitDepth >= 10 {
                    print("KSPlayerView: [HDR] But bitDepth=\(track.bitDepth), might be HDR")
                    // Analyze track name for HDR hints
                    let trackName = track.name.lowercased()
                    if trackName.contains("dolby") || trackName.contains("vision") || trackName.contains("dovi") {
                        hdrInfo["hdrType"] = "Dolby Vision"
                    } else if trackName.contains("hdr10+") {
                        hdrInfo["hdrType"] = "HDR10+"
                    } else if trackName.contains("hdr") {
                        hdrInfo["hdrType"] = "HDR10"
                    } else {
                        hdrInfo["hdrType"] = "HDR10"
                        hdrInfo["colorSpace"] = "BT.2020 (assumed from bit depth)"
                    }
                }
            }

            // If we found HDR info, break
            if hdrInfo["hdrType"] != nil {
                break
            }
        }

        return hdrInfo
    }

    // MARK: - Developer Stats HUD

    /// Gets current playback statistics for developer HUD
    func getPlaybackStats() -> [String: Any] {
        guard let player = playerView.playerLayer?.player else {
            return [:]
        }

        var stats: [String: Any] = [:]

        // Basic playback info
        stats["currentTime"] = player.currentPlaybackTime
        stats["duration"] = player.duration
        stats["isPlaying"] = !isPaused
        stats["naturalSize"] = [
            "width": player.naturalSize.width,
            "height": player.naturalSize.height
        ]

        // Get video track info
        let videoTracks = player.tracks(mediaType: .video)
        if let videoTrack = videoTracks.first(where: { $0.isEnabled }) ?? videoTracks.first {
            stats["videoCodec"] = videoTrack.name
            stats["bitDepth"] = videoTrack.bitDepth
            stats["dynamicRange"] = videoTrack.dynamicRange?.description ?? "Unknown"
            stats["fps"] = videoTrack.nominalFrameRate
            stats["bitRate"] = videoTrack.bitRate
        }

        // Get audio track info
        let audioTracks = player.tracks(mediaType: .audio)
        if let audioTrack = audioTracks.first(where: { $0.isEnabled }) ?? audioTracks.first {
            stats["audioCodec"] = audioTrack.name
            stats["audioChannels"] = audioTrack.audioStreamBasicDescription?.mChannelsPerFrame ?? 0
            stats["audioBitRate"] = audioTrack.bitRate
        }

        // Buffer info
        stats["playableTime"] = player.playableTime
        stats["bufferProgress"] = player.duration > 0 ? (player.playableTime / player.duration) : 0

        // Real-time render statistics (only available for KSMEPlayer)
        if let dynamicInfo = player.dynamicInfo {
            // Actual display FPS (render rate, not source FPS)
            stats["displayFPS"] = dynamicInfo.displayFPS
            // Audio/video sync difference in seconds
            stats["avSyncDiff"] = dynamicInfo.audioVideoSyncDiff
            // Dropped frames count
            stats["droppedFrames"] = dynamicInfo.droppedVideoFrameCount + dynamicInfo.droppedVideoPacketCount
            stats["droppedVideoFrames"] = dynamicInfo.droppedVideoFrameCount
            stats["droppedVideoPackets"] = dynamicInfo.droppedVideoPacketCount
            // Real-time bitrates
            stats["videoBitrateActual"] = dynamicInfo.videoBitrate
            stats["audioBitrateActual"] = dynamicInfo.audioBitrate
            // Bytes read from network/disk
            stats["bytesRead"] = dynamicInfo.bytesRead
        }

        // Player type indicator
        stats["isHardwareAccelerated"] = player is KSMEPlayer

        return stats
    }
}

// MARK: - High Performance KSOptions Subclass

/// Custom KSOptions subclass that overrides frame buffer capacity for high bitrate content
/// More buffered frames absorb decode spikes and network hiccups without quality loss
private class HighPerformanceOptions: KSOptions {
    /// Override to increase frame buffer capacity for high bitrate content
    /// - Parameters:
    ///   - fps: Video frame rate
    ///   - naturalSize: Video resolution
    ///   - isLive: Whether this is a live stream
    /// - Returns: Number of frames to buffer
    override func videoFrameMaxCount(fps: Float, naturalSize: CGSize, isLive: Bool) -> UInt8 {
        if isLive {
            // Increased from 4 to 8 for better live stream stability
            return 8
        }

        // For high bitrate VOD: increase buffer based on resolution
        if naturalSize.width >= 3840 || naturalSize.height >= 2160 {
            // 4K needs more buffer frames to handle decode spikes
            return 32
        } else if naturalSize.width >= 1920 || naturalSize.height >= 1080 {
            // 1080p benefits from more frames
            return 24
        }

        // Default for lower resolutions
        return 16
    }
}

extension KSPlayerView: KSPlayerLayerDelegate {
    func player(layer: KSPlayerLayer, state: KSPlayerState) {
        switch state {
        case .readyToPlay:
            // Ensure AirPlay is properly configured when player is ready
            layer.player.allowsExternalPlayback = allowsExternalPlayback
            layer.player.usesExternalPlaybackWhileExternalScreenIsActive = usesExternalPlaybackWhileExternalScreenIsActive

            // Initialize subtitle state - only clear if user hasn't selected one
            let shouldClearSelection = (lastSelectedTextTrackId == nil || lastSelectedTextTrackId == -1)
            if shouldClearSelection {
                playerView.srtControl.selectedSubtitleInfo = nil
                playerView.subtitleLabel.isHidden = true
                playerView.subtitleBackView.isHidden = true
                NSLog("KSPlayerView: [READY TO PLAY] Subtitle selection cleared - no subtitle will render until user selects one")
                logToFile("readyToPlay cleared selection (no user selection)")
            } else {
                NSLog("KSPlayerView: [READY TO PLAY] Preserving subtitle selection")
                logToFile("readyToPlay preserving selection trackId=\(lastSelectedTextTrackId ?? -1)")
            }

            // Debug: Check subtitle data source connection
            let hasSubtitleDataSource = layer.player.subtitleDataSouce != nil
            NSLog("KSPlayerView: [READY TO PLAY] subtitle data source available: \(hasSubtitleDataSource)")
            logToFile("readyToPlay hasSubtitleDataSource=\(hasSubtitleDataSource)")

            // Manually connect subtitle data source to srtControl
            // This enables subtitle parsing for when user selects a subtitle later
            if let subtitleDataSouce = layer.player.subtitleDataSouce {
                NSLog("KSPlayerView: [READY TO PLAY] subtitleDataSouce has \(subtitleDataSouce.infos.count) subtitle infos")

                // Wait 1 second like the original KSPlayer code does for data source connection
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 1) { [weak self] in
                    guard let self = self else { return }

                    // Connect the subtitle data source (enables parsing)
                    self.playerView.srtControl.addSubtitle(dataSouce: subtitleDataSouce)
                    NSLog("KSPlayerView: [READY TO PLAY] Subtitle data source connected, \(self.playerView.srtControl.subtitleInfos.count) subtitles available")
                    self.logToFile("readyToPlay connected subtitleInfos=\(self.playerView.srtControl.subtitleInfos.count)")

                    // Log subtitle infos for debugging (helps debug PGS matching)
                    for (index, info) in self.playerView.srtControl.subtitleInfos.enumerated() {
                        NSLog("KSPlayerView: [SUBTITLE INFO] [\(index)]: name='\(info.name)', subtitleID='\(info.subtitleID)'")
                    }

                    // DO NOT clear selectedSubtitleInfo here!
                    // If user already selected a subtitle, we don't want to clear it
                    // The selection is already cleared at the START of readyToPlay
                    if let pendingTrackId = self.pendingTextTrackId {
                        NSLog("KSPlayerView: [READY TO PLAY] Applying pending subtitle selection: \(pendingTrackId)")
                        self.logToFile("readyToPlay applying pending trackId=\(pendingTrackId)")
                        self.setTextTrack(pendingTrackId)
                    } else if self.playerView.srtControl.selectedSubtitleInfo == nil,
                              let lastTrackId = self.lastSelectedTextTrackId,
                              lastTrackId != -1 {
                        self.logToFile("readyToPlay reselecting last trackId=\(lastTrackId)")
                        self.setTextTrack(lastTrackId)
                    }
                }
            } else {
                NSLog("KSPlayerView: [READY TO PLAY] No subtitle data source available")
                logToFile("readyToPlay no subtitle data source")
            }

            // Determine actual player backend type
            let playerBackend = layer.player is KSMEPlayer ? "KSMEPlayer" : "KSAVPlayer"

            // Detect HDR information from video tracks
            let hdrInfo = detectHDRInfo(player: layer.player)
            print("KSPlayerView: [READY TO PLAY] HDR Info: \(hdrInfo)")

            // Send onLoad event to React Native with track information
            let p = layer.player
            let tracks = getAvailableTracks()
            var loadEventData: [String: Any] = [
                "duration": p.duration,
                "currentTime": p.currentPlaybackTime,
                "naturalSize": [
                    "width": p.naturalSize.width,
                    "height": p.naturalSize.height
                ],
                "audioTracks": tracks["audioTracks"] ?? [],
                "textTracks": tracks["textTracks"] ?? [],
                "playerBackend": playerBackend
            ]

            // Add HDR info if available
            if let hdrType = hdrInfo["hdrType"] {
                loadEventData["hdrType"] = hdrType
            }
            if let colorSpace = hdrInfo["colorSpace"] {
                loadEventData["colorSpace"] = colorSpace
            }
            if let colorPrimaries = hdrInfo["colorPrimaries"] {
                loadEventData["colorPrimaries"] = colorPrimaries
            }
            if let colorTransfer = hdrInfo["colorTransfer"] {
                loadEventData["colorTransfer"] = colorTransfer
            }
            loadEventData["nativeLogPath"] = nativeLogFilePath()

            sendEvent("onLoad", loadEventData)
        case .buffering:
            sendEvent("onBuffering", ["isBuffering": true])
        case .bufferFinished:
            sendEvent("onBuffering", ["isBuffering": false])
        case .playedToTheEnd:
            sendEvent("onEnd", [:])
        case .error:
            // Error will be handled by the finish delegate method
            break
        default:
            break
        }
    }

    func player(layer: KSPlayerLayer, currentTime: TimeInterval, totalTime: TimeInterval) {
        // Debug: Confirm delegate method is being called
        if currentTime.truncatingRemainder(dividingBy: 10.0) < 0.1 {
            print("KSPlayerView: [DELEGATE CALLED] time=\(currentTime), total=\(totalTime)")
        }

        // Manually implement subtitle rendering logic from VideoPlayerView
        // This is the critical missing piece that was preventing subtitle rendering

        // Debug: Check srtControl state
        let subtitleInfoCount = playerView.srtControl.subtitleInfos.count
        let selectedSubtitle = playerView.srtControl.selectedSubtitleInfo

        // Periodic file logging for subtitle state
        if currentTime - lastSubtitleDebugTime >= 5.0 {
            let selectedName = selectedSubtitle?.name ?? "nil"
            logToFile("subtitleDebug time=\(String(format: "%.2f", currentTime)) infos=\(subtitleInfoCount) selected=\(selectedName) parts=\(playerView.srtControl.parts.count)")
            lastSubtitleDebugTime = currentTime
        }

        // If selection gets cleared unexpectedly, attempt to re-apply last requested track
        if selectedSubtitle == nil,
           let lastTrackId = lastSelectedTextTrackId,
           lastTrackId != -1,
           currentTime - lastSubtitleReselectTime >= 2.0 {
            logToFile("subtitleReselect time=\(String(format: "%.2f", currentTime)) reapplying trackId=\(lastTrackId)")
            lastSubtitleReselectTime = currentTime
            setTextTrack(lastTrackId)
        }

        // CRITICAL: Only render subtitles if a subtitle is explicitly selected
        // This prevents the "flash" issue where subtitles show briefly on load
        guard selectedSubtitle != nil else {
            // No subtitle selected - ensure views are hidden
            if !playerView.subtitleLabel.isHidden || !playerView.subtitleBackView.isHidden {
                playerView.subtitleBackView.image = nil
                playerView.subtitleLabel.attributedText = nil
                playerView.subtitleBackView.isHidden = true
                playerView.subtitleLabel.isHidden = true
            }
            // Skip to progress event below
            let p = layer.player
            if totalTime > 0 {
                sendEvent("onProgress", [
                    "currentTime": currentTime,
                    "duration": totalTime,
                    "bufferTime": p.playableTime,
                    "playbackRate": isPaused ? 0.0 : p.playbackRate,
                    "isPlaying": !isPaused,
                    "airPlayState": getAirPlayState()
                ])
            }
            return
        }

        // Debug logging every 10 seconds when a subtitle is selected
        if currentTime.truncatingRemainder(dividingBy: 10.0) < 0.1 {
            print("KSPlayerView: [SUBTITLE DEBUG] time=\(currentTime), selected=\(selectedSubtitle?.name ?? "none")")
        }

        // Call srtControl.subtitle() to get parts for current time
        let hasSubtitleParts = playerView.srtControl.subtitle(currentTime: currentTime)

        // Debug logging every 10 seconds
        if currentTime.truncatingRemainder(dividingBy: 10.0) < 0.1 {
            print("KSPlayerView: [SUBTITLE] time=\(currentTime), hasParts=\(hasSubtitleParts), partsCount=\(playerView.srtControl.parts.count)")
        }
        if currentTime - lastSubtitlePartsLogTime >= 5.0 {
            if let part = playerView.srtControl.parts.first {
                let hasImage = part.image != nil
                let hasText = part.text != nil
                logToFile("subtitleParts time=\(String(format: "%.2f", currentTime)) hasParts=\(hasSubtitleParts) partHasImage=\(hasImage) partHasText=\(hasText)")
            } else {
                logToFile("subtitleParts time=\(String(format: "%.2f", currentTime)) hasParts=\(hasSubtitleParts) partsEmpty=true")
            }
            lastSubtitlePartsLogTime = currentTime
        }

        // Render subtitles with caching to avoid flash/vanish between ticks
        if hasSubtitleParts, let part = playerView.srtControl.parts.first {
            lastSubtitleRender = SubtitleRender(
                start: part.start,
                end: part.end,
                text: part.text,
                image: part.image
            )
        }

        if let cached = lastSubtitleRender, currentTime >= cached.start, currentTime <= cached.end {
            playerView.subtitleBackView.image = cached.image
            playerView.subtitleLabel.attributedText = cached.text
            playerView.subtitleBackView.isHidden = false
            playerView.subtitleLabel.isHidden = false
        } else if hasSubtitleParts == false {
            playerView.subtitleBackView.image = nil
            playerView.subtitleLabel.attributedText = nil
            playerView.subtitleBackView.isHidden = true
            playerView.subtitleLabel.isHidden = true
        }

        let p = layer.player
        // Ensure we have valid duration before sending progress updates
        if totalTime > 0 {
            sendEvent("onProgress", [
                "currentTime": currentTime,
                "duration": totalTime,
                "bufferTime": p.playableTime,
                "playbackRate": isPaused ? 0.0 : p.playbackRate,
                "isPlaying": !isPaused,
                "airPlayState": getAirPlayState()
            ])
        }
    }

    func player(layer: KSPlayerLayer, finish error: Error?) {
        if let error = error {
            let errorMessage = error.localizedDescription
            print("KSPlayerView: Player finished with error: \(errorMessage)")

            // Provide more specific error messages for common issues
            var detailedError = errorMessage
            if errorMessage.contains("avformat can't open input") {
                detailedError = "Unable to open video stream. This could be due to:\n• Invalid or malformed URL\n• Network connectivity issues\n• Server blocking the request\n• Unsupported video format\n• Missing required headers"
            } else if errorMessage.contains("timeout") {
                detailedError = "Stream connection timed out. The server may be slow or unreachable."
            } else if errorMessage.contains("404") || errorMessage.contains("Not Found") {
                detailedError = "Video stream not found. The URL may be expired or incorrect."
            } else if errorMessage.contains("403") || errorMessage.contains("Forbidden") {
                detailedError = "Access denied. The server may be blocking requests or require authentication."
            }

            sendEvent("onError", ["error": detailedError])
        }
    }

    func player(layer: KSPlayerLayer, bufferedCount: Int, consumeTime: TimeInterval) {
        // Handle buffering progress if needed
        sendEvent("onBufferingProgress", [
            "bufferedCount": bufferedCount,
            "consumeTime": consumeTime
        ])
    }
}

extension KSPlayerView {
    private func sendEvent(_ eventName: String, _ body: [String: Any]) {
        DispatchQueue.main.async {
            switch eventName {
            case "onLoad":
                self.onLoad?(body)
            case "onProgress":
                self.onProgress?(body)
            case "onBuffering":
                self.onBuffering?(body)
            case "onEnd":
                self.onEnd?([:])
            case "onError":
                self.onError?(body)
            case "onBufferingProgress":
                self.onBufferingProgress?(body)
            default:
                break
            }
        }
    }
    // Renamed to avoid clashing with React's UIView category method
    private func findHostViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let nextResponder = responder?.next {
            if let viewController = nextResponder as? UIViewController {
                return viewController
            }
            responder = nextResponder
        }
        return nil
    }
}
