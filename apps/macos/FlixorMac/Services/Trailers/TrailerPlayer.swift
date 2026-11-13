//
//  TrailerPlayer.swift
//  FlixorMac
//
//  One player for trailers. Direct streams (Apple TV trailers from MyBluray)
//  play in AVPlayer as they are, falling back to the trailer's YouTube video if
//  the stream fails. YouTube trailers have two backends:
//  - native: AVPlayer on a direct stream from YouTubeStreamExtractor (HLS
//    master served through a resource loader, or a progressive MP4). No
//    YouTube chrome, no end screens, hardware decoding, starts at 1080p.
//  - embed: the YouTubePlayerKit web embed, used when extraction finds nothing
//    or native playback fails, so trailers keep working if YouTube changes.
//
//  Callers create it, call `load()`, wait for `status == .ready`, then drive
//  play/pause/mute/seek. TrailerVideoSurface and TrailerModal show the video.
//

import AVFoundation
import AVKit
import Combine
import SwiftUI
import YouTubePlayerKit

@MainActor
final class TrailerPlayer: ObservableObject {
    enum Backend {
        case native(AVPlayer)
        case embed(YouTubePlayer)
    }

    enum Status: Equatable {
        /// Looking up a stream / creating the backend.
        case resolving
        /// The backend can play.
        case ready
        /// Neither backend could play.
        case failed
    }

    enum Playback: Equatable {
        case idle
        case playing
        case paused
        case ended
    }

    struct Options {
        /// Height of the HLS variant playback starts on.
        var maxHeight = YouTubeStreamExtractor.defaultMaxHeight
        /// Whether the embed shows YouTube's own controls (the modal does).
        var embedShowsControls = false
        /// Whether playback keeps the display awake (the modal does).
        var preventsDisplaySleep = false
        /// Look for black bars baked into the video and publish a zoom that
        /// crops them (`letterboxZoom`). For views that fill their frame.
        var detectsLetterbox = true
        /// Let direct streams go above `maxHeight` (Apple serves up to 4K HDR).
        var allowsUHD = false
        /// How far ahead a direct stream buffers; 0 lets AVPlayer decide, which
        /// on a fast connection is most of the trailer.
        var forwardBufferSeconds: Double = 0
        /// Play only the SDR versions of a direct stream. Apple's HDR10 and
        /// Dolby Vision versions show with a purple/green cast in a bare
        /// AVPlayerLayer under the hero's overlays; AVPlayerView (the modal)
        /// shows them correctly.
        var sdrOnly = true
    }

    static let nativeDisabledKey = "trailerNativePlaybackDisabled"

    /// YouTube video to play; for a direct stream, the one to fall back to ("" if none).
    let videoKey: String
    /// Direct HLS/MP4 stream played before (instead of) YouTube.
    let streamURL: URL?
    let options: Options

    @Published private(set) var backend: Backend?
    @Published private(set) var status: Status = .resolving
    @Published private(set) var playback: Playback = .idle
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double?
    @Published private(set) var isMuted: Bool
    /// Zoom that crops letterbox bars baked into the native video (1 = none).
    @Published private(set) var letterboxZoom: CGFloat = 1

    private var cancellables = Set<AnyCancellable>()
    private var timeObserver: (player: AVPlayer, token: Any)?
    private var hlsLoader: TrailerHLSLoader?
    private var loadTask: Task<Void, Never>?
    private var letterboxTask: Task<Void, Never>?
    private var didLoad = false
    private var isStopped = false
    private var isPlayingDirect = false

    var usesEmbed: Bool {
        if case .embed = backend { return true }
        return false
    }

    init(videoKey: String, muted: Bool, options: Options = Options()) {
        self.videoKey = videoKey
        self.streamURL = nil
        self.isMuted = muted
        self.options = options
    }

    /// Plays a trailer from TrailerService: its direct stream when it has one
    /// (with its YouTube fallback), its YouTube video otherwise.
    init(trailer: Trailer, muted: Bool, options: Options = Options()) {
        self.videoKey = trailer.youtubeKey ?? ""
        self.streamURL = trailer.streamURL
        self.isMuted = muted
        self.options = options
    }

    // MARK: - Loading

