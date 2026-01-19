//
//  MPVPlayerViewManager.swift
//  Flixor
//
//  React Native View Manager for MPV Player
//  Manages the bridge between React Native and MPVPlayerView
//

import Foundation
import React

@objc(MPVPlayerViewManager)
class MPVPlayerViewManager: RCTViewManager {

    override func view() -> UIView! {
        NSLog("[MPVPlayerViewManager] view() called - creating MPVPlayerView")
        let view = MPVPlayerView()
        NSLog("[MPVPlayerViewManager] MPVPlayerView created: \(view)")
        return view
    }

    override static func requiresMainQueueSetup() -> Bool {
        NSLog("[MPVPlayerViewManager] requiresMainQueueSetup() called")
        return true
    }

    override func constantsToExport() -> [AnyHashable : Any]! {
        return [
            "EventTypes": [
                "onLoad": "onLoad",
                "onProgress": "onProgress",
                "onBuffering": "onBuffering",
                "onEnd": "onEnd",
                "onError": "onError",
                "onTracksChanged": "onTracksChanged"
            ]
        ]
    }

    // MARK: - Imperative Commands

    @objc func seek(_ node: NSNumber, toTime time: NSNumber) {
        DispatchQueue.main.async {
            if let view = self.bridge.uiManager.view(forReactTag: node) as? MPVPlayerView {
                view.seek(to: TimeInterval(truncating: time))
            }
        }
    }

    @objc func setSource(_ node: NSNumber, source: NSDictionary) {
        DispatchQueue.main.async {
            if let view = self.bridge.uiManager.view(forReactTag: node) as? MPVPlayerView {
                view.setSource(source)
            }
        }
    }

    @objc func setPaused(_ node: NSNumber, paused: Bool) {
        DispatchQueue.main.async {
            if let view = self.bridge.uiManager.view(forReactTag: node) as? MPVPlayerView {
                view.setPaused(paused)
            }
        }
    }

    @objc func setVolume(_ node: NSNumber, volume: NSNumber) {
        DispatchQueue.main.async {
            if let view = self.bridge.uiManager.view(forReactTag: node) as? MPVPlayerView {
                view.setVolume(Double(truncating: volume))
            }
        }
    }

    @objc func setPlaybackRate(_ node: NSNumber, rate: NSNumber) {
        DispatchQueue.main.async {
            if let view = self.bridge.uiManager.view(forReactTag: node) as? MPVPlayerView {
                view.setPlaybackRate(Double(truncating: rate))
            }
        }
    }

    @objc func setAudioTrack(_ node: NSNumber, trackId: NSNumber) {
        DispatchQueue.main.async {
            if let view = self.bridge.uiManager.view(forReactTag: node) as? MPVPlayerView {
                view.setAudioTrack(Int(truncating: trackId))
            }
        }
    }

    @objc func setSubtitleTrack(_ node: NSNumber, trackId: NSNumber) {
        DispatchQueue.main.async {
            if let view = self.bridge.uiManager.view(forReactTag: node) as? MPVPlayerView {
                view.setSubtitleTrack(Int(truncating: trackId))
            }
        }
    }

    // MARK: - Promise-based Methods

    @objc func getTracks(_ node: NSNumber, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        DispatchQueue.main.async {
            if let view = self.bridge.uiManager.view(forReactTag: node) as? MPVPlayerView {
                let tracks = view.getAvailableTracks()
                resolve(tracks)
            } else {
                reject("NO_VIEW", "MPVPlayerView not found", nil)
            }
        }
    }

    @objc func getPlaybackStats(_ node: NSNumber, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        DispatchQueue.main.async {
            if let view = self.bridge.uiManager.view(forReactTag: node) as? MPVPlayerView {
                let stats = view.getPlaybackStats()
                resolve(stats)
            } else {
                reject("NO_VIEW", "MPVPlayerView not found", nil)
            }
        }
    }

    // MARK: - AirPlay Methods

    @objc func showAirPlayPicker(_ node: NSNumber) {
        DispatchQueue.main.async {
            if let view = self.bridge.uiManager.view(forReactTag: node) as? MPVPlayerView {
                view.showAirPlayPicker()
            }
        }
    }

    @objc func getAirPlayState(_ node: NSNumber, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        DispatchQueue.main.async {
            if let view = self.bridge.uiManager.view(forReactTag: node) as? MPVPlayerView {
                let state = view.getAirPlayState()
                resolve(state)
            } else {
                reject("NO_VIEW", "MPVPlayerView not found", nil)
            }
        }
    }
}
