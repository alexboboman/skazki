import MediaPlayer

/// Play/pause on the lock screen and in Control Center while a story is read, with the story name as the title.
@MainActor
final class LockScreenControls {
    private let title: String
    private let play: @MainActor () -> Void
    private let pause: @MainActor () -> Void
    private var tokens: [(MPRemoteCommand, Any)] = []

    init(title: String, play: @escaping @MainActor () -> Void, pause: @escaping @MainActor () -> Void) {
        self.title = title
        self.play = play
        self.pause = pause
    }

    func update(playing: Bool) {
        if tokens.isEmpty { register() }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: "Сказочник",
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
        ]
    }

    func clear() {
        for (command, token) in tokens { command.removeTarget(token) }
        tokens = []
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func register() {
        let center = MPRemoteCommandCenter.shared()
        let handlers: [(MPRemoteCommand, @MainActor () -> Void)] = [
            (center.playCommand, play),
            (center.pauseCommand, pause),
            (center.togglePlayPauseCommand, { [weak self] in self?.toggle() }),
        ]
        for (command, action) in handlers {
            command.isEnabled = true
            let token = command.addTarget { _ in
                Task { @MainActor in action() }
                return .success
            }
            tokens.append((command, token))
        }
    }

    private var isPlaying: Bool {
        (MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? Double ?? 0) > 0
    }

    private func toggle() {
        isPlaying ? pause() : play()
    }
}
