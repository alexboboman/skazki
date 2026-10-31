import Foundation
import Testing
@testable import SkazochnikCore

/// Fixtures in Tests/SkazochnikCoreTests/Fixtures are real responses of apps/api (see scripts note in ios/README.md),
/// so these tests fail when the API contract and the Swift models drift apart.
@Suite(.serialized) struct APIClientTests {
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try APIClient.decoder.decode(type, from: fixture(name))
    }

    // MARK: Decoding

    @Test func decodesAnonymousAuth() throws {
        let auth = try decode(AuthResponse.self, "auth_anonymous")
        #expect(auth.token == "test-token")
        #expect(auth.user.anonymous)
    }

    @Test func decodesTrialEntitlements() throws {
        let entitlements = try decode(Entitlements.self, "entitlements_trial")
        #expect(entitlements.tier == .family)
        #expect(entitlements.source == "trial")
        #expect(nil != entitlements.trialEndsAt)
        #expect(entitlements.limits.profiles.limit == 3)
        #expect(entitlements.quotas.first { $0.feature == "quick_story" }?.period == "month")
    }

    @Test func decodesProfileWithAppearance() throws {
        let profile = try decode(ChildProfile.self, "profile")
        #expect(profile.name == "Аня")
        #expect(profile.gender == .girl)
        #expect(profile.appearance == Appearance(skin: 1, hair: 3, hairStyle: .long, outfit: 0))
        #expect(profile.worlds == [.forest])
    }

    @Test func decodesGeneratedStory() throws {
        let response = try decode(GenerateStoryResponse.self, "generate")
        #expect(nil != response.storyId)
        #expect(response.story.title == "Саша и дракончик")
        #expect(response.story.moral == "Дружба делает мир теплее.")
        #expect(response.story.closing == "Спи сладко.")
        #expect(!response.story.text.contains("[IMAGE"))
        #expect(response.media.map(\.afterParagraph) == [1, 2])
        #expect(response.steps.map(\.name) == ["generate_text", "safety_check", "parse_media_prompts", "generate_images"])
    }

    @Test func decodesLibraryAndStory() throws {
        struct Envelope: Decodable { var stories: [StorySummary] }
        let list = try decode(Envelope.self, "stories").stories
        #expect(list.count == 1)
        #expect(list[0].favorite)
        #expect(abs(list[0].readProgress - 0.62) < 0.0001)
        #expect(list[0].coverImageUrl?.hasPrefix("/v1/media/") ?? false)

        let story = try decode(Story.self, "story")
        #expect(story.parts.count == 1)
        #expect(story.parts[0].media.count == 2)
        #expect(story.world == "forest")
        #expect(story.moral == "Дружба делает мир теплее.")
    }

    @Test func encodesGenerateRequestLikeTheAPIExpects() throws {
        let request = GenerateStoryRequest(profileIds: ["a", "b"], topic: "Не страшно в темноте", lengthMinutes: 7, world: .castle)
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect(object["profileIds"] as? [String] == ["a", "b"])
        #expect(object["format"] as? String == "quick_story")
        #expect(object["lengthMinutes"] as? Int == 7)
        #expect(object["world"] as? String == "castle")
        let media = try #require(object["mediaOptions"] as? [String: Any])
        #expect(media["imageQuality"] as? String == "standard")
    }

    // MARK: Client

    private func makeClient(store: SessionStore = MemorySessionStore(), responding: @escaping (URLRequest) -> (Int, Data)) -> APIClient {
        StubProtocol.handler = responding
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return APIClient(baseURL: URL(string: "http://localhost:3000")!, store: store, session: URLSession(configuration: configuration))
    }

    @Test func ensureSignedInCreatesGuestOnceAndStoresToken() async throws {
        let store = MemorySessionStore()
        let auth = try fixture("auth_anonymous")
        var calls = 0
        let client = makeClient(store: store) { request in
            calls += 1
            #expect(request.url?.path == "/v1/auth/anonymous")
            #expect(nil == request.value(forHTTPHeaderField: "authorization"))
            return (201, auth)
        }

        let created = try await client.ensureSignedIn()
        #expect(created)
        #expect(store.loadToken() == "test-token")

        let again = try await client.ensureSignedIn()
        #expect(!again)
        #expect(calls == 1)
    }

    @Test func sendsBearerTokenAndEncodesProfile() async throws {
        let profile = try fixture("profile")
        let client = makeClient(store: MemorySessionStore(token: "abc")) { request in
            #expect(request.value(forHTTPHeaderField: "authorization") == "Bearer abc")
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/v1/profiles")
            let body = request.bodyData
            let sent = try? JSONDecoder().decode(ChildProfileInput.self, from: body)
            #expect(sent?.worlds == [.forest])
            #expect(sent?.appearance?.hairStyle == .long)
            return (201, profile)
        }

        let created = try await client.createProfile(ChildProfileInput(
            name: "Аня", age: 5, gender: .girl,
            appearance: Appearance(skin: 1, hair: 3, hairStyle: .long, outfit: 0),
            interests: ["Феи"], worlds: [.forest]
        ))
        #expect(created.name == "Аня")
    }

    @Test func libraryQueryItems() async throws {
        let stories = try fixture("stories")
        let client = makeClient(store: MemorySessionStore(token: "t")) { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            #expect(query.first { $0.name == "profileId" }?.value == "p1")
            #expect(query.first { $0.name == "favorite" }?.value == "true")
            return (200, stories)
        }
        let list = try await client.stories(profileId: "p1", favorite: true)
        #expect(list.count == 1)
    }

    @Test func paywallErrorsAreMapped() async throws {
        let quota = try fixture("error_paywall_quota")
        let profiles = try fixture("error_paywall_profiles")
        var next = quota
        let client = makeClient(store: MemorySessionStore(token: "t")) { _ in (402, next) }

        do {
            _ = try await client.generateStory(GenerateStoryRequest(profileIds: ["p"]))
            Issue.record("expected a paywall error")
        } catch let APIError.paywall(info) {
            #expect(info.code == .limitReached)
            #expect(info.feature == "quick_story")
            #expect(info.tier == .free)
            #expect(info.limit == 3)
            #expect(nil != info.resetsAt)
        }

        next = profiles
        do {
            _ = try await client.createProfile(ChildProfileInput(name: "Б", age: 5))
            Issue.record("expected a paywall error")
        } catch let APIError.paywall(info) {
            #expect(info.feature == "profiles")
        }
    }

    @Test func otherErrorsAreMapped() async throws {
        let rejected = try fixture("error_story_rejected")
        let unauthorized = try fixture("error_unauthorized")
        var status = 422
        var body = rejected
        let client = makeClient(store: MemorySessionStore(token: "t")) { _ in (status, body) }

        do {
            _ = try await client.generateStory(GenerateStoryRequest(profileIds: ["p"]))
            Issue.record("expected a rejection")
        } catch let APIError.storyRejected(message) {
            #expect(message.contains("safety"))
        }

        status = 401
        body = unauthorized
        do {
            _ = try await client.profiles()
            Issue.record("expected unauthorized")
        } catch {
            #expect(error as? APIError == .unauthorized)
        }

        status = 502
        body = Data("oops".utf8)
        do {
            _ = try await client.profiles()
            Issue.record("expected a server error")
        } catch {
            #expect(error as? APIError == .server(status: 502, code: "unknown", message: "HTTP 502"))
        }
    }

    @Test func mediaURLIsResolvedAgainstTheBase() {
        let client = APIClient(baseURL: URL(string: "http://localhost:3000")!, store: MemorySessionStore())
        #expect(client.mediaURL("/v1/media/x.webp")?.absoluteString == "http://localhost:3000/v1/media/x.webp")
    }

    @Test func keychainStoreRoundTrips() {
        let store = KeychainSessionStore(service: "app.skazochnik.tests.\(UUID().uuidString)")
        #expect(nil == store.loadToken())
        store.saveToken("secret")
        #expect(store.loadToken() == "secret")
        store.saveToken(nil)
        #expect(nil == store.loadToken())
    }
}

