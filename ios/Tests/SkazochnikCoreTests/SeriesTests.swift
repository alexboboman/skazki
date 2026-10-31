import Foundation
import Testing
@testable import SkazochnikCore

private final class SeriesStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (status, data) = Self.handler?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Fixtures series_* are real responses of apps/api for a 3-part series (mock providers): part 1, part 2,
/// the story after part 1 was read, and the library list.
@Suite(.serialized) struct SeriesTests {
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try APIClient.decoder.decode(type, from: fixture(name))
    }

    private func makeClient(_ handler: @escaping (URLRequest) -> (Int, Data)) -> APIClient {
        SeriesStub.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SeriesStub.self]
        return APIClient(baseURL: URL(string: "http://localhost:3000")!, store: MemorySessionStore(token: "t"), session: URLSession(configuration: configuration))
    }

    // MARK: Decoding

    @Test func decodesTheStartOfASeries() throws {
        let response = try decode(GenerateStoryResponse.self, "series_start")
        #expect(response.partNumber == 1)
        #expect(response.arc == StoryArcInfo(length: 3, partsReady: 1, status: .active))
        #expect(response.story.title == "Аня и звёздная пещера")
        #expect(response.story.moral == nil)
        #expect(response.story.closing != nil)
    }

    @Test func decodesTheStoryOfASeries() throws {
        let story = try decode(Story.self, "series_story")
        #expect(story.isSeries)
        #expect(story.arc == StoryArcInfo(length: 3, partsReady: 2, status: .active))
        #expect(story.totalParts == 3)
        #expect(story.parts.map(\.partNumber) == [1, 2])
        #expect(story.parts.map(\.isRead) == [true, false])
        #expect(story.parts[1].title == "Ночь 2: огоньки ведут дальше")
        #expect(abs(story.readProgress - 1.0 / 3) < 0.001)
    }

    @Test func singleStoriesDecodeWithoutSeriesFields() throws {
        let story = try decode(Story.self, "story")
        #expect(!story.isSeries)
        #expect(story.parts[0].title == nil)
        #expect(!story.parts[0].isRead)
    }

    @Test func decodesTheSeriesInTheLibraryList() throws {
        struct Envelope: Decodable { var stories: [StorySummary] }
        let list = try decode(Envelope.self, "series_stories").stories
        #expect(list.count == 1)
        #expect(list[0].format == .storyArcPart)
        #expect(list[0].arc?.partsReady == 2)
    }

    @Test func decodesTheSeriesLimitPaywall() async throws {
        let body = try fixture("error_paywall_arc_limit")
        let client = makeClient { _ in (402, body) }
        do {
            _ = try await client.generateStory(GenerateStoryRequest(profileIds: ["p"], format: .storyArcPart, arcLength: 3))
            Issue.record("expected a paywall")
        } catch let APIError.paywall(info) {
            #expect(info.feature == "story_arc")
            #expect(info.code == .limitReached)
            #expect(info.limit == 1)
        }
    }

    @Test func entitlementsCountUnfinishedSeries() throws {
        let entitlements = try decode(Entitlements.self, "entitlements_arc")
        #expect(entitlements.limits.activeArcs == 1)
        #expect(entitlements.limits.activeArcsUsed == 1)
    }

    // MARK: Requests

    @Test func startingASeriesSendsTheLength() throws {
        let request = GenerateStoryRequest(profileIds: ["a"], format: .storyArcPart, lengthMinutes: 4, arcLength: 5)
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect(object["format"] as? String == "story_arc_part")
        #expect(object["arcLength"] as? Int == 5)

        let single = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(GenerateStoryRequest(profileIds: ["a"]))) as? [String: Any])
        #expect(single["arcLength"] == nil)
    }

    @Test func nextPartPostsToThePartsEndpoint() async throws {
        let part = try fixture("series_part2")
        let client = makeClient { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/v1/stories/abc/parts")
            let body = try? JSONSerialization.jsonObject(with: request.bodyData) as? [String: Any]
            #expect((body?["mediaOptions"] as? [String: Any])?["imageQuality"] as? String == "hd")
            return (200, part)
        }
        let response = try await client.generateNextPart(storyId: "abc")
        #expect(response.partNumber == 2)
        #expect(response.arc?.partsReady == 2)
    }

    @Test func markingAPartReadSendsReadPartAndUpdatesTheCache() async throws {
        let story = try fixture("series_story")
        let cache = MemoryLibraryCache()
        let list = try decode(StoriesEnvelope.self, "series_stories").stories
        cache.save(list, key: "stories")

        var sent: [String: Any]?
        let client = makeClient { request in
            #expect(request.httpMethod == "PATCH")
            sent = try? JSONSerialization.jsonObject(with: request.bodyData) as? [String: Any]
            return (200, story)
        }
        let repository = LibraryRepository(client: client, cache: cache)

        try await repository.markPartRead(id: list[0].id, part: 1)

        #expect(sent?["readPart"] as? Int == 1)
        #expect(sent?["favorite"] == nil)
        #expect(abs((repository.cachedStories().first?.readProgress ?? 0) - 1.0 / 3) < 0.001)
        #expect(repository.cachedStory(id: list[0].id)?.parts.first?.isRead == true)
    }

    private struct StoriesEnvelope: Codable { var stories: [StorySummary] }

    // MARK: Reading a part

    @Test func readingAPartUsesItsTitleTextAndClosing() throws {
        let story = try decode(Story.self, "series_story")
        let second = ReadableStory(story: story, part: 2)
        #expect(second.title == "Ночь 2: огоньки ведут дальше")
        #expect(second.seriesTitle == "Аня и звёздная пещера")
        #expect(second.partNumber == 2)
        #expect(second.partCount == 3)
        #expect(!second.isLastPart)
        #expect(second.moral == nil)
        #expect(second.closing == story.parts[1].closing)
        #expect(second.paragraphs.first == story.parts[1].text.components(separatedBy: "\n\n").first)
    }

    @Test func theMoralComesOnlyWithTheLastPart() throws {
        var story = try decode(Story.self, "series_story")
        story.moral = "Вместе любой путь волшебный."
        story.arc = StoryArcInfo(length: 2, partsReady: 2, status: .completed)

        #expect(ReadableStory(story: story, part: 1).moral == nil)
        let last = ReadableStory(story: story, part: 2)
        #expect(last.isLastPart)
        #expect(last.moral == "Вместе любой путь волшебный.")
    }

    @Test func aGeneratedPartKnowsItsPlaceInTheSeries() throws {
        let first = ReadableStory(response: try decode(GenerateStoryResponse.self, "series_start"))
        #expect(first.partNumber == 1)
        #expect(first.seriesTitle == first.title)

        let second = ReadableStory(response: try decode(GenerateStoryResponse.self, "series_part2"), seriesTitle: "Аня и звёздная пещера")
        #expect(second.partNumber == 2)
        #expect(second.seriesTitle == "Аня и звёздная пещера")
        #expect(second.title != second.seriesTitle)
    }

    @Test func aSingleStoryIsNotASeriesPart() throws {
        let single = ReadableStory(response: try decode(GenerateStoryResponse.self, "generate"))
        #expect(!single.isSeriesPart)
        #expect(single.seriesTitle == nil)
    }
}
