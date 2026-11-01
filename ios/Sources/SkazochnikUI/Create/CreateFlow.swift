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
    /// Opens the series screen of a story that was just started as a series.
    var onOpenSeries: (String) -> Void = { _ in }
    let onClose: () -> Void

    @State private var stage: Stage = .form

    private func seriesFinale(for story: ReadableStory) -> SeriesFinale? {
        guard let id = story.storyId, let number = story.partNumber, let count = story.partCount else { return nil }
        return SeriesFinale(
            title: "Часть \(number) из \(count) прочитана",
            message: "Продолжение — в следующий вечер. Новую часть можно сочинить на экране серии.",
            buttonTitle: "К серии",
            action: { onOpenSeries(id) }
        )
    }

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
                RevealView(
                    story: story,
                    hero: HeroInfo(profile: main),
                    kicker: story.isSeriesPart ? "Готово · новая серия" : "Готово · новая сказка",
                    coverURL: story.coverImagePath.flatMap(app.client.mediaURL),
                    coverKicker: story.partCount.map { "Серия · \($0) \(SeriesOverview.partsWord($0))" } ?? "Сказка на ночь"
                ) {
                    stage = .reading(story, main)
                }
            case .reading(let story, let main):
                ReadingView(
                    story: story,
                    hero: HeroInfo(profile: main),
                    mediaURL: app.client.mediaURL,
                    onBack: onClose,
                    onReachedEnd: {
                        guard let id = story.storyId else { return }
                        Task {
                            if let part = story.partNumber { await app.markPartRead(id: id, part: part) } else { await app.markRead(id: id) }
                        }
                    },
                    favorite: story.storyId.flatMap { id in app.stories.first { $0.id == id }?.favorite },
                    onToggleFavorite: {
                        if let id = story.storyId, let summary = app.stories.first(where: { $0.id == id }) {
                            Task { await app.toggleFavorite(summary) }
                        }
                    },
                    finale: seriesFinale(for: story),
                    premiumVoice: app.premiumVoice(for: story)
                )
            case .paywall(let info, let main):
                PaywallView(hero: HeroInfo(profile: main), reason: info, onPurchased: { stage = .form }, onFree: onClose)
            }
        }
        .animation(.easeOut(duration: 0.35), value: stage)
    }
}
