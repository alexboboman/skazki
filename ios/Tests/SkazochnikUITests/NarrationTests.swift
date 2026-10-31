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

/// Stands in for the file player.
@MainActor
private final class FakePlayer: FilePlayback {
    private(set) var played: [(url: URL, rate: Double)] = []
    private(set) var paused = false
    private(set) var seeks: [Double] = []
    private(set) var rates: [Double] = []
    private(set) var stops = 0
    private var finish: (@MainActor () -> Void)?

    func play(_ url: URL, rate: Double, onFinished: @escaping @MainActor () -> Void) {
        played.append((url, rate))
        finish = onFinished
        paused = false
    }

    func pause() { paused = true }
    func resume() { paused = false }
    func stop() { stops += 1; finish = nil }
    func seek(by seconds: Double) { seeks.append(seconds) }
    func setRate(_ rate: Double) { rates.append(rate) }
    func finishFile() { let callback = finish; finish = nil; callback?() }
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

// MARK: Premium voice

@MainActor
@Suite struct PremiumNarrationTests {
    private let script = [
        NarrationSegment(text: "Название."),
        NarrationSegment(text: "Абзац.", paragraph: 1),
    ]
    private let file = URL(fileURLWithPath: "/tmp/narration.mp3")

    private func make(
        available: Bool = true,
        prepare: @escaping @Sendable () async throws -> URL
    ) -> (NarrationController, FakeSpeech, FakePlayer) {
        let speech = FakeSpeech()
        let player = FakePlayer()
        let controller = NarrationController(
            script: script,
            backend: speech,
            premium: PremiumVoice(isAvailable: available, prepare: prepare),
            player: player,
            minuteLength: .milliseconds(20)
        )
        return (controller, speech, player)
    }

    private func settle(_ narration: NarrationController) async {
        for _ in 0..<200 where narration.isPreparing { try? await Task.sleep(for: .milliseconds(5)) }
    }

    @Test func premiumIsTheDefaultVoiceWhenThePlanHasIt() {
        #expect(make { URL(fileURLWithPath: "/x") }.0.voice == .premium)
        #expect(make(available: false) { URL(fileURLWithPath: "/x") }.0.voice == .device)
        let plain = NarrationController(script: script, backend: FakeSpeech(), player: FakePlayer())
        #expect(!plain.offersPremium)
        #expect(plain.voice == .device)
    }

    @Test func playingPreparesTheFileThenPlaysIt() async {
        let url = file
        let (narration, speech, player) = make { try await Task.sleep(for: .milliseconds(20)); return url }

        narration.play()
        #expect(narration.isPreparing)
        #expect(narration.isActive)
        #expect(narration.state == .idle)
        await settle(narration)

        #expect(!narration.isPreparing)
        #expect(narration.state == .playing)
        #expect(player.played.map(\.url) == [url])
        #expect(speech.spoken.isEmpty, "the system voice stays silent")
        #expect(narration.currentParagraph == nil, "there is no paragraph highlight for the file")
    }

    @Test func pauseSeekSpeedAndTheEndOfTheFile() async {
        let url = file
        let (narration, _, player) = make { url }
        narration.play()
        await settle(narration)

        narration.pause()
        #expect(narration.state == .paused)
        #expect(player.paused)
        narration.play()
        #expect(!player.paused)

        narration.skip(1)
        narration.skip(-1)
        #expect(player.seeks == [15, -15])

        narration.setSpeed(.fast)
        #expect(player.rates == [1.2])

        player.finishFile()
        #expect(narration.state == .idle)
        #expect(narration.isFinished)
    }

    @Test func cancellingWhilePreparingStopsEverything() async {
        let url = file
        let (narration, speech, player) = make { try await Task.sleep(for: .milliseconds(60)); return url }
        narration.play()
        narration.stop()
        try? await Task.sleep(for: .milliseconds(100))

        #expect(!narration.isPreparing)
        #expect(narration.state == .idle)
        #expect(player.played.isEmpty, "a cancelled preparation must not start playing later")
        #expect(speech.spoken.isEmpty)
    }

    @Test func aFailedPreparationFallsBackToTheSystemVoice() async {
        let (narration, speech, player) = make { throw NarrationError.failed("down") }
        narration.play()
        await settle(narration)

        #expect(narration.voice == .device)
        #expect(narration.state == .playing)
        #expect(speech.spoken.map(\.text) == ["Название."])
        #expect(player.played.isEmpty)
        #expect(narration.notice?.contains("голосом устройства") == true)
    }

    @Test func aMissingPlanIsExplainedInTheFallback() async {
        let (narration, _, _) = make { throw NarrationError.needsPlan }
        narration.play()
        await settle(narration)
        #expect(narration.notice?.contains("Family+") == true)
    }

    @Test func aLockedVoiceIsOfferedButCannotBeChosen() {
        let (narration, speech, _) = make(available: false) { URL(fileURLWithPath: "/x") }
        #expect(narration.premiumLocked)

        narration.select(.premium)
        #expect(narration.voice == .device)
        #expect(narration.notice?.contains("Family+") == true)

        narration.play()
        #expect(speech.spoken.count == 1)
    }

    @Test func switchingVoiceStartsOverAndKeepsTheSleepTimer() async {
        let url = file
        let (narration, speech, player) = make { url }
        narration.play()
        await settle(narration)
        narration.setSleepTimer(minutes: 30)

        narration.select(.device)
        #expect(narration.voice == .device)
        #expect(player.stops >= 1)
        #expect(speech.spoken.map(\.text) == ["Название."])
        #expect(narration.sleepMinutes == 30)

        narration.select(.premium)
        await settle(narration)
        #expect(player.played.count == 2)
        #expect(narration.sleepMinutes == 30)
    }

    @Test func theSleepTimerStopsThePremiumNarrationToo() async {
        let url = file
        let (narration, _, player) = make { url }
        narration.play()
        await settle(narration)
        narration.setSleepTimer(minutes: 1)

        for _ in 0..<100 where narration.state != .idle { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(narration.state == .idle)
        #expect(player.stops >= 1)
    }
}
