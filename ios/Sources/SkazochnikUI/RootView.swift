import SwiftUI
import SkazochnikCore

/// App root: onboarding until the first profile exists, then the main app (built next).
public struct RootView: View {
    private let client: APIClient
    @AppStorage("onboardingFinished") private var onboardingFinished = false
    @AppStorage("heroName") private var heroName = ""

    public init(client: APIClient) {
        self.client = client
    }

    public var body: some View {
        if onboardingFinished {
            HomePlaceholder(heroName: heroName) {
                onboardingFinished = false
                heroName = ""
                client.signOut()
            }
        } else {
            OnboardingFlow(client: client) { profile in
                heroName = profile.name
                onboardingFinished = true
            }
        }
    }
}

/// Stands in for the "Сегодня" tab until the main screens are built.
struct HomePlaceholder: View {
    let heroName: String
    let onRestart: () -> Void

    var body: some View {
        ZStack {
            NightBackground(starCount: 50, seed: 11)
            VStack(spacing: 0) {
                Spacer()
                MoonIcon(size: 90).padding(.bottom, 28)
                Text("Профиль создан").kicker().padding(.bottom, 14)
                Text("\(heroName.isEmpty ? "Малыш" : heroName) ждёт сказку").display(32).padding(.bottom, 16)
                Text("Экран «Сегодня» и создание сказок — следующий шаг.").bodyStyle().multilineTextAlignment(.center).frame(maxWidth: 290)
                Spacer()
                Button("Пройти онбординг заново", action: onRestart).buttonStyle(.ghostPill).padding(.bottom, 24)
            }
            .padding(.horizontal, 26)
        }
        .preferredColorScheme(.dark)
    }
}