    /// Resolves a direct stream and sets up the native backend, or the embed when
    /// there is none. Safe to call more than once.
    func load() {
        guard !didLoad, !isStopped else { return }
        didLoad = true
        if let streamURL {
            startDirect(streamURL)
            return
        }
        loadYouTube()
    }

    private func loadYouTube() {
        guard !videoKey.isEmpty else {
            status = .failed
            return
        }
        // Off switch for native playback, if YouTube ever breaks it badly:
        //   defaults write com.flixor.mac trailerNativePlaybackDisabled -bool YES
        if UserDefaults.standard.bool(forKey: Self.nativeDisabledKey) {
            startEmbed()
            return
        }
        loadTask = Task { [weak self] in
            guard let self else { return }
            let stream = await YouTubeStreamExtractor.shared.stream(for: self.videoKey, maxHeight: self.options.maxHeight)
            guard !Task.isCancelled, !self.isStopped else { return }
            if let stream {
                self.startNative(stream)
            } else {
                self.startEmbed()
            }
        }
    }

    /// A direct stream (Apple TV HLS). Capped at `maxHeight` unless UHD is
    /// allowed; AVPlayer picks the variant and handles HDR / Dolby Vision.
    private func startDirect(_ url: URL) {
        guard options.sdrOnly else {
            startDirectItem(AVPlayerItem(url: url), url: url)
            return
        }
        loadTask = Task { [weak self] in
            let master = await TrailerHLSLoader.sdrOnlyMaster(for: url)
            guard let self, !Task.isCancelled, !self.isStopped else { return }
            guard let master else {
                // Couldn't fetch or rewrite the playlist: play it as it is.
                self.startDirectItem(AVPlayerItem(url: url), url: url)
                return
            }
            let loader = TrailerHLSLoader(master: master)
            self.hlsLoader = loader
            let asset = AVURLAsset(url: TrailerHLSLoader.directMasterURL())
            asset.resourceLoader.setDelegate(loader, queue: TrailerHLSLoader.queue)
            self.startDirectItem(AVPlayerItem(asset: asset), url: url)
        }
    }

    private func startDirectItem(_ item: AVPlayerItem, url: URL) {
        if !options.allowsUHD {
            let height = CGFloat(options.maxHeight)
            item.preferredMaximumResolution = CGSize(width: (height * 16 / 9).rounded(), height: height)
        }
        item.preferredForwardBufferDuration = options.forwardBufferSeconds
        isPlayingDirect = true
        startPlayer(item: item, logData: [
            "stream": url.host ?? "direct", "maxHeight": options.allowsUHD ? "any" : "\(options.maxHeight)",
            "sdrOnly": options.sdrOnly,
        ])
    }

    private func startNative(_ stream: YouTubeTrailerStream) {
        let item: AVPlayerItem
        switch stream.source {
        case .hls(let master, _, _):
            let loader = TrailerHLSLoader(master: master)
            hlsLoader = loader
            let asset = AVURLAsset(url: TrailerHLSLoader.masterURL(for: stream.videoKey))
            asset.resourceLoader.setDelegate(loader, queue: TrailerHLSLoader.queue)
            item = AVPlayerItem(asset: asset)
            // Start on the variant the rewritten master lists first (the best
            // H.264 one) instead of AVPlayer's 240p default.
            item.startsOnFirstEligibleVariant = true
        case .progressive(let url, _):
            item = AVPlayerItem(url: url)
        }
        isPlayingDirect = false
        startPlayer(item: item, logData: [
            "videoId": stream.videoKey, "kind": stream.kindLabel, "height": stream.height, "client": stream.client,
        ])
    }

