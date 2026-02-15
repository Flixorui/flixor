import Foundation
import Libmpv
import UIKit

/// warning: metal API validation has been disabled to ignore crash when playing HDR videos.
/// Edit Scheme -> Run -> Diagnostics -> Metal API Validation -> Turn it off
/// https://github.com/KhronosGroup/MoltenVK/issues/2226
final class MPVPlayerViewController: UIViewController {
    var metalLayer = MetalLayer()
    private var lastDrawableSize: CGSize?
    var mpv: OpaquePointer?
    var playDelegate: MPVPlayerDelegate?
    private let queue = DispatchQueue(label: "mpv", qos: .userInitiated)
    private let queueSpecificKey = DispatchSpecificKey<UInt8>()
    private var isDestroying = false
    private let options: PlayerOptions

    var playUrl: URL?
    var hdrAvailable: Bool = false
    var hdrEnabled = false {
        didSet {
            // FIXME: target-colorspace-hint does not support being changed at runtime.
            // this option should be set as early as possible otherwise can cause issues
            // not recommended to use this way.
            guard let mpv else { return }
            if hdrEnabled {
                checkError(mpv_set_option_string(mpv, "target-colorspace-hint", "yes"))
            } else {
                checkError(mpv_set_option_string(mpv, "target-colorspace-hint", "no"))
            }
        }
    }

    init(options: PlayerOptions) {
        self.options = options
        queue.setSpecific(key: queueSpecificKey, value: 1)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        destruct()
        updateIdleTimer(isPlaying: false)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        metalLayer.framebufferOnly = true
        metalLayer.backgroundColor = UIColor.black.cgColor

        view.layer.addSublayer(metalLayer)

        updateMetalLayerLayout()
        setupMpv()

        if let url = playUrl {
            loadFile(url)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        updateMetalLayerLayout()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        updateIdleTimer(isPlaying: false)
    }

    func setupMpv() {
        mpv = mpv_create()
        guard let mpv else {
            print("failed creating context\n")
            exit(1)
        }

        // https://mpv.io/manual/stable/#options
        checkError(mpv_request_log_messages(mpv, "no"))
        checkError(mpv_set_option(mpv, "wid", MPV_FORMAT_INT64, &metalLayer))
        checkError(mpv_set_option_string(mpv, "vo", "gpu-next"))
        checkError(mpv_set_option_string(mpv, "gpu-api", "vulkan"))
        checkError(mpv_set_option_string(mpv, "gpu-context", "moltenvk"))
        checkError(mpv_set_option_string(mpv, "hwdec", "videotoolbox"))
        checkError(mpv_set_option_string(mpv, "video-rotate", "no"))
        let subtitleScale = Double(options.subtitleScale) / 100.0
        let scaleString = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), subtitleScale)
        checkError(mpv_set_option_string(mpv, "sub-scale", scaleString))

//        checkError(mpv_set_option_string(mpv, "target-colorspace-hint", "yes")) // HDR passthrough
//        checkError(mpv_set_option_string(mpv, "tone-mapping-visualize", "yes"))  // only for debugging purposes
//        checkError(mpv_set_option_string(mpv, "profile", "fast"))   // can fix frame drop in poor device when play 4k

        checkError(mpv_initialize(mpv))

