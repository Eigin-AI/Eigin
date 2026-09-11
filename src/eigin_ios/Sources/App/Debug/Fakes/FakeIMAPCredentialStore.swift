#if DEBUG || EIGIN_DEV
import Foundation

/// In-memory ``IMAPCredentialStore`` for tests — no Keychain access.
final class FakeIMAPCredentialStore: IMAPCredentialStore, @unchecked Sendable {
    private var storage: [UUID: IMAPAccountSettings] = [:]
    private(set) var clearedIDs: [UUID] = []

    func save(_ settings: IMAPAccountSettings, for integrationID: UUID) {
        storage[integrationID] = settings
    }

    func read(for integrationID: UUID) -> IMAPAccountSettings? {
        storage[integrationID]
    }

    func clear(for integrationID: UUID) {
        clearedIDs.append(integrationID)
        storage.removeValue(forKey: integrationID)
    }
}
#endif
