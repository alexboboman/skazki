import SwiftUI
import SkazochnikCore

/// Header with back button and progress, scrolling body and a pinned footer button.
private struct ProfileShell<Content: View, Footer: View>: View {
    let step: Int
    var scrolls = true
    let onBack: () -> Void
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                CircleIconButton(systemName: "chevron.left", label: "Назад", action: onBack)
                ProgressSegments(step: step, total: OnboardingStep.profileSteps)
            }
            .padding(.top, 8)
            .padding(.bottom, 22)

            if scrolls {
                AdaptiveScroll {
                    content()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                content().frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            footer().padding(.top, 14).padding(.bottom, 24)
        }
        .padding(.horizontal, 26)
    }
}

private struct StepHead: View {
    let kicker: String
    let title: String
    var sub: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(kicker).kicker().padding(.bottom, 12)
            Text(title).titleStyle(28)
            if let sub {
                Text(sub).bodyStyle().padding(.top, 10)
            }
        }
        .padding(.bottom, 26)
    }
}

// MARK: 1. Name

struct NameStepView: View {
    @ObservedObject var model: OnboardingModel
    @FocusState private var focused: Bool

    var body: some View {
        ProfileShell(step: 0, scrolls: false, onBack: model.back) {
            VStack(spacing: 0) {
                Spacer()
                Text("Профиль ребёнка").kicker().padding(.bottom, 14)
                Text("Как зовут\nвашего малыша?").display(32).padding(.bottom, 40)
                TextField("", text: $model.draft.name, prompt: Text("Имя").foregroundStyle(Theme.text3))
                    .font(Theme.serif(30))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .tint(Theme.accent)
                    .focused($focused)
                    .submitLabel(.continue)
                    .onSubmit { if !model.draft.trimmedName.isEmpty { model.next() } }
                    .onChange(of: model.draft.name) { _, name in
                        if name.count > 18 { model.draft.name = String(name.prefix(18)) }
                    }
                    #if os(iOS)
                    .textInputAutocapitalization(.words)
                    #endif
                    .padding(.bottom, 12)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(focused ? Theme.accent : Theme.borderStrong).frame(height: 2)
                    }
                Text("Имя будет звучать в каждой сказке").captionStyle().padding(.top, 18)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } footer: {
            Button("Продолжить") { model.next() }
                .buttonStyle(.primaryPill)
                .disabled(model.draft.trimmedName.isEmpty)
        }
        .task {
            try? await Task.sleep(nanoseconds: 360_000_000)
            focused = true
        }
    }
}

// MARK: 2. Age

struct AgeStepView: View {
    @ObservedObject var model: OnboardingModel
    private let ages = Array(2...12)

    var body: some View {
        let name = model.draft.trimmedName.isEmpty ? "малыш" : model.draft.trimmedName

        ProfileShell(step: 1, onBack: model.back) {
            VStack(alignment: .leading, spacing: 0) {
                StepHead(kicker: "Профиль ребёнка", title: "Сколько лет — \(name)?", sub: "Подберём длину и сложность сказки под возраст.")

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(model.draft.age)").font(Theme.serif(78)).foregroundStyle(Theme.text)
                    Text(ageWord(model.draft.age)).font(Theme.serif(24)).foregroundStyle(Theme.gold)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
                .padding(.bottom, 30)
                .accessibilityElement(children: .combine)

                AdaptiveScroll(axis: .horizontal) {
                    HStack(spacing: 12) {
                        ForEach(ages, id: \.self) { age in
                            let selected = model.draft.age == age
                            Button {
                                withAnimation(.easeOut(duration: 0.22)) { model.draft.age = age }
                            } label: {
                                Text("\(age)")
                                    .font(Theme.serif(selected ? 30 : 23))
                                    .foregroundStyle(selected ? Color(hex: 0x1A1330) : Theme.text2)
                                    .frame(width: selected ? 72 : 58, height: selected ? 72 : 58)
                                    .background(
                                        selected
                                            ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xD9CCFF), Theme.accent], startPoint: .topLeading, endPoint: .bottomTrailing))
                                            : AnyShapeStyle(Theme.card),
                                        in: Circle()
                                    )
                                    .overlay(Circle().strokeBorder(selected ? .clear : Theme.border))
                                    .shadow(color: selected ? Theme.accent.opacity(0.5) : .clear, radius: 12, y: 8)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(age) \(ageWord(age))")
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 10)
                }
            }
        } footer: {
            Button("Продолжить") { model.next() }.buttonStyle(.primaryPill)
        }
    }
}

// MARK: 3. Appearance