    private func startPlayer(item: AVPlayerItem, logData: [String: Any]) {
        let player = AVPlayer(playerItem: item)
        player.isMuted = isMuted
        player.allowsExternalPlayback = false
        player.preventsDisplaySleepDuringVideoPlayback = options.preventsDisplaySleep
        player.actionAtItemEnd = .pause

        item.publisher(for: \.status)
            .receive(on: RunLoop.main)
            .sink { [weak self, weak item] state in
                guard let self, let item, self.isCurrent(player) else { return }
                switch state {
                case .readyToPlay:
                    if self.status == .resolving {
                        self.status = .ready
                        if self.options.detectsLetterbox { self.startLetterboxDetection(player: player, item: item) }
                    }
                    let seconds = item.duration.seconds
                    if seconds.isFinite, seconds > 0 { self.duration = seconds }
                case .failed:
                    self.nativeFailed(player, error: item.error)
                default:
                    break
                }
            }
            .store(in: &cancellables)

        item.publisher(for: \.duration)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                guard let self, self.isCurrent(player) else { return }
                let seconds = value.seconds
                if seconds.isFinite, seconds > 0 { self.duration = seconds }
            }
            .store(in: &cancellables)

        player.publisher(for: \.timeControlStatus)
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self, self.isCurrent(player) else { return }
                switch state {
                case .playing:
                    self.playback = .playing
                case .paused:
                    if self.playback == .playing { self.playback = .paused }
                default:
                    break
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.isCurrent(player) else { return }
                self.playback = .ended
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime, object: item)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                guard let self, self.isCurrent(player) else { return }
                self.nativeFailed(player, error: note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)
            }
            .store(in: &cancellables)

        let token = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.isCurrent(player) else { return }
                self.currentTime = time.seconds.isFinite ? time.seconds : 0
            }
        }
        timeObserver = (player, token)
        backend = .native(player)

        AppLogger.shared.debug("[TrailerPlayer] native", data: logData)
    }

    /// Native playback broke (expired URL, 403 on segments...): switch to the
    /// embed, unless playback already got going and simply ended badly.
    private func nativeFailed(_ player: AVPlayer, error: Error?) {
        if isPlayingDirect {
            // A direct stream that won't play: use the YouTube trailer, if there is one.
            AppLogger.shared.warn("[TrailerPlayer] direct stream failed, using YouTube", data: [
                "stream": streamURL?.absoluteString ?? "", "fallback": videoKey,
                "error": error?.localizedDescription ?? "unknown",
            ])
            // Callers start playback on `.ready`, so the YouTube video picks up from here.
            tearDownBackend()
            isPlayingDirect = false
            status = .resolving
            loadYouTube()
            return
        }
        AppLogger.shared.warn("[TrailerPlayer] native playback failed, using embed", data: [
            "videoId": videoKey, "error": error?.localizedDescription ?? "unknown",
        ])
        Task { await YouTubeStreamExtractor.shared.clearCache() }
        let wasPlaying = playback == .playing
        tearDownBackend()
        status = .resolving
        startEmbed(autoPlay: wasPlaying)
    }

    private func startEmbed(autoPlay: Bool = false) {
        let player = YouTubePlayer(
            source: .video(id: videoKey),
            parameters: .init(
                autoPlay: false,
                loopEnabled: false,
                showControls: options.embedShowsControls,
                showFullscreenButton: options.embedShowsControls,
                keyboardControlsDisabled: !options.embedShowsControls,
                showCaptions: false,
                restrictRelatedVideosToSameChannel: true
            ),
            configuration: .init(fullscreenMode: .web, allowsPictureInPictureMediaPlayback: false)
        )

        player.statePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self, weak player] state in
                guard let self, let player, self.isCurrent(player) else { return }
                switch state {
                case .ready:
                    Task {
                        if self.isMuted { try? await player.mute() } else { try? await player.unmute() }
                        guard self.isCurrent(player) else { return }
                        self.status = .ready
                        if autoPlay { self.play() }
                    }
                case .error:
                    self.status = .failed
                case .idle:
                    break
                }
            }
            .store(in: &cancellables)

        player.playbackStatePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self, weak player] state in
                guard let self, let player, self.isCurrent(player) else { return }
                switch state {
                case .playing: self.playback = .playing
                case .paused: if self.playback == .playing { self.playback = .paused }
                case .ended: self.playback = .ended
                default: break
                }
            }
            .store(in: &cancellables)

        player.durationPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self, weak player] value in
                guard let self, let player, self.isCurrent(player) else { return }
                self.duration = value.converted(to: .seconds).value
            }
            .store(in: &cancellables)

        player.currentTimePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self, weak player] value in
                guard let self, let player, self.isCurrent(player) else { return }
                self.currentTime = value.converted(to: .seconds).value
            }
            .store(in: &cancellables)

        backend = .embed(player)
        AppLogger.shared.debug("[TrailerPlayer] embed", data: ["videoId": videoKey])
    }

    // MARK: - Controls

    func play() {
        switch backend {
        case .native(let player):
            if playback == .ended { player.seek(to: .zero) }
            player.play()
        case .embed(let player):
            Task { try? await player.play() }
        case nil:
            break
        }
    }

    func pause() {
        switch backend {
        case .native(let player):
            player.pause()
            if playback == .playing { playback = .paused }
        case .embed(let player):
            Task { try? await player.pause() }
        case nil:
            break
        }
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        switch backend {
        case .native(let player):
            player.isMuted = muted
        case .embed(let player):
            Task { if muted { try? await player.mute() } else { try? await player.unmute() } }
        case nil:
            break
        }
    }

    /// Seeks to the start and plays when `play` is true.
    func restart(play shouldPlay: Bool) {
        switch backend {
        case .native(let player):
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .positiveInfinity) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isCurrent(player) else { return }
                    if shouldPlay { player.play() } else { self.playback = .paused }
                }
            }
        case .embed(let player):
            Task {
                try? await player.seek(to: .init(value: 0, unit: .seconds))
                if shouldPlay { try? await player.play() } else { self.playback = .paused }
            }
        case nil:
            break
        }
    }

    /// Stops playback and releases the backend. The player can't be reused.
    func stop() {
        isStopped = true
        loadTask?.cancel()
        loadTask = nil
        tearDownBackend()
        playback = .idle
    }

    private func tearDownBackend() {
        cancellables.removeAll()
        letterboxTask?.cancel()
        letterboxTask = nil
        if let (player, token) = timeObserver {
            player.removeTimeObserver(token)
        }
        timeObserver = nil
        switch backend {
        case .native(let player):
            player.pause()
            player.replaceCurrentItem(with: nil)
        case .embed(let player):
            Task { try? await player.stop() }
        case nil:
            break
        }
        backend = nil
        hlsLoader = nil
    }

    // MARK: - Letterbox

    /// Samples frames while the first part of the trailer plays and, once the
    /// same bar size is seen several times in a row, publishes a zoom that
    /// crops it. Stops after that, or once the sampling window is over.
    private func startLetterboxDetection(player: AVPlayer, item: AVPlayerItem) {
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        item.add(output)
        letterboxTask = Task { [weak self, weak item] in
            var tracker = LetterboxTracker()
            defer { item?.remove(output) }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: LetterboxDetector.sampleIntervalNanos)
                guard !Task.isCancelled, let self, let item, self.isCurrent(player) else { return }
                guard self.playback == .playing else { continue }
                let position = item.currentTime().seconds
                let duration = item.duration.seconds
                if duration.isFinite, duration > 0, position >= duration * LetterboxDetector.sampleWindowFraction { return }

                let itemTime = output.itemTime(forHostTime: CACurrentMediaTime())
                guard let buffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil),
                      let bar = LetterboxDetector.detectBar(in: buffer),
                      let zoom = tracker.onSample(bar) else { continue }
                AppLogger.shared.debug("[TrailerPlayer] letterbox", data: [
                    "videoId": self.videoKey, "bar": bar, "zoom": zoom,
                ])
                self.letterboxZoom = zoom
                return
            }
        }
    }

    private func isCurrent(_ player: AVPlayer) -> Bool {
        if case .native(let current) = backend { return current === player }
        return false
    }

    private func isCurrent(_ player: YouTubePlayer) -> Bool {
        if case .embed(let current) = backend { return current === player }
        return false
    }
}

