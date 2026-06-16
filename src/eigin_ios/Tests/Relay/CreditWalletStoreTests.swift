@testable import Eigin
import Foundation
import Testing

@Suite("CreditWalletStore")
struct CreditWalletStoreTests {
    private func wallet(
        _ token: String,
        credits: Int = 100,
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

    @Test func upsertAppendsThenUpdatesByToken() {
        let store = CreditWalletStore(keychain: FakeKeychainService())
        store.upsert(wallet("a", credits: 100))
        store.upsert(wallet("b", credits: 50))
        #expect(store.all().count == 2)

        store.upsert(wallet("a", credits: 10))
        #expect(store.all().count == 2)
        #expect(store.all().first { $0.token == "a" }?.credits == 10)
    }

    @Test func roundTripsThroughKeychain() {
        let keychain = FakeKeychainService()
        CreditWalletStore(keychain: keychain).upsert(wallet("a"))
        // A fresh store over the same keychain reads what the first wrote.
        let reloaded = CreditWalletStore(keychain: keychain)
        #expect(reloaded.all().map(\.token) == ["a"])
    }

    @Test func removeDeletesByToken() {
        let store = CreditWalletStore(keychain: FakeKeychainService())
        store.upsert(wallet("a"))
        store.upsert(wallet("b"))
        store.remove(token: "a")
        #expect(store.all().map(\.token) == ["b"])
    }

    @Test func returnsEmptyWhenBlobIsUnreadable() {
        let keychain = FakeKeychainService()
        keychain.save(key: keychain.creditWalletsKey, value: "not json")
        #expect(CreditWalletStore(keychain: keychain).all().isEmpty)
    }
}
