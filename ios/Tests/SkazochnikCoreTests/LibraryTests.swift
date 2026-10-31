import Foundation
import Testing
@testable import SkazochnikCore

private final class LibraryStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> Result<(Int, Data), Error>)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        switch Self.handler?(request) ?? .failure(URLError(.notConnectedToInternet)) {
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

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

@Suite(.serialized) struct LibraryRepositoryTests {
    private func makeRepository(
        cache: LibraryCache = MemoryLibraryCache(),
        _ handler: @escaping (URLRequest) -> Result<(Int, Data), Error>
    ) -> LibraryRepository {
        LibraryStub.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LibraryStub.self]
        let client = APIClient(
            baseURL: URL(string: "http://localhost:3000")!,
            store: MemorySessionStore(token: "t"),
            session: URLSession(configuration: configuration)
        )
        return LibraryRepository(client: client, cache: cache)
    }

    @Test func networkResultIsCachedAndServedWhenOffline() async throws {
        let stories = try fixture("stories")
        var online = true
        let repository = makeRepository { _ in online ? .success((200, stories)) : .failure(URLError(.notConnectedToInternet)) }

        #expect(repository.cachedStories().isEmpty)
        let fresh = try await repository.stories()
        #expect(!fresh.fromCache)
        #expect(fresh.value.count == 1)
        #expect(repository.cachedStories().count == 1)

        online = false
        let offline = try await repository.stories()
        #expect(offline.fromCache)
        #expect(offline.value.map(\.id) == fresh.value.map(\.id))
    }

    @Test func offlineWithoutACacheStillFails() async throws {
        let repository = makeRepository { _ in .failure(URLError(.notConnectedToInternet)) }
        do {
            _ = try await repository.profiles()
            Issue.record("expected a transport error")
        } catch {
            if case .transport = error as? APIError {} else { Issue.record("wrong error: \(error)") }
        }
    }

    @Test func serverErrorsAreNotHiddenByTheCache() async throws {
        let stories = try fixture("stories")
        let unauthorized = try fixture("error_unauthorized")
        var answer: (Int, Data) = (200, stories)
        let repository = makeRepository { _ in .success(answer) }
        _ = try await repository.stories()

        answer = (401, unauthorized)
        do {
            _ = try await repository.stories()
            Issue.record("expected unauthorized")
        } catch {
            #expect(error as? APIError == .unauthorized)
        }
    }

    @Test func storyDetailIsCachedForOfflineReading() async throws {
        let story = try fixture("story")
        var online = true
        let repository = makeRepository { _ in online ? .success((200, story)) : .failure(URLError(.timedOut)) }

        let id = try APIClient.decoder.decode(Story.self, from: story).id
        #expect(repository.cachedStory(id: id) == nil)
        _ = try await repository.story(id: id)
        #expect(repository.cachedStory(id: id)?.closing == "Спи сладко.")

        online = false
        let offline = try await repository.story(id: id)
        #expect(offline.fromCache)
        #expect(offline.value.parts.first?.media.count == 2)
    }

    @Test func favoriteAndProgressWriteThroughToTheCache() async throws {
        let stories = try fixture("stories")
        let story = try fixture("story")
        let id = try APIClient.decoder.decode(Story.self, from: story).id
        var sent: [String: Any] = [:]
        let repository = makeRepository { request in
            if request.httpMethod == "PATCH" {
                let body = request.bodyStreamData
                sent = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
                return .success((200, story))
            }
            return .success((200, stories))
        }
        _ = try await repository.stories()

        try await repository.setFavorite(id: id, false)
        #expect(sent["favorite"] as? Bool == false)
        #expect(repository.cachedStories().first?.favorite == false)

        try await repository.setProgress(id: id, 0.4)
        #expect(sent["readProgress"] as? Double == 0.4)
        #expect(abs((repository.cachedStories().first?.readProgress ?? 0) - 0.4) < 0.0001)
    }

    @Test func deletingRemovesTheStoryFromTheCache() async throws {
        let stories = try fixture("stories")
        let story = try fixture("story")
        let id = try APIClient.decoder.decode(Story.self, from: story).id
        let repository = makeRepository { request in
            request.httpMethod == "DELETE" ? .success((204, Data())) : .success((200, stories))
        }
        _ = try await repository.stories()
        repository.remember(try APIClient.decoder.decode(Story.self, from: story))
        #expect(repository.cachedStory(id: id) != nil)

        try await repository.deleteStory(id: id)
        #expect(repository.cachedStories().isEmpty)
        #expect(repository.cachedStory(id: id) == nil)
    }
}

@Suite struct CacheAndLabelTests {
    @Test func fileCacheRoundTripsAndRemoves() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lib-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileLibraryCache(directory: directory)

        let list = try APIClient.decoder.decode([StorySummary].self, from: {
            let wrapper = try JSONSerialization.jsonObject(with: fixture("stories")) as? [String: Any]
            return try JSONSerialization.data(withJSONObject: wrapper?["stories"] ?? [])
        }())
        cache.save(list, key: "stories")

        let loaded = try #require(cache.load([StorySummary].self, key: "stories"))
        #expect(loaded.count == list.count)
        #expect(loaded[0].title == list[0].title)
        #expect(abs(loaded[0].createdAt.timeIntervalSince(list[0].createdAt)) < 1)

        // A second instance sees the same files, as after an app restart.
        #expect(FileLibraryCache(directory: directory).load([StorySummary].self, key: "stories")?.count == list.count)

        cache.remove(key: "stories")
        #expect(cache.load([StorySummary].self, key: "stories") == nil)
    }

    @Test func keysWithOddCharactersStaySafe() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lib-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileLibraryCache(directory: directory)
        cache.save(["a"], key: "../../etc/passwd")
        #expect(cache.load([String].self, key: "../../etc/passwd") == ["a"])
        #expect((try? FileManager.default.contentsOfDirectory(atPath: directory.path))?.count == 1)
    }

    @Test func dayLabels() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 20))!
        func ago(_ days: Int) -> Date { calendar.date(byAdding: .day, value: -days, to: now)! }

        #expect(StoryDateLabel.label(for: now, now: now, calendar: calendar) == "Сегодня")
        #expect(StoryDateLabel.label(for: ago(1), now: now, calendar: calendar) == "Вчера")
        #expect(StoryDateLabel.label(for: ago(3), now: now, calendar: calendar) == "3 дня назад")
        #expect(StoryDateLabel.label(for: ago(6), now: now, calendar: calendar) == "На неделе")
        #expect(StoryDateLabel.label(for: ago(40), now: now, calendar: calendar) == "В сентябре")
    }
}

private extension URLRequest {
    var bodyStreamData: Data {
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
