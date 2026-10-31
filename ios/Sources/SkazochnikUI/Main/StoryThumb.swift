import SwiftUI
import SkazochnikCore

/// Library card art: the generated cover when there is one, otherwise the world scene with the hero.
struct StoryThumb: View {
    let story: StorySummary
    let hero: HeroInfo
    let coverURL: URL?
    var height: CGFloat = 120
    var radius: CGFloat = 18

    var body: some View {
        // The scene is an overlay so that it never decides the size of the card, only the height does.
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay {
                ZStack(alignment: .bottom) {
                    WorldInfo.named(WorldID(rawValue: story.world ?? "") ?? .forest).gradient
                    StarField(count: 8, seed: 5, animated: false)
                    Ellipse().fill(.black.opacity(0.28)).frame(width: 150, height: 90).offset(x: -50, y: 56)
                    Ellipse().fill(.black.opacity(0.2)).frame(width: 150, height: 100).offset(x: 60, y: 62)
                    HeroAvatarView(appearance: hero.appearance, size: height * 0.46).padding(.bottom, 4)
                    if let coverURL {
                        AsyncImage(url: coverURL) { phase in
                            if let image = phase.image { image.resizable().scaledToFill() }
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.text.opacity(0.08)))
            .accessibilityHidden(true)
    }
}

/// Child picker pill in the header of "Сегодня".
struct KidSwitch: View {
    @ObservedObject var app: AppModel

    var body: some View {
        if let active = app.activeProfile {
            Menu {
                ForEach(app.profiles) { profile in
                    Button {
                        app.activeProfileId = profile.id
                    } label: {
                        if profile.id == active.id {
                            Label(profile.name, systemImage: "checkmark")
                        } else {
                            Text(profile.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Avatar(hero: app.hero(for: active), size: 34)
                    Text(active.name).font(Theme.sans(15, weight: .semibold)).foregroundStyle(Theme.text)
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.text3)
                }
                .padding(.leading, 4)
                .padding(.trailing, 12)
                .padding(.vertical, 4)
                .background(Theme.card, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.border))
            }
            .accessibilityLabel("Ребёнок: \(active.name)")
        }
    }
}

/// Round portrait of a hero.
struct Avatar: View {
    let hero: HeroInfo
    var size: CGFloat = 34

    var body: some View {
        HeroAvatarView(appearance: hero.appearance, size: size)
            .frame(width: size, height: size, alignment: .bottom)
            .background(Theme.accentSoft)
            .clipShape(Circle())
    }
}
