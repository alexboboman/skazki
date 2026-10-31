import Foundation
import Testing
import SkazochnikCore
@testable import SkazochnikUI

@Suite struct CreateDraftTests {
    private let anya = Sample.anya // world: forest
    private let misha = Sample.misha // world: space
    private let third = Sample.profile("k3", "Соня", age: 6, worlds: ["ocean"])
    private let fourth = Sample.profile("k4", "Петя", age: 7, worlds: ["castle"])
    private var all: [ChildProfile] { [anya, misha, third, fourth] }

    @Test func startsWithTheActiveChildAndTheChildsWorld() {
        let draft = CreateDraft(activeProfile: misha)
        #expect(draft.heroIds == ["k2"])
        #expect(draft.world == .space)
        #expect(draft.lengthMinutes == 7)
    }

    @Test func aChildWithoutAWorldGetsTheForest() {
        let draft = CreateDraft(activeProfile: Sample.profile("x", "Х", age: 4, worlds: []))
        #expect(draft.world == .forest)
    }

    @Test func childrenAreAddedInOrderAndCappedAtThree() {
        var draft = CreateDraft(activeProfile: anya)
        draft.toggle(misha, in: all)
        draft.toggle(third, in: all)
        draft.toggle(fourth, in: all)
        #expect(draft.heroIds == ["k1", "k2", "k3"])
        #expect(!draft.isSelected(fourth))
    }

    @Test func theLastChildCannotBeRemoved() {
        var draft = CreateDraft(activeProfile: anya)
        draft.toggle(anya, in: all)
        #expect(draft.heroIds == ["k1"])

        draft.toggle(misha, in: all)
        draft.toggle(anya, in: all)
        #expect(draft.heroIds == ["k2"]) // the second child became the main hero
    }

    @Test func theWorldFollowsTheMainHeroUntilTheParentPicksOne() {
        var draft = CreateDraft(activeProfile: anya)
        draft.toggle(misha, in: all)
        draft.toggle(anya, in: all)
        #expect(draft.world == .space)

        draft.pickWorld(.castle)
        draft.toggle(third, in: all)
        draft.toggle(misha, in: all)
        #expect(draft.world == .castle)
    }

    @Test func topicRules() {
        var draft = CreateDraft(activeProfile: anya)
        #expect(draft.topicText == nil) // "Просто волшебная"

        draft.topic = "Не страшно в темноте"
        #expect(draft.topicText == "Не страшно в темноте")

        draft.note = "  Сегодня Аня потеряла зайца  "
        #expect(draft.topicText == "Сегодня Аня потеряла зайца")
        #expect(draft.hasNote)

        draft.note = "   "
        #expect(!draft.hasNote)
        #expect(draft.topicText == "Не страшно в темноте")

        draft.note = String(repeating: "я", count: 400)
        #expect(draft.topicText?.count == 300)
    }

    @Test func buildsTheGenerateRequest() {
        var draft = CreateDraft(activeProfile: anya)
        draft.toggle(misha, in: all)
        draft.topic = "Новый братик"
        draft.lengthMinutes = 12
        draft.pickWorld(.ocean)

        let request = draft.request()
        #expect(request.profileIds == ["k1", "k2"])
        #expect(request.format == .quickStory)
        #expect(request.topic == "Новый братик")
        #expect(request.lengthMinutes == 12)
        #expect(request.world == .ocean)
        #expect(request.mediaOptions?.requestedTypes == ["image"])
        #expect(request.mediaOptions?.imageQuality == .standard)
    }

    @Test func namesAreJoinedForTheHint() {
        var draft = CreateDraft(activeProfile: anya)
        draft.toggle(misha, in: all)
        #expect(draft.names(in: all) == "Аня и Миша")
    }
}
