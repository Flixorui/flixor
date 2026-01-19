//
//  MPVPlayerModule.swift
//  Flixor
//
//  React Native Native Module for MPV Player async methods
//  Provides promise-based API for player operations
//

import Foundation
import React

@objc(MPVPlayerModule)
class MPVPlayerModule: NSObject {

    @objc static func requiresMainQueueSetup() -> Bool {
        return true
    }

    // MARK: - Track Methods

    @objc func getTracks(_ node: NSNumber, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        DispatchQueue.main.async {
            guard let bridge = RCTBridge.current(),
                  let uiManager = bridge.module(for: RCTUIManager.self) as? RCTUIManager,
                  let view = uiManager.view(forReactTag: node) as? MPVPlayerView else {
                reject("NO_VIEW", "MPVPlayerView not found", nil)
                return
            }

            let tracks = view.getAvailableTracks()
            resolve(tracks)
        }
    }

    // MARK: - Playback Stats

    @objc func getPlaybackStats(_ node: NSNumber, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        DispatchQueue.main.async {
            guard let bridge = RCTBridge.current(),
                  let uiManager = bridge.module(for: RCTUIManager.self) as? RCTUIManager,
                  let view = uiManager.view(forReactTag: node) as? MPVPlayerView else {
                reject("NO_VIEW", "MPVPlayerView not found", nil)
                return
            }

            let stats = view.getPlaybackStats()
            resolve(stats)
        }
    }

    // MARK: - AirPlay

    @objc func getAirPlayState(_ node: NSNumber, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        DispatchQueue.main.async {
            guard let bridge = RCTBridge.current(),
                  let uiManager = bridge.module(for: RCTUIManager.self) as? RCTUIManager,
                  let view = uiManager.view(forReactTag: node) as? MPVPlayerView else {
                reject("NO_VIEW", "MPVPlayerView not found", nil)
                return
            }

            let state = view.getAirPlayState()
            resolve(state)
        }
    }

    @objc func showAirPlayPicker(_ node: NSNumber) {
        DispatchQueue.main.async {
            guard let bridge = RCTBridge.current(),
                  let uiManager = bridge.module(for: RCTUIManager.self) as? RCTUIManager,
                  let view = uiManager.view(forReactTag: node) as? MPVPlayerView else {
                return
            }

            view.showAirPlayPicker()
        }
    }

    // MARK: - Native Log

    @objc func getNativeLog(_ resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        // MPV logs can be captured via the log-message event
        // This method provides access to the log file if one is being written
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let logURL = documentsDirectory?.appendingPathComponent("mpv_native.log")

        if let logPath = logURL?.path, FileManager.default.fileExists(atPath: logPath) {
            do {
                let logContent = try String(contentsOfFile: logPath, encoding: .utf8)
                resolve(["path": logPath, "content": logContent])
            } catch {
                resolve(["path": logPath, "content": "", "error": error.localizedDescription])
            }
        } else {
            resolve(["path": "", "content": "", "error": "No log file found"])
        }
    }
}
