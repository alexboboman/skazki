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
}
#endif
