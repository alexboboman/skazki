import SwiftUI
import SkazochnikCore

/// The finished story as a book cover with the first lines as a teaser.
struct RevealView: View {
    let story: ReadableStory
    let hero: HeroInfo
    var kicker = "Готово · ваша первая сказка"
    var coverURL: URL?
    let onRead: () -> Void

    var body: some View {
        ZStack {
            NightBackground(starCount: 40, seed: 32)
            VStack(spacing: 0) {
                AdaptiveScroll {
                    VStack(spacing: 0) {
                        Text(kicker).kicker().foregroundStyle(Theme.gold).padding(.top, 8).padding(.bottom, 22)
                        BookCover(hero: hero, imageURL: coverURL)
                        Text(story.title).titleStyle(27).multilineTextAlignment(.center).padding(.top, 22).padding(.bottom, 14)
                        HStack(spacing: 8) {
                            meta("≈ \(story.readingMinutes) мин чтения")
                            meta("\(hero.age) \(ageWord(hero.age))")
                            if story.illustrationCount > 0 {
                                meta("\(story.illustrationCount) \(illustrations(story.illustrationCount))")
                            }
                        }
                        .padding(.bottom, 18)
                        if let first = story.paragraphs.first {
                            Text("«\(first)»")
                                .font(Theme.serif(17, weight: .regular).italic())
                                .foregroundStyle(Theme.text2)
                                .lineSpacing(5)
                                .multilineTextAlignment(.center)
                                .lineLimit(5)
                                .frame(maxWidth: 320)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                    Button { onRead() } label: {
                    Label("Читать сказку", systemImage: "sparkles")
                }
                .buttonStyle(.primaryPill)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 26)
        }
        .preferredColorScheme(.dark)
    }

    private func meta(_ text: String) -> some View {
        Text(text)
            .font(Theme.sans(12.5))
            .foregroundStyle(Theme.text2)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(Theme.card, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.border))
    }

    private func illustrations(_ n: Int) -> String {
        let m10 = n % 10
        let m100 = n % 100
        if m10 == 1 && m100 != 11 { return "иллюстрация" }
        if (2...4).contains(m10) && !(12...14).contains(m100) { return "иллюстрации" }
        return "иллюстраций"
    }
}
