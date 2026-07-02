@testable import Eigin
import Foundation

/// Programmable `RelayClient` for tests. Each handler defaults to throwing `.notConfigured`.
final class FakeRelayClient: RelayClient, @unchecked Sendable {
    var searchHandler: @Sendable (String, String?, String?) async throws -> String = { _, _, _ in
        throw RelayClientError.notConfigured
    }

    var productsHandler: @Sendable () async throws -> [CreditProduct] = {
        throw RelayClientError.notConfigured
    }

    var redeemHandler: @Sendable (String, String) async throws -> RedeemResponse = { _, _ in
        throw RelayClientError.notConfigured
    }

    var balanceHandler: @Sendable (String) async throws -> BalanceResponse = { _ in
        throw RelayClientError.notConfigured
    }

    var modelsHandler: @Sendable () async throws -> [String] = {
        throw RelayClientError.notConfigured
    }

    func search(query: String, region: String?, focus: String?) async throws -> String {
        try await searchHandler(query, region, focus)
    }

    func products() async throws -> [CreditProduct] {
        try await productsHandler()
    }

    func redeem(type: String, proof: String) async throws -> RedeemResponse {
        try await redeemHandler(type, proof)
    }

    func balance(token: String) async throws -> BalanceResponse {
        try await balanceHandler(token)
    }

    func models() async throws -> [String] {
        try await modelsHandler()
    }
}
