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
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            if handleKeyDown(event) {
                return nil // Event handled, don't propagate
            }
            return event // Event not handled, propagate
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
        #endif
    }

    /// Seek step from the profile's Player settings (Small Seek / Large Seek).
    func seekSeconds(large: Bool) -> TimeInterval {
        let value = large ? UserDefaults.standard.seekTimeLarge : UserDefaults.standard.seekTimeSmall
        return TimeInterval(max(1, value))
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        // Get the key code and characters
        let keyCode = event.keyCode
        let characters = event.charactersIgnoringModifiers?.lowercased() ?? ""

        // Handle arrow keys and special keys
        switch keyCode {
        case 49: // Space bar
            viewModel.togglePlayPause()
            return true

        case 123: // Left arrow (Shift = large seek)
            viewModel.skip(seconds: -seekSeconds(large: event.modifierFlags.contains(.shift)))
            return true

        case 124: // Right arrow (Shift = large seek)
            viewModel.skip(seconds: seekSeconds(large: event.modifierFlags.contains(.shift)))
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
            if isFullScreen {
                toggleFullScreen()
            } else {
                viewModel.stopPlayback()
                dismiss()
            }
            return true

        default:
            // Handle character keys
            switch characters {
            case "m":
                viewModel.toggleMute()
                return true
            case "p":
                toggleMPVPiP()
                return true
            case "f":
                toggleFullScreen()
                return true
            case "i":
                // Toggle performance stats overlay
                viewModel.togglePerformanceOverlay()
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
                return false
            }
        }
    }
}
