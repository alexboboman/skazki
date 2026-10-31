import Foundation
import SkazochnikCore

/// Choices on the «Сочинить» screen and how they become a generate request.
struct CreateDraft: Equatable {
    static let maxHeroes = 3

    /// Ready-made topics of the design; the first one means "no special topic".
    static let topics = [
        "Просто волшебная", "Не страшно в темноте", "Первый день в саду",
        "Поход к врачу", "Новый братик", "Как помириться с другом",
    ]
    static let lengths: [(minutes: Int, title: String)] = [(4, "~4 мин"), (7, "~7 мин"), (12, "~12 мин")]

    /// Children in the order they were picked; the first one is the main hero.
    private(set) var heroIds: [String]
    var topic = CreateDraft.topics[0]
    var note = ""
    private(set) var world: WorldID
    var lengthMinutes = 7
    private var worldTouched = false

    init(activeProfile: ChildProfile) {
        heroIds = [activeProfile.id]
        world = activeProfile.worlds.first ?? .forest
    }

    var hasNote: Bool { !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func isSelected(_ profile: ChildProfile) -> Bool { heroIds.contains(profile.id) }

    /// Taps a child: adds up to three, removes unless it is the last one left.
    mutating func toggle(_ profile: ChildProfile, in all: [ChildProfile]) {
        if let index = heroIds.firstIndex(of: profile.id) {
            guard heroIds.count > 1 else { return }
            heroIds.remove(at: index)
        } else if heroIds.count < Self.maxHeroes {
            heroIds.append(profile.id)
        }
        // Until the parent picks a world, it follows the main hero's favourite.
        if !worldTouched, let main = all.first(where: { $0.id == heroIds[0] }) {
            world = main.worlds.first ?? .forest
        }
    }

    mutating func pickWorld(_ world: WorldID) {
        self.world = world
        worldTouched = true
    }

    /// The parent's own words win over a preset; the first preset sends nothing.
    var topicText: String? {
        let own = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !own.isEmpty { return String(own.prefix(300)) }
        return topic == Self.topics[0] ? nil : topic
    }

    func names(in all: [ChildProfile]) -> String {
        heroIds.compactMap { id in all.first { $0.id == id }?.name }.joined(separator: " и ")
    }

    func request(imageQuality: ImageQuality = .standard) -> GenerateStoryRequest {
        GenerateStoryRequest(
            profileIds: heroIds,
            format: .quickStory,
            topic: topicText,
            lengthMinutes: lengthMinutes,
            world: world,
            mediaOptions: MediaOptions(requestedTypes: ["image"], imageQuality: imageQuality)
        )
    }
}
