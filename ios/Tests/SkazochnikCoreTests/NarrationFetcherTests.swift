import Foundation
import Testing
@testable import SkazochnikCore

private final class FetchStub: URLProtocol, @unchecked Sendable {
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

private let readyJSON = Data(#"{"id":"a1","type":"audio","variant":"standard","provider":"phygital","url":"/v1/media/a1.mp3","contentType":"audio/mpeg","prompt":"","afterParagraph":1}"#.utf8)
private let processingJSON = Data(#"{"status":"processing"}"#.utf8)

@Suite(.serialized) struct NarrationFetcherTests {
    private func makeFetcher(maxWait: Duration = .seconds(5), _ handler: @escaping (URLRequest) -> (Int, Data)) -> (NarrationFetcher, URL) {
        FetchStub.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FetchStub.self]
        let client = APIClient(baseURL: URL(string: "http://localhost:3000")!, store: MemorySessionStore(token: "t"), session: URLSession(configuration: configuration))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("narration-\(UUID().uuidString)", isDirectory: true)
        return (NarrationFetcher(client: client, directory: directory, pollInterval: .milliseconds(5), maxWait: maxWait), directory)
    }

    private var asset: MediaAsset {
        try! APIClient.decoder.decode(MediaAsset.self, from: readyJSON)
    }

    @Test func clientTellsProcessingFromReady() async throws {
        let (_, _) = makeFetcher { _ in (202, processingJSON) }
        let client = APIClient(baseURL: URL(string: "http://localhost:3000")!, store: MemorySessionStore(token: "t"), session: {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [FetchStub.self]
            return URLSession(configuration: configuration)
        }())
        #expect(try await client.narration(storyId: "s", part: 1) == .processing)

        FetchStub.handler = { request in
            #expect(request.url?.path == "/v1/stories/s/audio")
            #expect(request.httpMethod == "POST")
            return (200, readyJSON)
        }
        #expect(try await client.narration(storyId: "s", part: 2) == .ready(asset))
    }

    @Test func waitsWhileProcessingThenDownloadsAndKeepsTheFile() async throws {
        var asks = 0
        var downloads = 0
        let (fetcher, directory) = makeFetcher { request in
            if request.url?.path == "/v1/media/a1.mp3" {
                downloads += 1
                return (200, Data("MP3DATA".utf8))
            }
            asks += 1
            return asks < 3 ? (202, processingJSON) : (200, readyJSON)
        }
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = try await fetcher.file(storyId: "s", part: 1, known: nil)
        #expect(asks == 3)
        #expect(file.lastPathComponent == "a1.mp3")
        #expect(try Data(contentsOf: file) == Data("MP3DATA".utf8))

        // The second time nothing is asked and nothing is downloaded: the file is on the device.
        let again = try await fetcher.file(storyId: "s", part: 1, known: asset)
        #expect(again == file)
        #expect(downloads == 1)
        #expect(asks == 3)
    }

    @Test func aKnownNarrationIsDownloadedWithoutAskingTheServerToVoice() async throws {
        var asked = false
        let (fetcher, directory) = makeFetcher { request in
            if request.url?.path.hasSuffix("/audio") == true { asked = true }
            return (200, Data("X".utf8))
        }
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = try await fetcher.file(storyId: "s", part: 1, known: asset)
        #expect(!asked)
    }

    @Test func aPlanWithoutPremiumVoiceIsReported() async {
        let body = Data(#"{"error":{"code":"upgrade_required","message":"m","feature":"premium_voice","tier":"family"}}"#.utf8)
        let (fetcher, _) = makeFetcher { _ in (402, body) }
        await #expect(throws: NarrationError.needsPlan) { try await fetcher.file(storyId: "s", part: 1, known: nil) }
    }

    @Test func aServerWithoutAVoiceIsReported() async {
        let body = Data(#"{"error":{"code":"premium_voice_unavailable","message":"m"}}"#.utf8)
        let (fetcher, _) = makeFetcher { _ in (503, body) }
        await #expect(throws: NarrationError.unavailable) { try await fetcher.file(storyId: "s", part: 1, known: nil) }
    }

    @Test func aFailedVoicingCarriesTheServersMessage() async {
        let body = Data(#"{"error":{"code":"audio_generation_failed","message":"voice provider down"}}"#.utf8)
        let (fetcher, _) = makeFetcher { _ in (502, body) }
        await #expect(throws: NarrationError.failed("voice provider down")) { try await fetcher.file(storyId: "s", part: 1, known: nil) }
    }

    @Test func givesUpWhenVoicingNeverFinishes() async {
        let (fetcher, _) = makeFetcher(maxWait: .milliseconds(60)) { _ in (202, processingJSON) }
        await #expect(throws: NarrationError.timedOut) { try await fetcher.file(storyId: "s", part: 1, known: nil) }
    }

    @Test func aStoryCarriesItsNarrationAndNeverShowsItAsAnIllustration() throws {
        let json = """
        {"id":"s1","title":"Т","format":"quick_story","heroIds":[],"readingMinutes":3,"favorite":false,"readProgress":0,
         "createdAt":"2026-10-30T18:00:00Z","totalParts":1,
         "parts":[{"partNumber":1,"text":"Раз.\\n\\nДва.","media":[
           {"id":"i1","type":"image","variant":"standard","provider":"p","url":"/v1/media/i1.webp","contentType":"image/webp","prompt":"","afterParagraph":1},
           {"id":"a1","type":"audio","variant":"standard","provider":"p","url":"/v1/media/a1.mp3","contentType":"audio/mpeg","prompt":"","afterParagraph":1}]}]}
        """
        let story = try APIClient.decoder.decode(Story.self, from: Data(json.utf8))
        let readable = ReadableStory(story: story)

        #expect(readable.audio?.id == "a1")
        #expect(readable.illustrationCount == 1)
        #expect(readable.blocks.map(\.id) == ["p1", "mi1", "p2"])
    }
}
