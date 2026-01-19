//
//  MPVPlayerView.swift
//  Flixor
//
//  React Native UIView component for MPV player on iOS
//  Provides the bridge between React Native and MPVPlayerCore
//

import Foundation
import UIKit
import React
import AVKit

@objc(MPVPlayerView)
class MPVPlayerView: UIView, MPVPlayerDelegate {

    // MARK: - Properties

    private var playerCore: MPVPlayerCore?
    private var progressTimer: Timer?
    private var isSetup = false

    // Pending source (set before MPV is initialized)
    private var pendingSource: NSDictionary?

    // AirPlay route picker for casting
    private var routePickerView: AVRoutePickerView?

    // Event blocks for React Native
    @objc var onLoad: RCTDirectEventBlock?
    @objc var onProgress: RCTDirectEventBlock?
    @objc var onBuffering: RCTDirectEventBlock?
    @objc var onEnd: RCTDirectEventBlock?
    @objc var onError: RCTDirectEventBlock?
    @objc var onTracksChanged: RCTDirectEventBlock?

    // MARK: - React Native Properties

    @objc var source: NSDictionary? {
        didSet {
            NSLog("[MPVPlayerView] source property changed: \(String(describing: source))")
            if let source = source {
                setSource(source)
            }
        }
    }

    @objc var paused: Bool = true {
        didSet {
            NSLog("[MPVPlayerView] paused property changed: \(paused)")
            setPaused(paused)
        }
    }

    @objc var volume: NSNumber = 1.0 {
        didSet {
            setVolume(volume.doubleValue)
        }
    }

    @objc var rate: NSNumber = 1.0 {
        didSet {
            setPlaybackRate(rate.doubleValue)
        }
    }

    @objc var audioTrack: NSNumber = -1 {
        didSet {
            setAudioTrack(audioTrack.intValue)
        }
    }

    @objc var subtitleTrack: NSNumber = -1 {
        didSet {
            setSubtitleTrack(subtitleTrack.intValue)
        }
    }

    @objc var resizeMode: NSString = "contain" {
        didSet {
            // MPV handles aspect ratio internally via --video-aspect-override
            // or vo options. For now, we maintain the container aspect.
            print("[MPVPlayerView] resizeMode set to: \(resizeMode)")
        }
    }

    // Subtitle styling properties
    @objc var subtitleSize: NSNumber = 48 {
        didSet {
            updateSubtitleStyle()
        }
    }

    @objc var subtitleColor: NSString = "#FFFFFF" {
        didSet {
            updateSubtitleStyle()
        }
    }

    @objc var subtitlePosition: NSNumber = 100 {
        didSet {
            updateSubtitleStyle()
        }
    }

