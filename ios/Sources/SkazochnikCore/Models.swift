import Foundation

// Mirrors packages/shared/src/index.ts. Keep the two in sync when the API contract changes.

public enum Gender: String, Codable, Sendable, CaseIterable {
    case boy, girl
}

public enum WorldID: String, Codable, Sendable, CaseIterable {
    case forest, ocean, space, castle, clouds, jungle
}

public enum StoryFormat: String, Codable, Sendable {
    case quickStory = "quick_story"
    case classicStory = "classic_story"
    case storyArcPart = "story_arc_part"
}

public enum HairStyle: String, Codable, Sendable, CaseIterable {
    case short, long
}

/// Hero look as indexes into the palettes (see `Palette` in SkazochnikUI and docs/design/prototype/ui.jsx).
public struct Appearance: Codable, Equatable, Sendable {
    public var skin: Int
    public var hair: Int
    public var hairStyle: HairStyle
    public var outfit: Int

    public init(skin: Int = 1, hair: Int = 1, hairStyle: HairStyle = .short, outfit: Int = 0) {
        self.skin = skin
        self.hair = hair
        self.hairStyle = hairStyle
        self.outfit = outfit
    }
}

public struct ChildProfileInput: Codable, Equatable, Sendable {
    public var name: String
    public var age: Int
    public var gender: Gender?
    public var appearance: Appearance?
    public var interests: [String]
    public var worlds: [WorldID]
    public var favoriteCharacter: String?
    public var language: String

    public init(
        name: String,
        age: Int,
        gender: Gender? = nil,
        appearance: Appearance? = nil,
        interests: [String] = [],
        worlds: [WorldID] = [],
        favoriteCharacter: String? = nil,
        language: String = "Русский"
    ) {
        self.name = name
        self.age = age
        self.gender = gender
        self.appearance = appearance
        self.interests = interests
        self.worlds = worlds
        self.favoriteCharacter = favoriteCharacter
        self.language = language
    }
}

public struct ChildProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var age: Int
    public var gender: Gender?
    public var appearance: Appearance?
    public var interests: [String]
    public var worlds: [WorldID]
    public var favoriteCharacter: String?
    public var language: String
    public var createdAt: Date
}

public struct AuthUser: Codable, Equatable, Sendable {
    public var id: String
    public var email: String?
    public var anonymous: Bool
}

public struct AuthResponse: Codable, Equatable, Sendable {
    public var token: String
    public var user: AuthUser
}

public enum Tier: String, Codable, Sendable {
    case free, family
    case familyPlus = "family_plus"
}

public struct QuotaStatus: Codable, Equatable, Sendable {
    public var feature: String
    public var period: String
    public var limit: Int
    public var used: Int
    public var resetsAt: Date
}

public struct Entitlements: Codable, Equatable, Sendable {
    public struct Limits: Codable, Equatable, Sendable {
        public struct Profiles: Codable, Equatable, Sendable {
            public var limit: Int
            public var used: Int
        }
        public var profiles: Profiles
        public var activeArcs: Int
        public var imageQuality: String
    }

    public var tier: Tier
    public var source: String
    public var trialEndsAt: Date?
    public var limits: Limits
    public var quotas: [QuotaStatus]
}

public struct MediaAsset: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var type: String
    public var variant: String
    public var provider: String
    public var url: String
    public var contentType: String
    public var prompt: String
    public var afterParagraph: Int
}

public struct StorySummary: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String?
    public var format: StoryFormat
    public var world: String?
    public var heroIds: [String]
    public var coverImageUrl: String?
    public var readingMinutes: Int
    public var favorite: Bool
    public var readProgress: Double
    public var createdAt: Date
}

public struct StoryPart: Codable, Equatable, Sendable {
    public var partNumber: Int
    public var text: String
    public var media: [MediaAsset]
}

public struct Story: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String?
    public var format: StoryFormat
    public var world: String?
    public var heroIds: [String]
    public var coverImageUrl: String?
    public var readingMinutes: Int
    public var favorite: Bool
    public var readProgress: Double
    public var createdAt: Date
    public var moral: String?
    public var closing: String?
    public var totalParts: Int
    public var parts: [StoryPart]
}

public enum ImageQuality: String, Codable, Sendable {
    case standard, hd
}

public struct MediaOptions: Codable, Equatable, Sendable {
    public var requestedTypes: [String]
    public var imageQuality: ImageQuality

    public init(requestedTypes: [String] = ["image"], imageQuality: ImageQuality = .standard) {
        self.requestedTypes = requestedTypes
        self.imageQuality = imageQuality
    }
}

/// Body of POST /v1/stories/generate for saved profiles (the first id is the main hero).
public struct GenerateStoryRequest: Codable, Equatable, Sendable {
    public var profileIds: [String]
    public var format: StoryFormat
    public var topic: String?
    public var lengthMinutes: Int?
    public var world: WorldID?
    public var mediaOptions: MediaOptions?

    public init(
        profileIds: [String],
        format: StoryFormat = .quickStory,
        topic: String? = nil,
        lengthMinutes: Int? = nil,
        world: WorldID? = nil,
        mediaOptions: MediaOptions? = MediaOptions()
    ) {
        self.profileIds = profileIds
        self.format = format
        self.topic = topic
        self.lengthMinutes = lengthMinutes
        self.world = world
        self.mediaOptions = mediaOptions
    }
}

public struct GeneratedStory: Codable, Equatable, Sendable {
    public var title: String?
    public var text: String
    public var moral: String?
    public var closing: String?
    public var readingMinutes: Int
}

public struct PipelineStep: Codable, Equatable, Sendable {
    public var name: String
    public var status: String
    public var provider: String?
    public var durationMs: Int
    public var error: String?
}

public struct GenerateStoryResponse: Codable, Equatable, Sendable {
    public var storyId: String?
    public var story: GeneratedStory
    public var media: [MediaAsset]
    public var steps: [PipelineStep]
}
