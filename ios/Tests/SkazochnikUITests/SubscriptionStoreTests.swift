import Foundation
import Testing
import SkazochnikCore
@testable import SkazochnikUI

extension StubbedNetwork {
    @MainActor
    @Suite struct SubscriptionStoreTests {
        private let userID = "3f0c1e2a-8d4b-4c5e-9a6f-1b2c3d4e5f60"

        init() { RouteStub.routes = [:] }

        /// A token shaped like the server's JWT, with the account id in `sub`.
        private func token() -> String {
            let payload = Data(#"{"sub":"3f0c1e2a-8d4b-4c5e-9a6f-1b2c3d4e5f60","exp":4102444800}"#.utf8)
                .base64EncodedString().replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            return "e30.\(payload).sig"
        }

        private func client() -> APIClient {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [RouteStub.self]
            return APIClient(baseURL: URL(string: "http://route.test")!, store: MemorySessionStore(token: token()), session: URLSession(configuration: configuration))
        }

        private func entitlements(tier: String, source: String) -> Data {
            Data(#"{"tier":"\#(tier)","source":"\#(source)","limits":{"profiles":{"limit":3,"used":1},"activeArcs":1,"imageQuality":"hd"},"quotas":[]}"#.utf8)
        }

        private func serverAccepts(tier: String = "family") {
            RouteStub.routes["POST /v1/subscription/sync"] = { [self] _ in .success((200, entitlements(tier: tier, source: "subscription"))) }
        }

        // MARK: Catalog and account id

        @Test func theCatalogMatchesTheServersProductIds() {
            #expect(SubscriptionCatalog.productIDs == ["family_monthly", "family_yearly", "family_plus_monthly", "family_plus_yearly"])
            #expect(SubscriptionCatalog.product(id: "family_plus_yearly")?.tier == .familyPlus)
            #expect(SubscriptionCatalog.product(id: "family_plus_yearly")?.period == .year)
            #expect(SubscriptionCatalog.product(id: "gems") == nil)
        }

        @Test func theAccountIdComesFromTheToken() {
            #expect(client().currentUserID() == userID)
            let signedOut = APIClient(baseURL: URL(string: "http://route.test")!, store: MemorySessionStore())
            #expect(signedOut.currentUserID() == nil)
            let garbage = APIClient(baseURL: URL(string: "http://route.test")!, store: MemorySessionStore(token: "not-a-jwt"))
            #expect(garbage.currentUserID() == nil)
        }

        // MARK: Offers

        @Test func offersAreLoadedAndYearlyComesFirstWithASavingsBadge() async {
            let store = SubscriptionStore(client: client(), storefront: FakeStorefront())
            await store.load()
            #expect(store.offers(for: .family).map(\.id) == ["family_yearly", "family_monthly"])
            #expect(store.offers(for: .familyPlus).map(\.id) == ["family_plus_yearly", "family_plus_monthly"])
            #expect(store.yearlySavings(for: .family) == 40)
            #expect(store.yearlySavings(for: .familyPlus) == 42)
            #expect(!store.offersFailed)
        }

        @Test func failingToLoadOffersIsReportedAndCanBeRetried() async {
            let fake = FakeStorefront()
            fake.offersError = URLError(.notConnectedToInternet)
            let store = SubscriptionStore(client: client(), storefront: fake)
            await store.load()
            #expect(store.offersFailed)
            #expect(store.offers.isEmpty)

            fake.offersError = nil
            await store.load()
            #expect(!store.offersFailed)
            #expect(store.offers.count == 4)
        }

        @Test func withoutAStorefrontNothingCanBeBought() async {
            let store = SubscriptionStore(client: nil, storefront: nil)
            await store.load()
            #expect(store.offers.isEmpty)
            let offer = StoreOffer(product: SubscriptionCatalog.products[0], displayPrice: "", monthlyPrice: "", price: 1)
            #expect(await store.purchase(offer) == false)
        }

        // MARK: Buying

        @Test func aPurchaseIsConfirmedByTheServerThenFinished() async throws {
            serverAccepts(tier: "family_plus")
            let finished = FinishCounter()
            let fake = FakeStorefront()
            fake.outcome = .purchased(finished.transaction("signed-jws"))
            var sentBody: Data?
            RouteStub.routes["POST /v1/subscription/sync"] = { [self] request in
                sentBody = request.httpBody ?? request.httpBodyStream.flatMap { stream in
                    stream.open(); defer { stream.close() }
                    var data = Data(); var buffer = [UInt8](repeating: 0, count: 1024)
                    while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; data.append(buffer, count: n) }
                    return data
                }
                return .success((200, entitlements(tier: "family_plus", source: "subscription")))
            }

            let store = SubscriptionStore(client: client(), storefront: fake)
            await store.load()
            let offer = try #require(store.offers(for: .familyPlus).first)
            let ok = await store.purchase(offer)

            #expect(ok)
            #expect(finished.count == 1)
            #expect(store.entitlements?.tier == .familyPlus)
            #expect(fake.purchasedID == "family_plus_yearly")
            #expect(fake.accountToken == UUID(uuidString: userID))
            #expect(String(decoding: try #require(sentBody), as: UTF8.self).contains("signed-jws"))
            #expect(store.message == nil)
            #expect(store.phase == .idle)
        }

        @Test func aCancelledPurchaseChangesNothing() async throws {
            let fake = FakeStorefront()
            fake.outcome = .cancelled
            let store = SubscriptionStore(client: client(), storefront: fake)
            await store.load()
            #expect(await store.purchase(try #require(store.offers.first)) == false)
            #expect(store.message == nil)
            #expect(store.phase == .idle)
        }

        @Test func aPendingPurchaseExplainsTheWait() async throws {
            let fake = FakeStorefront()
            fake.outcome = .pending
            let store = SubscriptionStore(client: client(), storefront: fake)
            await store.load()
            #expect(await store.purchase(try #require(store.offers.first)) == false)
            #expect(store.message?.contains("подтверждения") == true)
        }

        @Test func aStoreErrorIsShownAsAMessage() async throws {
            let fake = FakeStorefront()
            fake.purchaseError = URLError(.badServerResponse)
            let store = SubscriptionStore(client: client(), storefront: fake)
            await store.load()
            #expect(await store.purchase(try #require(store.offers.first)) == false)
            #expect(store.message != nil)
        }

        @Test func whenTheServerCannotConfirmThePurchaseStaysUnfinished() async throws {
            // Paid but the server is down: the transaction must stay open so StoreKit hands it over again.
            let finished = FinishCounter()
            let fake = FakeStorefront()
            fake.outcome = .purchased(finished.transaction("jws"))
            let store = SubscriptionStore(client: client(), storefront: fake) // no route: offline
            await store.load()
            #expect(await store.purchase(try #require(store.offers.first)) == false)
            #expect(finished.count == 0)
            #expect(store.message?.contains("подтвердить") == true)
        }

        // MARK: Restore and sync

        @Test func restoreSendsEverythingTheAppleIdHolds() async {
            serverAccepts()
            let finished = FinishCounter()
            let fake = FakeStorefront()
            fake.restored = [finished.transaction("a"), finished.transaction("b")]
            let store = SubscriptionStore(client: client(), storefront: fake)
            #expect(await store.restore())
            #expect(finished.count == 2)
            #expect(store.entitlements?.source == "subscription")
        }

        @Test func restoreWithNothingToRestoreSaysSo() async {
            let store = SubscriptionStore(client: client(), storefront: FakeStorefront())
            #expect(await store.restore() == false)
            #expect(store.message?.contains("не нашлось") == true)
        }

        @Test func launchSyncTellsTheServerAboutHeldSubscriptionsQuietly() async {
            serverAccepts()
            let finished = FinishCounter()
            let fake = FakeStorefront()
            fake.held = [finished.transaction("held")]
            let store = SubscriptionStore(client: client(), storefront: fake)
            await store.syncCurrent()
            #expect(store.entitlements?.tier == .family)
            #expect(finished.count == 1)
            #expect(store.message == nil)
        }

        @Test func launchSyncWithoutSubscriptionsDoesNotCallTheServer() async {
            var called = false
            RouteStub.routes["POST /v1/subscription/sync"] = { _ in called = true; return .success((200, Data())) }
            let store = SubscriptionStore(client: client(), storefront: FakeStorefront())
            await store.syncCurrent()
            #expect(!called)
        }

        @Test func transactionsArrivingLaterAreSyncedToo() async throws {
            serverAccepts()
            let finished = FinishCounter()
            let fake = FakeStorefront()
            fake.incoming = [finished.transaction("renewal")]
            let store = SubscriptionStore(client: client(), storefront: fake)
            store.startListening()
            store.startListening() // a second call must not start a second listener
            for _ in 0..<50 where finished.count == 0 { try await Task.sleep(for: .milliseconds(20)) }
            #expect(finished.count == 1)
            #expect(store.entitlements?.tier == .family)
        }
    }
}
