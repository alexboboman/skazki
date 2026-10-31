import Foundation
import SwiftUI
import Testing
import SkazochnikCore
@testable import SkazochnikUI

#if canImport(AppKit)
import AppKit

/// Renders the onboarding screens at iPhone size so they can be looked at without a simulator.
/// Set RENDER_DIR to also write the PNGs to disk.
@MainActor
@Suite(.serialized) struct ScreenRenderTests {
    static let size = CGSize(width: 402, height: 874)

    private func model(step: OnboardingStep) -> OnboardingModel {
        let client = APIClient(baseURL: URL(string: "http://localhost:3000")!, store: MemorySessionStore())
        let model = OnboardingModel(client: client) { _ in }
        model.step = step
        model.draft.name = "Аня"
        model.draft.age = 5
        model.draft.gender = .girl
        model.draft.appearance = Appearance(skin: 1, hair: 3, hairStyle: .long, outfit: 0)
        model.draft.interests = ["Феи", "Море", "Животные"]
        return model
    }

    private func render<V: View>(_ name: String, @ViewBuilder _ content: () -> V) throws {
        let framed = ZStack {
            NightBackground(starCount: 40, seed: 7)
            content()
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .environment(\.colorScheme, .dark)
        .environment(\.snapshotMode, true)

        let renderer = ImageRenderer(content: framed)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let tiff = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        #expect(png.count > 5_000, "\(name) rendered almost empty")

        if let dir = ProcessInfo.processInfo.environment["RENDER_DIR"] {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    @Test func rendersIntroScreens() throws {
        try render("01-welcome") { WelcomeView(model: model(step: .welcome)) }
        try render("02-value") { ValueView(model: model(step: .value)) }
    }

    @Test func rendersProfileSteps() throws {
        try render("03-name") { NameStepView(model: model(step: .name)) }
        try render("04-age") { AgeStepView(model: model(step: .age)) }
        try render("05-appearance") { AppearanceStepView(model: model(step: .appearance)) }
        try render("06-interests") { InterestsStepView(model: model(step: .interests)) }
        try render("07-world") { WorldStepView(model: model(step: .world)) }
    }

    @Test func rendersHeroVariants() throws {
        try render("08-heroes") {
            HStack(spacing: 8) {
                HeroAvatarView(appearance: Appearance(skin: 0, hair: 3, hairStyle: .short, outfit: 1), size: 90)
                HeroAvatarView(appearance: Appearance(skin: 3, hair: 5, hairStyle: .long, outfit: 4), size: 90)
                HeroAvatarView(appearance: Appearance(skin: 4, hair: 0, hairStyle: .short, outfit: 2), size: 90)
            }
        }
    }

    // MARK: Story flow

    private let hero = HeroInfo(name: "Аня", age: 5, appearance: Appearance(skin: 1, hair: 3, hairStyle: .long, outfit: 0))

    private let story = ReadableStory(
        storyId: "s1",
        title: "Аня и звёздная пещера",
        text: """
        Когда над миром зажглись первые звёзды, Аня услышала тихий шёпот ветра. «Идём, — позвал он, — я покажу тебе самое волшебное место».

        Рядом семенил маленький друг — дракончик Рекс, чешуя которого блестела, словно изумруды. Вместе они прошли мимо спящих цветов.

        Внутри потолок мерцал тысячами огоньков. «Это светлячки, — прошептал Рекс».
        """,
        media: [
            MediaAsset(id: "a", type: "image", variant: "standard", provider: "mock", url: "/v1/media/a.svg", contentType: "image/svg+xml", prompt: "", afterParagraph: 2)
        ],
        moral: "Даже когда мы отдыхаем, жизнь остаётся волшебной.",
        closing: "Спи сладко. Пусть тебе приснятся звёзды и добрые драконы…",
        readingMinutes: 5
    )

    private func generationModel() -> StoryGenerationModel {
        let client = APIClient(baseURL: URL(string: "http://localhost:3000")!, store: MemorySessionStore(token: "t"))
        return StoryGenerationModel(client: client, request: GenerateStoryRequest(profileIds: ["p"]), stepDelay: .seconds(3600))
    }

    @Test func rendersStoryScreens() throws {
        try render("10-generate") { GenerateView(model: generationModel(), hero: hero, onPaywall: { _ in }, onClose: {}) }
        try render("11-reveal") { RevealView(story: story, hero: hero, onRead: {}) }
        try render("12-reading") { ReadingView(story: story, hero: hero, mediaURL: { _ in nil }, onBack: {}, onUpsell: {}) }
        try render("13-paywall") { PaywallView(hero: hero, onTrial: {}, onFree: {}) }
        try render("14-done") { DoneView(hero: hero, trial: true, onHome: {}) }
    }
}
#endif
