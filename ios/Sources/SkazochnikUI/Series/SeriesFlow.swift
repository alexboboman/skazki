import SwiftUI
import SkazochnikCore

/// One series: the list of its parts, reading a part and writing the next one.
struct SeriesFlow: View {
    private enum Stage: Equatable {
        case overview
        case generating
        case reading(ReadableStory)
        case paywall(PaywallInfo)
    }

    @ObservedObject var app: AppModel
    let storyId: String
    let onClose: () -> Void

    @State private var story: Story?
    @State private var stage: Stage = .overview
    @State private var loadFailed = false

    private var summary: StorySummary? { app.stories.first { $0.id == storyId } }
    private var profile: ChildProfile? { summary.flatMap(app.profile(for:)) ?? app.activeProfile }
    private var hero: HeroInfo { summary.map(app.hero(for:)) ?? app.hero(for: app.activeProfile) }

    var body: some View {
        Group {
            switch stage {
            case .overview:
                SeriesOverview(
                    story: story,
                    hero: hero,
                    mediaURL: app.client.mediaURL,
                    loadFailed: loadFailed,
                    onClose: onClose,
                    onRetry: { Task { await load() } },
                    onRead: read,
                    onNextPart: { stage = .generating }
                )
            case .generating:
                if let profile, let story {
                    GenerationHost(
                        client: app.client,
                        profile: profile,
                        nextPartOf: storyId,
                        seriesTitle: story.title,
                        onDone: partWritten,
                        onPaywall: { stage = .paywall($0) },
                        onClose: { stage = .overview }
                    )
                }
            case .reading(let readable):
                reader(readable)
            case .paywall(let info):
                // Purchasing arrives with StoreKit; both buttons just go back to the series for now.
                PaywallView(hero: hero, reason: info, onTrial: { stage = .overview }, onFree: { stage = .overview })
            }
        }
        .animation(.easeOut(duration: 0.35), value: stage)
        .task { await load() }
    }

    private func reader(_ readable: ReadableStory) -> some View {
        ReadingView(
            story: readable,
            hero: hero,
            mediaURL: app.client.mediaURL,
            onBack: { stage = .overview },
            onReachedEnd: {
                guard let part = readable.partNumber else { return }
                Task {
                    await app.markPartRead(id: storyId, part: part)
                    await load()
                }
            },
            favorite: summary?.favorite,
            onToggleFavorite: { if let summary { Task { await app.toggleFavorite(summary) } } },
            finale: finale(for: readable),
            premiumVoice: app.premiumVoice(for: readable)
        )
    }

    private func finale(for readable: ReadableStory) -> SeriesFinale? {
        guard let number = readable.partNumber, let count = readable.partCount else { return nil }
        if readable.isLastPart {
            return SeriesFinale(
                title: "Серия закончена",
                message: "Вы прошли весь путь до конца. Спокойной ночи!",
                buttonTitle: "К серии",
                action: { stage = .overview }
            )
        }
        return SeriesFinale(
            title: "Часть \(number) из \(count) прочитана",
            message: "Продолжение — в следующий вечер. Новую часть можно сочинить в любой момент.",
            buttonTitle: "К серии",
            action: { stage = .overview }
        )
    }

    private func read(part number: Int) {
        guard let story else { return }
        stage = .reading(ReadableStory(story: story, part: number))
    }

    private func partWritten(_ readable: ReadableStory) {
        Task {
            await app.storyCreated(readable)
            await load()
            stage = .reading(readable)
        }
    }

    private func load() async {
        do {
            story = try await app.series(id: storyId)
            loadFailed = false
        } catch {
            loadFailed = story == nil
        }
    }
}

/// The list of parts with a progress line and the one button that makes sense now.
struct SeriesOverview: View {
    let story: Story?
    let hero: HeroInfo
    let mediaURL: (String) -> URL?
    let loadFailed: Bool
    let onClose: () -> Void
    let onRetry: () -> Void
    let onRead: (Int) -> Void
    let onNextPart: () -> Void

    private var arc: StoryArcInfo? { story?.arc }
    private var firstUnread: StoryPart? { story?.parts.first { !$0.isRead } }