        mpv_observe_property(mpv, 0, MPVProperty.pause, MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, MPVProperty.videoParamsSigPeak, MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, MPVProperty.pausedForCache, MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, MPVProperty.timePos, MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, MPVProperty.duration, MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, MPVProperty.demuxerCacheDuration, MPV_FORMAT_DOUBLE)
        mpv_set_wakeup_callback(mpv, { ctx in
            guard let ctx else { return }
            let client = Unmanaged<MPVPlayerViewController>.fromOpaque(ctx).takeUnretainedValue()
            client.readEvents()
        }, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))

        setupNotification()
    }

    func setupNotification() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(enterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(enterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil,
        )
    }

    @objc func enterBackground() {
        // fix black screen issue when app enter foreground again
        guard let mpv else { return }
        pause()
        checkError(mpv_set_option_string(mpv, "vid", "no"))
    }

    @objc func enterForeground() {
        guard let mpv else { return }
        checkError(mpv_set_option_string(mpv, "vid", "auto"))
        play()
    }

    func loadFile(
        _ url: URL,
    ) {
        var args = [url.absoluteString]
        let options = [String]()

        args.append("replace")

        if !options.isEmpty {
            args.append(options.joined(separator: ","))
        }

        command("loadfile", args: args)
    }

    func togglePause() {
        getFlag(MPVProperty.pause) ? play() : pause()
    }

    func play() {
        setFlag(MPVProperty.pause, false)
        updateIdleTimer(isPlaying: true)
    }

    func pause() {
        setFlag(MPVProperty.pause, true)
        updateIdleTimer(isPlaying: false)
    }

    func seek(to time: Double) {
        setDouble(MPVProperty.timePos, time)
    }

    func seek(by delta: Double) {
        guard mpv != nil else { return }
        command(
            "seek",
            args: [
                String(delta),
                "relative",
                "exact",
            ],
        )
    }

    func setPlaybackRate(_ rate: Float) {
        let clamped = max(0.1, Double(rate))
        setDouble("speed", clamped)
    }

    func setVolume(_ value: Double) {
        let clamped = min(max(value, 0), 100)
        setDouble("volume", clamped)
    }

    func setAudioTrack(id: Int?) {
        setTrackProperty("aid", trackID: id)
    }

    func setSubtitleTrack(id: Int?) {
        setTrackProperty("sid", trackID: id)
    }

    func trackList() -> [PlayerTrack] {
        guard let mpv else { return [] }

        var node = mpv_node()
        guard mpv_get_property(mpv, "track-list", MPV_FORMAT_NODE, &node) >= 0 else { return [] }
        defer { mpv_free_node_contents(&node) }

        guard node.format == MPV_FORMAT_NODE_ARRAY, let list = node.u.list?.pointee else { return [] }

        var tracks: [PlayerTrack] = []
        for index in 0 ..< Int(list.num) {
            let entry = list.values[index]
            guard entry.format == MPV_FORMAT_NODE_MAP, let map = entry.u.list?.pointee else { continue }
            let values = parseMap(map)

            guard
                let typeString = values["type"] as? String,
                let type = PlayerTrack.TrackType(rawValue: typeString),
                let id = values["id"] as? Int
            else {
                continue
            }

            let track = PlayerTrack(
                id: id,
                ffIndex: values["ff-index"] as? Int,
                type: type,
                title: values["title"] as? String,
                language: values["lang"] as? String,
                codec: values["codec"] as? String,
                isDefault: values["default"] as? Bool ?? false,
                isSelected: values["selected"] as? Bool ?? false,
            )

            tracks.append(track)
        }

        return tracks
    }

    private func getFlag(_ name: String) -> Bool {
        guard let mpv else { return false }
        var data = Int64()
        mpv_get_property(mpv, name, MPV_FORMAT_FLAG, &data)
        return data > 0
    }

    private func setFlag(_ name: String, _ flag: Bool) {
        guard let mpv else { return }
        var data: Int = flag ? 1 : 0
        mpv_set_property(mpv, name, MPV_FORMAT_FLAG, &data)
    }

    private func setDouble(_ name: String, _ value: Double) {
        guard let mpv else { return }
        var data = value
        mpv_set_property(mpv, name, MPV_FORMAT_DOUBLE, &data)
    }

    private func setTrackProperty(_ name: String, trackID: Int?) {
        let value = trackID.map(String.init) ?? "no"
        command("set", args: [name, value])
    }

    func command(
        _ command: String,
        args: [String?] = [],
        checkForErrors: Bool = true,
        returnValueCallback: ((Int32) -> Void)? = nil,
    ) {
        guard let mpv else {
            return
        }
        var cargs = makeCArgs(command, args).map { $0.flatMap { UnsafePointer<CChar>(strdup($0)) } }
        defer {
            for ptr in cargs where ptr != nil {
                free(UnsafeMutablePointer(mutating: ptr!))
            }
        }
        // print("\(command) -- \(args)")
        let returnValue = mpv_command(mpv, &cargs)
        if checkForErrors {
            checkError(returnValue)
        }
        if let cb = returnValueCallback {
            cb(returnValue)
        }
    }

    private func makeCArgs(_ command: String, _ args: [String?]) -> [String?] {
        if !args.isEmpty, args.last == nil {
            fatalError("Command do not need a nil suffix")
        }

        var strArgs = args
        strArgs.insert(command, at: 0)
        strArgs.append(nil)

        return strArgs
    }

    func readEvents() {
        queue.async { [weak self] in
            guard let self else { return }

            while true {
                guard let mpv else { break }
                let event = mpv_wait_event(mpv, 0)
                if event?.pointee.event_id == MPV_EVENT_NONE {
                    break
                }

                switch event!.pointee.event_id {
                case MPV_EVENT_PROPERTY_CHANGE:
                    let dataOpaquePtr = OpaquePointer(event!.pointee.data)
                    if let eventProperty = UnsafePointer<mpv_event_property>(dataOpaquePtr)?.pointee {
                        let propertyName = String(cString: eventProperty.name)
                        guard let playerProperty = PlayerProperty(rawValue: propertyName) else { break }
                        switch playerProperty {
                        case .videoParamsSigPeak:
                            if let sigPeak = UnsafePointer<Double>(OpaquePointer(eventProperty.data))?.pointee {
                                DispatchQueue.main.async {
                                    let maxEDRRange = self.view.window?.screen.potentialEDRHeadroom ?? 1.0
                                    // display screen support HDR and current playing HDR video
                                    self.hdrAvailable = maxEDRRange > 1.0 && sigPeak > 1.0
                                    self.playDelegate?.propertyChange(mpv: mpv, property: playerProperty, data: sigPeak)
                                }
                            }
                        case .pause:
                            let pausedValue = UnsafePointer<Int64>(OpaquePointer(eventProperty.data))?.pointee ?? 0
                            let isPaused = pausedValue > 0
                            DispatchQueue.main.async {
                                self.playDelegate?.propertyChange(mpv: mpv, property: playerProperty, data: isPaused)
                                self.updateIdleTimer(isPlaying: !isPaused)
                            }
                        case .pausedForCache:
                            let buffering = UnsafePointer<Bool>(OpaquePointer(eventProperty.data))?.pointee ?? true
                            DispatchQueue.main.async {
                                self.playDelegate?.propertyChange(mpv: mpv, property: playerProperty, data: buffering)
                            }
                        case .timePos, .duration, .demuxerCacheDuration:
                            let value = UnsafePointer<Double>(OpaquePointer(eventProperty.data))?.pointee
                            DispatchQueue.main.async {
                                self.playDelegate?.propertyChange(mpv: mpv, property: playerProperty, data: value)
                            }
                        default:
                            break
                        }
                    }
                case MPV_EVENT_END_FILE:
                    let endFileData = UnsafeMutablePointer<mpv_event_end_file>(OpaquePointer(event!.pointee.data))
                    let reason = endFileData?.pointee.reason ?? MPV_END_FILE_REASON_ERROR
                    if reason == MPV_END_FILE_REASON_EOF {
                        updateIdleTimer(isPlaying: false)
                        DispatchQueue.main.async {
                            self.playDelegate?.playbackEnded()
                        }
                    }
                case MPV_EVENT_FILE_LOADED:
                    DispatchQueue.main.async {
                        self.playDelegate?.fileLoaded()
                    }
                case MPV_EVENT_SHUTDOWN:
                    print("event: shutdown\n")
                    destruct()
                    return
                case MPV_EVENT_LOG_MESSAGE:
                    let msg = UnsafeMutablePointer<mpv_event_log_message>(OpaquePointer(event!.pointee.data))
                    print(
                        "[\(String(cString: (msg!.pointee.prefix)!))] \(String(cString: (msg!.pointee.level)!)): \(String(cString: (msg!.pointee.text)!))",
                        terminator: "",
                    )
                default:
                    let eventName = mpv_event_name(event!.pointee.event_id)
                    print("event: \(String(cString: eventName!))")
                }
            }
        }
    }

    func destruct() {
        NotificationCenter.default.removeObserver(self)
        guard let mpv, !isDestroying else { return }
        isDestroying = true

        // Drop the wakeup callback to avoid mpv calling back into a deallocated controller.
        mpv_set_wakeup_callback(mpv, nil, nil)

        let mpvHandle = mpv
        self.mpv = nil
        let destroy = { [weak self] in
            mpv_terminate_destroy(mpvHandle)
            guard let self else { return }
            DispatchQueue.main.async {
                self.isDestroying = false
            }
        }

        if DispatchQueue.getSpecific(key: queueSpecificKey) != nil {
            destroy()
        } else {
            // Block until teardown is complete so CAMetalLayer-backed resources are not deallocated
            // while MoltenVK command buffers still reference them.
            queue.sync(execute: destroy)
        }
    }

    private func updateIdleTimer(isPlaying: Bool) {
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = isPlaying
        }
    }

    func updateMetalLayerLayout() {
        debugPrint("updateMetalLayerLayout: \(view.bounds.size)")
        let nativeScale = view.window?.screen.nativeScale ?? UIScreen.main.nativeScale
        let size = view.bounds.size
        let roundedDrawableSize = CGSize(
            width: (size.width * nativeScale).rounded(),
            height: (size.height * nativeScale).rounded(),
        )
        metalLayer.contentsScale = nativeScale
        metalLayer.frame = view.bounds

        guard roundedDrawableSize != lastDrawableSize else { return }
        metalLayer.drawableSize = roundedDrawableSize
        lastDrawableSize = roundedDrawableSize
    }

    private func parseMap(_ map: mpv_node_list) -> [String: Any] {
        var values: [String: Any] = [:]

        for index in 0 ..< Int(map.num) {
            guard let keyPointer = map.keys?[index] else { continue }
            let key = String(cString: keyPointer)
            let valueNode = map.values[index]

            switch valueNode.format {
            case MPV_FORMAT_STRING:
                if let pointer = valueNode.u.string {
                    values[key] = String(cString: pointer)
                }
            case MPV_FORMAT_INT64:
                values[key] = Int(valueNode.u.int64)
            case MPV_FORMAT_DOUBLE:
                values[key] = valueNode.u.double_
            case MPV_FORMAT_FLAG:
                values[key] = valueNode.u.flag != 0
            default:
                continue
            }
        }

        return values
    }

    private func checkError(_ status: CInt) {
        if status < 0 {
            print("MPV API error: \(String(cString: mpv_error_string(status)))\n")
        }
    }
}
