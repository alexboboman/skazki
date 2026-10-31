import Foundation
import Testing
import SkazochnikCore
@testable import SkazochnikUI

/// Stands in for the system voice: records what was asked and lets a test finish the utterance.
@MainActor
private final class FakeSpeech: SpeechBackend {
    private(set) var spoken: [(text: String, rate: Double)] = []
    private(set) var paused = false
    private(set) var stops = 0
    private var finish: (@MainActor () -> Void)?

    func speak(_ text: String, rate: Double, onFinished: @escaping @MainActor () -> Void) {
        spoken.append((text, rate))
        finish = onFinished
        paused = false
    }

    func pause() { paused = true }
    func resume() { paused = false }
    func stop() { stops += 1; finish = nil }

    var finishCallbackForTests: (@MainActor () -> Void)? { finish }

    /// The current utterance ends on its own.
    func finishUtterance() {
        let callback = finish
        finish = nil
        callback?()
    }
}

@MainActor
@Suite struct NarrationTests {
    private let script = [
        NarrationSegment(text: "Название."),
        NarrationSegment(text: "Первый абзац.", paragraph: 1),
        NarrationSegment(text: "Второй абзац.", paragraph: 2),
        NarrationSegment(text: "Спи сладко."),
    ]

    private func make(minuteLength: Duration = .seconds(60)) -> (NarrationController, FakeSpeech) {
        let speech = FakeSpeech()
        return (NarrationController(script: script, backend: speech, minuteLength: minuteLength), speech)
    }

    // MARK: Script

