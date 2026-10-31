import Foundation
import SwiftUI
import Testing
import SkazochnikCore
@testable import SkazochnikUI

#if canImport(AppKit)
import AppKit

/// CreateView with the series switch on (its state is private to the view, so the preview asks the draft in).
private struct CreateSeriesPreview: View {
    @ObservedObject var app: AppModel
    var body: some View { CreateView(app: app, profile: Sample.anya, initialDraft: { $0.formatChoice = 3 }, onClose: {}, onCreate: { _ in }) }
}

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

    // MARK: Main app

    private func mainScreen<V: View>(_ tab: MainTab, @ViewBuilder _ content: () -> V) -> some View {
        VStack(spacing: 0) {
            content().frame(maxWidth: .infinity, maxHeight: .infinity)
            MainTabBar(tab: .constant(tab), onCreate: {})
        }
    }

    @Test func rendersMainScreens() throws {
        let app = Sample.appModel()
        try render("20-home") { mainScreen(.home) { HomeView(app: app, onOpen: { _ in }, onCreate: {}, onAllStories: {}) } }
        try render("21-library") { mainScreen(.library) { LibraryView(app: app, onOpen: { _ in }, onFavorite: { _ in }) } }
        try render("22-kids") { mainScreen(.kids) { KidsView(app: app, onAdd: {}, onEdit: { _ in }) } }
        try render("23-library-empty") {
            mainScreen(.library) { LibraryView(app: Sample.appModel(stories: []), onOpen: { _ in }, onFavorite: { _ in }) }
        }
    }

    // MARK: Create

    @Test func rendersCreateScreen() throws {
        let app = Sample.appModel()
        try render("30-create") { CreateView(app: app, profile: Sample.anya, onClose: {}, onCreate: { _ in }) }
        try render("31-create-one-child") {
            CreateView(app: Sample.appModel(profiles: [Sample.anya]), profile: Sample.anya, onClose: {}, onCreate: { _ in })
        }
    }

    // MARK: Series

    private var seriesStory: Story {
        let json = """
        {"id":"series1","title":"Аня и звёздная пещера","format":"story_arc_part","world":"forest","heroIds":["k1"],
         "readingMinutes":4,"favorite":false,"readProgress":0.33,"arc":{"length":5,"partsReady":3,"status":"active"},
         "createdAt":"2026-10-30T18:00:00Z","totalParts":5,
         "parts":[
          {"partNumber":1,"title":"Аня и звёздная пещера","text":"Раз.","closing":"Спи.","read":true,"media":[]},
          {"partNumber":2,"title":"Огоньки ведут дальше","text":"Два.","closing":"Спи.","read":true,"media":[]},
          {"partNumber":3,"title":"Река тихих историй","text":"Три.","closing":"Спи.","read":false,"media":[]}]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try! decoder.decode(Story.self, from: Data(json.utf8))
    }

    @Test func rendersSeriesScreens() throws {
        try render("40-series") {
            SeriesOverview(story: seriesStory, hero: hero, mediaURL: { _ in nil }, loadFailed: false, onClose: {}, onRetry: {}, onRead: { _ in }, onNextPart: {})
        }
        var allRead = seriesStory
        allRead.parts[2].read = true
        try render("41-series-all-read") {
            SeriesOverview(story: allRead, hero: hero, mediaURL: { _ in nil }, loadFailed: false, onClose: {}, onRetry: {}, onRead: { _ in }, onNextPart: {})
        }
        var done = allRead
        done.arc = StoryArcInfo(length: 5, partsReady: 5, status: .completed)
        try render("42-series-completed") {
            SeriesOverview(story: done, hero: hero, mediaURL: { _ in nil }, loadFailed: false, onClose: {}, onRetry: {}, onRead: { _ in }, onNextPart: {})
        }
        try render("43-series-failed") {
            SeriesOverview(story: nil, hero: hero, mediaURL: { _ in nil }, loadFailed: true, onClose: {}, onRetry: {}, onRead: { _ in }, onNextPart: {})
        }
        var part = ReadableStory(story: seriesStory, part: 2)
        part.closing = "Спи сладко."
        try render("44-series-reading") {
            ReadingView(
                story: part, hero: hero, mediaURL: { _ in nil }, onBack: {},
                finale: SeriesFinale(title: "Часть 2 из 5 прочитана", message: "Продолжение — в следующий вечер.", buttonTitle: "К серии", action: {})
            )
        }
    }

    @Test func rendersCreateScreenWithASeries() throws {
        let app = Sample.appModel()
        try render("32-create-series") {
            VStack {
                Text("").frame(height: 0)
                CreateSeriesPreview(app: app)
            }
        }
    }

    // MARK: App icon

    /// Draws the 1024 pt app icon. `APP_ICON_DIR=ios/App/Assets.xcassets/AppIcon.appiconset swift test --filter writesAppIcon` rewrites it.
    @Test func writesAppIcon() throws {
        let icon = ZStack {
            RadialGradient(colors: [Theme.bg2, Theme.bg1, Theme.bg0], center: UnitPoint(x: 0.5, y: 0.1), startRadius: 0, endRadius: 900)
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0x8B6EDB, opacity: 0.55), .clear], center: .center, startRadius: 0, endRadius: 360))
                .frame(width: 720, height: 720)
                .offset(x: -260, y: -300)
            StarField(count: 26, seed: 21, animated: false)
            MoonIcon(size: 520)
            Sparkle(size: 92).offset(x: -250, y: -190)
            Sparkle(size: 56, color: .white).offset(x: 270, y: 250)
            Sparkle(size: 40).offset(x: 300, y: -260)
        }
        .frame(width: 1024, height: 1024)
        .clipped()

        let renderer = ImageRenderer(content: icon)
        renderer.scale = 1
        let image = try #require(renderer.nsImage)
        let tiff = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        #expect(png.count > 20_000)

        if let dir = ProcessInfo.processInfo.environment["APP_ICON_DIR"] {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("icon-1024.png"))
        }
    }
}
#endif