    @objc var subtitleBorderSize: NSNumber = 3 {
        didSet {
            updateSubtitleStyle()
        }
    }

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        NSLog("[MPVPlayerView] init(frame:) called with frame: \(frame)")
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        NSLog("[MPVPlayerView] init(coder:) called")
        setupView()
    }

    private func setupView() {
        NSLog("[MPVPlayerView] setupView() called")
        backgroundColor = .black
        clipsToBounds = true

        // Initialize player core
        let core = MPVPlayerCore()
        core.delegate = self
        playerCore = core

        NSLog("[MPVPlayerView] View initialized with playerCore")
        print("[MPVPlayerView] View initialized")

        // Send debug event to JS (delayed to ensure callbacks are set up)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.sendEvent("onError", ["error": "DEBUG: Native view initialized"])
        }
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        NSLog("[MPVPlayerView] didMoveToSuperview - superview: \(String(describing: superview)), frame: \(frame)")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        NSLog("[MPVPlayerView] didMoveToWindow - window: \(String(describing: window)), frame: \(frame)")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        NSLog("[MPVPlayerView] layoutSubviews() called - bounds: \(bounds), isSetup: \(isSetup)")

        // Send debug info to JS
        if !isSetup {
            sendEvent("onError", ["error": "DEBUG: layoutSubviews called - bounds: \(bounds.width)x\(bounds.height)"])
        }

        // Initialize MPV on first layout when we have a valid frame
        if !isSetup && bounds.width > 0 && bounds.height > 0 {
            NSLog("[MPVPlayerView] First valid layout, initializing MPV...")
            sendEvent("onError", ["error": "DEBUG: Initializing MPV with valid bounds"])
            isSetup = true
            if playerCore?.initialize(in: self) == true {
                NSLog("[MPVPlayerView] MPV initialized successfully in layoutSubviews")
                print("[MPVPlayerView] MPV initialized in layoutSubviews")
                sendEvent("onError", ["error": "DEBUG: MPV initialized successfully!"])
                startProgressTimer()

                // Load pending source if any
                if let source = pendingSource {
                    NSLog("[MPVPlayerView] Loading pending source...")
                    sendEvent("onError", ["error": "DEBUG: Loading pending source now"])
                    pendingSource = nil
                    setSource(source)
                }
            } else {
                NSLog("[MPVPlayerView] ERROR: Failed to initialize MPV")
                print("[MPVPlayerView] Failed to initialize MPV")
                sendEvent("onError", ["error": "Failed to initialize MPV player"])
            }
        } else if isSetup {
            playerCore?.updateFrame(bounds)
        }
    }

    // MARK: - Source Management

    func setSource(_ source: NSDictionary) {
        NSLog("[MPVPlayerView] setSource() called with: \(source)")
        sendEvent("onError", ["error": "DEBUG: setSource called, isSetup: \(isSetup)"])

        guard let uri = source["uri"] as? String else {
            NSLog("[MPVPlayerView] ERROR: No URI provided in source")
            print("[MPVPlayerView] No URI provided")
            sendEvent("onError", ["error": "No URI provided in source"])
            return
        }

        // If MPV isn't initialized yet, queue the source for later
        if !isSetup {
            NSLog("[MPVPlayerView] MPV not ready, queueing source...")
            sendEvent("onError", ["error": "DEBUG: MPV not ready, queueing source"])
            pendingSource = source
            return
        }

        var headers: [String: String] = [:]
        if let headersDict = source["headers"] as? [String: String] {
            headers = headersDict
        }

        NSLog("[MPVPlayerView] Loading source URI: \(uri.prefix(100))...")
        print("[MPVPlayerView] Loading source: \(uri.prefix(100))...")
        sendEvent("onError", ["error": "DEBUG: Loading URI \(uri.prefix(80))..."])

        playerCore?.loadFile(uri, headers: headers.isEmpty ? nil : headers)
    }

    // MARK: - Playback Control

    func setPaused(_ paused: Bool) {
        if paused {
            playerCore?.pause()
        } else {
            playerCore?.play()
        }
    }

    func setVolume(_ volume: Double) {
        playerCore?.setVolume(volume)
    }

    func setPlaybackRate(_ rate: Double) {
        playerCore?.setSpeed(rate)
    }

    func seek(to time: TimeInterval) {
        playerCore?.seek(to: time)
    }

    func setAudioTrack(_ trackId: Int) {
        playerCore?.setAudioTrack(trackId)
    }

    func setSubtitleTrack(_ trackId: Int) {
        playerCore?.setSubtitleTrack(trackId)
    }

    private func updateSubtitleStyle() {
        guard let core = playerCore else { return }

        // Convert subtitle size to MPV scale
        let size = subtitleSize.doubleValue
        core.setProperty("sub-font-size", value: String(Int(size)))

        // Parse and set subtitle color
        let colorHex = subtitleColor as String
        if colorHex.hasPrefix("#") {
            // MPV uses ARGB format
            let rgb = String(colorHex.dropFirst())
            core.setProperty("sub-color", value: "#FF\(rgb)")
        }

        // Subtitle position (0 = top, 100 = bottom)
        let position = subtitlePosition.doubleValue
        core.setProperty("sub-pos", value: String(Int(position)))

        // Border size
        let borderSize = subtitleBorderSize.doubleValue
        core.setProperty("sub-border-size", value: String(borderSize))

        print("[MPVPlayerView] Subtitle style updated: size=\(size), color=\(colorHex), pos=\(position)")
    }

    // MARK: - Track Information

    func getAvailableTracks() -> [String: Any] {
        guard let core = playerCore else {
            return ["audioTracks": [], "subtitleTracks": []]
        }

        return [
            "audioTracks": core.audioTracks,
            "subtitleTracks": core.subtitleTracks
        ]
    }

    // MARK: - Playback Stats

    func getPlaybackStats() -> [String: Any] {
        return playerCore?.getPlaybackStats() ?? [:]
    }

    // MARK: - AirPlay

    func showAirPlayPicker() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Create temporary route picker
            let routePickerView = AVRoutePickerView()
            routePickerView.tintColor = .white
            routePickerView.alpha = 0.01

            self.addSubview(routePickerView)
            routePickerView.frame = CGRect(x: -100, y: -100, width: 44, height: 44)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.triggerAirPlayButton(routePickerView)

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    routePickerView.removeFromSuperview()
                }
            }
        }
    }

    private func triggerAirPlayButton(_ routePickerView: AVRoutePickerView) {
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
            button.sendActions(for: .touchUpInside)
        }
    }

    func getAirPlayState() -> [String: Any] {
        // MPV doesn't have direct AirPlay support like AVPlayer
        // This would need custom implementation or AVPlayer fallback for AirPlay
        return [
            "allowsExternalPlayback": false,
            "usesExternalPlaybackWhileExternalScreenIsActive": false,
            "isExternalPlaybackActive": false
        ]
    }

    // MARK: - Progress Timer

    private func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.sendProgressUpdate()
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func sendProgressUpdate() {
        guard let core = playerCore, core.duration > 0 else { return }

        sendEvent("onProgress", [
            "currentTime": core.currentTime,
            "duration": core.duration,
            "bufferTime": core.currentTime, // MPV doesn't expose buffer separately in this simple model
            "playbackRate": paused ? 0.0 : rate.doubleValue,
            "isPlaying": !paused,
            "airPlayState": getAirPlayState()
        ])
    }

    // MARK: - MPVPlayerDelegate

    func onPropertyChange(name: String, value: Any?) {
        switch name {
        case "paused-for-cache":
            if let isBuffering = value as? Bool {
                sendEvent("onBuffering", ["isBuffering": isBuffering])
            }
        default:
            break
        }
    }

    func onEvent(name: String, data: [String: Any]?) {
        switch name {
        case "file-loaded":
            guard let data = data else { return }

            let loadData: [String: Any] = [
                "duration": data["duration"] ?? 0,
                "currentTime": 0,
                "naturalSize": [
                    "width": data["width"] ?? 0,
                    "height": data["height"] ?? 0
                ],
                "audioTracks": data["audioTracks"] ?? [],
                "textTracks": data["subtitleTracks"] ?? [],
                "playerBackend": "MPV"
            ]
            sendEvent("onLoad", loadData)

            // Also send tracks changed
            sendEvent("onTracksChanged", [
                "audioTracks": data["audioTracks"] ?? [],
                "subtitleTracks": data["subtitleTracks"] ?? []
            ])

        case "end-file":
            sendEvent("onEnd", [:])

        case "log-message":
            // Log MPV messages for debugging
            if let logData = data {
                let level = logData["level"] as? String ?? ""
                let text = logData["text"] as? String ?? ""
                if level == "error" || level == "fatal" {
                    print("[MPVPlayerView] MPV \(level): \(text)")
                    if level == "fatal" {
                        sendEvent("onError", ["error": text])
                    }
                }
            }

        default:
            break
        }
    }

    // MARK: - Event Sending

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
            case "onTracksChanged":
                self.onTracksChanged?(body)
            default:
                break
            }
        }
    }

    // MARK: - Cleanup

    override func removeFromSuperview() {
        stopProgressTimer()
        playerCore?.dispose()
        playerCore = nil
        super.removeFromSuperview()
        print("[MPVPlayerView] Removed from superview and disposed")
    }

    deinit {
        stopProgressTimer()
        playerCore?.dispose()
        print("[MPVPlayerView] Deinitialized")
    }
}
