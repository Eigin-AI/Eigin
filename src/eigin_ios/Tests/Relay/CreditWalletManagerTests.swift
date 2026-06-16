@testable import Eigin
import Foundation
import Testing

@Suite("CreditWalletManager")
struct CreditWalletManagerTests {
    private func makeManager(relay: FakeRelayClient = FakeRelayClient())
        -> DefaultCreditWalletManager
    {
        DefaultCreditWalletManager(relayClient: relay, keychain: FakeKeychainService())
    }

    private func wallet(
        _ token: String,
        credits: Int,
        status: WalletStatus = .active
    ) -> CreditWallet {
        CreditWallet(
            token: token,
            credits: credits,
            status: status,
            productID: nil,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test func spendableWalletSkipsNonSpendable() {
        let manager = makeManager()
        manager.add(wallet("refunded", credits: 100, status: .refunded))
        manager.add(wallet("zero", credits: 0))
        manager.add(wallet("good", credits: 5))
        #expect(manager.spendableWallet()?.token == "good")
    }

    @Test func evictEmptyDropsDeadWallets() {
        let manager = makeManager()
        manager.add(wallet("good", credits: 10))
        manager.add(wallet("zero", credits: 0))
        manager.add(wallet("closed", credits: 10, status: .closed))
        manager.evictEmpty()
        #expect(manager.wallets().map(\.token) == ["good"])
    }

    @Test func withCreditsFailsOverToNextWallet() async throws {
        let manager = makeManager()
        manager.add(wallet("a", credits: 100))
        manager.add(wallet("b", credits: 100))

        let result = try await manager.withCredits { token in
            if token == "a" { throw RelayClientError.insufficientCredits(nil) }
            return token
        }

        #expect(result == "b")
        // The exhausted wallet is evicted.
        #expect(manager.wallets().map(\.token) == ["b"])
    }

    @Test func withCreditsThrowsWhenAllExhausted() async {
        let manager = makeManager()
        manager.add(wallet("a", credits: 100))
        await #expect(throws: CreditsError.noCreditsRemaining) {
            _ = try await manager.withCredits { _ in
                throw RelayClientError.insufficientCredits(nil)
            }
        }
    }

    @Test func refreshBalancesUpdatesKnownAndDropsUnknown() async {
        let relay = FakeRelayClient()
        relay.balanceHandler = { token in
            if token == "known" { return BalanceResponse(credits: 7, status: .active) }
            throw RelayClientError.authentication(nil)
        }
        let manager = makeManager(relay: relay)
        manager.add(wallet("known", credits: 100))
        manager.add(wallet("unknown", credits: 100))

        await manager.refreshBalances()

        #expect(manager.wallets().map(\.token) == ["known"])
        #expect(manager.wallets().first?.credits == 7)
    }
}
