//
//  MPVPlayerManager.m
//  Flixor
//
//  Objective-C bridge declarations for MPV Player React Native integration
//

#import <Foundation/Foundation.h>
#import <React/RCTBridgeModule.h>
#import <React/RCTViewManager.h>
#import <React/RCTUIManager.h>
#import <React/RCTEventEmitter.h>

// Debug: Log when this file is loaded
__attribute__((constructor))
static void MPVPlayerManagerLoaded(void) {
    NSLog(@"[MPVPlayerManager] Native module loaded");
}

// MARK: - View Manager Bridge

@interface RCT_EXTERN_MODULE(MPVPlayerViewManager, RCTViewManager)

// React Native Properties
RCT_EXPORT_VIEW_PROPERTY(source, NSDictionary)
RCT_EXPORT_VIEW_PROPERTY(paused, BOOL)
RCT_EXPORT_VIEW_PROPERTY(volume, NSNumber)
RCT_EXPORT_VIEW_PROPERTY(rate, NSNumber)
RCT_EXPORT_VIEW_PROPERTY(audioTrack, NSNumber)
RCT_EXPORT_VIEW_PROPERTY(subtitleTrack, NSNumber)
RCT_EXPORT_VIEW_PROPERTY(resizeMode, NSString)

// Subtitle Styling Properties
RCT_EXPORT_VIEW_PROPERTY(subtitleSize, NSNumber)
RCT_EXPORT_VIEW_PROPERTY(subtitleColor, NSString)
RCT_EXPORT_VIEW_PROPERTY(subtitlePosition, NSNumber)
RCT_EXPORT_VIEW_PROPERTY(subtitleBorderSize, NSNumber)

// Event Callbacks
RCT_EXPORT_VIEW_PROPERTY(onLoad, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onProgress, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onBuffering, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onEnd, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onError, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onTracksChanged, RCTDirectEventBlock)

// Imperative Commands
RCT_EXTERN_METHOD(seek:(nonnull NSNumber *)node toTime:(nonnull NSNumber *)time)
RCT_EXTERN_METHOD(setSource:(nonnull NSNumber *)node source:(NSDictionary *)source)
RCT_EXTERN_METHOD(setPaused:(nonnull NSNumber *)node paused:(BOOL)paused)
RCT_EXTERN_METHOD(setVolume:(nonnull NSNumber *)node volume:(nonnull NSNumber *)volume)
RCT_EXTERN_METHOD(setPlaybackRate:(nonnull NSNumber *)node rate:(nonnull NSNumber *)rate)
RCT_EXTERN_METHOD(setAudioTrack:(nonnull NSNumber *)node trackId:(nonnull NSNumber *)trackId)
RCT_EXTERN_METHOD(setSubtitleTrack:(nonnull NSNumber *)node trackId:(nonnull NSNumber *)trackId)

// Promise-based Methods
RCT_EXTERN_METHOD(getTracks:(nonnull NSNumber *)node
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(getPlaybackStats:(nonnull NSNumber *)node
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)

// AirPlay Methods
RCT_EXTERN_METHOD(showAirPlayPicker:(nonnull NSNumber *)node)

RCT_EXTERN_METHOD(getAirPlayState:(nonnull NSNumber *)node
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)

// Performance Stats (Comprehensive)
RCT_EXTERN_METHOD(getPerformanceStats:(nonnull NSNumber *)node
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)

// Aspect Ratio / BoxFit Mode
RCT_EXTERN_METHOD(cycleAspectRatio:(nonnull NSNumber *)node
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(getAspectRatioMode:(nonnull NSNumber *)node
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)

@end

// MARK: - Native Module Bridge

@interface RCT_EXTERN_MODULE(MPVPlayerModule, NSObject)

RCT_EXTERN_METHOD(getTracks:(nonnull NSNumber *)node
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(getPlaybackStats:(nonnull NSNumber *)node
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(getAirPlayState:(nonnull NSNumber *)node
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(showAirPlayPicker:(nonnull NSNumber *)node)

RCT_EXTERN_METHOD(getNativeLog:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)

// Performance Stats (Comprehensive)
RCT_EXTERN_METHOD(getPerformanceStats:(nonnull NSNumber *)node
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)

// Aspect Ratio / BoxFit Mode
RCT_EXTERN_METHOD(cycleAspectRatio:(nonnull NSNumber *)node
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(getAspectRatioMode:(nonnull NSNumber *)node
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)

@end
