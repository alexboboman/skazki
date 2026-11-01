import SwiftUI
import SkazochnikCore

/// Purchases of the app: loads the offers, buys and restores, and keeps the server's view of the
/// subscription in step with the App Store. The server decides what a subscription unlocks; this class
/// only delivers Apple's signed transactions to it.
@MainActor
public final class SubscriptionStore: ObservableObject {
    public enum Phase: Equatable {
        case idle, loading, purchasing, restoring
    }

    @Published public private(set) var offers: [StoreOffer] = []
    @Published public private(set) var phase: Phase = .idle
    @Published public private(set) var offersFailed = false
    /// The server's latest answer about the account's plan.
    @Published public private(set) var entitlements: Entitlements?
    /// Something to tell the person on the paywall (declined, waiting for approval, could not confirm).
    @Published public var message: String?

    private let client: APIClient?
    private let storefront: Storefront?
    private var listener: Task<Void, Never>?

    /// Without a storefront (previews, tests) there is nothing to buy.
    public init(client: APIClient?, storefront: Storefront?) {
        self.client = client
        self.storefront = storefront
    }

    public var isBusy: Bool { phase != .idle }

    public func offers(for tier: Tier) -> [StoreOffer] {
        offers.filter { $0.product.tier == tier }.sorted { $0.product.period == .year && $1.product.period == .month }
    }

    /// How much cheaper a year is than twelve months of the monthly plan, in whole percent (nil when it is not worth a badge).
    public func yearlySavings(for tier: Tier) -> Int? {
        guard let monthly = offers.first(where: { $0.product.tier == tier && $0.product.period == .month }),
              let yearly = offers.first(where: { $0.product.tier == tier && $0.product.period == .year }),
              monthly.price > 0
        else { return nil }
        let ratio = NSDecimalNumber(decimal: yearly.price / (monthly.price * Decimal(12))).doubleValue
        let percent = Int(((1 - ratio) * 100).rounded())
        return percent >= 5 ? percent : nil
    }

    // MARK: Loading

    /// Loads the offers (when needed) and the account's plan.
    public func load() async {
        if let client, let fresh = try? await client.entitlements() { entitlements = fresh }
        guard let storefront, offers.isEmpty, phase == .idle else { return }
        phase = .loading
        defer { phase = .idle }
        do {
            offers = try await storefront.offers()
            offersFailed = offers.isEmpty
        } catch {
            offersFailed = true
        }
    }

    // MARK: Buying

    /// Returns true when the purchase is confirmed by the server and the plan is active.
    @discardableResult
    public func purchase(_ offer: StoreOffer) async -> Bool {
        guard let storefront, !isBusy else { return false }
        phase = .purchasing
        message = nil
        defer { phase = .idle }

        do {
            let token = client?.currentUserID().flatMap { UUID(uuidString: $0) }
            switch try await storefront.purchase(offer.id, accountToken: token) {
            case .purchased(let transaction):
                return await confirm([transaction], quiet: false)
            case .pending:
                message = "Покупка ждёт подтверждения. Как только её одобрят, тариф откроется сам."
                return false
            case .cancelled:
                return false
            }
        } catch {
            message = "Не удалось оформить подписку. Попробуйте ещё раз."
            return false
        }
    }

    @discardableResult
    public func restore() async -> Bool {
        guard let storefront, !isBusy else { return false }
        phase = .restoring
        message = nil
        defer { phase = .idle }

        do {
            let found = try await storefront.restore()
            guard !found.isEmpty else {
                message = "Подписок на этом Apple ID не нашлось."
                return false
            }
            return await confirm(found, quiet: false)
        } catch {
            message = "Не удалось восстановить покупки. Попробуйте ещё раз."
            return false
        }
    }

    // MARK: Staying in step with the App Store

    /// At launch: tells the server about the subscriptions this Apple ID holds (renewals, a new device, a lost account).
    public func syncCurrent() async {
        guard let storefront, client?.currentUserID() != nil else { return }
        let held = await storefront.currentTransactions()
        if !held.isEmpty { _ = await confirm(held, quiet: true) }
    }

    /// Listens for transactions that arrive outside a purchase. Safe to call more than once.
    public func startListening() {
        guard listener == nil, let storefront else { return }
        listener = Task { [weak self] in
            for await transaction in storefront.updates() {
                _ = await self?.confirm([transaction], quiet: true)
            }
        }
    }

    /// Gives the transactions to the server and, once it accepted them, finishes them for the App Store.
    /// An unconfirmed transaction stays unfinished: StoreKit hands it over again, and launch syncs it too.
    private func confirm(_ transactions: [StoreTransaction], quiet: Bool) async -> Bool {
        guard let client else { return false }
        do {
            let fresh = try await client.syncSubscription(transactions: transactions.map(\.jws))
            entitlements = fresh
            for transaction in transactions { await transaction.finish() }
            return fresh.source == "subscription"
        } catch {
            if !quiet { message = "Оплата прошла, но подтвердить её пока не удалось. Мы повторим при следующем запуске." }
            return false
        }
    }
}