// MARK: - Letterbox detection

/// Finds black bars baked into a video frame (a 2.39:1 film inside a 16:9
/// upload). Same rules as Nuvio's LetterboxDetector: a row is dark when at
/// most 3% of its sampled pixels are brighter than luma 40.
enum LetterboxDetector {
    static let sampleIntervalNanos: UInt64 = 400_000_000
    /// Only sample during the first 20% of the trailer.
    static let sampleWindowFraction = 0.2

    private static let sampleColumns = 64
    private static let sampleRows = 120
    private static let darkLuma = 40
    private static let brightPixelTolerance = 0.03
    private static let minBarFraction = 0.03
    private static let maxBarFraction = 0.2
    private static let edgePadding = 0.01

    /// Bar height as a fraction of the frame (0 = no bars), or nil when the
    /// frame can't tell (all dark, or bars too large to be letterboxing).
    static func detectBar(in buffer: CVPixelBuffer) -> Double? {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard width > 0, height > 0 else { return nil }
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        let allowedBright = Int(Double(sampleColumns) * brightPixelTolerance)

        func isDark(_ row: Int) -> Bool {
            let y = min(height - 1, row * height / sampleRows)
            let rowStart = pixels + y * bytesPerRow
            var bright = 0
            for column in 0..<sampleColumns {
                let x = min(width - 1, column * width / sampleColumns + width / (sampleColumns * 2))
                let pixel = rowStart + x * 4
                let luma = (Int(pixel[2]) * 299 + Int(pixel[1]) * 587 + Int(pixel[0]) * 114) / 1000
                if luma > darkLuma {
                    bright += 1
                    if bright > allowedBright { return false }
                }
            }
            return true
        }

        guard let top = (0..<sampleRows).first(where: { !isDark($0) }),
              let bottom = (0..<sampleRows).reversed().first(where: { !isDark($0) }) else { return nil }
        let bar = Double(min(top, sampleRows - 1 - bottom)) / Double(sampleRows)
        if bar > maxBarFraction { return nil }
        if bar < minBarFraction { return 0 }
        return bar + edgePadding
    }

