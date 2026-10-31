import SwiftUI
import SkazochnikCore

/// "Создаём сказку": orbiting moon, the active step and the checklist of all five.
struct GenerateView: View {
    @ObservedObject var model: StoryGenerationModel
    let hero: HeroInfo
    let onPaywall: (PaywallInfo) -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            NightBackground(starCount: 70, seed: 31)
            switch model.phase {
            case .failed(let failure):
                FailureView(failure: failure, retry: model.retry, onPaywall: onPaywall, onClose: onClose)
            default:
                progress
            }
        }
        .task { model.start() }
        .preferredColorScheme(.dark)
    }

    private var progress: some View {
        VStack(spacing: 0) {
            Spacer()
            emblem.padding(.bottom, 44)
            Text("Создаём сказку").kicker().padding(.bottom, 14)
            Text("\(hero.name),\nтвоя сказка рождается").display(28).padding(.bottom, 30).frame(maxWidth: 300)
            Text(StoryGenerationModel.steps[min(model.currentStep, StoryGenerationModel.steps.count - 1)])
                .font(Theme.sans(17, weight: .medium))
                .foregroundStyle(Theme.text2)
                .id(model.currentStep)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .frame(minHeight: 24)
            Spacer()
            checklist.padding(.bottom, 32)
        }
        .padding(.horizontal, 26)
        .animation(.easeOut(duration: 0.4), value: model.currentStep)
        .accessibilityElement(children: .contain)
    }

    private var emblem: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ZStack {
                    Sparkle(size: 20).offset(y: -100)
                    Sparkle(size: 14, color: .white).offset(x: -76, y: 80)
                    Sparkle(size: 16).offset(x: 78, y: 72)
                }
                .rotationEffect(.degrees(t * 40))
                Circle()
                    .strokeBorder(Theme.accent.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
                    .frame(width: 150, height: 150)
                    .rotationEffect(.degrees(-t * 22))
                MoonIcon(size: 96).scaleEffect(1 + 0.03 * sin(t * 2.4))
            }
            .frame(width: 200, height: 200)
        }
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(StoryGenerationModel.steps.enumerated()), id: \.offset) { index, label in
                let done = index < model.currentStep
                let active = index == model.currentStep
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(done ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xD9CCFF), Theme.accent], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(Color.clear))
                        Circle().strokeBorder(done ? .clear : Theme.borderStrong, lineWidth: 1.5)
                        if done {
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Color(hex: 0x1A1330))
                        } else if active {
                            Circle().fill(Theme.gold).frame(width: 7, height: 7)
                        }
                    }
                    .frame(width: 22, height: 22)
                    Text(label).captionStyle().foregroundStyle(done || active ? Theme.text2 : Theme.text3)
                }
                .opacity(done || active ? 1 : 0.4)
                .accessibilityElement(children: .combine)
                .accessibilityValue(done ? "готово" : active ? "выполняется" : "ждёт")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Error states of generation: paywall, rejected draft, no network, server error.
private struct FailureView: View {
    let failure: StoryGenerationModel.Failure
    let retry: () -> Void
    let onPaywall: (PaywallInfo) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            MoonIcon(size: 72).padding(.bottom, 28)
            Text(title).display(28).padding(.bottom, 14)
            Text(message).bodyStyle().multilineTextAlignment(.center).frame(maxWidth: 300)
            Spacer()
            VStack(spacing: 6) {
                switch failure {
                case .paywall(let info):
                    Button("Открыть тарифы") { onPaywall(info) }.buttonStyle(.goldPill)
                    Button("Не сейчас", action: onClose).buttonStyle(.ghostPill)
                default:
                    Button("Попробовать ещё раз", action: retry).buttonStyle(.primaryPill)
                    Button("Назад", action: onClose).buttonStyle(.ghostPill)
                }
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 26)
    }

    private var title: String {
        switch failure {
        case .paywall(let info): info.code == .upgradeRequired ? "Это есть в подписке" : "Сказки на сегодня закончились"
        case .rejected: "Сказка не получилась"
        case .offline: "Нет связи"
        case .other: "Что-то пошло не так"
        }
    }

    private var message: String {
        switch failure {
        case .paywall(let info):
            info.code == .upgradeRequired
                ? "Сериалы на несколько вечеров доступны в подписке."
                : "Бесплатный лимит исчерпан. Новая сказка будет доступна позже, или откройте безлимит."
        case .rejected: "Мы проверяем каждую сказку и не показываем ту, что не подходит ребёнку. Попробуйте ещё раз."
        case .offline: "Проверьте интернет и попробуйте ещё раз."
        case .other(let text): text
        }
    }
}
