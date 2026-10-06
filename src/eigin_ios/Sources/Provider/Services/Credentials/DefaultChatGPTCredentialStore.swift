import Foundation

/// Keychain-backed storage and refresh for ChatGPT sign-in credentials.
///
/// Refreshed SIWC refresh tokens rotate: a second refresh issued with the
/// previous token fails terminally and destroys the connection. The actor
/// queues refreshes so concurrent requests share one in-flight refresh
/// instead of racing.
/// Keychain-backed storage for ChatGPT sign-in credentials, read from the
/// inference path and refreshed before expiry.
///
/// Refreshed SIWC refresh tokens rotate: a second refresh issued with the
/// previous token fails terminally and destroys the connection. The actor
/// queues refreshes so concurrent requests share one in-flight refresh
/// instead of racing.
protocol ProviderCredentialStoring: Sendable {
    /// A valid access token for this provider, refreshing first when needed.
    /// `nil` when nothing is stored or the refresh failed — terminal refresh
    /// failures clear the store, which is the durable "sign in again" signal.
    func validAccessToken(providerID: UUID) async -> String?
    func save(_ credential: ChatGPTCredential, providerID: UUID) async
    /// Clears all stored credential data for the provider.
    func clear(providerID: UUID) async
    func clientID(providerID: UUID) async -> String?
    func idToken(providerID: UUID) async -> String?
    /// The stable per-install host ID sent as `ext_agent_host_id`.
    func hostID() async -> String?
}

actor DefaultChatGPTCredentialStore: ProviderCredentialStoring {
    enum Suffix {
        static let accessToken = "access_token"
        static let refreshToken = "refresh_token"
        static let idToken = "id_token"
        static let tokenExpiry = "token_expiry"
        static let clientID = "client_id"
        static let scope = "scope"
        static let all = [
            accessToken, refreshToken, idToken, tokenExpiry, clientID, scope,
        ]
    }

    /// Under this key the identifier OpenAI treats as this installation's
    /// `ext_agent_host_id` is stored, created on first use.
    let hostIDKey: String

    private let keychain: any KeychainService
    private let refreshStore: RefreshableCredentialStore
    /// Serializes refreshes per provider; queued callers share the result.
    private var inFlight: [UUID: Task<String?, Never>] = [:]

    /// `refresh` performs the SIWC refresh-token grant; it throws
    /// ``CredentialRefreshError/terminal(_:)`` when the refresh token is dead
    /// (clearing the store) and anything else on transient failure.
    init(
        keychain: any KeychainService,
        serviceKey: String,
        urlSession: URLSession = .shared,
        customRefresh: (@Sendable (UUID, String) async throws
            -> RefreshedCredentialTokens)? = nil
    ) {
        self.keychain = keychain
        refreshStore = RefreshableCredentialStore(
            read: { [keychain] id, suffix in
                keychain.read(key: keychain.providerKey(for: id, suffix: suffix))
            },
            write: { [keychain] id, suffix, value in
                keychain.save(
                    key: keychain.providerKey(for: id, suffix: suffix),
                    value: value
                )
            },
            remove: { [keychain] id, suffix in
                keychain.delete(key: keychain.providerKey(for: id, suffix: suffix))
            },
            refresh: { [keychain, urlSession, customRefresh] providerID, refreshToken in
                if let customRefresh {
                    return try await customRefresh(providerID, refreshToken)
                }
                let clientID = keychain.read(key: keychain.providerKey(
                    for: providerID,
                    suffix: Suffix.clientID
                ))
                return try await ChatGPTTokenRefresh.perform(
                    refreshToken: refreshToken,
                    clientID: clientID,
                    urlSession: urlSession
                )
            }
        )
        hostIDKey = "\(serviceKey).provider.chatgpt.host_id"
    }

    // MARK: - Protocol

    func validAccessToken(providerID: UUID) async -> String? {
        if let existing = inFlight[providerID] {
            return await existing.value
        }
        let task = Task { [refreshStore] in
            await refreshStore.validAccessToken(id: providerID)
        }
        inFlight[providerID] = task
        let value = await task.value
        inFlight[providerID] = nil
        return value
    }

    func save(_ credential: ChatGPTCredential, providerID: UUID) {
        let expiryString = ISO8601DateFormatter().string(from: credential.expiry)
        let entries: [(String, String)] = [
            (Suffix.clientID, credential.clientID),
            (Suffix.accessToken, credential.accessToken),
            (Suffix.refreshToken, credential.refreshToken),
            (Suffix.idToken, credential.idToken),
            (Suffix.tokenExpiry, expiryString),
            (Suffix.scope, credential.scopes.joined(separator: " ")),
        ]
        for (suffix, value) in entries {
            keychain.save(key: key(providerID, suffix), value: value)
        }
    }

    func clear(providerID: UUID) {
        for suffix in Suffix.all {
            keychain.delete(key: key(providerID, suffix))
        }
    }

    func clientID(providerID: UUID) -> String? {
        read(providerID, Suffix.clientID)
    }

    func idToken(providerID: UUID) -> String? {
        read(providerID, Suffix.idToken)
    }

    /// The Keychain key under which the host ID is stored (test-visible).
    var hostIDKeyVisible: String {
        hostIDKey
    }

    func hostID() -> String? {
        if let stored = keychain.read(key: hostIDKey) {
            // iOS emits uppercase UUIDs; RFC 9562 §5.4 (cited by SIWC) is
            // lowercase, and OpenAI refuses to finalize a grant to a
            // non-conforming host ID. Normalize in place once.
            let normalized = stored.lowercased()
            if normalized != stored {
                keychain.save(key: hostIDKey, value: normalized)
            }
            return normalized
        }
        let created = "urn:uuid:\(UUID().uuidString.lowercased())"
        keychain.save(key: hostIDKey, value: created)
        return created
    }

    // MARK: - Plumbing

    private func read(_ providerID: UUID, _ suffix: String) -> String? {
        keychain.read(key: key(providerID, suffix))
    }

    private func key(_ providerID: UUID, _ suffix: String) -> String {
        keychain.providerKey(for: providerID, suffix: suffix)
    }
}
