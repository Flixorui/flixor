//
//  KSPlayerModule.swift
//  Flixor
//
//  Created by KSPlayer integration
//

import Foundation
import KSPlayer
import React

@objc(KSPlayerModule)
class KSPlayerModule: RCTEventEmitter {
    override static func requiresMainQueueSetup() -> Bool {
        return true
    }

    override func supportedEvents() -> [String]! {
        return [
            "KSPlayer-onLoad",
            "KSPlayer-onProgress",
            "KSPlayer-onBuffering",
            "KSPlayer-onEnd",
            "KSPlayer-onError"
        ]
    }

    @objc func getTracks(_ nodeTag: NSNumber?, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        guard let nodeTag = nodeTag else {
            reject("INVALID_ARGUMENT", "nodeTag must not be nil", nil)
            return
        }
        DispatchQueue.main.async {
            if let viewManager = self.bridge.module(for: KSPlayerViewManager.self) as? KSPlayerViewManager {
                viewManager.getTracks(nodeTag, resolve: resolve, reject: reject)
            } else {
                reject("NO_VIEW_MANAGER", "KSPlayerViewManager not found", nil)
            }
        }
    }

    @objc func getAirPlayState(_ nodeTag: NSNumber?, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        guard let nodeTag = nodeTag else {
            reject("INVALID_ARGUMENT", "nodeTag must not be nil", nil)
            return
        }
        DispatchQueue.main.async {
            if let viewManager = self.bridge.module(for: KSPlayerViewManager.self) as? KSPlayerViewManager {
                viewManager.getAirPlayState(nodeTag, resolve: resolve, reject: reject)
            } else {
                reject("NO_VIEW_MANAGER", "KSPlayerViewManager not found", nil)
            }
        }
    }

    @objc func showAirPlayPicker(_ nodeTag: NSNumber?) {
        guard let nodeTag = nodeTag else {
             print("[KSPlayerModule] showAirPlayPicker called with nil nodeTag")
             return
        }
        print("[KSPlayerModule] showAirPlayPicker called for nodeTag: \(nodeTag)")
        DispatchQueue.main.async {
            if let viewManager = self.bridge.module(for: KSPlayerViewManager.self) as? KSPlayerViewManager {
                print("[KSPlayerModule] Found KSPlayerViewManager, calling showAirPlayPicker")
                viewManager.showAirPlayPicker(nodeTag)
            } else {
                print("[KSPlayerModule] Could not find KSPlayerViewManager")
            }
        }
    }

    @objc func getPlaybackStats(_ nodeTag: NSNumber?, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        guard let nodeTag = nodeTag else {
            reject("INVALID_ARGUMENT", "nodeTag must not be nil", nil)
            return
        }
        DispatchQueue.main.async {
            if let viewManager = self.bridge.module(for: KSPlayerViewManager.self) as? KSPlayerViewManager {
                viewManager.getPlaybackStats(nodeTag, resolve: resolve, reject: reject)
            } else {
                reject("NO_VIEW_MANAGER", "KSPlayerViewManager not found", nil)
            }
        }
    }

    @objc func getNativeLog(_ resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let logURL = documentsDirectory?.appendingPathComponent("ksplayer_native.log")
        guard let logURL = logURL else {
            reject("NO_LOG_PATH", "Could not resolve native log path", nil)
            return
        }

        guard let data = try? Data(contentsOf: logURL) else {
            resolve("")
            return
        }

        let maxBytes = 16_384
        let dataToDecode: Data
        if data.count > maxBytes {
            dataToDecode = data.suffix(maxBytes)
        } else {
            dataToDecode = data
        }

        let logString = String(data: dataToDecode, encoding: .utf8) ?? ""
        resolve(logString)
    }
}
