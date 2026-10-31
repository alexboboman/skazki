import Foundation
import Testing
import SkazochnikCore
@testable import SkazochnikUI

private final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> Result<(Int, Data), Error>)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        switch Self.handler?(request) ?? .failure(URLError(.badServerResponse)) {
        case .success(let (status, data)):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private let generateJSON = Data("""
{
  "storyId": "s1",
  "story": { "title": "Сказка", "text": "Раз.\\n\\nДва.", "moral": "М", "closing": "С", "readingMinutes": 4 },
  "media": [{ "id": "a", "type": "image", "variant": "standard", "provider": "mock", "url": "/v1/media/a.svg",
              "contentType": "image/svg+xml", "prompt": "p", "afterParagraph": 1 }],
  "steps": []
}
""".utf8)

private func errorJSON(_ code: String, feature: String? = nil) -> Data {
    let extra = feature.map { ", \"feature\": \"\($0)\", \"tier\": \"free\", \"limit\": 3" } ?? ""
    return Data("{\"error\": {\"code\": \"\(code)\", \"message\": \"m\"\(extra)}}".utf8)
}

@MainActor
@Suite(.serialized) struct StoryGenerationModelTests {
    private func makeModel(_ handler: @escaping (URLRequest) -> Result<(Int, Data), Error>) -> StoryGenerationModel {
        StubProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let client = APIClient(
            baseURL: URL(string: "http://localhost:3000")!,
            store: MemorySessionStore(token: "t"),
            session: URLSession(configuration: configuration)
        )
        return StoryGenerationModel(
            client: client,
            request: GenerateStoryRequest(profileIds: ["p"], lengthMinutes: 4),
            stepDelay: .milliseconds(2),
            finishDelay: .milliseconds(2)
        )
    }

    private func settle(_ model: StoryGenerationModel) async {
        for _ in 0..<400 {
            if model.phase != .running { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func successWalksAllStepsAndReturnsTheStory() async throws {
        let model = makeModel { _ in .success((200, generateJSON)) }
        model.start()
        await settle(model)

        guard case .done(let story) = model.phase else {
            Issue.record("expected done, got \(model.phase)")
            return
        }
        #expect(story.title == "Сказка")
        #expect(story.storyId == "s1")
        #expect(story.moral == "М")
        #expect(story.illustrationCount == 1)
        #expect(model.currentStep == StoryGenerationModel.steps.count)
    }

    @Test func sendsTheGenerateRequest() async throws {
        var seen: URLRequest?
        let model = makeModel { request in
            seen = request
            return .success((200, generateJSON))
        }
        model.start()
        await settle(model)

        let request = try #require(seen)
        #expect(request.url?.path == "/v1/stories/generate")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "authorization") == "Bearer t")
    }

    @Test func paywallShowsImmediatelyWithoutWalkingTheSteps() async {
        let model = makeModel { _ in .success((402, errorJSON("limit_reached", feature: "quick_story"))) }
        model.start()
        await settle(model)

        guard case .failed(.paywall(let info)) = model.phase else {
            Issue.record("expected a paywall failure, got \(model.phase)")
            return
        }
        #expect(info.feature == "quick_story")
        #expect(info.code == .limitReached)
        #expect(model.currentStep < StoryGenerationModel.steps.count)
    }

    @Test func mapsRejectedOfflineAndServerErrors() async {
        let rejected = makeModel { _ in .success((422, errorJSON("story_rejected"))) }
        rejected.start()
        await settle(rejected)
        #expect(rejected.phase == .failed(.rejected))

        let offline = makeModel { _ in .failure(URLError(.notConnectedToInternet)) }
        offline.start()
        await settle(offline)
        #expect(offline.phase == .failed(.offline))

        let broken = makeModel { _ in .success((502, errorJSON("story_generation_failed"))) }
        broken.start()
        await settle(broken)
        #expect(broken.phase == .failed(.other("m")))
    }

    @Test func retryAfterAFailureCanSucceed() async {
        var attempts = 0
        let model = makeModel { _ in
            attempts += 1
            return attempts == 1 ? .failure(URLError(.timedOut)) : .success((200, generateJSON))
        }
        model.start()
        await settle(model)
        #expect(model.phase == .failed(.offline))

        model.retry()
        await settle(model)
        if case .done = model.phase {} else { Issue.record("expected done after retry, got \(model.phase)") }
        #expect(attempts == 2)
    }
}
