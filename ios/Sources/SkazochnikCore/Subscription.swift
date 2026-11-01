import Foundation

public enum BillingPeriod: String, Sendable {
    case month, year
}

/// One auto-renewable subscription of the App Store. The ids are the same as in App Store Connect,
/// in `StoreKit/Skazochnik.storekit` and in `SUBSCRIPTION_PRODUCT_TIERS` on the server.
public struct SubscriptionProduct: Equatable, Identifiable, Sendable {
    public let id: String
    public let tier: Tier
    public let period: BillingPeriod
}

public enum SubscriptionCatalog {
    public static let products: [SubscriptionProduct] = [
        SubscriptionProduct(id: "family_monthly", tier: .family, period: .month),
        SubscriptionProduct(id: "family_yearly", tier: .family, period: .year),
        SubscriptionProduct(id: "family_plus_monthly", tier: .familyPlus, period: .month),
        SubscriptionProduct(id: "family_plus_yearly", tier: .familyPlus, period: .year),
    ]

    public static var productIDs: [String] { products.map(\.id) }

    public static func product(id: String) -> SubscriptionProduct? {
        products.first { $0.id == id }
    }
}
