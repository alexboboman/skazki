import SwiftUI
import SkazochnikCore

/// State of the main app: children, the library and which child is active.
@MainActor
public final class AppModel: ObservableObject {
    @Published public private(set) var profiles: [ChildProfile]
    @Published public private(set) var stories: [StorySummary]
    @Published public private(set) var isOffline = false
    @Published public private(set) var isLoading = false
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

    /// Stories of one child (or everyone), newest first, optionally only favourites.
    func stories(for profileId: String?, favoritesOnly: Bool = false) -> [StorySummary] {
        stories
            .filter { profileId == nil || $0.heroIds.contains(profileId!) }
            .filter { !favoritesOnly || $0.favorite }
            .sorted { $0.createdAt > $1.createdAt }
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
        do {
            async let loadedProfiles = repository.profiles()
            async let loadedStories = repository.stories()
            let (p, s) = try await (loadedProfiles, loadedStories)
            profiles = p.value
            stories = s.value
            isOffline = p.fromCache || s.fromCache
        } catch {
            isOffline = true
        }
    }

    func readable(_ summary: StorySummary) async throws -> ReadableStory {
        let loaded = try await repository.story(id: summary.id)
        return ReadableStory(story: loaded.value)
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
