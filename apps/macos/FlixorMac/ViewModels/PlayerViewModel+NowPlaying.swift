//
//  PlayerViewModel+NowPlaying.swift
//  FlixorMac
//
//  Now Playing info, remote commands (media keys / Control Center) and display sleep prevention
//

import Foundation
import AppKit
import MediaPlayer

extension PlayerViewModel {
    // MARK: - Now Playing Info (Control Center / Lock Screen)

    func setupNowPlayingInfo() {
        var nowPlayingInfo = [String: Any]()

        // Title
        nowPlayingInfo[MPMediaItemPropertyTitle] = item.title

        // Show/Series info
        if let grandparentTitle = item.grandparentTitle {
            nowPlayingInfo[MPMediaItemPropertyArtist] = grandparentTitle

            // Episode info
            if let seasonNum = item.parentIndex, let episodeNum = item.index {
                nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = String(localized: "Season \(String(seasonNum)), Episode \(String(episodeNum))")
            }
        } else {
            // Movie - use year as artist
            if let year = item.year {
                nowPlayingInfo[MPMediaItemPropertyArtist] = String(year)
            }
        }

        // Duration and playback rate
        if duration > 0 {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        }
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackSpeed : 0.0

        // Set the info
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        registerRemoteCommands()

        // Load artwork asynchronously
        loadNowPlayingArtwork()

        print("🎵 [Player] Now Playing info set: \(item.title)")
    }

    private func loadNowPlayingArtwork() {
        // Use the item's thumb for artwork
        guard let thumbPath = item.thumb ?? item.grandparentThumb,
              let imageURL = ImageService.shared.episodeThumbnailURL(thumbPath, width: 600, height: 600) else {
            return
        }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: imageURL)
                if let nsImage = NSImage(data: data) {
                    let artwork = MPMediaItemArtwork(boundsSize: nsImage.size) { _ in nsImage }

                    await MainActor.run {
                        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                        info[MPMediaItemPropertyArtwork] = artwork
                        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                        print("🖼️ [Player] Now Playing artwork loaded")
                    }
                }
            } catch {
                print("⚠️ [Player] Failed to load artwork: \(error)")
            }
        }
    }

    func updateNowPlayingInfo() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }

        // Update time and playback state
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackSpeed : 0.0

        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Media keys, AirPods/headphone controls and the Control Center Now Playing widget.
    private func registerRemoteCommands() {
        unregisterRemoteCommands()
        let center = MPRemoteCommandCenter.shared()

        func add(_ command: MPRemoteCommand, _ handler: @escaping @MainActor (PlayerViewModel, MPRemoteCommandEvent) -> Bool) {
            command.isEnabled = true
            let token = command.addTarget { [weak self] event in
                guard let self else { return .noActionableNowPlayingItem }
                // MPRemoteCommandCenter calls back on the main thread.
                let handled = MainActor.assumeIsolated { handler(self, event) }
                return handled ? .success : .commandFailed
            }
            remoteCommandTargets.append((command, token))
        }

        add(center.togglePlayPauseCommand) { vm, _ in vm.togglePlayPause(); return true }
        add(center.playCommand) { vm, _ in
            if !vm.isPlaying { vm.togglePlayPause() }
            return true
        }
        add(center.pauseCommand) { vm, _ in
            if vm.isPlaying { vm.togglePlayPause() }
            return true
        }

        let small = TimeInterval(max(1, UserDefaults.standard.seekTimeSmall))
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: small)]
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: small)]
        add(center.skipForwardCommand) { vm, event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? small
            vm.skip(seconds: interval)
            return true
        }
        add(center.skipBackwardCommand) { vm, event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? small
            vm.skip(seconds: -interval)
            return true
        }
        add(center.changePlaybackPositionCommand) { vm, event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return false }
            vm.seek(to: event.positionTime)
            return true
        }
        add(center.nextTrackCommand) { vm, _ in
            guard vm.nextEpisode != nil else { return false }
            vm.playNext()
            return true
        }
    }

    private func unregisterRemoteCommands() {
        for (command, token) in remoteCommandTargets {
            command.removeTarget(token)
        }
        remoteCommandTargets.removeAll()
    }

    func clearNowPlayingInfo() {
        unregisterRemoteCommands()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        print("🎵 [Player] Now Playing info cleared")
    }

    // MARK: - Display Sleep Prevention

    func enableDisplaySleep() {
        #if os(macOS)
        guard displaySleepAssertion == nil else { return }

        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleDisplaySleepDisabled, .userInitiated],
            reason: "Playing video"
        )
        displaySleepAssertion = activity
        print("💤 [Player] Display sleep disabled (media playing)")
        #endif
    }

    func disableDisplaySleep() {
        #if os(macOS)
        guard let activity = displaySleepAssertion else { return }

        ProcessInfo.processInfo.endActivity(activity)
        displaySleepAssertion = nil
        print("💤 [Player] Display sleep re-enabled (media stopped)")
        #endif
    }
}
