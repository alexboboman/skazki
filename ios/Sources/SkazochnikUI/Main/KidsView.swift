import SwiftUI
import SkazochnikCore

/// «Дети»: one card per child with the shelf size, interests and world; add a child.
struct KidsView: View {
    @ObservedObject var app: AppModel
    let onAdd: () -> Void
    let onEdit: (ChildProfile) -> Void

    @State private var pendingDelete: ChildProfile?
    @State private var deleteFailed = false

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
        .confirmationDialog(
            "Удалить \(pendingDelete?.name ?? "")?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                guard let profile = pendingDelete else { return }
                Task { deleteFailed = !(await app.deleteProfile(profile)) }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Сказки останутся в библиотеке, но уже не будут привязаны к этому ребёнку.")
        }
        .alert("Не получилось удалить", isPresented: $deleteFailed) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text("Проверьте интернет и попробуйте ещё раз.")
        }
    }

    private func card(_ profile: ChildProfile) -> some View {
        let active = app.activeProfile?.id == profile.id
        let count = app.storyCount(for: profile)

        return             VStack(alignment: .leading, spacing: 0) {
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
                    Menu {
                        Button { onEdit(profile) } label: { Label("Редактировать", systemImage: "pencil") }
                        if app.canDeleteProfiles {
                            Button(role: .destructive) { pendingDelete = profile } label: { Label("Удалить", systemImage: "trash") }
                        }
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.text2)
                            .frame(width: 38, height: 38)
                            .background(Theme.card, in: Circle())
                            .overlay(Circle().strokeBorder(Theme.border))
                    }
                    .accessibilityLabel("Действия: \(profile.name)")
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
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onTapGesture { app.activeProfileId = profile.id }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
    }

    private func storiesWord(_ n: Int) -> String {
        let m10 = n % 10
        let m100 = n % 100
        if m10 == 1 && m100 != 11 { return "сказка" }
        if (2...4).contains(m10) && !(12...14).contains(m100) { return "сказки" }
        return "сказок"
    }
}
