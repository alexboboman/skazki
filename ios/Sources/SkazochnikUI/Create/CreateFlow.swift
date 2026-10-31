import SwiftUI
import SkazochnikCore

/// «Сочинить» from the main app: the form, then generation, cover and reading of the new story.
struct CreateFlow: View {
    private enum Stage: Equatable {
        case form
        case generating(GenerateStoryRequest, ChildProfile)
        case reveal(ReadableStory, ChildProfile)
        case reading(ReadableStory, ChildProfile)
        case paywall(PaywallInfo, ChildProfile)
    }

    @ObservedObject var app: AppModel
    let profile: ChildProfile
    let onClose: () -> Void

    @State private var stage: Stage = .form

    var body: some View {
        Group {
            switch stage {
            case .form:
                CreateView(app: app, profile: profile, onClose: onClose) { draft in
                    // The main hero stands on the cover and in the reader; HD is requested and the server
                    // lowers it to standard on plans without HD.
                    let main = app.profiles.first { $0.id == draft.heroIds[0] } ?? profile
                    stage = .generating(draft.request(imageQuality: .hd), main)
                }
            case .generating(let request, let main):
                GenerationHost(
                    client: app.client,
                    profile: main,
                    request: request,
                    onDone: { story in
                        Task { await app.storyCreated(story) }
                        stage = .reveal(story, main)
                    },
                    onPaywall: { stage = .paywall($0, main) },
                    onClose: { stage = .form }
                )
            case .reveal(let story, let main):
                RevealView(story: story, hero: HeroInfo(profile: main), kicker: "Готово · новая сказка", coverURL: story.coverImagePath.flatMap(app.client.mediaURL)) {
                    stage = .reading(story, main)
                }
            case .reading(let story, let main):
                ReadingView(
                    story: story,
                    hero: HeroInfo(profile: main),
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
            case .paywall(let info, let main):
                // Purchasing arrives with StoreKit; both buttons just go back to the form for now.
                PaywallView(hero: HeroInfo(profile: main), reason: info, onTrial: { stage = .form }, onFree: onClose)
            }
        }
        .animation(.easeOut(duration: 0.35), value: stage)
    }
}
