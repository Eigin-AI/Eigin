import Foundation

/// Persists an ``AulaSession`` (tokens + cookies + captured children) for a
/// connected Aula integration, keyed by ``Integration/id`` — one JSON blob
/// per integration, since the whole session travels as one unit.
protocol AulaCredentialStore: Sendable {
    func save(_ session: AulaSession, for integrationID: UUID)
    func read(for integrationID: UUID) -> AulaSession?
    func clear(for integrationID: UUID)
}

final class DefaultAulaCredentialStore: AulaCredentialStore, @unchecked Sendable {
    private let keychainService: any KeychainService
    private static let suffix = "aula_session"

    init(keychainService: any KeychainService) {
        self.keychainService = keychainService
    }

    func save(_ session: AulaSession, for integrationID: UUID) {
        guard let data = try? JSONEncoder().encode(session),
              let json = String(data: data, encoding: .utf8)
        else { return }
        keychainService.save(key: key(for: integrationID), value: json)
    }

    func read(for integrationID: UUID) -> AulaSession? {
        guard let json = keychainService.read(key: key(for: integrationID)),
              let data = json.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(AulaSession.self, from: data)
    }

    func clear(for integrationID: UUID) {
        keychainService.delete(key: key(for: integrationID))
    }

    private func key(for integrationID: UUID) -> String {
        keychainService.integrationKey(for: integrationID, suffix: Self.suffix)
    }
}
