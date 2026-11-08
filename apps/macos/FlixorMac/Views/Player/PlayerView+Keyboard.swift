//
//  PlayerView+Keyboard.swift
//  FlixorMac
//
//  Player keyboard shortcuts (local key monitor and key handling)
//

import SwiftUI

extension PlayerView {
    // MARK: - Keyboard Controls

    func startKeyboardMonitoring() {
        #if os(macOS)
        // Remove any existing monitor first
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }

        // Add new monitor and store the reference
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [self] event in
            let handled = event.type == .keyDown ? handleKeyDown(event) : handleKeyUp(event)
            return handled ? nil : event // Handled events don't propagate
        }
        #endif
    }

    func stopKeyboardMonitoring() {
        #if os(macOS)
        // IMPORTANT: Must explicitly remove the event monitor
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }
        releaseSpaceHold()
        #endif
    }

    /// Seek step from the profile's Player settings (Small Seek / Large Seek).
    func seekSeconds(large: Bool) -> TimeInterval {
        let value = large ? UserDefaults.standard.seekTimeLarge : UserDefaults.standard.seekTimeSmall
        return TimeInterval(max(1, value))
    }

    private static let spaceKeyCode: UInt16 = 49
    private static let fineSeekSeconds: TimeInterval = 2
    private static let speedStep: Float = 0.25
    private static let subtitleDelayStep = 0.1
    private static let subtitleDelayLimit = 3600.0

    /// True while typing somewhere, so shortcuts leave the keys alone. The field
    /// editor behind a TextField is an NSTextView, which is an NSText.
    private func isTextInputFocused(for event: NSEvent) -> Bool {
        (event.window ?? NSApp.keyWindow)?.firstResponder is NSText
    }

    private func handleKeyUp(_ event: NSEvent) -> Bool {
        guard event.keyCode == Self.spaceKeyCode, isSpaceHeld else { return false }
        spaceHoldTask?.cancel()
        spaceHoldTask = nil
        isSpaceHeld = false
        if spaceBoostEngaged {
            spaceBoostEngaged = false
            viewModel.endSpeedBoost()
        } else {
            viewModel.togglePlayPause()
        }
        return true
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard !isTextInputFocused(for: event) else { return false }

        // Get the key code and characters
        let keyCode = event.keyCode
        let characters = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let isFine = event.modifierFlags.contains(.option)
        let isLarge = event.modifierFlags.contains(.shift)

        // Handle arrow keys and special keys
        switch keyCode {
        case Self.spaceKeyCode: // Tap = play/pause (on release), hold = 2x
            if !event.isARepeat && !isSpaceHeld { beginSpaceHold() }
            return true

        case 123: // Left arrow (Option = fine seek, Shift = large seek)
            viewModel.skip(seconds: -(isFine ? Self.fineSeekSeconds : seekSeconds(large: isLarge)))
            return true

        case 124: // Right arrow (Option = fine seek, Shift = large seek)
            viewModel.skip(seconds: isFine ? Self.fineSeekSeconds : seekSeconds(large: isLarge))
            return true

        case 126: // Up arrow
            let newVolume = min(1.0, viewModel.volume + 0.1)
            viewModel.setVolume(newVolume)
            return true

        case 125: // Down arrow
            let newVolume = max(0.0, viewModel.volume - 0.1)
            viewModel.setVolume(newVolume)
            return true

        case 53: // Escape
            if showShortcutsOverlay {
                showShortcutsOverlay = false
            } else if isFullScreen {
                toggleFullScreen()
            } else {
                viewModel.stopPlayback()
                dismiss()
            }
            return true

        default:
            return handleCharacterKey(characters, event: event)
        }
    }

    private func handleCharacterKey(_ characters: String, event: NSEvent) -> Bool {
        // Keys that toggle something shouldn't flip back and forth while held.
        let isRepeat = event.isARepeat

        switch characters {
        case "m":
            if !isRepeat { viewModel.toggleMute() }
            return true
        case "p":
            if !isRepeat { toggleMPVPiP() }
            return true
        case "f":
            if !isRepeat { toggleFullScreen() }
            return true
        case "i":
            // Toggle performance stats overlay
            if !isRepeat { viewModel.togglePerformanceOverlay() }
            return true
        case "[":
            // Previous chapter
            viewModel.previousChapter()
            return true
        case "]":
            // Next chapter
            viewModel.nextChapter()
            return true
        default:
            break
        }

        // The keys below are plain letters: leave Cmd+H, Cmd+A, Cmd+V etc. to the system.
        guard event.modifierFlags.isDisjoint(with: [.command, .control]) else { return false }

        switch characters {
        case "j":
            viewModel.skip(seconds: -seekSeconds(large: true))
        case "l":
            viewModel.skip(seconds: seekSeconds(large: true))
        case "k":
            if !isRepeat { viewModel.togglePlayPause() }
        case "g":
            adjustSubtitleDelay(by: -Self.subtitleDelayStep)
        case "h":
            adjustSubtitleDelay(by: Self.subtitleDelayStep)
        case "v":
            if !isRepeat { cycleSubtitleTrack() }
        case "b":
            if !isRepeat { cycleAudioTrack() }
        case "<":
            stepSpeed(by: -Self.speedStep)
        case ">":
            stepSpeed(by: Self.speedStep)
        case "/":
            viewModel.setPlaybackSpeed(1.0)
            showKeyboardFeedback("Speed 1×")
        case "n":
            guard event.modifierFlags.contains(.shift) else { return false }
            if !isRepeat { viewModel.playNext() }
        case "a":
            guard !isRepeat else { return true }
            viewModel.cycleAspectMode()
            showKeyboardFeedback("Aspect: \(viewModel.aspectMode.displayName)")
        case "?":
            if !isRepeat {
                withAnimation(DS.Motion.standard) { showShortcutsOverlay.toggle() }
            }
        default:
            return false
        }
        return true
    }

    // MARK: - Hold Space for 2x

    private func beginSpaceHold() {
        isSpaceHeld = true
        spaceBoostEngaged = false
        spaceHoldTask?.cancel()
        spaceHoldTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            // Paused: holding has nothing to speed up, so the release just plays.
            guard !Task.isCancelled, isSpaceHeld, viewModel.isPlaying else { return }
            spaceBoostEngaged = true
            viewModel.beginSpeedBoost()
        }
    }

    /// Drops any Space hold without toggling playback (focus lost, player closing).
    func releaseSpaceHold() {
        spaceHoldTask?.cancel()
        spaceHoldTask = nil
        isSpaceHeld = false
        if spaceBoostEngaged {
            spaceBoostEngaged = false
            viewModel.endSpeedBoost()
        }
    }

    // MARK: - Shortcut actions

    private func stepSpeed(by delta: Float) {
        viewModel.stepPlaybackSpeed(by: delta)
        showKeyboardFeedback(String(format: "Speed %g×", viewModel.playbackSpeed))
    }

    private func adjustSubtitleDelay(by delta: Double) {
        let limit = Self.subtitleDelayLimit
        let delay = min(limit, max(-limit, ((viewModel.subtitleDelay + delta) * 1000).rounded() / 1000))
        viewModel.setSubtitleDelay(delay)
        showKeyboardFeedback(String(format: "Subtitle offset %+.1f s", delay))
    }

    /// Off -> embedded tracks -> addon subtitles -> Off.
    private func cycleSubtitleTrack() {
        let embedded = viewModel.availableSubtitleTracks
        let external = viewModel.availableExternalSubtitleOptions
        guard !embedded.isEmpty || !external.isEmpty else {
            showKeyboardFeedback("No subtitle tracks")
            return
        }

        let current: Int
        if let externalId = viewModel.selectedExternalSubtitleId,
           let index = external.firstIndex(where: { $0.id == externalId }) {
            current = 1 + embedded.count + index
        } else if let index = embedded.firstIndex(where: { $0.id == viewModel.currentSubtitleTrackId }) {
            current = 1 + index
        } else {
            current = 0
        }

        let next = (current + 1) % (1 + embedded.count + external.count)
        if next == 0 {
            viewModel.disableSubtitles()
            showKeyboardFeedback("Subtitles off")
        } else if next <= embedded.count {
            let track = embedded[next - 1]
            viewModel.setSubtitleTrack(track.id)
            showKeyboardFeedback("Subtitles: \(track.displayName)")
        } else {
            let subtitle = external[next - 1 - embedded.count]
            viewModel.loadExternalSubtitle(subtitle)
            showKeyboardFeedback("Subtitles: \(subtitle.lang.uppercased()) • \(subtitle.addonName ?? "Stremio")")
        }
    }

    private func cycleAudioTrack() {
        let tracks = viewModel.availableAudioTracks
        guard tracks.count > 1 else {
            showKeyboardFeedback(tracks.isEmpty ? "No audio tracks" : "Only one audio track")
            return
        }
        let current = tracks.firstIndex(where: { $0.id == viewModel.currentAudioTrackId }) ?? -1
        let track = tracks[(current + 1) % tracks.count]
        viewModel.setAudioTrack(track.id)
        showKeyboardFeedback("Audio: \(track.displayName)")
    }

    /// Brief confirmation for shortcuts that change something off-screen.
    private func showKeyboardFeedback(_ message: String) {
        keyboardFeedback = message
        keyboardFeedbackTask?.cancel()
        keyboardFeedbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            keyboardFeedback = nil
        }
    }
}
