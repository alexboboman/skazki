import Foundation

/// Data plus whether it came from the offline cache because the network was unreachable.
public struct Loaded<Value: Sendable>: Sendable {
    public var value: Value
    public var fromCache: Bool

    public init(value: Value, fromCache: Bool) {
        self.value = value
        self.fromCache = fromCache
    }
}

/// Profiles and stories from the API with a disk cache behind them. Only network failures fall back to
/// the cache; server errors (401, 402, 5xx) are real answers and are passed on.
public struct LibraryRepository: Sendable {
    private let client: APIClient
    private let cache: LibraryCache

    public init(client: APIClient, cache: LibraryCache) {
        self.client = client
        self.cache = cache
    }

    // MARK: Instant reads for the first paint

    public func cachedProfiles() -> [ChildProfile] { cache.load([ChildProfile].self, key: "profiles") ?? [] }
    public func cachedStories() -> [StorySummary] { cache.load([StorySummary].self, key: "stories") ?? [] }
    public func cachedStory(id: String) -> Story? { cache.load(Story.self, key: "story-\(id)") }

    // MARK: Network with fallback

    public func profiles() async throws -> Loaded<[ChildProfile]> {
        try await fetch(key: "profiles") { try await client.profiles() }
    }

    public func stories() async throws -> Loaded<[StorySummary]> {
        try await fetch(key: "stories") { try await client.stories() }
    }

    public func story(id: String) async throws -> Loaded<Story> {
        try await fetch(key: "story-\(id)") { try await client.story(id: id) }
    }

    // MARK: Writes keep the cache in step

    public func setFavorite(id: String, _ favorite: Bool) async throws {
        let updated = try await client.updateStory(id: id, favorite: favorite)
        cache.save(updated, key: "story-\(id)")
        var list = cachedStories()
        if let index = list.firstIndex(where: { $0.id == id }) {
            list[index].favorite = favorite
            cache.save(list, key: "stories")
        }
    }

    public func setProgress(id: String, _ progress: Double) async throws {
        let updated = try await client.updateStory(id: id, readProgress: progress)
        cache.save(updated, key: "story-\(id)")
        var list = cachedStories()
        if let index = list.firstIndex(where: { $0.id == id }) {
            list[index].readProgress = progress
            cache.save(list, key: "stories")
        }
    }

    public func deleteStory(id: String) async throws {
        try await client.deleteStory(id: id)
        cache.remove(key: "story-\(id)")
        cache.save(cachedStories().filter { $0.id != id }, key: "stories")
    }

    public func updateProfile(id: String, _ input: ChildProfileInput) async throws -> ChildProfile {
        let updated = try await client.updateProfile(id: id, input)
        var list = cachedProfiles()
        if let index = list.firstIndex(where: { $0.id == id }) { list[index] = updated } else { list.append(updated) }
        cache.save(list, key: "profiles")
        return updated
    }

    public func deleteProfile(id: String) async throws {
        try await client.deleteProfile(id: id)
        cache.save(cachedProfiles().filter { $0.id != id }, key: "profiles")
    }

    /// Stores a story that was just generated, so it can be reopened offline straight away.
    public func remember(_ story: Story) {
        cache.save(story, key: "story-\(story.id)")
    }

    public func forgetEverything() { cache.removeAll() }

    private func fetch<T: Codable & Sendable>(key: String, _ request: () async throws -> T) async throws -> Loaded<T> {
        do {
            let value = try await request()
            cache.save(value, key: key)
            return Loaded(value: value, fromCache: false)
        } catch APIError.transport(let message) {
            if let cached = cache.load(T.self, key: key) {
                return Loaded(value: cached, fromCache: true)
            }
            throw APIError.transport(message)
        }
    }
}
