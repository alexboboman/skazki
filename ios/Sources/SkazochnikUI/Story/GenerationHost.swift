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

    /// Writes the next part of a series.
    init(
        client: APIClient,
        profile: ChildProfile,
        nextPartOf storyId: String,
        seriesTitle: String?,
        onDone: @escaping (ReadableStory) -> Void,
        onPaywall: @escaping (PaywallInfo) -> Void,
        onClose: @escaping () -> Void
    ) {
        _model = StateObject(wrappedValue: StoryGenerationModel(client: client, job: .nextPart(storyId: storyId, seriesTitle: seriesTitle)))
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