/// Serves canned responses instead of hitting the network.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else { return }
        let (status, data) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension URLRequest {
    /// URLSession turns httpBody into a stream before it reaches a URLProtocol.
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

@Suite struct ReadableStoryTests {
    private func asset(_ id: String, after: Int) -> MediaAsset {
        MediaAsset(id: id, type: "image", variant: "standard", provider: "mock", url: "/v1/media/\(id).webp", contentType: "image/webp", prompt: "", afterParagraph: after)
    }

    @Test func placesIllustrationsAfterTheirParagraphs() {
        let story = ReadableStory(
            title: "Т", text: "Раз.\n\nДва.\n\nТри.",
            media: [asset("a", after: 1), asset("b", after: 2)], readingMinutes: 1
        )
        #expect(story.blocks.map(\.id) == ["p1", "ma", "p2", "mb", "p3"])
        #expect(story.paragraphs == ["Раз.", "Два.", "Три."])
        #expect(story.illustrationCount == 2)
    }

    @Test func imagesPastTheEndGoToTheEnd() {
        let story = ReadableStory(title: "Т", text: "Раз.\n\nДва.", media: [asset("x", after: 9)], readingMinutes: 1)
        #expect(story.blocks.map(\.id) == ["p1", "p2", "mx"])
    }

    @Test func ignoresBlankParagraphs() {
        let story = ReadableStory(title: "Т", text: "\n\nРаз.\n\n  \n\nДва.\n", media: [], readingMinutes: 1)
        #expect(story.paragraphs == ["Раз.", "Два."])
    }

    @Test func buildsFromTheRealGenerateResponse() throws {
        let url = try #require(Bundle.module.url(forResource: "generate", withExtension: "json", subdirectory: "Fixtures"))
        let response = try APIClient.decoder.decode(GenerateStoryResponse.self, from: Data(contentsOf: url))
        let story = ReadableStory(response: response)
        #expect(story.title == "Саша и дракончик")
        #expect(story.storyId == response.storyId)
        #expect(story.moral == "Дружба делает мир теплее.")
        #expect(story.blocks.map(\.id).filter { $0.hasPrefix("m") }.count == 2)
        #expect(story.blocks.first?.id == "p1")
    }

    @Test func buildsFromASavedStory() throws {
        let url = try #require(Bundle.module.url(forResource: "story", withExtension: "json", subdirectory: "Fixtures"))
        let saved = try APIClient.decoder.decode(Story.self, from: Data(contentsOf: url))
        let story = ReadableStory(story: saved)
        #expect(story.storyId == saved.id)
        #expect(story.closing == "Спи сладко.")
        #expect(story.illustrationCount == 2)
    }
}
