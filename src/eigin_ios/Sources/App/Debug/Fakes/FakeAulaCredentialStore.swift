#if DEBUG || EIGIN_DEV
import Foundation

/// In-memory ``AulaCredentialStore`` for tests — no Keychain access.
final class FakeAulaCredentialStore: AulaCredentialStore, @unchecked Sendable {
    private var storage: [UUID: AulaSession] = [:]
    private(set) var clearedIDs: [UUID] = []

    init(seed: [UUID: AulaSession] = [:]) {
        storage = seed
    }

    func save(_ session: AulaSession, for integrationID: UUID) {
        storage[integrationID] = session
    }

    func read(for integrationID: UUID) -> AulaSession? {
        storage[integrationID]
    }

    func clear(for integrationID: UUID) {
        clearedIDs.append(integrationID)
        storage.removeValue(forKey: integrationID)
    }
}
#endif
