import Foundation

@MainActor
protocol PlayerCoordinating: AnyObject {
    func play(_ url: URL)
    func togglePlayback()
    func pause()
    func resume()
    func seek(to time: Double)
    func seek(by delta: Double)
    func setPlaybackRate(_ rate: Float)
    func setVolume(_ volume: Double)
    func selectAudioTrack(id: Int?)
    func selectSubtitleTrack(id: Int?)
    func trackList() -> [PlayerTrack]
    func destruct()
}
