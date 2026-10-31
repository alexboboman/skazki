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

/// Reads a story aloud with play/pause, skipping, speed and a sleep timer. Two voices: the system voice
/// (paragraph by paragraph, free, offline) and the premium narration file (Family+).
@MainActor
public final class NarrationController: ObservableObject {
    public enum State: Equatable { case idle, playing, paused }
    public enum Voice: Equatable { case device, premium }

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
    /// What the skip buttons do with the premium narration, which has no paragraphs to jump between.
    static let seekSeconds: Double = 15

    @Published public private(set) var state: State = .idle {
        didSet { if state != oldValue { stateChanged() } }
    }
    @Published public private(set) var segmentIndex: Int?
    @Published public private(set) var speed: Speed = .normal
    @Published public private(set) var sleepMinutes: Int?
    @Published public private(set) var isFinished = false
    @Published public private(set) var voice: Voice
    /// The premium narration is being voiced or downloaded (about a minute the first time).
    @Published public private(set) var isPreparing = false
    /// A short message above the player ("premium voice needs Family+", a fallback after an error).
    @Published public private(set) var notice: String?

    let script: [NarrationSegment]
    private let backend: SpeechBackend
    private let player: FilePlayback
    private let premium: PremiumVoice?
    private let minuteLength: Duration
    private var sleepTask: Task<Void, Never>?
    private var prepareTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var lockScreen: LockScreenControls?

    /// Body paragraph being read now, for the highlight in the reader (the system voice only).
    public var currentParagraph: Int? { segmentIndex.flatMap { script[$0].paragraph } }
    public var isActive: Bool { state != .idle || isPreparing }
    /// The premium voice is part of the player (maybe locked behind the plan).
    public var offersPremium: Bool { premium != nil }
    public var premiumLocked: Bool { premium.map { !$0.isAvailable } ?? false }

    init(
        script: [NarrationSegment],
        backend: SpeechBackend,
        premium: PremiumVoice? = nil,
        player: FilePlayback? = nil,
        minuteLength: Duration = .seconds(60)
    ) {
        self.script = script.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        self.backend = backend
        self.premium = premium
        self.player = player ?? AVFilePlayback()
        self.minuteLength = minuteLength
        voice = premium?.isAvailable == true ? .premium : .device
    }

    public convenience init(story: ReadableStory, premium: PremiumVoice? = nil) {
        self.init(script: story.narrationScript, backend: AVSpeechBackend(), premium: premium)
        lockScreen = LockScreenControls(title: story.title, play: { [weak self] in self?.play() }, pause: { [weak self] in self?.pause() })
    }

    // MARK: Controls

    public func play() {
        switch state {
        case .playing:
            return
        case .paused:
            state = .playing
            voice == .premium ? player.resume() : backend.resume()
        case .idle:
            guard !isPreparing else { return }
            isFinished = false
            voice == .premium ? startPremium() : startDevice()
        }
    }

    public func pause() {
        guard state == .playing else { return }
        state = .paused
        voice == .premium ? player.pause() : backend.pause()
    }

    public func toggle() {
        state == .playing ? pause() : play()
    }

    /// Stops and forgets the position.
    public func stop() {
        prepareTask?.cancel()
        prepareTask = nil
        isPreparing = false
        sleepTask?.cancel()
        sleepTask = nil
        sleepMinutes = nil
        backend.stop()
        player.stop()
        state = .idle
        segmentIndex = nil
    }

    /// The system voice jumps a paragraph forward (1) or back (-1); the premium narration jumps 15 seconds.
    public func skip(_ step: Int) {
        if voice == .premium {
            if state != .idle { player.seek(by: Double(step) * Self.seekSeconds) }
            return
        }

        guard let current = segmentIndex else { return }
        speakSegment(at: min(max(current + step, 0), script.count - 1))
    }

    public func setSpeed(_ value: Speed) {
        guard value != speed else { return }
        speed = value

        if voice == .premium {
            player.setRate(value.rawValue)
        } else if state == .playing, let index = segmentIndex {
            // The rate applies to the next utterance, so the current paragraph starts over at the new speed.
            speakSegment(at: index)
        }
    }

    /// Switches voice; a reading in progress starts over with the new one. The sleep timer stays.
    public func select(_ newVoice: Voice) {
        guard newVoice != voice else { return }

        if newVoice == .premium, premiumLocked {
            show("Премиум-голос доступен в тарифе Family+")
            return
        }

        guard newVoice == .device || premium != nil else { return }
        let wasActive = isActive
        let timer = sleepMinutes
        stop()
        voice = newVoice
        setSleepTimer(minutes: timer)
        if wasActive { play() }
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

    // MARK: System voice

    private func startDevice() {
        guard !script.isEmpty else { return }
        speakSegment(at: 0)
    }

    private func speakSegment(at index: Int) {
        segmentIndex = index
        state = .playing
        backend.speak(script[index].text, rate: speed.rawValue) { [weak self] in
            self?.segmentFinished(index)
        }
    }

    private func segmentFinished(_ index: Int) {
        // A callback of a segment that was skipped or restarted in the meantime is stale.
        guard voice == .device, state == .playing, segmentIndex == index else { return }

        if index + 1 < script.count {
            speakSegment(at: index + 1)
        } else {
            stop()
            isFinished = true
        }
    }

    // MARK: Premium voice

    private func startPremium() {
        guard let premium else { return startDevice() }
        isPreparing = true

        prepareTask = Task { [weak self] in
            do {
                let file = try await premium.prepare()
                guard !Task.isCancelled, let self else { return }
                self.isPreparing = false
                self.prepareTask = nil
                self.playFile(file)
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.premiumFailed(error)
            }
        }
    }

    private func playFile(_ url: URL) {
        state = .playing
        player.play(url, rate: speed.rawValue) { [weak self] in
            guard let self, self.voice == .premium, self.state == .playing else { return }
            self.stop()
            self.isFinished = true
        }
    }

    /// The story is still read: the system voice takes over.
    private func premiumFailed(_ error: Error) {
        isPreparing = false
        prepareTask = nil
        voice = .device
        show(error as? NarrationError == .needsPlan ? "Премиум-голос доступен в тарифе Family+. Читаю голосом устройства." : "Не удалось подготовить премиум-голос. Читаю голосом устройства.")
        startDevice()
    }

    private func show(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    private func stateChanged() {
        switch state {
        case .idle: lockScreen?.clear()
        case .playing: lockScreen?.update(playing: true)
        case .paused: lockScreen?.update(playing: false)
        }
    }
}
