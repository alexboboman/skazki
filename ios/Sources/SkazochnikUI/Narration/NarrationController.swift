import SwiftUI
import SkazochnikCore

/// Whatever turns text into sound; the real one is `AVSpeechBackend`, tests use a fake.
@MainActor
protocol SpeechBackend: AnyObject {
    /// Starts speaking `text` (replacing anything still playing); `onFinished` runs only when the text
    /// was spoken to the end, not when it was stopped.
    func speak(_ text: String, rate: Double, onFinished: @escaping @MainActor () -> Void)
    func pause()
    func resume()
    func stop()
}

/// Reads a story aloud segment by segment with play/pause, paragraph skipping, speed and a sleep timer.
@MainActor
public final class NarrationController: ObservableObject {
    public enum State: Equatable { case idle, playing, paused }

    public enum Speed: Double, CaseIterable, Identifiable {
        case slow = 0.85, normal = 1, fast = 1.2
        public var id: Double { rawValue }
        public var title: String {
            switch self {
            case .slow: "0.85×"
            case .normal: "1×"
            case .fast: "1.2×"
            }
        }
    }

    /// Minutes until reading stops by itself; nil means "until the end of the story".
    public static let sleepOptions: [Int?] = [nil, 10, 20, 30]

    @Published public private(set) var state: State = .idle {
        didSet { if state != oldValue { stateChanged() } }
    }
    @Published public private(set) var segmentIndex: Int?
    @Published public private(set) var speed: Speed = .normal
    @Published public private(set) var sleepMinutes: Int?
    @Published public private(set) var isFinished = false

    let script: [NarrationSegment]
    private let backend: SpeechBackend
    private let minuteLength: Duration
    private var sleepTask: Task<Void, Never>?
    private var lockScreen: LockScreenControls?

    /// Body paragraph being read now, for the highlight in the reader.
    public var currentParagraph: Int? { segmentIndex.flatMap { script[$0].paragraph } }
    public var isActive: Bool { state != .idle }

    init(script: [NarrationSegment], backend: SpeechBackend, minuteLength: Duration = .seconds(60)) {
        self.script = script.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        self.backend = backend
        self.minuteLength = minuteLength
    }

    public convenience init(story: ReadableStory) {
        self.init(script: story.narrationScript, backend: AVSpeechBackend())
        lockScreen = LockScreenControls(title: story.title, play: { [weak self] in self?.play() }, pause: { [weak self] in self?.pause() })
    }

    // MARK: Controls

    public func play() {
        switch state {
        case .playing:
            return
        case .paused:
            state = .playing
            backend.resume()
        case .idle:
            guard !script.isEmpty else { return }
            isFinished = false
            speakSegment(at: 0)
        }
    }

    public func pause() {
        guard state == .playing else { return }
        state = .paused
        backend.pause()
    }

    public func toggle() {
        state == .playing ? pause() : play()
    }

    /// Stops and forgets the position.
    public func stop() {
        sleepTask?.cancel()
        sleepTask = nil
        sleepMinutes = nil
        backend.stop()
        state = .idle
        segmentIndex = nil
    }

    /// Jumps a paragraph forward (1) or back (-1) and keeps playing.
    public func skip(_ step: Int) {
        guard let current = segmentIndex else { return }
        let target = min(max(current + step, 0), script.count - 1)
        speakSegment(at: target)
    }

    public func setSpeed(_ value: Speed) {
        guard value != speed else { return }
        speed = value
        // The rate applies to the next utterance, so the current paragraph starts over at the new speed.
        if state == .playing, let index = segmentIndex { speakSegment(at: index) }
    }

    /// Sets (or clears) the timer; when it runs out the reading stops.
    public func setSleepTimer(minutes: Int?) {
        sleepTask?.cancel()
        sleepTask = nil
        sleepMinutes = minutes

        guard let minutes else { return }
        let length = minuteLength * minutes
        sleepTask = Task { [weak self] in
            try? await Task.sleep(for: length)
            guard !Task.isCancelled, let self else { return }
            self.stop()
        }
    }

    private func stateChanged() {
        switch state {
        case .idle: lockScreen?.clear()
        case .playing: lockScreen?.update(playing: true)
        case .paused: lockScreen?.update(playing: false)
        }
    }

    // MARK: Playback

    private func speakSegment(at index: Int) {
        segmentIndex = index
        state = .playing
        backend.speak(script[index].text, rate: speed.rawValue) { [weak self] in
            self?.segmentFinished(index)
        }
    }

    private func segmentFinished(_ index: Int) {
        // A callback of a segment that was skipped or restarted in the meantime is stale.
        guard state == .playing, segmentIndex == index else { return }

        if index + 1 < script.count {
            speakSegment(at: index + 1)
        } else {
            stop()
            isFinished = true
        }
    }
}