    static func zoom(for bar: Double) -> CGFloat {
        bar <= 0 ? 1 : CGFloat(1 / (1 - 2 * bar))
    }
}

/// Accepts a bar size once it has been seen in 4 samples in a row (within
/// 1.5%), so a dark scene or a title card doesn't trigger a zoom.
struct LetterboxTracker {
    private static let stableSamples = 4
    private static let stableTolerance = 0.015

    private var streakBar: Double?
    private var streak = 0

    /// The zoom to apply once the bar is stable and non-zero.
    mutating func onSample(_ bar: Double) -> CGFloat? {
        if let current = streakBar, abs(bar - current) <= Self.stableTolerance {
            streak += 1
            streakBar = min(current, bar)
        } else {
            streak = 1
            streakBar = bar
        }
        guard streak >= Self.stableSamples, let stable = streakBar, stable > 0 else { return nil }
        return LetterboxDetector.zoom(for: stable)
    }
}

// MARK: - HLS master loader

/// Serves the rewritten HLS master playlist to AVPlayer from a custom URL
/// scheme. Only the master goes through here: the variant and audio playlists
/// it lists are absolute https URLs AVPlayer loads itself.
final class TrailerHLSLoader: NSObject, AVAssetResourceLoaderDelegate {
    static let scheme = "flixor-trailer"
    static let queue = DispatchQueue(label: "flixor.trailer.hls-loader")

    private let master: Data

    init(master: String) {
        self.master = Data(master.utf8)
    }

    static func masterURL(for videoKey: String) -> URL {
        URL(string: "\(scheme)://youtube/\(videoKey)/master.m3u8")!
    }

    /// A unique address for a rewritten direct-stream master.
    static func directMasterURL() -> URL {
        URL(string: "\(scheme)://direct/\(UUID().uuidString)/master.m3u8")!
    }

