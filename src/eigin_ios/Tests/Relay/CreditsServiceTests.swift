@testable import Eigin
import Foundation
import Testing

@Suite("CreditsService")
struct CreditsServiceTests {
    private func makeService(
        relay: FakeRelayClient,
        store: FakeStoreKitPurchaseService
    ) -> DefaultCreditsService {
        let manager = DefaultCreditWalletManager(
            relayClient: relay,
            keychain: FakeKeychainService()
        )
        return DefaultCreditsService(
            relayClient: relay,
            purchaseService: store,
            walletManager: manager
        )
    }

    @Test func availableProductsMergesRelayCreditsWithStorePrice() async throws {
        let relay = FakeRelayClient()
        relay.productsHandler = {
            [CreditProduct(id: "eigin.credits.v1.apple.500", credits: 500)]
        }
        let store = FakeStoreKitPurchaseService()
        store.vended = [
            "eigin.credits.v1.apple.500": StoreProduct(
                id: "eigin.credits.v1.apple.500",
                displayName: "500 Credits",
                displayPrice: "$4.99"
            ),
        ]

        let products = try await makeService(relay: relay, store: store).availableProducts()

        #expect(products.count == 1)
        let product = try #require(products.first)
        #expect(product.id == "eigin.credits.v1.apple.500")
        #expect(product.credits == 500) // from the relay
        #expect(product.displayName == "500 Credits") // from the store
        #expect(product.displayPrice == "$4.99") // from the store
    }

    @Test func availableProductsDropsCatalogIDsTheStoreDoesNotVend() async throws {
        let relay = FakeRelayClient()
        relay.productsHandler = {
            [
                CreditProduct(id: "eigin.credits.v1.apple.500", credits: 500),
                CreditProduct(id: "eigin.credits.v1.apple.dev.500", credits: 500),
            ]
        }
        // The store only vends the dev product (mirrors the dev app's App Store Connect listing).
        let store = FakeStoreKitPurchaseService()
        store.vended = [
            "eigin.credits.v1.apple.dev.500": StoreProduct(
                id: "eigin.credits.v1.apple.dev.500",
                displayName: "500 Credits (Dev)",
                displayPrice: "$4.99"
            ),
        ]

        let products = try await makeService(relay: relay, store: store).availableProducts()

        #expect(products.map(\.id) == ["eigin.credits.v1.apple.dev.500"])
    }

    @Test func availableProductsSortsByCreditsAscending() async throws {
        let relay = FakeRelayClient()
        relay.productsHandler = {
            [
                CreditProduct(id: "big", credits: 500),
                CreditProduct(id: "small", credits: 100),
            ]
        }
        let store = FakeStoreKitPurchaseService()
        store.vended = [
            "big": StoreProduct(id: "big", displayName: "Big", displayPrice: "$4.99"),
            "small": StoreProduct(id: "small", displayName: "Small", displayPrice: "$0.99"),
        ]

        let products = try await makeService(relay: relay, store: store).availableProducts()

        #expect(products.map(\.credits) == [100, 500])
    }
}
