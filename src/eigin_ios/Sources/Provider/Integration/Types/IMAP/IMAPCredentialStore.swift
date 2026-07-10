import Foundation

/// Persists ``IMAPAccountSettings`` (server config + password) for a
/// connected IMAP integration, keyed by ``Integration/id``.
///
/// Mirrors ``IntegrationOAuthService``'s Keychain namespacing, but stores one
/// JSON blob per integration rather than several named tokens — there's no
/// refresh/expiry lifecycle to track, just a single settings value.
protocol IMAPCredentialStore: Sendable {
    func save(_ settings: IMAPAccountSettings, for integrationID: UUID)
    func read(for integrationID: UUID) -> IMAPAccountSettings?
    func clear(for integrationID: UUID)
}

final class DefaultIMAPCredentialStore: IMAPCredentialStore, @unchecked Sendable {
    private let keychainService: any KeychainService
    private static let suffix = "imap_settings"

    init(keychainService: any KeychainService) {
        self.keychainService = keychainService
    }

    func save(_ settings: IMAPAccountSettings, for integrationID: UUID) {
        guard let data = try? JSONEncoder().encode(settings),
              let json = String(data: data, encoding: .utf8)
        else { return }
        keychainService.save(key: key(for: integrationID), value: json)
    }

    func read(for integrationID: UUID) -> IMAPAccountSettings? {
        guard let json = keychainService.read(key: key(for: integrationID)),
              let data = json.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(IMAPAccountSettings.self, from: data)
    }

    func clear(for integrationID: UUID) {
        keychainService.delete(key: key(for: integrationID))
    }

    private func key(for integrationID: UUID) -> String {
        keychainService.integrationKey(for: integrationID, suffix: Self.suffix)
    }
}
