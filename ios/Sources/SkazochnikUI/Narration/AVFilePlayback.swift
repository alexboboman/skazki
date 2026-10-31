import AVFoundation
import Foundation

/// Playing a narration file.
@MainActor
protocol FilePlayback: AnyObject {
    /// Starts the file; `onFinished` runs when it ends by itself, not when it is stopped.
    func play(_ url: URL, rate: Double, onFinished: @escaping @MainActor () -> Void)
    func pause()
    func resume()
    func stop()
    func seek(by seconds: Double)
    func setRate(_ rate: Double)
}

/// Playback session shared by both voices: it keeps playing with the screen locked.
enum AudioSession {
    static func activate() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    static func deactivate() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}

@MainActor
final class AVFilePlayback: FilePlayback {
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var rate: Float = 1

    func play(_ url: URL, rate: Double, onFinished: @escaping @MainActor () -> Void) {
        stop()
        AudioSession.activate()
        self.rate = Float(rate)

        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = .timeDomain // speech keeps its pitch at other speeds
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
            Task { @MainActor in onFinished() }
        }

        let player = AVPlayer(playerItem: item)
        self.player = player
        player.playImmediately(atRate: self.rate)
    }

    func pause() { player?.pause() }
    func resume() { player?.playImmediately(atRate: rate) }

    func stop() {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player?.pause()
        player = nil
        AudioSession.deactivate()
    }

    func seek(by seconds: Double) {
        guard let player, let item = player.currentItem else { return }
        var target = max(0, player.currentTime().seconds + seconds)
        if item.duration.seconds.isFinite { target = min(target, max(0, item.duration.seconds - 1)) }
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }

    func setRate(_ rate: Double) {
        self.rate = Float(rate)
        if player?.timeControlStatus == .playing { player?.rate = self.rate }
    }
}
