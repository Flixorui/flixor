//
//  PlayerViewModel+Engine.swift
//  FlixorMac
//
//  Playback-engine plumbing: per-file engine state (applied on file-loaded),
//  live application of engine settings changed in Settings, and aspect modes.
//

import Foundation

// MARK: - Aspect mode

/// How the video fills the player view.
enum PlayerAspectMode: String, CaseIterable, Identifiable, Codable {
    /// Whole picture visible, letterboxed/pillarboxed (default).
    case fit
    /// Crop to fill the view, keeping proportions (mpv `panscan=1`).
    case fill
    /// Stepwise zoom into the picture (mpv `video-zoom`), see `zoomFactors`.
    case zoom
    /// Stretch to the view, ignoring proportions (mpv `keepaspect=no`).
    case stretch

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fit: return String(localized: "Fit")
        case .fill: return String(localized: "Fill")
        case .zoom: return String(localized: "Zoom")
        case .stretch: return String(localized: "Stretch")
        }
    }

    /// SF Symbol for menus/buttons.
    var systemImage: String {
        switch self {
        case .fit: return "rectangle.arrowtriangle.2.inward"
        case .fill: return "rectangle.arrowtriangle.2.outward"
        case .zoom: return "plus.magnifyingglass"
        case .stretch: return "arrow.left.and.right.square"
        }
    }

    /// Zoom factors for `.zoom`, indexed by `PlayerViewModel.zoomStep`.
    static let zoomFactors: [Double] = [1.1, 1.2, 1.33, 1.5, 1.75, 2.0]
}

/// Holds NotificationCenter tokens and removes them when the owner goes away
/// (PlayerViewModel's deinit lives in a file this feature doesn't own).
final class PlaybackEngineObserverBag {
    private var tokens: [NSObjectProtocol] = []
    var isEmpty: Bool { tokens.isEmpty }

    func add(_ token: NSObjectProtocol) {
        tokens.append(token)
    }

    deinit {
        tokens.forEach { NotificationCenter.default.removeObserver($0) }
    }
}

extension PlayerViewModel {
    // MARK: - Aspect API

    /// Current zoom factor (1.0 unless `aspectMode == .zoom`).
    var zoomFactor: Double {
        guard aspectMode == .zoom else { return 1.0 }
        let factors = PlayerAspectMode.zoomFactors
        return factors[min(max(0, zoomStep), factors.count - 1)]
    }

    /// Switches the aspect mode, applies it to mpv and saves it for this profile.
    func setAspectMode(_ mode: PlayerAspectMode) {
        aspectMode = mode
        UserDefaults.standard.playerAspectMode = mode
        applyAspectMode()
    }

    /// Cycles Fit -> Fill -> Zoom -> Stretch -> Fit (e.g. for a keyboard shortcut).
    func cycleAspectMode() {
        let all = PlayerAspectMode.allCases
        let next = all[((all.firstIndex(of: aspectMode) ?? 0) + 1) % all.count]
        setAspectMode(next)
    }

    /// One zoom step in (switches to `.zoom` at the first step when not zoomed).
    func zoomIn() {
        if aspectMode != .zoom {
            setZoomStep(0)
        } else {
            setZoomStep(zoomStep + 1)
        }
    }

    /// One zoom step out; stepping out of the first step returns to `.fit`.
    func zoomOut() {
        guard aspectMode == .zoom else { return }
        if zoomStep <= 0 {
            setAspectMode(.fit)
        } else {
            setZoomStep(zoomStep - 1)
        }
    }

    /// Selects a zoom step (clamped to `PlayerAspectMode.zoomFactors`) and switches to `.zoom`.
    func setZoomStep(_ step: Int) {
        zoomStep = min(max(0, step), PlayerAspectMode.zoomFactors.count - 1)
        UserDefaults.standard.playerZoomStep = zoomStep
        setAspectMode(.zoom)
    }

    /// Pushes `aspectMode`/`zoomStep` to mpv.
    func applyAspectMode() {
        guard let mpv = mpvController else { return }
        switch aspectMode {
        case .fit: mpv.applyAspect(panscan: 0, zoomFactor: 1, keepAspect: true)
        case .fill: mpv.applyAspect(panscan: 1, zoomFactor: 1, keepAspect: true)
        case .zoom: mpv.applyAspect(panscan: 0, zoomFactor: zoomFactor, keepAspect: true)
        case .stretch: mpv.applyAspect(panscan: 0, zoomFactor: 1, keepAspect: false)
        }
    }

    // MARK: - Per-file engine state

    /// Called on every mpv file-loaded (through `applySubtitleStyling()`): wires
    /// engine observers once, re-applies aspect mode, syncs the published speed
    /// with mpv and starts loading subtitle cues / the subtitle hash lookup.
    func applyEngineStateForLoadedFile() {
        registerEngineObserversIfNeeded()
        // Fit is mpv's default: leave it alone so custom MPV config entries still apply
        if aspectMode != .fit { applyAspectMode() }

        if !isSpeedBoostActive, let speed = mpvController?.getPropertyIfAvailable("speed"), speed > 0 {
            // mpv starts at the profile's default speed; keep the UI in sync
            playbackSpeed = Float(speed)
        }

        mpvController?.onSubtitleCueShown = { [weak self] shown in
            Task { @MainActor [weak self] in
                self?.recordShownSubtitleCue(shown)
            }
        }
        recentSubtitleCues = []
        refreshSubtitleCues()
        startSubtitleHashLookupIfNeeded()
    }

    /// Applies engine settings changed in Settings while this player is open.
    private func registerEngineObserversIfNeeded() {
        guard engineObservers.isEmpty else { return }
        let token = NotificationCenter.default.addObserver(
            forName: .playbackEngineSettingsDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadEngineSettingsFromDefaults()
            }
        }
        engineObservers.add(token)
    }

    /// Re-reads the profile's engine settings and applies them live.
    func reloadEngineSettingsFromDefaults() {
        let defaults = UserDefaults.standard
        let mode = defaults.playerAspectMode
        let step = defaults.playerZoomStep
        if mode != aspectMode || step != zoomStep {
            aspectMode = mode
            zoomStep = step
            applyAspectMode()
        }
        applySubtitleAppearanceFromDefaults()
        if subtitleFilterSDH != defaults.subtitleFilterSDH {
            setSubtitleFilterSDH(defaults.subtitleFilterSDH)
        }
    }
}
