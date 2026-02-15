import Foundation

@MainActor
protocol MPVPlayerDelegate: AnyObject {
    func propertyChange(mpv: OpaquePointer, property: PlayerProperty, data: Any?)
    func fileLoaded()
    func playbackEnded()
}
