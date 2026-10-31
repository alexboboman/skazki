import SwiftUI
import SkazochnikCore

/// State of the main app: children, the library and which child is active.
@MainActor
public final class AppModel: ObservableObject {
    @Published public private(set) var profiles: [ChildProfile]
    @Published public private(set) var stories: [StorySummary]
    @Published public private(set) var isOffline = false
    @Published public private(set) var isLoading = false
    /// The server no longer recognises this account (token expired or the account is gone).
    @Published public private(set) var sessionExpired = false
    @Published public var activeProfileId: String? {
        didSet { defaults.set(activeProfileId, forKey: Self.activeKey) }
    }

    public let client: APIClient
    let repository: LibraryRepository
    private let defaults: UserDefaults
    private static let activeKey = "activeProfileId"

    public init(client: APIClient, repository: LibraryRepository, defaults: UserDefaults = .standard) {
        self.client = client
        self.repository = repository
        self.defaults = defaults
        profiles = repository.cachedProfiles()
        stories = repository.cachedStories()
        activeProfileId = defaults.string(forKey: Self.activeKey)
    }

    // MARK: Children

    public var activeProfile: ChildProfile? {
        profiles.first { $0.id == activeProfileId } ?? profiles.first
    }

    func hero(for profile: ChildProfile?) -> HeroInfo {
        profile.map(HeroInfo.init(profile:)) ?? HeroInfo(name: "Малыш", age: 5)
    }

    /// The first hero of a story, falling back to the active child when that profile was deleted.
    func hero(for story: StorySummary) -> HeroInfo {
        let profile = story.heroIds.first.flatMap { id in profiles.first { $0.id == id } } ?? activeProfile
        return hero(for: profile)
    }

    func storyCount(for profile: ChildProfile) -> Int {
        stories.filter { $0.heroIds.contains(profile.id) }.count
    }

    public func added(_ profile: ChildProfile) {
        profiles.removeAll { $0.id == profile.id }
        profiles.append(profile)
        activeProfileId = profile.id
    }

    // MARK: Library

    /// Stories of one child (or everyone), newest first, optionally only favourites and matching a search.
    func stories(for profileId: String?, favoritesOnly: Bool = false, matching query: String = "") -> [StorySummary] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return stories
            .filter { profileId == nil || $0.heroIds.contains(profileId!) }
            .filter { !favoritesOnly || $0.favorite }
            .filter { needle.isEmpty || ($0.title ?? "").localizedCaseInsensitiveContains(needle) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Replaces an edited profile in place.
    public func updated(_ profile: ChildProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
    }

    /// At least one child always stays: the app has nothing to tell stories about otherwise.
    var canDeleteProfiles: Bool { profiles.count > 1 }

    /// Returns false when the child could not be deleted.
    @discardableResult
    func deleteProfile(_ profile: ChildProfile) async -> Bool {
        guard canDeleteProfiles else { return false }
        do {
            try await repository.deleteProfile(id: profile.id)
        } catch {
            return false
        }
        profiles.removeAll { $0.id == profile.id }
        if activeProfileId == profile.id { activeProfileId = profiles.first?.id }
        // The server drops the child from its stories; do the same here until the next refresh.
        for index in stories.indices { stories[index].heroIds.removeAll { $0 == profile.id } }
        return true
    }

    @discardableResult
    func deleteStory(_ story: StorySummary) async -> Bool {
        do {
            try await repository.deleteStory(id: story.id)
        } catch {
            return false
        }
        stories.removeAll { $0.id == story.id }
        return true
    }

    /// A story the child has started but not finished.
    func storyToContinue(for profileId: String?) -> StorySummary? {
        stories(for: profileId).first { $0.readProgress > 0 && $0.readProgress < 1 }
    }

    func recentStories(for profileId: String?, excluding excluded: StorySummary?) -> [StorySummary] {
        Array(stories(for: nil).filter { $0.id != excluded?.id }.prefix(6))
    }

    public func refresh() async {
        isLoading = true
        defer { isLoading = false }

        // Renew the token first, so an account that is used regularly never expires.
        do {
            try await client.refreshToken()
        } catch APIError.unauthorized {
            sessionExpired = true
            return
        } catch {}

        do {
            async let loadedProfiles = repository.profiles()
            async let loadedStories = repository.stories()
            let (p, s) = try await (loadedProfiles, loadedStories)
            profiles = p.value
            stories = s.value
            isOffline = p.fromCache || s.fromCache
        } catch APIError.unauthorized {
            sessionExpired = true
        } catch {
            isOffline = true
        }
    }

    /// Wipes the local data of the lost account, the caller then restarts onboarding.
    public func startOver() {
        repository.forgetEverything()
        client.signOut()
        defaults.removeObject(forKey: Self.activeKey)
        profiles = []
        stories = []
        activeProfileId = nil
    }

    func readable(_ summary: StorySummary) async throws -> ReadableStory {
        let loaded = try await repository.story(id: summary.id)
        return ReadableStory(story: loaded.value)
    }

    /// The full story of a series (all parts written so far).
    func series(id: String) async throws -> Story {
        try await repository.story(id: id).value
    }

    /// A part of a series was read to the end.
    func markPartRead(id: String, part: Int) async {
        try? await repository.markPartRead(id: id, part: part)
        if let progress = repository.cachedStories().first(where: { $0.id == id })?.readProgress,
           let index = stories.firstIndex(where: { $0.id == id }) {
            stories[index].readProgress = progress
        }
    }

    /// The profile whose avatar stands for a story: its first hero, else the active child.
    func profile(for story: StorySummary) -> ChildProfile? {
        story.heroIds.first.flatMap { id in profiles.first { $0.id == id } } ?? activeProfile
    }

    /// Called after a new story was generated: pull it into the library and the offline cache.
    public func storyCreated(_ story: ReadableStory) async {
        await refresh()
        if let id = story.storyId, let loaded = try? await repository.story(id: id) {
            repository.remember(loaded.value)
        }
    }

    func toggleFavorite(_ summary: StorySummary) async {
        guard let index = stories.firstIndex(where: { $0.id == summary.id }) else { return }
        let target = !stories[index].favorite
        stories[index].favorite = target
        do {
            try await repository.setFavorite(id: summary.id, target)
        } catch {
            if let current = stories.firstIndex(where: { $0.id == summary.id }) { stories[current].favorite = !target }
        }
    }

    func markRead(id: String) async {
        if let index = stories.firstIndex(where: { $0.id == id }) { stories[index].readProgress = 1 }
        try? await repository.setProgress(id: id, 1)
    }
}
