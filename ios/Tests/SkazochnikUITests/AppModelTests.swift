import Foundation
import Testing
import SkazochnikCore
@testable import SkazochnikUI

extension StubbedNetwork {
    @MainActor
    @Suite struct AppModelTests {
        init() { RouteStub.routes = [:] }

        @Test func startsFromTheOfflineCache() {
            let app = Sample.appModel()
            #expect(app.profiles.count == 2)
            #expect(app.stories.count == 6)
            #expect(app.activeProfile?.id == "k1")
        }

        @Test func activeChildIsRememberedBetweenLaunches() {
            let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
            let first = Sample.appModel(defaults: defaults)
            first.activeProfileId = "k2"
            #expect(first.activeProfile?.name == "Миша")

            let second = Sample.appModel(defaults: defaults)
            #expect(second.activeProfile?.name == "Миша")
        }

        @Test func libraryFiltersByChildAndFavourites() {
            let app = Sample.appModel()
            #expect(app.stories(for: nil).map(\.id) == ["s1", "s2", "s3", "s4", "s5", "s6"])
            #expect(app.stories(for: "k2").map(\.id) == ["s3", "s4", "s5"]) // s4 has both children
            #expect(app.stories(for: "k1", favoritesOnly: true).map(\.id) == ["s1", "s6"])
            #expect(app.stories(for: nil, favoritesOnly: true).count == 3)
        }

        @Test func continueCardPicksAStartedUnfinishedStory() {
            let app = Sample.appModel()
            #expect(app.storyToContinue(for: "k1")?.id == "s1")
            #expect(app.storyToContinue(for: "k2") == nil)

            let finished = Sample.appModel(stories: [Sample.story("x", "Т", hero: ["k1"], progress: 1)])
            #expect(finished.storyToContinue(for: "k1") == nil)
        }

        @Test func recentExcludesTheContinueCardAndIsCapped() {
            let app = Sample.appModel()
            let resume = app.storyToContinue(for: "k1")
            let recent = app.recentStories(for: "k1", excluding: resume)
            #expect(!recent.contains { $0.id == "s1" })
            #expect(recent.count == 5)
        }

        @Test func storyCountsPerChildIncludeSharedStories() {
            let app = Sample.appModel()
            #expect(app.storyCount(for: Sample.anya) == 4)
            #expect(app.storyCount(for: Sample.misha) == 3)
        }

        @Test func heroOfAStoryFallsBackToTheActiveChild() {
            let app = Sample.appModel()
            let known = app.hero(for: Sample.stories[2])
            #expect(known.name == "Миша")

            let orphan = Sample.story("o", "Т", hero: ["deleted"])
            #expect(app.hero(for: orphan).name == "Аня")
        }

        @Test func addedChildBecomesActive() {
            let app = Sample.appModel(profiles: [Sample.anya])
            app.added(Sample.misha)
            #expect(app.profiles.map(\.id) == ["k1", "k2"])
            #expect(app.activeProfile?.id == "k2")
        }

        @Test func refreshReplacesCacheWithServerDataAndClearsOffline() async throws {
            let profiles = #"{"profiles":[{"id":"k1","name":"Аня","age":6,"interests":[],"worlds":[],"language":"Русский","createdAt":"2026-10-01T10:00:00.000Z"}]}"#
            let stories = #"{"stories":[]}"#
            RouteStub.routes["GET /v1/profiles"] = { _ in .success((200, Data(profiles.utf8))) }
            RouteStub.routes["GET /v1/stories"] = { _ in .success((200, Data(stories.utf8))) }

            let app = Sample.appModel()
            await app.refresh()
            #expect(app.profiles.count == 1)
            #expect(app.profiles[0].age == 6)
            #expect(app.stories.isEmpty)
            #expect(!app.isOffline)
        }

        @Test func refreshOfflineKeepsWhatWeHave() async {
            let app = Sample.appModel() // no routes: every request fails like without internet
            await app.refresh()
            #expect(app.isOffline)
            #expect(app.stories.count == 6)
            #expect(app.profiles.count == 2)
        }

        @Test func favouriteIsOptimisticAndRevertsWhenTheServerFails() async {
            let app = Sample.appModel()
            let target = Sample.stories[1] // s2, not a favourite
            #expect(!target.favorite)

            await app.toggleFavorite(target) // no route: the request fails
            #expect(app.stories.first { $0.id == "s2" }?.favorite == false)
        }

        @Test func favouriteSticksWhenTheServerAnswers() async {
            RouteStub.routes["PATCH /v1/stories/s2"] = { _ in
                .success((200, Data(#"{"id":"s2","format":"quick_story","heroIds":["k1"],"readingMinutes":5,"favorite":true,"readProgress":0,"createdAt":"2026-10-29T18:00:00.000Z","totalParts":1,"parts":[]}"#.utf8)))
            }
            let app = Sample.appModel()
            await app.toggleFavorite(Sample.stories[1])
            #expect(app.stories.first { $0.id == "s2" }?.favorite == true)
            #expect(app.repository.cachedStories().first { $0.id == "s2" }?.favorite == true)
        }

        @Test func markingReadSetsFullProgress() async {
            RouteStub.routes["PATCH /v1/stories/s2"] = { _ in
                .success((200, Data(#"{"id":"s2","format":"quick_story","heroIds":["k1"],"readingMinutes":5,"favorite":false,"readProgress":1,"createdAt":"2026-10-29T18:00:00.000Z","totalParts":1,"parts":[]}"#.utf8)))
            }
            let app = Sample.appModel()
            await app.markRead(id: "s2")
            #expect(app.stories.first { $0.id == "s2" }?.readProgress == 1)
        }
    }
}