    var body: some View {
        ZStack(alignment: .bottom) {
            NightBackground(starCount: 30, seed: 52)

            AdaptiveScroll {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        CircleIconButton(systemName: "chevron.left", label: "Назад", action: onClose)
                        Spacer()
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 18)

                    if let story, let arc {
                        content(story, arc)
                    } else if loadFailed {
                        VStack(spacing: 14) {
                            Text("Не удалось открыть серию").titleStyle(22)
                            Text("Проверьте интернет и попробуйте ещё раз.").bodyStyle().multilineTextAlignment(.center)
                            Button("Повторить", action: onRetry).buttonStyle(.primaryPill)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                    } else {
                        ProgressView().tint(Theme.accent).frame(maxWidth: .infinity).padding(.top, 120)
                    }
                    Color.clear.frame(height: 150)
                }
                .padding(.horizontal, 26)
            }

            if let arc {
                callToAction(arc)
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private func content(_ story: Story, _ arc: StoryArcInfo) -> some View {
        BookCover(
            hero: hero,
            kicker: "Серия · \(arc.length) \(Self.partsWord(arc.length))",
            height: 220,
            heroSize: 100,
            imageURL: story.coverImageUrl.flatMap(mediaURL)
        )
        Text(story.title ?? "Сказка на ночь").titleStyle(27).padding(.top, 22)
        Text(progressLine(story, arc)).captionStyle().padding(.top, 6)
        progressDots(story, arc).padding(.top, 16)

        VStack(spacing: 10) {
            ForEach(story.parts, id: \.partNumber) { part in
                partRow(part)
            }
        }
        .padding(.top, 22)
    }

    private func progressLine(_ story: Story, _ arc: StoryArcInfo) -> String {
        let read = story.parts.filter(\.isRead).count
        if arc.isCompleted { return "Серия закончена · прочитано \(read) из \(arc.length)" }
        return "Написано \(arc.partsReady) из \(arc.length) · прочитано \(read)"
    }

    private func progressDots(_ story: Story, _ arc: StoryArcInfo) -> some View {
        HStack(spacing: 6) {
            ForEach(1...max(arc.length, 1), id: \.self) { number in
                let part = story.parts.first { $0.partNumber == number }
                Capsule()
                    .fill(part?.isRead == true ? Theme.accent : part != nil ? Theme.accent.opacity(0.45) : Theme.card2)
                    .frame(height: 6)
            }
        }
        .accessibilityHidden(true)
    }

    private func partRow(_ part: StoryPart) -> some View {
        Button { onRead(part.partNumber) } label: {
            HStack(spacing: 14) {
                Text("\(part.partNumber)")
                    .font(Theme.serif(17, weight: .semibold))
                    .foregroundStyle(part.isRead ? Color(hex: 0x1A1330) : Theme.text)
                    .frame(width: 38, height: 38)
                    .background(part.isRead ? Theme.accent : Theme.card2, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(part.title ?? "Часть \(part.partNumber)")
                        .font(Theme.sans(15.5, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(part.isRead ? "Прочитана" : "Новая").captionStyle(12.5)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text3)
            }
            .padding(14)
            .glassCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Часть \(part.partNumber). \(part.title ?? ""). \(part.isRead ? "Прочитана" : "Новая")")
    }

    @ViewBuilder private func callToAction(_ arc: StoryArcInfo) -> some View {
        VStack(spacing: 6) {
            if arc.isCompleted {
                Text("Серия закончена. Любую часть можно перечитать.").captionStyle().multilineTextAlignment(.center)
            } else if let unread = firstUnread {
                Button { onRead(unread.partNumber) } label: { Label("Читать часть \(unread.partNumber)", systemImage: "book") }
                    .buttonStyle(.primaryPill)
                Button("Сочинить часть \(arc.partsReady + 1) сейчас") { onNextPart() }.buttonStyle(.ghostPill)
            } else {
                Button { onNextPart() } label: { Label("Сочинить часть \(arc.partsReady + 1)", systemImage: "sparkles") }
                    .buttonStyle(.goldPill)
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [Theme.bg0.opacity(0), Theme.bg0], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.4)))
    }

    static func partsWord(_ n: Int) -> String {
        n % 10 == 1 && n % 100 != 11 ? "часть" : (2...4).contains(n % 10) && !(12...14).contains(n % 100) ? "части" : "частей"
    }
}
