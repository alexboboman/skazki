import SwiftUI
import SkazochnikCore

/// «Сочинить»: who the story is for, topic, world and length. Audio mode and voice from the design are
/// left out: narration lives in the reader.
struct CreateView: View {
    @ObservedObject var app: AppModel
    @State private var draft: CreateDraft
    let onClose: () -> Void
    let onCreate: (CreateDraft) -> Void

    init(
        app: AppModel,
        profile: ChildProfile,
        initialDraft: (inout CreateDraft) -> Void = { _ in },
        onClose: @escaping () -> Void,
        onCreate: @escaping (CreateDraft) -> Void
    ) {
        self.app = app
        var draft = CreateDraft(activeProfile: profile)
        initialDraft(&draft)
        _draft = State(initialValue: draft)
        self.onClose = onClose
        self.onCreate = onCreate
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            NightBackground(starCount: 30, seed: 74)

            AdaptiveScroll {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    Text("О чём будет сказка сегодня?")
                        .display(29, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    section("Для кого") { kids }
                    section("Формат") { format }
                    section("Тема") { topic }
                    section("Мир") { worlds }
                    section("Длина") {
                        PillSegments(
                            options: CreateDraft.lengths.map { ($0.minutes, $0.title) },
                            selection: $draft.lengthMinutes
                        )
                    }
                    Color.clear.frame(height: 110)
                }
                .padding(.horizontal, 26)
            }

            Button { onCreate(draft) } label: { Label(draft.isSeries ? "Начать серию" : "Сочинить сказку", systemImage: "sparkles") }
                .buttonStyle(.goldPill)
                .padding(.horizontal, 26)
                .padding(.top, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
                .background(LinearGradient(colors: [Theme.bg0.opacity(0), Theme.bg0], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.4)))
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack {
            CircleIconButton(systemName: "xmark", label: "Закрыть", action: onClose)
            Spacer()
            Text("Новая сказка").captionStyle()
            Spacer()
            Color.clear.frame(width: 42, height: 42)
        }
        .padding(.top, 8)
        .padding(.bottom, 18)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).kicker().font(Theme.sans(11.5, weight: .semibold)).foregroundStyle(Theme.text3)
            content()
        }
        .padding(.top, 26)
    }

    private var kids: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ForEach(app.profiles) { profile in
                    let on = draft.isSelected(profile)
                    Button { draft.toggle(profile, in: app.profiles) } label: {
                        VStack(spacing: 7) {
                            Avatar(hero: app.hero(for: profile), size: 64)
                                .overlay(Circle().strokeBorder(on ? Theme.accent : Theme.border, lineWidth: on ? 2 : 1))
                            Text(profile.name)
                                .font(Theme.sans(13.5, weight: .medium))
                                .foregroundStyle(on ? Theme.text : Theme.text3)
                                .lineLimit(1)
                        }
                        .frame(width: 72)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(profile.name)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            if draft.heroIds.count > 1 {
                Text("\(draft.names(in: app.profiles)) будут героями вместе.").captionStyle()
            }
        }
    }

    private var format: some View {
        VStack(alignment: .leading, spacing: 12) {
            PillSegments(
                options: [(0, "Одна сказка"), (CreateDraft.arcLengths[0], "Серия")],
                selection: Binding(
                    get: { draft.isSeries ? CreateDraft.arcLengths[0] : 0 },
                    set: { draft.formatChoice = $0 }
                )
            )
            if draft.isSeries {
                HStack(spacing: 8) {
                    ForEach(CreateDraft.arcLengths, id: \.self) { count in
                        Chip("\(count) \(SeriesOverview.partsWord(count))", selected: draft.arcLength == count) { draft.arcLength = count }
                    }
                }
                Text("Одна часть на вечер. Первую напишем сейчас, каждую следующую — когда захотите продолжить.").captionStyle().fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var topic: some View {
        VStack(alignment: .leading, spacing: 12) {
            FlowLayout(spacing: 8) {
                ForEach(CreateDraft.topics, id: \.self) { title in
                    Chip(title, selected: draft.topic == title && !draft.hasNote) {
                        draft.topic = title
                        draft.note = ""
                    }
                }
            }
            TextField("", text: $draft.note, prompt: Text("Или своими словами…").foregroundStyle(Theme.text3), axis: .vertical)
                .lineLimit(2...4)
                .font(Theme.sans(15))
                .foregroundStyle(Theme.text)
                .tint(Theme.accent)
                .padding(.horizontal, 15)
                .padding(.vertical, 13)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.border))
        }
    }

    private var worlds: some View {
        AdaptiveScroll(axis: .horizontal) {
            HStack(spacing: 10) {
                ForEach(WorldInfo.all) { world in
                    let selected = draft.world == world.id
                    Button { draft.pickWorld(world.id) } label: {
                        WorldTile(world: world, selected: selected, height: 84, compact: true)
                            .frame(width: 118)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(world.name)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
    }
}
