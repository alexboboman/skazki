import SwiftUI
import SkazochnikCore

/// Reading mode: serif text, illustrations between paragraphs, the moral and a closing line.
public struct ReadingView: View {
    let story: ReadableStory
    let hero: HeroInfo
    let mediaURL: (String) -> URL?
    let onBack: () -> Void
    /// Called once when the reader reaches the closing line (marks the story as read).
    var onReachedEnd: () -> Void = {}
    /// Shows a gentle upsell card under the story (onboarding path only).
    var onUpsell: (() -> Void)?
    /// Heart in the top bar; nil hides it (stories that are not in the library yet).
    var favorite: Bool?
    var onToggleFavorite: () -> Void = {}

    @AppStorage("readingFontStep") private var fontStep = 1
    @State private var reachedEnd = false

    static let fontSizes: [CGFloat] = [17, 19, 22, 26]

    public init(
        story: ReadableStory,
        hero: HeroInfo,
        mediaURL: @escaping (String) -> URL?,
        onBack: @escaping () -> Void,
        onReachedEnd: @escaping () -> Void = {},
        onUpsell: (() -> Void)? = nil,
        favorite: Bool? = nil,
        onToggleFavorite: @escaping () -> Void = {}
    ) {
        self.story = story
        self.hero = hero
        self.mediaURL = mediaURL
        self.onBack = onBack
        self.onReachedEnd = onReachedEnd
        self.onUpsell = onUpsell
        self.favorite = favorite
        self.onToggleFavorite = onToggleFavorite
    }

    private var bodySize: CGFloat { Self.fontSizes[min(max(fontStep, 0), Self.fontSizes.count - 1)] }

    public var body: some View {
        ZStack(alignment: .top) {
            NightBackground(starCount: 24, seed: 41)
            AdaptiveScroll {
                VStack(spacing: 0) {
                    Text(story.title).titleStyle(30).multilineTextAlignment(.center).padding(.top, 74).padding(.bottom, 6)
                    Text("\(hero.name) · сказка на ночь").captionStyle().padding(.bottom, 22)

                    ForEach(story.blocks) { block in
                        switch block {
                        case .paragraph(_, let text):
                            Text(text)
                                .font(Theme.serif(bodySize, weight: .regular))
                                .foregroundStyle(Theme.text)
                                .lineSpacing(bodySize * 0.72 - 4)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.bottom, 18)
                        case .illustration(let asset):
                            StoryIllustration(url: mediaURL(asset.url), hero: hero)
                                .padding(.vertical, 6)
                                .padding(.bottom, 4)
                        }
                    }

                    if let moral = story.moral {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Мораль сказки").kicker().foregroundStyle(Theme.gold)
                            Text(moral)
                                .font(Theme.serif(bodySize, weight: .regular).italic())
                                .foregroundStyle(Theme.text)
                                .lineSpacing(bodySize * 0.72 - 4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 20)
                        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
                        .padding(.vertical, 22)
                    }

                    if let closing = story.closing {
                        Text(closing)
                            .font(Theme.serif(17, weight: .regular).italic())
                            .foregroundStyle(Theme.accent)
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 28)
                            .onAppear {
                                guard !reachedEnd else { return }
                                reachedEnd = true
                                onReachedEnd()
                            }
                    } else {
                        Color.clear.frame(height: 1).onAppear {
                            guard !reachedEnd else { return }
                            reachedEnd = true
                            onReachedEnd()
                        }
                    }

                    if let onUpsell {
                        upsell(onUpsell)
                    }
                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, 26)
            }

            topBar
        }
        .preferredColorScheme(.dark)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            CircleIconButton(systemName: "chevron.left", label: "Назад", action: onBack)
            Text("Режим чтения · ночник")
                .font(Theme.sans(13.5))
                .foregroundStyle(Theme.text2)
                .frame(maxWidth: .infinity)
            if let favorite {
                Button(action: onToggleFavorite) {
                    Image(systemName: favorite ? "heart.fill" : "heart")
                        .font(.system(size: 16))
                        .foregroundStyle(favorite ? Theme.gold : Theme.text2)
                        .frame(width: 42, height: 42)
                        .background(Theme.card, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.border))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(favorite ? "Убрать из любимых" : "В любимые")
            }
            Button {
                fontStep = (fontStep + 1) % Self.fontSizes.count
            } label: {
                Text("Аа")
                    .font(Theme.serif(16, weight: .semibold))
                    .foregroundStyle(Theme.text2)
                    .frame(width: 42, height: 42)
                    .background(Theme.card, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.border))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Размер текста")
        }
        .padding(.horizontal, 26)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .background(
            LinearGradient(stops: [.init(color: Theme.bg1, location: 0), .init(color: Theme.bg1, location: 0.7), .init(color: Theme.bg1.opacity(0), location: 1)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
        )
    }

    private func upsell(_ action: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Sparkle(size: 26)
            Text("Понравилось?").titleStyle(21)
            Text("Создавайте новую сказку каждый вечер — без ограничений.").bodyStyle().multilineTextAlignment(.center).padding(.bottom, 10)
            Button("Попробовать 7 дней бесплатно", action: action).buttonStyle(.goldPill)
        }
        .padding(22)
        .glassCard()
    }
}

/// Generated picture; while it loads or when it cannot be shown (the dev mock returns SVG) the
/// night scene with the hero stands in.
struct StoryIllustration: View {
    let url: URL?
    let hero: HeroInfo

    var body: some View {
        ZStack {
            fallback
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    }
                }
            }
        }
        .frame(height: 190)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.border))
        .accessibilityLabel("Иллюстрация к сказке")
    }

    private var fallback: some View {
        ZStack(alignment: .bottom) {
            NightLandscape(moonSize: 40)
            HeroAvatarView(appearance: hero.appearance, size: 92).padding(.bottom, 8)
        }
    }
}
