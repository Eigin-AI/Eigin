import Foundation
import Security

/// Secure key-value storage for sensitive data such as API tokens.
protocol KeychainService: Sendable {
    /// Stores a value in the keychain, replacing any existing entry for the same key.
    func save(key: String, value: String)
    /// Retrieves a previously stored value, or `nil` if no entry exists.
    func read(key: String) -> String?
    /// Removes the entry for the given key, if it exists.
    func delete(key: String)
    /// Returns the canonical keychain key for a provider credential: the
    /// provider's API token (suffix `nil`) or a named field of a refreshable
    /// credential (e.g. suffix `access_token`).
    func providerKey(for providerID: UUID, suffix: String?) -> String
    /// Returns the canonical keychain key for an MCP server credential.
    func mcpKey(for serverID: UUID, suffix: String) -> String
    /// Returns the canonical keychain key for an integration credential.
    func integrationKey(for integrationID: UUID, suffix: String) -> String
    /// The keychain key under which the credit-wallet collection is stored as a JSON blob.
    var creditWalletsKey: String { get }
}

extension KeychainService {
    /// The provider's static API-token key.
    func providerKey(for providerID: UUID) -> String {
        providerKey(for: providerID, suffix: nil)
    }
}

/// Implementation of ``KeychainService`` backed by the iOS Keychain (Security framework).
struct DefaultKeychainService: KeychainService {
    private let serviceKey: String

    init(serviceKey: String) {
        self.serviceKey = serviceKey
    }

    func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceKey,
            kSecAttrAccount as String: key,
        ]

        // Delete any existing item first
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        SecItemAdd(addQuery as CFDictionary, nil)
    }

    func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceKey,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceKey,
            kSecAttrAccount as String: key,
        ]

        SecItemDelete(query as CFDictionary)
    }

    func providerKey(for providerID: UUID, suffix: String?) -> String {
        if let suffix {
            "\(serviceKey).provider.\(providerID.uuidString).\(suffix)"
        } else {
            "\(serviceKey).provider.\(providerID.uuidString)"
        }
    }

    func mcpKey(for serverID: UUID, suffix: String) -> String {
        "\(serviceKey).mcp.\(serverID.uuidString).\(suffix)"
    }

    func integrationKey(for integrationID: UUID, suffix: String) -> String {
        "\(serviceKey).integration.\(integrationID.uuidString).\(suffix)"
    }

    var creditWalletsKey: String {
        "\(serviceKey).credits.wallets"
    }
}
