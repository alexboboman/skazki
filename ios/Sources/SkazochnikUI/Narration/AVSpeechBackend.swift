import AVFoundation
import SwiftUI

/// The system voice (AVSpeechSynthesizer): free, works offline. On iPhone the audio session is a playback
/// session, so reading goes on when the screen locks and the lock screen shows play/pause.
@MainActor
final class AVSpeechBackend: NSObject, SpeechBackend, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var onFinished: (@MainActor () -> Void)?
    /// Counts every start and stop; a finish callback counts only if it belongs to the latest utterance.
    private var generation = 0
    private var currentUtterance = 0

    /// Utterance rate at normal speed: a little slower than the system default suits a bedtime story.
    private static let baseRate: Float = 0.44

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Best Russian voice installed: Premium and Enhanced voices sound much better than the compact default.
    static func russianVoice() -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("ru") }
            .max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: "ru-RU")
    }

    func speak(_ text: String, rate: Double, onFinished: @escaping @MainActor () -> Void) {
        activateAudioSession()
        generation += 1
        self.onFinished = onFinished

        if synthesizer.isSpeaking || synthesizer.isPaused { synthesizer.stopSpeaking(at: .immediate) }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.russianVoice()
        utterance.rate = min(max(Self.baseRate * Float(rate), AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        utterance.pitchMultiplier = 0.98
        utterance.postUtteranceDelay = 0.45
        currentUtterance = generation
        synthesizer.speak(utterance)
    }

    func pause() { synthesizer.pauseSpeaking(at: .word) }
    func resume() { synthesizer.continueSpeaking() }

    func stop() {
        generation += 1
        onFinished = nil
        synthesizer.stopSpeaking(at: .immediate)
        deactivateAudioSession()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.currentUtterance == self.generation else { return }
            self.onFinished?()
        }
    }

    private func activateAudioSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    private func deactivateAudioSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}
