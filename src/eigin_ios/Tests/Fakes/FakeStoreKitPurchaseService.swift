@testable import Eigin
import Foundation

/// Programmable `StoreKitPurchaseService` for tests. `availableProducts` returns whatever the store
/// is configured to vend; `purchase` returns a canned JWS.
final class FakeStoreKitPurchaseService: StoreKitPurchaseService, @unchecked Sendable {
    /// Products the fake store vends, keyed by ID. `availableProducts(ids:)` returns the subset of
    /// requested IDs present here, mirroring StoreKit dropping unknown IDs.
    var vended: [String: StoreProduct] = [:]
    var purchaseHandler: @Sendable (String) async throws -> String = { _ in "fake-jws" }

    func availableProducts(ids: [String]) async throws -> [StoreProduct] {
        ids.compactMap { vended[$0] }
    }

    func purchase(productID: String) async throws -> String {
        try await purchaseHandler(productID)
    }
}
