import Foundation

/// Keychain-backed storage and refresh for Infercom sign-in credentials.
///
/// What is stored is the *exchanged* API token (inference Bearer) and the
/// *login* refresh token — it is the login token that rotates, and losing
/// it after a rotation forces a full re-login.
actor DefaultInfercomCredentialStore: InfercomCredentialStoring {
    enum Suffix {
        static let accessToken = "access_token"
        static let refreshToken = "refresh_token"
        static let tokenExpiry = "token_expiry"
    }

    private let keychain: any KeychainService
    private let urlSession: URLSession
    let refreshStore: RefreshableCredentialStore
    /// Serializes refreshes per provider; queued callers share the result.
    private var inFlight: [UUID: Task<String?, Never>] = [:]

    /// `customRefresh` swaps the refresh+re-exchange leg (tests).
    init(
        keychain: any KeychainService,
        urlSession: URLSession = .shared,
        customRefresh: (@Sendable (UUID, String) async throws
            -> RefreshedCredentialTokens)? = nil
    ) {
        self.keychain = keychain
        self.urlSession = urlSession
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
            refresh: { [urlSession, customRefresh] id, refreshToken in
                if let customRefresh {
                    return try await customRefresh(id, refreshToken)
                }
                return try await Self.refreshAndExchange(
                    refreshToken: refreshToken,
                    urlSession: urlSession
                )
            }
        )
    }

    /// Refresh grant at the login server, then re-exchange the fresh login
    /// access token for a new API token. The rotated login refresh token is
    /// returned so the shared store persists it — losing it forces re-login.
    private static func refreshAndExchange(
        refreshToken: String,
        urlSession: URLSession
    ) async throws -> RefreshedCredentialTokens {
        let refreshed = try await InfercomTokenRefresh.perform(
            refreshToken: refreshToken,
            urlSession: urlSession
        )
        let exchanged = try await DefaultInfercomSignInService(urlSession: urlSession)
            .exchange(accessToken: refreshed.accessToken)
        // Same malformed-response argument as at sign-in: no expires_in
        // must not pawn an already-expired credential on the store. Transient
        // rather than terminal — the credential itself is fine.
        guard let expiresIn = exchanged.expiresIn else {
            throw CredentialRefreshError.transient("Exchange response has no expires_in")
        }
        return RefreshedCredentialTokens(
            accessToken: exchanged.apiToken,
            refreshToken: refreshed.refreshToken,
            // The API token's lifetime is what gates the next refresh.
            expiresIn: expiresIn,
            scope: nil
        )
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

    func save(_ credential: InfercomCredential, providerID: UUID) {
        let expiryString = ISO8601DateFormatter().string(from: credential.expiry)
        let entries: [(String, String)] = [
            (Suffix.accessToken, credential.apiToken),
            (Suffix.refreshToken, credential.refreshToken),
            (Suffix.tokenExpiry, expiryString),
        ]
        for (suffix, value) in entries {
            keychain.save(key: key(providerID, suffix), value: value)
        }
    }

    func clear(providerID: UUID) {
        // Delegated so removal can't drift from what the shared store reads.
        refreshStore.clear(id: providerID)
    }

    func revokeAndClear(providerID: UUID) async {
        if let refreshToken = read(providerID, Suffix.refreshToken) {
            await InfercomTokenRevocation.perform(
                refreshToken: refreshToken,
                urlSession: urlSession
            )
        }
        clear(providerID: providerID)
    }

    /// The stored refresh token, for tests.
    func storedRefreshToken(providerID: UUID) -> String? {
        read(providerID, Suffix.refreshToken)
    }

    // MARK: - Plumbing

    private func read(_ providerID: UUID, _ suffix: String) -> String? {
        keychain.read(key: key(providerID, suffix))
    }

    private func key(_ providerID: UUID, _ suffix: String) -> String {
        keychain.providerKey(for: providerID, suffix: suffix)
    }
}
