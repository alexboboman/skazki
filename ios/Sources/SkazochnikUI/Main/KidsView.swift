import SwiftUI
import SkazochnikCore

/// «Дети»: one card per child with the shelf size, interests and world; add a child.
struct KidsView: View {
    @ObservedObject var app: AppModel
    let onAdd: () -> Void

    var body: some View {
        AdaptiveScroll {
            VStack(alignment: .leading, spacing: 0) {
                Text("Дети").display(30, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 6)
                Text("У каждого — свой герой, темы и полка сказок.").captionStyle().padding(.bottom, 22)

                VStack(spacing: 12) {
                    ForEach(app.profiles) { profile in card(profile) }
                    Button(action: onAdd) {
                        HStack(spacing: 10) {
                            Image(systemName: "plus").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.accent)
                            Text("Добавить ребёнка").font(Theme.sans(15.5, weight: .medium)).foregroundStyle(Theme.text2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                        .overlay(
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .strokeBorder(Theme.borderStrong, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
    }

    private func card(_ profile: ChildProfile) -> some View {
        let active = app.activeProfile?.id == profile.id
        let count = app.storyCount(for: profile)

        return Button { app.activeProfileId = profile.id } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    HeroAvatarView(appearance: profile.appearance ?? Appearance(), size: 64)
                        .frame(width: 72, height: 72, alignment: .bottom)
                        .background(LinearGradient(colors: [Color(hex: 0x2A1D52), Color(hex: 0x1C2752)], startPoint: .top, endPoint: .bottom))
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.name).font(Theme.serif(21)).foregroundStyle(Theme.text)
                        Text("\(profile.age) \(ageWord(profile.age)) · \(count) \(storiesWord(count))").captionStyle()
                    }
                    Spacer(minLength: 0)
                }
                if !profile.interests.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(profile.interests.prefix(4), id: \.self) { interest in
                            Text(interest)
                                .font(Theme.sans(12.5)).foregroundStyle(Theme.text2)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Theme.text.opacity(0.06), in: Capsule())
                        }
                        if let world = profile.worlds.first {
                            Text("· \(WorldInfo.named(world).name)").font(Theme.sans(12.5)).foregroundStyle(Theme.text3).padding(.vertical, 5)
                        }
                    }
                    .padding(.top, 14)
                }
                if active {
                    Text("Сейчас выбран").kicker().font(Theme.sans(10.5, weight: .semibold)).padding(.top, 14)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(active ? Theme.accent : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func storiesWord(_ n: Int) -> String {
        let m10 = n % 10
        let m100 = n % 100
        if m10 == 1 && m100 != 11 { return "сказка" }
        if (2...4).contains(m10) && !(12...14).contains(m100) { return "сказки" }
        return "сказок"
    }
}