struct AppearanceStepView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        let name = model.draft.trimmedName.isEmpty ? "герой" : model.draft.trimmedName

        ProfileShell(step: 2, onBack: model.back) {
            VStack(alignment: .leading, spacing: 0) {
                StepHead(kicker: "Внешность героя", title: "Сделаем героя похожим", sub: "Соберём портрет — и \(name) станет звездой собственных сказок.")

                HeroAvatarView(appearance: model.draft.appearance, size: 150)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                    .glassCard()
                    .padding(.bottom, 26)

                group("Кто наш герой?") {
                    HStack(spacing: 9) {
                        option("Мальчик", selected: model.draft.gender == .boy) { model.draft.gender = .boy }
                        option("Девочка", selected: model.draft.gender == .girl) { model.draft.gender = .girl }
                        option("Не указывать", selected: model.draft.gender == nil) { model.draft.gender = nil }
                    }
                }

                group("Оттенок кожи") {
                    swatches(Palette.skin, selected: model.draft.appearance.skin, ring: true) { model.draft.appearance.skin = $0 }
                }

                group("Цвет волос") {
                    swatches(Palette.hair, selected: model.draft.appearance.hair, ring: true) { model.draft.appearance.hair = $0 }
                }

                group("Длина волос") {
                    HStack(spacing: 9) {
                        option("Короткие", selected: model.draft.appearance.hairStyle == .short) { model.draft.appearance.hairStyle = .short }
                        option("Длинные", selected: model.draft.appearance.hairStyle == .long) { model.draft.appearance.hairStyle = .long }
                    }
                }

                group("Цвет одежды") {
                    swatches(Palette.outfit, selected: model.draft.appearance.outfit, ring: false) { model.draft.appearance.outfit = $0 }
                }
            }
        } footer: {
            Button("Продолжить") { model.next() }.buttonStyle(.primaryPill)
        }
    }

    private func group<Body: View>(_ title: String, @ViewBuilder body: () -> Body) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(Theme.sans(13.5, weight: .medium)).foregroundStyle(Theme.text2)
            body()
        }
        .padding(.bottom, 24)
    }

    private func option(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.sans(14.5, weight: .medium))
                .foregroundStyle(selected ? Theme.text : Theme.text2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .tileSurface(selected: selected, radius: 14)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func swatches(_ colors: [UInt32], selected: Int, ring: Bool, pick: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 14) {
            ForEach(colors.indices, id: \.self) { index in
                Button { pick(index) } label: {
                    Circle()
                        .fill(Color(hex: colors[index]))
                        .frame(width: 38, height: 38)
                        .overlay(Circle().strokeBorder(ring ? Theme.text.opacity(0.25) : .clear))
                        .padding(4)
                        .overlay(Circle().strokeBorder(selected == index ? Theme.accent : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Вариант \(index + 1)")
                .accessibilityAddTraits(selected == index ? .isSelected : [])
            }
        }
    }
}

// MARK: 4. Interests

struct InterestsStepView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        let name = model.draft.trimmedName.isEmpty ? "малыш" : model.draft.trimmedName
        let count = model.draft.interests.count

        ProfileShell(step: 3, onBack: model.back) {
            VStack(alignment: .leading, spacing: 0) {
                StepHead(kicker: "Увлечения", title: "Что любит \(name)?", sub: "Эти темы будут вплетаться в сюжеты сказок.")
                FlowLayout(spacing: 11) {
                    ForEach(Interests.all, id: \.self) { interest in
                        Chip(interest, selected: model.draft.interests.contains(interest)) {
                            model.toggleInterest(interest)
                        }
                    }
                }
            }
        } footer: {
            Button(count == 0 ? "Выберите хотя бы одно" : "Продолжить") { model.next() }
                .buttonStyle(.primaryPill)
                .disabled(count == 0)
        }
    }
}

/// Wraps its children onto new lines, like flex-wrap.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(in: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(in: bounds.width, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(in width: CGFloat, subviews: Subviews) -> (origins: [CGPoint], size: CGSize) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return (origins, CGSize(width: maxX, height: y + rowHeight))
    }
}

// MARK: 5. World

struct WorldStepView: View {
    @ObservedObject var model: OnboardingModel
    private let columns = [GridItem(.flexible(), spacing: 13), GridItem(.flexible(), spacing: 13)]

    var body: some View {
        ProfileShell(step: 4, onBack: model.back) {
            VStack(alignment: .leading, spacing: 0) {
                StepHead(kicker: "Любимый мир", title: "Где начнётся история?", sub: "Выберите мир — в нём будут происходить приключения.")
                LazyVGrid(columns: columns, spacing: 13) {
                    ForEach(WorldInfo.all) { world in
                        let selected = model.draft.world == world.id
                        Button { model.draft.world = world.id } label: {
                            WorldTile(world: world, selected: selected)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(world.name)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                if let message = model.errorMessage {
                    Text(message).captionStyle().foregroundStyle(Theme.gold).padding(.top, 16)
                }
            }
        } footer: {
            Button {
                Task { await model.finish() }
            } label: {
                if model.isSaving { ProgressView().tint(Color(hex: 0x1A1330)) } else { Text(model.isEditing ? "Сохранить" : "Создать первую сказку") }
            }
            .buttonStyle(.primaryPill)
            .disabled(model.isSaving)
        }
    }
}

/// World card with a small night landscape behind the name.
struct WorldTile: View {
    let world: WorldInfo
    var selected = false
    var height: CGFloat = 116
    /// Smaller card for the horizontal picker of «Сочинить»: 14 pt name, no checkmark.
    var compact = false

    var body: some View {
        // The scene is an overlay so that only `height` decides the size of the tile.
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay { scene }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(selected ? Theme.accent : Theme.border, lineWidth: selected ? 2 : 1)
        )
    }

    private var scene: some View {
        ZStack(alignment: .bottomLeading) {
            // Decoration sits in an overlay: shapes bigger than the tile must not change its layout.
            world.gradient.overlay {
                ZStack {
                    StarField(count: 10, seed: 3, animated: false)
                    Ellipse().fill(.black.opacity(0.28)).frame(width: 110, height: 100).offset(x: -40, y: 70)
                    Ellipse().fill(.black.opacity(0.2)).frame(width: 110, height: 110).offset(x: 70, y: 75)
                }
            }
            MoonIcon(size: 24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(12)
            Text(world.name)
                .font(Theme.serif(compact ? 14 : 16.5))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, compact ? 11 : 14)
                .padding(.bottom, compact ? 10 : 13)
            if selected && !compact {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(hex: 0x1A1330))
                    .frame(width: 24, height: 24)
                    .background(Theme.accent, in: Circle())
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}
