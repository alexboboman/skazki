import Foundation

public enum PaywallCode: String, Codable, Sendable {
    case limitReached = "limit_reached"
    case upgradeRequired = "upgrade_required"
}

/// HTTP 402 body: show the paywall. `feature` is `profiles`, `story_arc`, `classic_story` or `quick_story`.
public struct PaywallInfo: Equatable, Sendable {
    public var code: PaywallCode
    public var message: String
    public var feature: String
    public var tier: Tier
    public var limit: Int?
    public var resetsAt: Date?
}

public enum APIError: Error, Equatable, Sendable {
    case paywall(PaywallInfo)
    case unauthorized
    case notFound(String)
    /// The story was rejected by the safety check twice (HTTP 422).
    case storyRejected(String)
    case server(status: Int, code: String, message: String)
    case transport(String)
    case decoding(String)
}

public protocol SessionStore: Sendable {
    func loadToken() -> String?
    func saveToken(_ token: String?)
}

public final class MemorySessionStore: SessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?

    public init(token: String? = nil) {
        self.token = token
    }

    public func loadToken() -> String? {
        lock.lock(); defer { lock.unlock() }
        return token
    }

    public func saveToken(_ token: String?) {
        lock.lock(); defer { lock.unlock() }
        self.token = token
    }
}

public struct APIClient: Sendable {
    public let baseURL: URL
    private let session: URLSession
    private let store: SessionStore

    public init(baseURL: URL, store: SessionStore, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.store = store
        self.session = session
    }

    // MARK: Auth

    /// Returns the stored account or creates a guest one, so onboarding needs no sign-in.
    @discardableResult
    public func ensureSignedIn() async throws -> Bool {
        if store.loadToken() != nil { return false }
        let response: AuthResponse = try await send("POST", "/v1/auth/anonymous", authorized: false)
        store.saveToken(response.token)
        return true
    }

    /// Links the Apple ID to the current guest account (the guest token is sent along).
    public func signInWithApple(identityToken: String) async throws -> AuthResponse {
        let response: AuthResponse = try await send("POST", "/v1/auth/apple", body: ["identityToken": identityToken])
        store.saveToken(response.token)
        return response
    }

    /// Swaps the stored token for a fresh one; the app calls this on every launch so tokens never run out
    /// while the app is in use. Throws `.unauthorized` when the account is no longer recognised.
    public func refreshToken() async throws {
        guard store.loadToken() != nil else { return }
        let response: AuthResponse = try await send("POST", "/v1/auth/refresh")
        store.saveToken(response.token)
    }

    public func signOut() {
        store.saveToken(nil)
    }

    // MARK: Entitlements and profiles

    public func entitlements() async throws -> Entitlements {
        try await send("GET", "/v1/entitlements")
    }

    public func profiles() async throws -> [ChildProfile] {
        struct Envelope: Decodable { var profiles: [ChildProfile] }
        let envelope: Envelope = try await send("GET", "/v1/profiles")
        return envelope.profiles
    }

    public func createProfile(_ input: ChildProfileInput) async throws -> ChildProfile {
        try await send("POST", "/v1/profiles", body: input)
    }

    public func updateProfile(id: String, _ input: ChildProfileInput) async throws -> ChildProfile {
        try await send("PUT", "/v1/profiles/\(id)", body: input)
    }

    public func deleteProfile(id: String) async throws {
        try await sendEmpty("DELETE", "/v1/profiles/\(id)")
    }

    // MARK: Stories

    public func generateStory(_ request: GenerateStoryRequest) async throws -> GenerateStoryResponse {
        try await send("POST", "/v1/stories/generate", body: request)
    }

    public func stories(profileId: String? = nil, favorite: Bool? = nil) async throws -> [StorySummary] {
        struct Envelope: Decodable { var stories: [StorySummary] }
        var query: [URLQueryItem] = []
        if let profileId { query.append(URLQueryItem(name: "profileId", value: profileId)) }
        if let favorite { query.append(URLQueryItem(name: "favorite", value: favorite ? "true" : "false")) }
        let envelope: Envelope = try await send("GET", "/v1/stories", query: query)
        return envelope.stories
    }

    public func story(id: String) async throws -> Story {
        try await send("GET", "/v1/stories/\(id)")
    }

    public func updateStory(id: String, favorite: Bool? = nil, readProgress: Double? = nil) async throws -> Story {
        struct Patch: Encodable { var favorite: Bool?; var readProgress: Double? }
        return try await send("PATCH", "/v1/stories/\(id)", body: Patch(favorite: favorite, readProgress: readProgress))
    }

    public func deleteStory(id: String) async throws {
        try await sendEmpty("DELETE", "/v1/stories/\(id)")
    }

    /// Media urls come back relative (`/v1/media/<file>`); this makes them loadable.
    public func mediaURL(_ path: String) -> URL? {
        URL(string: path, relativeTo: baseURL)?.absoluteURL
    }

    // MARK: Transport

    private func send<Response: Decodable>(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        authorized: Bool = true
    ) async throws -> Response {
        let data = try await perform(method, path, query: query, body: nil as Data?, authorized: authorized)
        return try decode(data)
    }

    private func send<Response: Decodable, Body: Encodable>(
        _ method: String,
        _ path: String,
        body: Body,
        authorized: Bool = true
    ) async throws -> Response {
        let data = try await perform(method, path, query: [], body: try JSONEncoder().encode(body), authorized: authorized)
        return try decode(data)
    }

    private func sendEmpty(_ method: String, _ path: String) async throws {
        _ = try await perform(method, path, query: [], body: nil, authorized: true)
    }

    private func perform(
        _ method: String,
        _ path: String,
        query: [URLQueryItem],
        body: Data?,
        authorized: Bool
    ) async throws -> Data {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw APIError.transport("Bad URL: \(path)")
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.transport("Bad URL: \(path)") }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 90 // story generation can take 30 s or more
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "content-type")
        }
        if authorized, let token = store.loadToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.transport("No HTTP response") }
        if (200..<300).contains(http.statusCode) { return data }
        throw mapError(status: http.statusCode, data: data)
    }

    private func mapError(status: Int, data: Data) -> APIError {
        struct Envelope: Decodable {
            struct Body: Decodable {
                var code: String
                var message: String
                var feature: String?
                var tier: Tier?
                var limit: Int?
                var resetsAt: Date?
            }
            var error: Body
        }

        guard let body = (try? Self.decoder.decode(Envelope.self, from: data))?.error else {
            return .server(status: status, code: "unknown", message: "HTTP \(status)")
        }

        switch status {
        case 401:
            return .unauthorized
        case 402:
            if let code = PaywallCode(rawValue: body.code) {
                return .paywall(PaywallInfo(
                    code: code,
                    message: body.message,
                    feature: body.feature ?? "",
                    tier: body.tier ?? .free,
                    limit: body.limit,
                    resetsAt: body.resetsAt
                ))
            }
        case 404:
            return .notFound(body.message)
        case 422 where body.code == "story_rejected":
            return .storyRejected(body.message)
        default:
            break
        }
        return .server(status: status, code: body.code, message: body.message)
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    /// The API sends ISO 8601 dates with milliseconds (`toISOString()`).
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFraction.date(from: value) { return date }
            let plain = ISO8601DateFormatter()
            if let date = plain.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Bad date: \(value)")
        }
        return decoder
    }()
}
