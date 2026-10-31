import SwiftUI
import SkazochnikCore

struct WelcomeView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                MoonIcon(size: 118)
                Sparkle(size: 20).offset(x: -70, y: -50)
                Sparkle(size: 13, color: .white).offset(x: 62, y: 52)
            }
            .padding(.bottom, 30)
            Text("Сказки на ночь").kicker().padding(.bottom, 16)
            Text("Сказочник").display(46).padding(.bottom, 18)
            Text("Каждый вечер — новая добрая история, где главный герой похож на вашего ребёнка.")
                .bodyStyle(17.5)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 290)
            Spacer()
            VStack(spacing: 6) {
                Button("Начать") { model.next() }
                    .buttonStyle(.primaryPill)
                // Signing in with Apple is wired up with the account screen; for now it starts onboarding too.
                Button {
                    model.next()
                } label: {
                    Label("Уже есть аккаунт? Войти с Apple", systemImage: "apple.logo")
                }
                .buttonStyle(.ghostPill)
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 26)
    }
}

private struct ValueSlide {
    let kicker: String
    let title: String
    let body: String
    let scene: Scene

    enum Scene { case hero, safe, library }

    static let all = [
        ValueSlide(
            kicker: "Персонализация",
            title: "Герой сказки — ваш ребёнок",
            body: "Имя, внешность и любимые увлечения малыша оживают в каждой истории.",
            scene: .hero
        ),
        ValueSlide(
            kicker: "Спокойствие",
            title: "Мягко и безопасно",
            body: "Только добрые сюжеты — без страшного и тревожного. Тёплый ритуал перед сном.",
            scene: .safe
        ),
        ValueSlide(
            kicker: "Ваша библиотека",
            title: "Истории остаются с вами",
            body: "Сказки с иллюстрациями сохраняются и доступны для чтения даже без интернета.",
            scene: .library
        ),
    ]
}

struct ValueView: View {
    @ObservedObject var model: OnboardingModel
    @State private var index = 0
    private let slides = ValueSlide.all

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                CircleIconButton(systemName: "chevron.left", label: "Назад") { model.back() }
                Spacer()
            }
            .padding(.top, 8)

            TabView(selection: $index) {
                ForEach(slides.indices, id: \.self) { i in
                    VStack(spacing: 0) {
                        Spacer()
                        scene(slides[i].scene).frame(height: 260)
                        Text(slides[i].kicker).kicker().padding(.top, 26).padding(.bottom, 12)
                        Text(slides[i].title).display(30).padding(.bottom, 14)
                        Text(slides[i].body).bodyStyle().multilineTextAlignment(.center).frame(maxWidth: 310)
                        Spacer()
                    }
                    .tag(i)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif

            HStack(spacing: 8) {
                ForEach(slides.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == index ? Theme.accent : Theme.text.opacity(0.25))
                        .frame(width: i == index ? 22 : 7, height: 7)
                }
            }
            .animation(.easeOut(duration: 0.3), value: index)
            .padding(.bottom, 22)

            Button(index == slides.count - 1 ? "Создать профиль" : "Дальше") {
                if index == slides.count - 1 {
                    model.next()
                } else {
                    withAnimation { index += 1 }
                }
            }
            .buttonStyle(.primaryPill)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 26)
    }

    @ViewBuilder private func scene(_ scene: ValueSlide.Scene) -> some View {
        switch scene {
        case .hero:
            ZStack {
                Circle().strokeBorder(Theme.accent.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 5])).frame(width: 210, height: 210)
                Circle()
                    .fill(RadialGradient(colors: [Theme.accent.opacity(0.16), .clear], center: .center, startRadius: 0, endRadius: 140))
                    .frame(width: 250, height: 250)
                Sparkle(size: 20).offset(x: 70, y: -100)
                Sparkle(size: 14, color: .white).offset(x: -70, y: 80)
                HeroAvatarView(appearance: Appearance(skin: 1, hair: 2, hairStyle: .short, outfit: 0), size: 150)
            }
        case .safe:
            ZStack {
                UnevenRoundedRectangle(topLeadingRadius: 75, bottomLeadingRadius: 80, bottomTrailingRadius: 80, topTrailingRadius: 75)
                    .fill(LinearGradient(colors: [Theme.accent.opacity(0.18), Theme.accentDeep.opacity(0.06)], startPoint: .top, endPoint: .bottom))
                    .overlay(UnevenRoundedRectangle(topLeadingRadius: 75, bottomLeadingRadius: 80, bottomTrailingRadius: 80, topTrailingRadius: 75).strokeBorder(Theme.borderStrong))
                    .frame(width: 150, height: 168)
                MoonIcon(size: 74)
                Sparkle(size: 16).offset(x: -74, y: -78)
                Sparkle(size: 13, color: .white).offset(x: 72, y: 70)
            }
        case .library:
            ZStack {
                card(0x2A1D52, 0x14315C).rotationEffect(.degrees(-13)).offset(x: -54)
                card(0x3A2150, 0x5C2F4A).rotationEffect(.degrees(9)).offset(x: 50)
                card(0x1C2752, 0x14315C).rotationEffect(.degrees(-1)).overlay(MoonIcon(size: 40))
            }
        }
    }

    private func card(_ from: UInt32, _ to: UInt32) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: from), Color(hex: to)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.border))
            .frame(width: 130, height: 170)
            .shadow(color: .black.opacity(0.4), radius: 14, y: 10)
    }
}
