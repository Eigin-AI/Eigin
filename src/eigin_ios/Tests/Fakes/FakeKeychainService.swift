@testable import Eigin
import Foundation

/// In-memory `KeychainService` for tests.
final class FakeKeychainService: KeychainService, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String] = [:]

    func save(key: String, value: String) {
        lock.withLock { storage[key] = value }
    }

    func read(key: String) -> String? {
        lock.withLock { storage[key] }
    }

    func delete(key: String) {
        lock.withLock { storage[key] = nil }
    }

    func providerKey(for providerID: UUID) -> String {
        "provider.\(providerID.uuidString)"
    }

    func mcpKey(for serverID: UUID, suffix: String) -> String {
        "mcp.\(serverID.uuidString).\(suffix)"
    }

    func integrationKey(for integrationID: UUID, suffix: String) -> String {
        "integration.\(integrationID.uuidString).\(suffix)"
    }

    var creditWalletsKey: String {
        "credits.wallets"
    }
}
