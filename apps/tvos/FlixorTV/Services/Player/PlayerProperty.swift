import Foundation

enum PlayerProperty: String {
    case pause
    case pausedForCache = "paused-for-cache"
    case timePos = "time-pos"
    case duration
    case demuxerCacheDuration = "demuxer-cache-duration"
    case videoParamsSigPeak = "video-params/sig-peak"
}
