@testable import Eigin
import Foundation
import Synchronization
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

    @Test func exhaustionEvictsOnlyRejectedWallet() {
        let manager = makeManager()
        manager.add(wallet("a", credits: 100))
        manager.add(wallet("b", credits: 100))
        manager.markExhausted(token: "a")
        #expect(manager.wallets().map(\.token) == ["b"])
        manager.markExhausted(token: "missing")
        #expect(manager.wallets().map(\.token) == ["b"])
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

    @Test func concurrentSelectionAndExhaustionKeepTheRemainingWallet() throws {
        let keychain = FakeKeychainService()
        let manager = DefaultCreditWalletManager(relayClient: FakeRelayClient(), keychain: keychain)
        for token in ["first", "second"] {
            manager.add(CreditWallet(
                token: token,
                credits: 100,
                status: .active,
                productID: nil,
                updatedAt: .distantPast
            ))
        }
        let source = EiginRelayWalletAdapter(manager: manager)
        let selections = Mutex<[String?]>([])
        let failures = Mutex(0)
        DispatchQueue.concurrentPerform(iterations: 32) { _ in
            do {
                let token = try source.nextToken(excluded: ["first"])
                selections.withLock { $0.append(token) }
                try source.markExhausted(token: "first")
            } catch {
                failures.withLock { $0 += 1 }
            }
        }
        #expect(failures.withLock { $0 } == 0)
        #expect(selections.withLock { $0.count == 32 && $0.allSatisfy { $0 == "second" } })
        let reloaded = DefaultCreditWalletManager(
            relayClient: FakeRelayClient(),
            keychain: keychain
        )
        #expect(reloaded.wallets().map(\.token) == ["second"])
        #expect(try source.nextToken(excluded: ["first", "second"]) == nil)
    }
}
