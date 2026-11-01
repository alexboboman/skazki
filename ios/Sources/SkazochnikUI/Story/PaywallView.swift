import SwiftUI
import SkazochnikCore

/// Subscription offer: Family and Family+ with the App Store's own prices. Buying and restoring go through
/// `SubscriptionStore`; the screen only reports back when a plan is active (`onPurchased`) or the person goes on without one.
struct PaywallView: View {
    let hero: HeroInfo
    /// Why the paywall is open, when it was opened because of a limit.
    var reason: PaywallInfo?
    let onPurchased: () -> Void
    let onFree: () -> Void

    @EnvironmentObject private var store: SubscriptionStore
    @State private var tier: Tier
    @State private var period: BillingPeriod = .year

    init(hero: HeroInfo, reason: PaywallInfo? = nil, onPurchased: @escaping () -> Void, onFree: @escaping () -> Void) {
        self.hero = hero
        self.reason = reason
        self.onPurchased = onPurchased
        self.onFree = onFree
        // Family+ is the only plan with the neural voice.
        _tier = State(initialValue: reason?.feature == "premium_voice" ? .familyPlus : .family)
    }

    private static let benefits: [Tier: [String]] = [
        .family: [
            "Безлимит коротких сказок",
            "Сериал на 7, 14 или 30 вечеров",
            "HD-иллюстрации в едином стиле",
            "Герой, похожий на вашего ребёнка",
        ],
        .familyPlus: [
            "Всё из Family",
            "Сказку читает мягкий нейроголос",
            "До 3 сериалов одновременно",
            "До 5 детей в одном аккаунте",
        ],
    ]

    var body: some View {
        ZStack {
            NightBackground(starCount: 48, seed: 33)
            VStack(spacing: 0) {
                AdaptiveScroll {
                    VStack(spacing: 0) {
                        MoonIcon(size: 64).padding(.top, 8).padding(.bottom, 12)
                        Text("Откройте Сказочник\nполностью").display(30).padding(.bottom, 12)
                        Text(subtitle).bodyStyle().multilineTextAlignment(.center).frame(maxWidth: 300).padding(.bottom, 20)

                        tierPicker.padding(.bottom, 14)

                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Self.benefits[tier] ?? [], id: \.self) { benefit in
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

                        plans.padding(.bottom, 28)
                    }
                }

                if let message = store.message {
                    Text(message).captionStyle().multilineTextAlignment(.center).foregroundStyle(Theme.gold).padding(.bottom, 8)
                }

                Button(action: buy) {
                    if store.phase == .purchasing {
                        ProgressView().tint(Color(hex: 0x1A1330))
                    } else {
                        Label("Оформить подписку", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.goldPill)
                .disabled(selectedOffer == nil || store.isBusy)
                // Content fades out above the pinned button instead of being cut by it.
                .background(alignment: .top) {
                    LinearGradient(colors: [Theme.bg1.opacity(0), Theme.bg1], startPoint: .top, endPoint: .bottom)
                        .frame(height: 28)
                        .offset(y: -28)
                        .allowsHitTesting(false)
                }
                Text("Подписка продлевается автоматически. Отменить можно в настройках Apple ID за сутки до списания.")
                    .captionStyle(11)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                Button(continueTitle, action: onFree).buttonStyle(.ghostPill).padding(.top, 2).disabled(store.isBusy)
                HStack(spacing: 18) {
                    Button("Восстановить") { restore() }.buttonStyle(.plain).disabled(store.isBusy)
                    ForEach(["Условия", "Конфиденциальность"], id: \.self) { Text($0) }
                }
                .font(Theme.sans(11.5))
                .foregroundStyle(Theme.text3)
                .padding(.top, 6)
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 26)
        }
        .preferredColorScheme(.dark)
        .task { await store.load() }
    }

    private var selectedOffer: StoreOffer? {
        store.offers(for: tier).first { $0.product.period == period }
    }

    private var continueTitle: String {
        store.entitlements?.source == "trial" ? "Продолжить пробный период" : "Продолжить с Free"
    }

    private var subtitle: String {
        if let reason, reason.code == .limitReached {
            return "Бесплатный лимит исчерпан. С подпиской сказки без ограничений."
        }
        return "Новая сказка про вашего ребёнка каждый вечер."
    }

    private func buy() {
        guard let offer = selectedOffer else { return }
        Task { if await store.purchase(offer) { onPurchased() } }
    }

    private func restore() {
        Task { if await store.restore() { onPurchased() } }
    }

    private var tierPicker: some View {
        HStack(spacing: 6) {
            ForEach([Tier.family, Tier.familyPlus], id: \.self) { item in
                let selected = tier == item
                Button { tier = item } label: {
                    Text(item == .family ? "Family" : "Family+")
                        .font(Theme.sans(14.5, weight: .semibold))
                        .foregroundStyle(selected ? Color(hex: 0x1A1330) : Theme.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(selected ? Theme.accent : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.card2, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.border))
    }

    @ViewBuilder private var plans: some View {
        let offers = store.offers(for: tier)
        if offers.isEmpty {
            VStack(spacing: 10) {
                if store.phase == .loading {
                    ProgressView().tint(Theme.accent)
                } else {
                    Text("Тарифы пока недоступны. Проверьте соединение и попробуйте ещё раз.").captionStyle().multilineTextAlignment(.center)
                    Button("Повторить") { Task { await store.load() } }.buttonStyle(.ghostPill)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 90)
        } else {
            VStack(spacing: 11) {
                ForEach(offers) { planRow($0) }
            }
        }
    }

    private func planRow(_ offer: StoreOffer) -> some View {
        let selected = period == offer.product.period
        let yearly = offer.product.period == .year
        let name = (tier == .family ? "Family" : "Family+") + (yearly ? " · год" : " · месяц")
        return Button { period = offer.product.period } label: {
            HStack(spacing: 14) {
                Circle()
                    .strokeBorder(selected ? Theme.accent : Theme.borderStrong, lineWidth: 2)
                    .frame(width: 22, height: 22)
                    .overlay { if selected { Circle().fill(Theme.accent).frame(width: 11, height: 11) } }
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(Theme.sans(16, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(yearly ? "оплата \(offer.displayPrice) в год" : "без обязательств").captionStyle().lineLimit(2)
                }
                .layoutPriority(1)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 5) {
                    Text("\(offer.monthlyPrice) / мес").font(Theme.sans(15.5, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1).fixedSize()
                    if yearly, let savings = store.yearlySavings(for: tier) {
                        Text("Выгода \(savings)%")
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
