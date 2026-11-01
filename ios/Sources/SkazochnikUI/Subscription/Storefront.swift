import Foundation
import StoreKit
import SkazochnikCore

/// A subscription as the paywall shows it: the catalog entry plus the App Store's localized prices.
public struct StoreOffer: Equatable, Identifiable, Sendable {
    public let product: SubscriptionProduct
    public var id: String { product.id }
    /// Price of one billing period, localized ("699 ₽").
    public let displayPrice: String
    /// Price per month as text: the monthly price itself, or a twelfth of the yearly one.
    public let monthlyPrice: String
    public let price: Decimal

    public init(product: SubscriptionProduct, displayPrice: String, monthlyPrice: String, price: Decimal) {
        self.product = product
        self.displayPrice = displayPrice
        self.monthlyPrice = monthlyPrice
        self.price = price
    }
}

/// A signed transaction. The server verifies `jws`; `finish` tells the App Store it was delivered,
/// and is only called once the server has accepted the transaction.
public struct StoreTransaction: Sendable {
    public let jws: String
    public let finish: @Sendable () async -> Void

    public init(jws: String, finish: @escaping @Sendable () async -> Void) {
        self.jws = jws
        self.finish = finish
    }
}

public enum PurchaseOutcome: Sendable {
    case purchased(StoreTransaction)
    /// Waiting for approval (Ask to Buy, extra authentication); the transaction arrives later through `updates()`.
    case pending
    case cancelled
}

public enum StorefrontError: Error, Sendable {
    case productUnavailable
    case unverified
}

/// The App Store as the app needs it. StoreKit 2 in production, a fake in tests.
public protocol Storefront: Sendable {
    func offers() async throws -> [StoreOffer]
    func purchase(_ productID: String, accountToken: UUID?) async throws -> PurchaseOutcome
    /// Signed transactions of the subscriptions the Apple ID holds right now.
    func currentTransactions() async -> [StoreTransaction]
    /// Asks the App Store to refresh the purchases (may ask for the Apple ID password), then returns them.
    func restore() async throws -> [StoreTransaction]
    /// Transactions that arrive outside a purchase: renewals, approved Ask to Buy, purchases on another device.
    func updates() -> AsyncStream<StoreTransaction>
}

public actor StoreKitStorefront: Storefront {
    private var products: [String: Product] = [:]

    public init() {}

    public func offers() async throws -> [StoreOffer] {
        let loaded = try await Product.products(for: SubscriptionCatalog.productIDs)
        products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        return SubscriptionCatalog.products.compactMap { entry in
            guard let product = products[entry.id] else { return nil }
            let monthly = entry.period == .year ? (product.price / Decimal(12)).formatted(product.priceFormatStyle) : product.displayPrice
            return StoreOffer(product: entry, displayPrice: product.displayPrice, monthlyPrice: monthly, price: product.price)
        }
    }

    public func purchase(_ productID: String, accountToken: UUID?) async throws -> PurchaseOutcome {
        guard let product = products[productID] else { throw StorefrontError.productUnavailable }
        var options: Set<Product.PurchaseOption> = []
        // Lets Apple's server notifications be matched to this account even before the app syncs.
        if let accountToken { options.insert(.appAccountToken(accountToken)) }

        switch try await product.purchase(options: options) {
        case .success(let result):
            guard let transaction = Self.verified(result) else { throw StorefrontError.unverified }
            return .purchased(transaction)
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    public func currentTransactions() async -> [StoreTransaction] {
        var found: [StoreTransaction] = []
        for await result in Transaction.currentEntitlements {
            if let transaction = Self.verified(result) { found.append(transaction) }
        }
        return found
    }

    public func restore() async throws -> [StoreTransaction] {
        try await AppStore.sync()
        return await currentTransactions()
    }

    public nonisolated func updates() -> AsyncStream<StoreTransaction> {
        AsyncStream { continuation in
            let task = Task {
                for await result in Transaction.updates {
                    if let transaction = Self.verified(result) { continuation.yield(transaction) }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Only transactions StoreKit itself verified, and only of our subscriptions.
    private static func verified(_ result: VerificationResult<Transaction>) -> StoreTransaction? {
        guard case .verified(let transaction) = result, SubscriptionCatalog.product(id: transaction.productID) != nil else { return nil }
        return StoreTransaction(jws: result.jwsRepresentation, finish: { await transaction.finish() })
    }
}