    @Test func theScriptNamesTheStoryReadsParagraphsAndEndsWithMoralAndClosing() {
        let story = ReadableStory(title: "Лиса", text: "Раз.\n\nДва.", media: [
            MediaAsset(id: "a", type: "image", variant: "standard", provider: "p", url: "/x", contentType: "image/webp", prompt: "", afterParagraph: 1),
        ], moral: "Дружба.", closing: "Спи.", readingMinutes: 1)

        #expect(story.narrationScript == [
            NarrationSegment(text: "Лиса."),
            NarrationSegment(text: "Раз.", paragraph: 1),
            NarrationSegment(text: "Два.", paragraph: 2),
            NarrationSegment(text: "Мораль сказки. Дружба."),
            NarrationSegment(text: "Спи."),
        ])
    }

    @Test func aSeriesPartAnnouncesItsNumber() {
        var story = ReadableStory(title: "Огоньки", text: "Раз.", media: [], readingMinutes: 1)
        story.partNumber = 2
        story.partCount = 5
        #expect(story.narrationScript.first?.text == "Часть 2. Огоньки.")
        #expect(story.narrationScript.count == 2)
    }

    // MARK: Playback

    @Test func playingStartsFromTheTitleAndMovesThroughTheScript() {
        let (narration, speech) = make()
        #expect(narration.state == .idle)

        narration.play()
        #expect(narration.state == .playing)
        #expect(speech.spoken.map(\.text) == ["Название."])
        #expect(narration.currentParagraph == nil)

        speech.finishUtterance()
        #expect(narration.currentParagraph == 1)
        speech.finishUtterance()
        #expect(narration.currentParagraph == 2)
        #expect(speech.spoken.map(\.text) == ["Название.", "Первый абзац.", "Второй абзац."])
    }

    @Test func theLastSegmentEndsTheReading() {
        let (narration, speech) = make()
        narration.play()
        for _ in 0..<script.count { speech.finishUtterance() }

        #expect(narration.state == .idle)
        #expect(narration.isFinished)
        #expect(narration.segmentIndex == nil)
        #expect(narration.currentParagraph == nil)
    }

    @Test func pauseAndResumeKeepThePlace() {
        let (narration, speech) = make()
        narration.play()
        speech.finishUtterance()

        narration.pause()
        #expect(narration.state == .paused)
        #expect(speech.paused)
        #expect(narration.currentParagraph == 1)

        narration.play()
        #expect(narration.state == .playing)
        #expect(!speech.paused)
        #expect(speech.spoken.count == 2, "resuming must not start the paragraph again")
    }

    @Test func toggleSwitchesBetweenPlayAndPause() {
        let (narration, _) = make()
        narration.toggle()
        #expect(narration.state == .playing)
        narration.toggle()
        #expect(narration.state == .paused)
        narration.toggle()
        #expect(narration.state == .playing)
    }

    @Test func stopForgetsThePosition() {
        let (narration, speech) = make()
        narration.play()
        speech.finishUtterance()
        narration.stop()

        #expect(narration.state == .idle)
        #expect(narration.segmentIndex == nil)
        #expect(!narration.isFinished)

        narration.play()
        #expect(speech.spoken.last?.text == "Название.", "playing again starts from the beginning")
    }

    @Test func skippingJumpsAParagraphAndIsClamped() {
        let (narration, speech) = make()
        narration.play()
        narration.skip(1)
        #expect(narration.currentParagraph == 1)
        narration.skip(1)
        #expect(narration.currentParagraph == 2)
        narration.skip(-1)
        #expect(narration.currentParagraph == 1)
        narration.skip(-5)
        #expect(narration.segmentIndex == 0)
        narration.skip(9)
        #expect(narration.segmentIndex == script.count - 1)
        #expect(speech.spoken.last?.text == "Спи сладко.")
    }

    @Test func aSkippedParagraphDoesNotAdvanceWhenItsOldUtteranceEnds() {
        let (narration, speech) = make()
        narration.play()
        let staleFinish = speech.finishCallbackForTests
        narration.skip(1)
        staleFinish?()
        #expect(narration.currentParagraph == 1, "a stale callback must not move the reading on")
    }

    @Test func speedRestartsTheCurrentParagraphAtTheNewRate() {
        let (narration, speech) = make()
        narration.play()
        speech.finishUtterance()
        narration.setSpeed(.slow)

        #expect(narration.speed == .slow)
        #expect(speech.spoken.last?.text == "Первый абзац.")
        #expect(speech.spoken.last?.rate == 0.85)
        #expect(speech.spoken.count == 3)

        narration.setSpeed(.slow)
        #expect(speech.spoken.count == 3, "choosing the same speed changes nothing")
    }

    @Test func speedChosenWhilePausedAppliesLater() {
        let (narration, speech) = make()
        narration.play()
        narration.pause()
        narration.setSpeed(.fast)
        #expect(speech.spoken.count == 1)
        narration.skip(1)
        #expect(speech.spoken.last?.rate == 1.2)
    }

    @Test func emptySegmentsAreDropped() {
        let speech = FakeSpeech()
        let narration = NarrationController(script: [NarrationSegment(text: "  \n"), NarrationSegment(text: "Текст.", paragraph: 1)], backend: speech)
        narration.play()
        #expect(speech.spoken.map(\.text) == ["Текст."])

        let empty = NarrationController(script: [], backend: FakeSpeech())
        empty.play()
        #expect(empty.state == .idle)
    }

    // MARK: Sleep timer

    @Test func theSleepTimerStopsTheReading() async {
        let (narration, speech) = make(minuteLength: .milliseconds(20))
        narration.play()
        narration.setSleepTimer(minutes: 1)
        #expect(narration.sleepMinutes == 1)

        for _ in 0..<100 where narration.state != .idle { try? await Task.sleep(for: .milliseconds(10)) }

        #expect(narration.state == .idle)
        #expect(narration.sleepMinutes == nil)
        #expect(speech.stops >= 1)
    }

    @Test func clearingTheTimerKeepsReading() async {
        let (narration, _) = make(minuteLength: .milliseconds(20))
        narration.play()
        narration.setSleepTimer(minutes: 1)
        narration.setSleepTimer(minutes: nil)
        try? await Task.sleep(for: .milliseconds(80))

        #expect(narration.state == .playing)
        #expect(narration.sleepMinutes == nil)
    }
}
