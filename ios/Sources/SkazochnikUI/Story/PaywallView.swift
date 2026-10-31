import SwiftUI
import SkazochnikCore

/// Subscription offer. Purchasing is not wired yet: it needs the StoreKit 2 products and the
/// App Store Server Notifications integration on the backend, so the two buttons only report the choice.
struct PaywallView: View {
    struct Plan: Identifiable {
        let id: String
        let name: String
        let price: String
        let sub: String
        let badge: String?
    }

    /// Placeholder copy and prices from the design prototype. The real ones come from the StoreKit products;
    /// the ruble prices in the prototype are unconfirmed (see docs/product/UI_Flow.md, section 7).
    static let plans = [
        Plan(id: "year", name: "Family · год", price: "4 167 ₽ / мес", sub: "оплата 49 990 ₽ в год", badge: "Выгода 40%"),
        Plan(id: "month", name: "Family · месяц", price: "699 ₽ / мес", sub: "гибко, отмена в любой момент", badge: nil),
    ]

    let hero: HeroInfo
    /// Why the paywall is open, when it was opened because of a limit.
    var reason: PaywallInfo?
    let onTrial: () -> Void
    let onFree: () -> Void

    @State private var plan = "year"

    private let benefits = [
        "Безлимит коротких сказок каждый вечер",
        "Сериалы на 7, 14 и 30 вечеров",
        "HD-иллюстрации в едином стиле",
        "Герой, похожий на вашего ребёнка",
    ]

    var body: some View {
        ZStack {
            NightBackground(starCount: 48, seed: 33)
            VStack(spacing: 0) {
                AdaptiveScroll {
                    VStack(spacing: 0) {
                        MoonIcon(size: 64).padding(.top, 8).padding(.bottom, 12)
                        Text("Откройте Сказочник\nполностью").display(30).padding(.bottom, 12)
                        Text(subtitle).bodyStyle().multilineTextAlignment(.center).frame(maxWidth: 300).padding(.bottom, 24)

                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(benefits, id: \.self) { benefit in
                                HStack(spacing: 13) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(Color(hex: 0x1A1330))
                                        .frame(width: 24, height: 24)
                                        .background(LinearGradient(colors: [Color(hex: 0xD9CCFF), Theme.accent], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                                    Text(benefit).font(Theme.sans(15.5)).foregroundStyle(Theme.text)
                                }
                                .padding(.vertical, 9)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard()
                        .padding(.bottom, 16)

                        VStack(spacing: 11) {
                            ForEach(Self.plans) { item in planRow(item) }
                        }
                        .padding(.bottom, 20)
                    }
                }
    
                Button(action: onTrial) { Label("Попробовать 7 дней бесплатно", systemImage: "sparkles") }
                    .buttonStyle(.goldPill)
                Button("Продолжить с Free", action: onFree).buttonStyle(.ghostPill).padding(.top, 4)
                HStack(spacing: 18) {
                    ForEach(["Восстановить", "Условия", "Конфиденциальность"], id: \.self) { Text($0).captionStyle(11.5) }
                }
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 26)
        }
        .preferredColorScheme(.dark)
    }

    private var subtitle: String {
        if let reason, reason.code == .limitReached {
            return "Бесплатный лимит на сегодня исчерпан. С подпиской — новая сказка каждый вечер."
        }
        return "7 дней бесплатно. Затем — по цене одной книжки в месяц."
    }

    private func planRow(_ item: Plan) -> some View {
        let selected = plan == item.id
        return Button { plan = item.id } label: {
            HStack(spacing: 14) {
                Circle()
                    .strokeBorder(selected ? Theme.accent : Theme.borderStrong, lineWidth: 2)
                    .frame(width: 22, height: 22)
                    .overlay { if selected { Circle().fill(Theme.accent).frame(width: 11, height: 11) } }
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).font(Theme.sans(16, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(item.sub).captionStyle().lineLimit(2)
                }
                .layoutPriority(1)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 5) {
                    Text(item.price).font(Theme.sans(15.5, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1).fixedSize()
                    if let badge = item.badge {
                        Text(badge)
                            .font(Theme.sans(11, weight: .semibold))
                            .foregroundStyle(Theme.gold)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(Theme.goldSoft, in: Capsule())
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .tileSurface(selected: selected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// End of onboarding: the hero is ready for the first evening.
struct DoneView: View {
    let hero: HeroInfo
    let trial: Bool
    let onHome: () -> Void

    var body: some View {
        ZStack {
            NightBackground(starCount: 64, seed: 34)
            VStack(spacing: 0) {
                Spacer()
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [Theme.gold.opacity(0.3), .clear], center: .center, startRadius: 0, endRadius: 110))
                        .frame(width: 180, height: 180)
                    HeroAvatarView(appearance: hero.appearance, size: 132)
                    Sparkle(size: 20).offset(x: 60, y: -62)
                    Sparkle(size: 14, color: .white).offset(x: -64, y: 44)
                }
                .padding(.bottom, 30)
                Text(trial ? "Пробный период активен" : "Профиль создан").kicker().foregroundStyle(Theme.gold).padding(.bottom, 14)
                Text("Всё готово,\n\(hero.name) ждёт сказку").display(32).padding(.bottom, 16)
                Text("Каждый вечер вас будет ждать новая добрая история. Спокойных снов!")
                    .bodyStyle().multilineTextAlignment(.center).frame(maxWidth: 290)
                Spacer()
                Button("Перейти к сказкам", action: onHome).buttonStyle(.primaryPill).padding(.bottom, 24)
            }
            .padding(.horizontal, 26)
        }
        .preferredColorScheme(.dark)
    }
}
