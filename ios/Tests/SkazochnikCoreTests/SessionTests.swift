import Foundation
import Testing
@testable import SkazochnikCore

private final class SessionStub: URLProtocol, @unchecked Sendable {
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

@Suite(.serialized) struct SessionTests {
    private func makeClient(store: SessionStore, _ handler: @escaping (URLRequest) -> Result<(Int, Data), Error>) -> APIClient {
        SessionStub.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SessionStub.self]
        return APIClient(baseURL: URL(string: "http://localhost:3000")!, store: store, session: URLSession(configuration: configuration))
    }

    @Test func refreshReplacesTheStoredToken() async throws {
        let auth = try fixture("auth_anonymous") // token "test-token"
        let store = MemorySessionStore(token: "old")
        let client = makeClient(store: store) { request in
            #expect(request.url?.path == "/v1/auth/refresh")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "authorization") == "Bearer old")
            return .success((200, auth))
        }
        try await client.refreshToken()
        #expect(store.loadToken() == "test-token")
    }

    @Test func refreshWithoutATokenDoesNothing() async throws {
        var called = false
        let client = makeClient(store: MemorySessionStore()) { _ in called = true; return .success((200, Data())) }
        try await client.refreshToken()
        #expect(!called)
    }

    @Test func refreshReportsALostAccountAndKeepsTheToken() async throws {
        let unauthorized = try fixture("error_unauthorized")
        let store = MemorySessionStore(token: "old")
        let client = makeClient(store: store) { _ in .success((401, unauthorized)) }
        do {
            try await client.refreshToken()
            Issue.record("expected unauthorized")
        } catch {
            #expect(error as? APIError == .unauthorized)
        }
        #expect(store.loadToken() == "old")
    }

    @Test func refreshOfflineKeepsTheToken() async {
        let store = MemorySessionStore(token: "old")
        let client = makeClient(store: store) { _ in .failure(URLError(.notConnectedToInternet)) }
        try? await client.refreshToken()
        #expect(store.loadToken() == "old")
    }

    @Test func cachesCanBeWiped() throws {
        let memory = MemoryLibraryCache()
        memory.save(["a"], key: "x")
        memory.removeAll()
        #expect(memory.load([String].self, key: "x") == nil)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("wipe-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = FileLibraryCache(directory: directory)
        file.save(["a"], key: "x")
        file.save(["b"], key: "y")
        file.removeAll()
        #expect(file.load([String].self, key: "x") == nil)
        #expect(file.load([String].self, key: "y") == nil)
        file.save(["c"], key: "z") // still usable afterwards
        #expect(file.load([String].self, key: "z") == ["c"])
    }

    @Test func profileEditAndDeleteWriteThroughToTheCache() async throws {
        let profile = try fixture("profile")
        let profiles = try fixture("profiles")
        var lastMethod = ""
        let cache = MemoryLibraryCache()
        let client = makeClient(store: MemorySessionStore(token: "t")) { request in
            lastMethod = request.httpMethod ?? ""
            switch request.httpMethod {
            case "PUT": return .success((200, profile))
            case "DELETE": return .success((204, Data()))
            default: return .success((200, profiles))
            }
        }
        let repository = LibraryRepository(client: client, cache: cache)
        let loaded = try await repository.profiles()
        let id = try #require(loaded.value.first?.id)

        let updated = try await repository.updateProfile(id: id, ChildProfileInput(name: "Аня", age: 6))
        #expect(lastMethod == "PUT")
        #expect(repository.cachedProfiles().first { $0.id == id }?.name == updated.name)

        try await repository.deleteProfile(id: id)
        #expect(lastMethod == "DELETE")
        #expect(repository.cachedProfiles().isEmpty)

        repository.forgetEverything()
        #expect(repository.cachedStories().isEmpty)
    }
}