    /// Fetches an HLS master playlist and keeps only its SDR versions, with
    /// every URI made absolute (the rewritten copy is served from our own
    /// scheme). Nil when it can't be fetched or has no SDR versions.
    static func sdrOnlyMaster(for url: URL) async -> String? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: data, encoding: .utf8) else { return nil }
        let base = response.url ?? url
        return sdrOnly(master: text, base: base)
    }

    static func sdrOnly(master text: String, base: URL) -> String? {
        func absolute(_ uri: String) -> String {
            URL(string: uri, relativeTo: base)?.absoluteURL.absoluteString ?? uri
        }
        func isHDR(_ line: String) -> Bool {
            line.contains("VIDEO-RANGE=PQ") || line.contains("VIDEO-RANGE=HLG")
                || line.contains("dvh1") || line.contains("dvhe")
        }
        func absolutizeAttributes(_ line: String) -> String {
            guard let range = line.range(of: #"URI="[^"]+""#, options: .regularExpression) else { return line }
            let uri = String(line[range].dropFirst(5).dropLast())
            return line.replacingCharacters(in: range, with: "URI=\"\(absolute(uri))\"")
        }

        var output: [String] = []
        var keptVariants = 0
        var skipNextURI = false
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#EXT-X-STREAM-INF") {
                if isHDR(line) {
                    skipNextURI = true
                } else {
                    output.append(line)
                    keptVariants += 1
                }
            } else if line.hasPrefix("#EXT-X-I-FRAME-STREAM-INF") {
                if !isHDR(line) { output.append(absolutizeAttributes(line)) }
            } else if line.hasPrefix("#") {
                output.append(absolutizeAttributes(line))
            } else if line.isEmpty {
                continue
            } else if skipNextURI {
                skipNextURI = false
            } else {
                output.append(absolute(line))
            }
        }
        return keptVariants > 0 ? output.joined(separator: "\n") + "\n" : nil
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard loadingRequest.request.url?.scheme == Self.scheme else { return false }
        if let info = loadingRequest.contentInformationRequest {
            info.contentType = "public.m3u-playlist"
            info.contentLength = Int64(master.count)
            info.isByteRangeAccessSupported = false
        }
        if let dataRequest = loadingRequest.dataRequest {
            let start = Int(dataRequest.requestedOffset)
            let length = dataRequest.requestsAllDataToEndOfResource
                ? master.count - start
                : min(dataRequest.requestedLength, master.count - start)
            if start >= 0, length > 0, start < master.count {
                dataRequest.respond(with: master.subdata(in: start..<(start + length)))
            }
        }
        loadingRequest.finishLoading()
        return true
    }
}

// MARK: - Views

/// The trailer video with no controls: AVPlayerLayer for the native backend,
/// the YouTube web view (slightly overscanned to hide its chrome) for the embed.
struct TrailerVideoSurface: View {
    @ObservedObject var player: TrailerPlayer
    /// Fill the frame (cropping) instead of fitting it.
    var fill = true
    /// Extra zoom for the embed only, so YouTube's title strip and logo fall
    /// outside the clip. The native video has none.
    var embedOverscan: CGFloat = 1.0

    var body: some View {
        GeometryReader { geo in
            Group {
                switch player.backend {
                case .native(let avPlayer):
                    let zoom = fill ? player.letterboxZoom : 1
                    TrailerPlayerLayerView(player: avPlayer, fill: fill)
                        .frame(width: geo.size.width * zoom, height: geo.size.height * zoom)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .animation(.easeInOut(duration: 0.6), value: zoom)
                case .embed(let ytPlayer):
                    YouTubePlayerView(ytPlayer) { _ in EmptyView() }
                        .frame(width: geo.size.width * embedOverscan, height: geo.size.height * embedOverscan)
                        .frame(width: geo.size.width, height: geo.size.height)
                case nil:
                    Color.clear
                }
            }
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Bare AVPlayerLayer host.
struct TrailerPlayerLayerView: NSViewRepresentable {
    let player: AVPlayer
    var fill: Bool

    func makeNSView(context: Context) -> PlayerLayerNSView {
        let view = PlayerLayerNSView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        return view
    }

    func updateNSView(_ view: PlayerLayerNSView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
        view.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
    }

    static func dismantleNSView(_ view: PlayerLayerNSView, coordinator: ()) {
        view.playerLayer.player = nil
    }

    final class PlayerLayerNSView: NSView {
        let playerLayer = AVPlayerLayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer = CALayer()
            layer?.backgroundColor = NSColor.clear.cgColor
            playerLayer.backgroundColor = NSColor.clear.cgColor
            layer?.addSublayer(playerLayer)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = bounds
            CATransaction.commit()
        }
    }
}

/// Native player with AVKit's own controls (for the trailer modal).
struct TrailerAVPlayerControlsView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.videoGravity = .resizeAspect
        view.showsFullScreenToggleButton = true
        view.allowsPictureInPicturePlayback = true
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player = nil
    }
}
