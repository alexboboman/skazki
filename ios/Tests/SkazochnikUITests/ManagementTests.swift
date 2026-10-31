import Foundation
import Testing
import SkazochnikCore
@testable import SkazochnikUI

extension StubbedNetwork {
    @MainActor
    @Suite struct ManagementTests {
        init() { RouteStub.routes = [:] }

        private func profileJSON(id: String, name: String, age: Int) -> Data {
            Data(#"{"id":"\#(id)","name":"\#(name)","age":\#(age),"gender":"girl","appearance":{"skin":2,"hair":1,"hairStyle":"short","outfit":3},"interests":["Феи"],"worlds":["ocean"],"favoriteCharacter":"Рекс","language":"English","createdAt":"2026-10-01T10:00:00Z"}"#.utf8)
        }

        // MARK: Search

        @Test func searchMatchesTitlesIgnoringCaseAndCombinesWithFilters() {
            let app = Sample.appModel()
            #expect(app.stories(for: nil, matching: "лиса").map(\.id) == ["s1"])
            #expect(app.stories(for: nil, matching: "  ЛИСА ").map(\.id) == ["s1"])
            #expect(app.stories(for: nil, matching: "").count == 6)
            #expect(app.stories(for: nil, matching: "дракон").isEmpty)
            #expect(app.stories(for: "k2", matching: "ракета").map(\.id) == ["s3"])
            #expect(app.stories(for: "k1", favoritesOnly: true, matching: "тропа").map(\.id) == ["s6"])
            #expect(app.stories(for: "k1", matching: "ракета").isEmpty)
        }

        // MARK: Delete a story

        @Test func deletingAStoryRemovesItWhenTheServerAgrees() async {
            RouteStub.routes["DELETE /v1/stories/s2"] = { _ in .success((204, Data())) }
            let app = Sample.appModel()
            let ok = await app.deleteStory(Sample.stories[1])
            #expect(ok)
            #expect(!app.stories.contains { $0.id == "s2" })
            #expect(app.repository.cachedStories().count == 5)
        }

        @Test func aFailedStoryDeleteKeepsTheStory() async {
            let app = Sample.appModel() // no route: offline
            let ok = await app.deleteStory(Sample.stories[1])
            #expect(!ok)
            #expect(app.stories.count == 6)
        }

        // MARK: Delete a child

        @Test func deletingAChildMovesTheActiveChildAndDetachesStories() async {
            RouteStub.routes["DELETE /v1/profiles/k1"] = { _ in .success((204, Data())) }
            let app = Sample.appModel()
            app.activeProfileId = "k1"

            let ok = await app.deleteProfile(Sample.anya)
            #expect(ok)
            #expect(app.profiles.map(\.id) == ["k2"])
            #expect(app.activeProfile?.id == "k2")
            #expect(!app.stories.contains { $0.heroIds.contains("k1") })
            #expect(app.stories.count == 6) // the stories stay in the library
            #expect(app.repository.cachedProfiles().map(\.id) == ["k2"])
        }

        @Test func theLastChildCannotBeDeleted() async {
            let app = Sample.appModel(profiles: [Sample.anya])
            #expect(!app.canDeleteProfiles)
            #expect(await app.deleteProfile(Sample.anya) == false)
            #expect(app.profiles.count == 1)
        }

        @Test func aFailedChildDeleteChangesNothing() async {
            let app = Sample.appModel()
            #expect(await app.deleteProfile(Sample.misha) == false)
            #expect(app.profiles.count == 2)
        }

        @Test func updatedReplacesTheChildInPlace() throws {
            let app = Sample.appModel()
            let changed = try Sample.decoder.decode(ChildProfile.self, from: profileJSON(id: "k1", name: "Аня Новая", age: 6))
            app.updated(changed)
            #expect(app.profiles.map(\.name) == ["Аня Новая", "Миша"])
        }

        // MARK: Session

        @Test func anUnrecognisedAccountIsReportedOnRefresh() async {
            let unauthorized = Data(#"{"error":{"code":"unauthorized","message":"m"}}"#.utf8)
            RouteStub.routes["POST /v1/auth/refresh"] = { _ in .success((401, unauthorized)) }
            let app = Sample.appModel()
            await app.refresh()
            #expect(app.sessionExpired)
        }

        @Test func refreshRenewsTheTokenBeforeLoading() async {
            let auth = Data(#"{"token":"fresh","user":{"id":"u","anonymous":true}}"#.utf8)
            var order: [String] = []
            RouteStub.routes["POST /v1/auth/refresh"] = { _ in order.append("refresh"); return .success((200, auth)) }
            RouteStub.routes["GET /v1/profiles"] = { _ in order.append("profiles"); return .success((200, Data(#"{"profiles":[]}"#.utf8))) }
            RouteStub.routes["GET /v1/stories"] = { _ in order.append("stories"); return .success((200, Data(#"{"stories":[]}"#.utf8))) }

            let app = Sample.appModel()
            await app.refresh()
            #expect(order.first == "refresh")
            #expect(!app.sessionExpired)
        }

        @Test func startingOverWipesTheLocalAccount() {
            let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
            let app = Sample.appModel(defaults: defaults)
            app.activeProfileId = "k2"
            app.startOver()
            #expect(app.profiles.isEmpty)
            #expect(app.stories.isEmpty)
            #expect(app.activeProfileId == nil)
            #expect(defaults.string(forKey: "activeProfileId") == nil)
            #expect(app.repository.cachedProfiles().isEmpty)
            #expect(app.repository.cachedStories().isEmpty)
        }

        // MARK: Editing a child

        @Test func editingStartsFromTheProfileAndSavesWithPut() async throws {
            let existing = try Sample.decoder.decode(ChildProfile.self, from: profileJSON(id: "k1", name: "Аня", age: 5))
            var sentBody: [String: Any] = [:]
            RouteStub.routes["PUT /v1/profiles/k1"] = { request in
                sentBody = (try? JSONSerialization.jsonObject(with: request.bodyData) as? [String: Any]) ?? [:]
                return .success((200, self.profileJSON(id: "k1", name: "Аня Новая", age: 6)))
            }
            let app = Sample.appModel()
            var saved: ChildProfile?
            let model = OnboardingModel(client: app.client, editing: existing, onFinished: { saved = $0 })

            #expect(model.isEditing)
            #expect(model.step == .name)
            #expect(model.draft.name == "Аня")
            #expect(model.draft.appearance == Appearance(skin: 2, hair: 1, hairStyle: .short, outfit: 3))
            #expect(model.draft.world == .ocean)

            model.draft.name = "Аня Новая"
            model.draft.age = 6
            await model.finish()

            #expect(saved?.name == "Аня Новая")
            #expect(sentBody["name"] as? String == "Аня Новая")
            #expect(sentBody["age"] as? Int == 6)
            // Fields the steps do not edit are carried over, not reset.
            #expect(sentBody["language"] as? String == "English")
            #expect(sentBody["favoriteCharacter"] as? String == "Рекс")
        }

        @Test func goingBackFromTheFirstEditStepCancels() async throws {
            let existing = try Sample.decoder.decode(ChildProfile.self, from: profileJSON(id: "k1", name: "Аня", age: 5))
            var cancelled = false
            let model = OnboardingModel(client: Sample.appModel().client, editing: existing, onFinished: { _ in }, onCancel: { cancelled = true })
            model.back()
            #expect(cancelled)
            #expect(model.step == .name)
        }

        private func makeClient(store: MemorySessionStore) -> APIClient {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [RouteStub.self]
            return APIClient(baseURL: URL(string: "http://route.test")!, store: store, session: URLSession(configuration: configuration))
        }

        @Test func aStaleTokenAfterAReinstallIsReplacedWithAFreshGuest() async throws {
            let store = MemorySessionStore(token: "stale")
            var profileCalls = 0
            RouteStub.routes["POST /v1/profiles"] = { request in
                profileCalls += 1
                if request.value(forHTTPHeaderField: "authorization") == "Bearer stale" {
                    return .success((401, Data(#"{"error":{"code":"unauthorized","message":"m"}}"#.utf8)))
                }
                return .success((201, self.profileJSON(id: "new", name: "Мия", age: 5)))
            }
            RouteStub.routes["POST /v1/auth/anonymous"] = { _ in
                .success((201, Data(#"{"token":"fresh","user":{"id":"u","anonymous":true}}"#.utf8)))
            }

            var saved: ChildProfile?
            let model = OnboardingModel(client: makeClient(store: store), onFinished: { saved = $0 })
            model.draft.name = "Мия"
            await model.finish()

            #expect(saved?.id == "new")
            #expect(profileCalls == 2)
            #expect(store.loadToken() == "fresh")
            #expect(model.errorMessage == nil)
        }

        @Test func aFreePlanLimitOnAddingAChildShowsAMessage() async {
            RouteStub.routes["POST /v1/profiles"] = { _ in
                .success((402, Data(#"{"error":{"code":"limit_reached","message":"m","feature":"profiles","tier":"free","limit":1}}"#.utf8)))
            }
            var finished = false
            let model = OnboardingModel(client: makeClient(store: MemorySessionStore(token: "t")), onFinished: { _ in finished = true })
            model.draft.name = "Мия"
            await model.finish()

            #expect(!finished)
            #expect(model.paywall?.feature == "profiles")
            #expect(model.errorMessage?.contains("1") == true)
        }

        @Test func limitMessageNamesTheResetDate() {
            let date = ISO8601DateFormatter().date(from:  "2026-11-02T00:00:00Z")
            let note = FailureView.resetNote(date)
            #expect(note.hasPrefix("Новая сказка будет доступна "))
            #expect(note.contains("ноября"))
            #expect(FailureView.resetNote(nil) == "Новая сказка будет доступна позже. ")
        }

        @Test func aFailedSaveShowsAMessageAndDoesNotFinish() async throws {
            let existing = try Sample.decoder.decode(ChildProfile.self, from: profileJSON(id: "k1", name: "Аня", age: 5))
            var finished = false
            let model = OnboardingModel(client: Sample.appModel().client, editing: existing, onFinished: { _ in finished = true })
            await model.finish() // no route: offline
            #expect(!finished)
            #expect(model.errorMessage != nil)
        }
    }
}

private extension URLRequest {
    var bodyData: Data {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
