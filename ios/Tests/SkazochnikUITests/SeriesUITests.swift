import Foundation
import Testing
import SkazochnikCore
@testable import SkazochnikUI

private let partJSON = Data("""
{
  "storyId": "s1", "partNumber": 2,
  "arc": { "length": 3, "partsReady": 2, "status": "active" },
  "story": { "title": "Огоньки", "text": "Раз.\\n\\nДва.", "closing": "С", "readingMinutes": 3 },
  "media": [], "steps": []
}
""".utf8)

private let storyJSON = Data("""
{
  "id": "series1", "title": "Звёздная пещера", "format": "story_arc_part", "world": "forest",
  "heroIds": ["k1"], "readingMinutes": 3, "favorite": false, "readProgress": 0.3333,
  "arc": { "length": 3, "partsReady": 2, "status": "active" },
  "createdAt": "2026-10-30T18:00:00Z", "totalParts": 3,
  "parts": [
    { "partNumber": 1, "title": "Звёздная пещера", "text": "Раз.", "closing": "Спи.", "read": true, "media": [] },
    { "partNumber": 2, "title": "Огоньки", "text": "Два.", "closing": "Спи.", "read": false, "media": [] }
  ]
}
""".utf8)

extension StubbedNetwork {
    @MainActor @Suite struct SeriesUITests {
        // MARK: Create form

        @Test func aSeriesRequestCarriesTheFormatAndLength() {
            var draft = CreateDraft(activeProfile: Sample.anya)
            #expect(!draft.isSeries)
            #expect(draft.request().format == .quickStory)
            #expect(draft.request().arcLength == nil)

            draft.formatChoice = 3
            #expect(draft.isSeries)
            #expect(draft.arcLength == CreateDraft.arcLengths[0])

            draft.arcLength = 7
            let request = draft.request()
            #expect(request.format == .storyArcPart)
            #expect(request.arcLength == 7)
            #expect(request.profileIds == [Sample.anya.id])

            draft.formatChoice = 0
            #expect(draft.arcLength == nil)
            #expect(draft.request().format == .quickStory)
        }

        // MARK: Next part

        private func makeModel(storyId: String = "s1", _ handler: @escaping (URLRequest) -> Result<(Int, Data), Error>) -> StoryGenerationModel {
            RouteStub.routes["POST /v1/stories/\(storyId)/parts"] = handler
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [RouteStub.self]
            let client = APIClient(baseURL: URL(string: "http://route.test")!, store: MemorySessionStore(token: "t"), session: URLSession(configuration: configuration))
            return StoryGenerationModel(client: client, job: .nextPart(storyId: storyId, seriesTitle: "Звёздная пещера"), stepDelay: .milliseconds(2), finishDelay: .milliseconds(2))
        }

        private func settle(_ model: StoryGenerationModel) async {
            for _ in 0..<400 {
                if model.phase != .running { return }
                try? await Task.sleep(for: .milliseconds(5))
            }
        }

        @Test func nextPartYieldsAReadablePartOfTheSeries() async {
            let model = makeModel { _ in .success((200, partJSON)) }
            model.start()
            await settle(model)

            guard case .done(let story) = model.phase else {
                Issue.record("expected done, got \(model.phase)")
                return
            }
            #expect(story.partNumber == 2)
            #expect(story.partCount == 3)
            #expect(story.title == "Огоньки")
            #expect(story.seriesTitle == "Звёздная пещера")
            #expect(story.moral == nil)
        }

        @Test func aPartThatAlreadyExistsGivesAFriendlyMessage() async {
            let body = Data(#"{"error":{"code":"part_conflict","message":"Part 2 already exists."}}"#.utf8)
            let model = makeModel { _ in .success((409, body)) }
            model.start()
            await settle(model)

            guard case .failed(.other(let text)) = model.phase else {
                Issue.record("expected a failure, got \(model.phase)")
                return
            }
            #expect(text.contains("уже готова"))
        }

        @Test func deletedHeroesAreExplained() async {
            let body = Data(#"{"error":{"code":"heroes_missing","message":"x"}}"#.utf8)
            let model = makeModel { _ in .success((409, body)) }
            model.start()
            await settle(model)

            guard case .failed(.other(let text)) = model.phase else {
                Issue.record("expected a failure, got \(model.phase)")
                return
            }
            #expect(text.contains("удалены"))
        }

        @Test func theSeriesLimitIsExplainedOnThePaywall() async {
            let body = Data(#"{"error":{"code":"limit_reached","message":"m","feature":"story_arc","tier":"family","limit":1}}"#.utf8)
            let model = makeModel { _ in .success((402, body)) }
            model.start()
            await settle(model)

            guard case .failed(.paywall(let info)) = model.phase else {
                Issue.record("expected a paywall, got \(model.phase)")
                return
            }
            #expect(info.feature == "story_arc")
            #expect(info.limit == 1)
        }

        // MARK: Library

        @Test func readingAPartUpdatesTheProgressInTheLibrary() async {
            var series = Sample.story("series1", "Звёздная пещера", hero: ["k1"])
            series.arc = StoryArcInfo(length: 3, partsReady: 2)
            let app = Sample.appModel(stories: [series])
            var patched: [String: Any]?
            RouteStub.routes["PATCH /v1/stories/series1"] = { request in
                patched = try? JSONSerialization.jsonObject(with: request.bodyData) as? [String: Any]
                return .success((200, storyJSON))
            }

            await app.markPartRead(id: "series1", part: 1)

            #expect(patched?["readPart"] as? Int == 1)
            #expect(app.stories.first?.readProgress ?? 0 > 0.3)
            #expect(app.stories.first?.readProgress ?? 1 < 0.4)
        }

        @Test func aSeriesShowsItsProgressInTheLibrary() {
            var series = Sample.story("series1", "Звёздная пещера", hero: ["k1"], minutes: 4)
            series.arc = StoryArcInfo(length: 7, partsReady: 2)
            #expect(series.metaLine == "Серия · 2 из 7")
            #expect(Sample.story("x", "Т", hero: ["k1"], minutes: 4).metaLine == "4 мин")
            #expect(series.isSeries)
        }

        @Test func openingASeriesLoadsItsStory() async throws {
            let app = Sample.appModel()
            RouteStub.routes["GET /v1/stories/series1"] = { _ in .success((200, storyJSON)) }
            let story = try await app.series(id: "series1")
            #expect(story.parts.map(\.partNumber) == [1, 2])
            #expect(story.arc?.partsReady == 2)
        }
    }
}
