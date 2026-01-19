//
// Use this file to import your target's public headers that you would like to expose to Swift.
//

// React Native headers
#import <React/RCTBridgeModule.h>
#import <React/RCTViewManager.h>
#import <React/RCTUIManager.h>
#import <React/RCTEventEmitter.h>

// MPV (libmpv) headers for video playback
#if __has_include(<Libmpv/client.h>)
#import <Libmpv/client.h>
#import <Libmpv/render.h>
#import <Libmpv/render_gl.h>
#endif
