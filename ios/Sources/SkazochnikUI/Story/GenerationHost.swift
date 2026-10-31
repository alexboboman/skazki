import SwiftUI
import SkazochnikCore

/// Owns the generation model of one story request and shows the progress or error screen.
struct GenerationHost: View {
    @StateObject private var model: StoryGenerationModel
    let hero: HeroInfo
    let onDone: (ReadableStory) -> Void
    let onPaywall: (PaywallInfo) -> Void
    let onClose: () -> Void

    init(
        client: APIClient,
        profile: ChildProfile,
        request: GenerateStoryRequest,
        onDone: @escaping (ReadableStory) -> Void,
        onPaywall: @escaping (PaywallInfo) -> Void,
        onClose: @escaping () -> Void
    ) {
        _model = StateObject(wrappedValue: StoryGenerationModel(client: client, request: request))
        hero = HeroInfo(profile: profile)
        self.onDone = onDone
        self.onPaywall = onPaywall
        self.onClose = onClose
    }

    var body: some View {
        GenerateView(model: model, hero: hero, onPaywall: onPaywall, onClose: onClose)
            .onChange(of: model.phase) { _, phase in
                if case .done(let story) = phase { onDone(story) }
            }
    }
}

/// Create a story from the main app: generate, reveal the cover, read it. Uses the active child and the
/// default settings until the full «Сочинить» screen (topic, length, world, several heroes) exists.
struct QuickCreateFlow: View {
    private enum Stage: Equatable {
        case generating
        case reveal(ReadableStory)
        case reading(ReadableStory)
        case paywall(PaywallInfo)
    }

    @ObservedObject var app: AppModel
    let profile: ChildProfile
    let onClose: () -> Void

    @State private var stage: Stage = .generating

    var body: some View {
        let hero = HeroInfo(profile: profile)

        Group {
            switch stage {
            case .generating:
                GenerationHost(
                    client: app.client,
                    profile: profile,
                    request: GenerateStoryRequest(profileIds: [profile.id], format: .quickStory, lengthMinutes: 7),
                    onDone: { story in
                        Task { await app.storyCreated(story) }
                        stage = .reveal(story)
                    },
                    onPaywall: { stage = .paywall($0) },
                    onClose: onClose
                )
            case .reveal(let story):
                RevealView(story: story, hero: hero, kicker: "Готово · новая сказка") { stage = .reading(story) }
            case .reading(let story):
                ReadingView(
                    story: story,
                    hero: hero,
                    mediaURL: app.client.mediaURL,
                    onBack: onClose,
                    onReachedEnd: { if let id = story.storyId { Task { await app.markRead(id: id) } } },
                    favorite: story.storyId.flatMap { id in app.stories.first { $0.id == id }?.favorite },
                    onToggleFavorite: {
                        if let id = story.storyId, let summary = app.stories.first(where: { $0.id == id }) {
                            Task { await app.toggleFavorite(summary) }
                        }
                    }
                )
            case .paywall(let info):
                // Purchasing arrives with StoreKit; both buttons just close for now.
                PaywallView(hero: hero, reason: info, onTrial: onClose, onFree: onClose)
            }
        }
        .animation(.easeOut(duration: 0.35), value: stage)
    }
}
