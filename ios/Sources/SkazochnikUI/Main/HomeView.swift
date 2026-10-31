import SwiftUI
import SkazochnikCore

/// «Сегодня»: greeting, continue-reading card, the create card and recent stories.
struct HomeView: View {
    @ObservedObject var app: AppModel
    let onOpen: (StorySummary) -> Void
    let onCreate: () -> Void
    let onAllStories: () -> Void

    var body: some View {
        let hero = app.hero(for: app.activeProfile)
        let resume = app.storyToContinue(for: app.activeProfile?.id)
        let recent = app.recentStories(for: app.activeProfile?.id, excluding: resume)

        AdaptiveScroll {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label(greeting, systemImage: "moon").font(Theme.sans(13.5)).foregroundStyle(Theme.text3).labelStyle(GoldIconLabelStyle())
                    Spacer()
                    KidSwitch(app: app)
                }
                .padding(.bottom, 22)

                Text("Что почитаем сегодня?").display(30, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 20)

                if app.isOffline { OfflineNote().padding(.bottom, 14) }

                if let resume { continueCard(resume).padding(.bottom, 14) }

                createCard(hero: hero).padding(.bottom, 28)

                if !recent.isEmpty {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Недавние").titleStyle(21)
                        Spacer()
                        Button("Все сказки", action: onAllStories)
                            .font(Theme.sans(14, weight: .medium))
                            .foregroundStyle(Theme.accent)
                            .buttonStyle(.plain)
                    }
                    .padding(.bottom, 14)

                    AdaptiveScroll(axis: .horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(recent) { story in
                                Button { onOpen(story) } label: { recentCard(story) }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .refreshable { await app.refresh() }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Доброе утро"
        case 12..<18: "Добрый день"
        default: "Добрый вечер"
        }
    }

    private func continueCard(_ story: StorySummary) -> some View {
        Button { onOpen(story) } label: {
            HStack(spacing: 14) {
                StoryThumb(story: story, hero: app.hero(for: story), coverURL: app.client.mediaURL(story.coverImageUrl ?? ""), height: 64, radius: 14)
                    .frame(width: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Продолжить").kicker().font(Theme.sans(11, weight: .semibold)).foregroundStyle(Theme.gold)
                    Text(story.title ?? "Сказка на ночь").font(Theme.serif(16.5)).foregroundStyle(Theme.text).lineLimit(2).multilineTextAlignment(.leading)
                    ProgressBar(value: story.readProgress).padding(.top, 4)
                }
                Spacer(minLength: 0)
                Image(systemName: "play.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: 0x1A1330))
                    .frame(width: 44, height: 44)
                    .background(Theme.accent, in: Circle())
            }
            .padding(14)
            .glassCard()
        }
        .buttonStyle(.plain)
    }

    private func createCard(hero: HeroInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            BookCover(hero: hero, kicker: "На сегодня", height: 210, heroSize: 86)
            Text("Сочинить новую историю на сегодня")
                .font(Theme.serif(21)).foregroundStyle(Theme.text).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16).padding(.horizontal, 10).padding(.bottom, 6)
            Text("Учтём любимые темы и то, что было в прошлых сказках.")
                .captionStyle().padding(.horizontal, 10).padding(.bottom, 16)
            Button(action: onCreate) { Label("Сочинить сказку", systemImage: "sparkles") }
                .buttonStyle(.primaryPill)
                .padding(.horizontal, 10).padding(.bottom, 8)
        }
        .padding(8)
        .glassCard()
    }

    private func recentCard(_ story: StorySummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            StoryThumb(story: story, hero: app.hero(for: story), coverURL: app.client.mediaURL(story.coverImageUrl ?? ""), height: 110)
            Text(story.title ?? "Сказка на ночь")
                .font(Theme.serif(15)).foregroundStyle(Theme.text).lineLimit(2).multilineTextAlignment(.leading)
                .padding(.top, 9).padding(.bottom, 4)
            Text("\(story.readingMinutes) мин · \(StoryDateLabel.label(for: story.createdAt))").captionStyle(12.5)
        }
        .frame(width: 150, alignment: .leading)
    }
}

struct GoldIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.gold)
            configuration.title
        }
    }
}

struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.text.opacity(0.12))
                Capsule()
                    .fill(LinearGradient(colors: [Theme.accent, Theme.gold], startPoint: .leading, endPoint: .trailing))
                    .frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 3)
        .accessibilityLabel("Прочитано \(Int(value * 100)) процентов")
    }
}

struct OfflineNote: View {
    var body: some View {
        Label("Нет связи — показаны сохранённые сказки", systemImage: "wifi.slash")
            .font(Theme.sans(12.5))
            .foregroundStyle(Theme.text3)
    }
}
