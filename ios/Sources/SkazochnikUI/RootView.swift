import SwiftUI
import SkazochnikCore

/// App root. Onboarding ends with the first story (generate, cover, read, paywall, done);
/// after that the main app (tabs, library, children) takes over.
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
    private let cache: LibraryCache
    @AppStorage("onboardingFinished") private var onboardingFinished = false
    @State private var stage: Stage = .onboarding

    public init(client: APIClient, cache: LibraryCache = FileLibraryCache()) {
        self.client = client
        self.cache = cache
    }

    public var body: some View {
        Group {
            if onboardingFinished {
                MainView(client: client, cache: cache) {
                    stage = .onboarding
                    onboardingFinished = false
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
                stage = .generating(profile)
            }
        case .generating(let profile):
            GenerationHost(
                client: client,
                profile: profile,
                request: GenerateStoryRequest(profileIds: [profile.id], format: .quickStory, lengthMinutes: 4),
                onDone: { story in stage = .reveal(profile, story) },
                onPaywall: { info in stage = .paywall(profile, info) },
                onClose: { stage = .done(profile, trial: false) }
            )
        case .reveal(let profile, let story):
            RevealView(story: story, hero: HeroInfo(profile: profile), coverURL: story.coverImagePath.flatMap(client.mediaURL)) {
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
