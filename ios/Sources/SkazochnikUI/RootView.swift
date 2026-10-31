import SwiftUI
import SkazochnikCore

/// App root. Onboarding ends with the first story (generate, cover, read, paywall, done);
/// after that the main app takes over (built next, a placeholder for now).
public struct RootView: View {
    enum Stage: Equatable {
        case onboarding
        case generating(ChildProfile)
        case reveal(ChildProfile, ReadableStory)
        case reading(ChildProfile, ReadableStory)
        case paywall(ChildProfile, PaywallInfo?)
        case done(ChildProfile, trial: Bool)
    }

    private let client: APIClient
    @AppStorage("onboardingFinished") private var onboardingFinished = false
    @AppStorage("heroName") private var heroName = ""
    @State private var stage: Stage = .onboarding

    public init(client: APIClient) {
        self.client = client
    }

    public var body: some View {
        Group {
            if onboardingFinished {
                HomePlaceholder(heroName: heroName) {
                    onboardingFinished = false
                    heroName = ""
                    stage = .onboarding
                    client.signOut()
                }
            } else {
                flow
            }
        }
        .animation(.easeOut(duration: 0.35), value: stage)
    }

    @ViewBuilder private var flow: some View {
        switch stage {
        case .onboarding:
            OnboardingFlow(client: client) { profile in
                heroName = profile.name
                stage = .generating(profile)
            }
        case .generating(let profile):
            GenerationHost(client: client, profile: profile) { story in
                stage = .reveal(profile, story)
            } onPaywall: { info in
                stage = .paywall(profile, info)
            } onClose: {
                stage = .done(profile, trial: false)
            }
        case .reveal(let profile, let story):
            RevealView(story: story, hero: HeroInfo(profile: profile)) {
                stage = .reading(profile, story)
            }
        case .reading(let profile, let story):
            ReadingView(
                story: story,
                hero: HeroInfo(profile: profile),
                mediaURL: client.mediaURL,
                onBack: { stage = .reveal(profile, story) },
                onReachedEnd: { markRead(story) },
                onUpsell: { stage = .paywall(profile, nil) }
            )
        case .paywall(let profile, let reason):
            // Purchasing arrives with StoreKit; both buttons just continue for now.
            PaywallView(hero: HeroInfo(profile: profile), reason: reason) {
                stage = .done(profile, trial: true)
            } onFree: {
                stage = .done(profile, trial: false)
            }
        case .done(let profile, let trial):
            DoneView(hero: HeroInfo(profile: profile), trial: trial) {
                onboardingFinished = true
            }
        }
    }

    private func markRead(_ story: ReadableStory) {
        guard let id = story.storyId else { return }
        Task { _ = try? await client.updateStory(id: id, readProgress: 1) }
    }
}

/// Owns the generation model for the first story (4 minutes, with illustrations).
private struct GenerationHost: View {
    @StateObject private var model: StoryGenerationModel
    let hero: HeroInfo
    let onDone: (ReadableStory) -> Void
    let onPaywall: (PaywallInfo) -> Void
    let onClose: () -> Void

    init(
        client: APIClient,
        profile: ChildProfile,
        onDone: @escaping (ReadableStory) -> Void,
        onPaywall: @escaping (PaywallInfo) -> Void,
        onClose: @escaping () -> Void
    ) {
        _model = StateObject(wrappedValue: StoryGenerationModel(
            client: client,
            request: GenerateStoryRequest(profileIds: [profile.id], format: .quickStory, lengthMinutes: 4)
        ))
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

/// Stands in for the "Сегодня" tab until the main screens are built.
struct HomePlaceholder: View {
    let heroName: String
    let onRestart: () -> Void

    var body: some View {
        ZStack {
            NightBackground(starCount: 50, seed: 11)
            VStack(spacing: 0) {
                Spacer()
                MoonIcon(size: 90).padding(.bottom, 28)
                Text("Профиль создан").kicker().padding(.bottom, 14)
                Text("\(heroName.isEmpty ? "Малыш" : heroName) ждёт сказку").display(32).padding(.bottom, 16)
                Text("Экран «Сегодня» и создание сказок — следующий шаг.").bodyStyle().multilineTextAlignment(.center).frame(maxWidth: 290)
                Spacer()
                Button("Пройти онбординг заново", action: onRestart).buttonStyle(.ghostPill).padding(.bottom, 24)
            }
            .padding(.horizontal, 26)
        }
        .preferredColorScheme(.dark)
    }
}
