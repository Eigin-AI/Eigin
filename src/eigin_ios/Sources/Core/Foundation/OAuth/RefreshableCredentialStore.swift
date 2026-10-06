import Foundation

/// Tokens and metadata produced by an OAuth token refresh.
struct RefreshedCredentialTokens: Sendable, Equatable {
    let accessToken: String
    /// Fresh refresh token from a rotating provider; `nil` keeps the stored one.
    let refreshToken: String?
    let expiresIn: TimeInterval?
    let scope: String?
}

/// Refresh failures distinguish what should happen to the stored credential:
/// terminal errors mean the refresh token is dead (clear it — the durable
/// "needs reconnect" signal); transient errors mean the network failed (keep
/// the credential and surface an empty token for this request).
enum CredentialRefreshError: Error, Equatable {
    case terminal(String)
    case transient(String)
}

/// Storage and expiry-check machinery shared by refresh-token OAuth services
/// (integrations, MCP, ChatGPT). Each service keeps its own keychain suffix
/// namespace and supplies its refresh call; this type owns the read-check-
/// refresh-clear sequence. Integrations and MCP still carry their own copies
/// today — migrating them onto this is deferred until this shape has proven
/// itself with the ChatGPT store.
struct RefreshableCredentialStore: Sendable {
    private let read: @Sendable (UUID, String) -> String?
    private let write: @Sendable (UUID, String, String) -> Void
    private let remove: @Sendable (UUID, String) -> Void
    private let refresh: @Sendable (UUID, String) async throws -> RefreshedCredentialTokens

    /// Suffixes every credential store in this pattern carries; namespace-local
    /// extras (e.g. `client_id`) are read/written by the owning service directly.
    static let standardSuffixes = ["access_token", "refresh_token", "token_expiry", "scope"]

    init(
        read: @escaping @Sendable (UUID, String) -> String?,
        write: @escaping @Sendable (UUID, String, String) -> Void,
        remove: @escaping @Sendable (UUID, String) -> Void,
        refresh: @escaping @Sendable (UUID, String) async throws -> RefreshedCredentialTokens
    ) {
        self.read = read
        self.write = write
        self.remove = remove
        self.refresh = refresh
    }

    /// Whether any access token is stored under `id`.
    func hasCredential(id: UUID) -> Bool {
        read(id, "access_token") != nil
    }

    /// Reads the access token, refreshing it first when expiry (with a 60s
    /// skew) has passed. Returns `nil` when nothing is stored or the refresh
    /// failed — stored credentials survive a transient failure, terminal
    /// failures clear them.
    func validAccessToken(id: UUID) async -> String? {
        guard let accessToken = read(id, "access_token") else {
            return nil
        }

        let expiry = read(id, "token_expiry").flatMap { ISO8601DateFormatter().date(from: $0) }
        if let expiry, expiry.timeIntervalSinceNow > 60 {
            return accessToken
        }
        // Expired, missing, or unparseable expiry — don't trust the stored
        // token; refresh. A missing/dead refresh token clears the credential.
        return await refreshedAccessToken(id: id, accessToken: accessToken)
    }

    private func refreshedAccessToken(id: UUID, accessToken _: String) async -> String? {
        guard let refreshToken = read(id, "refresh_token") else {
            clear(id: id)
            return nil
        }

        do {
            let refreshed = try await refresh(id, refreshToken)
            write(id, "access_token", refreshed.accessToken)
            if let refreshToken = refreshed.refreshToken {
                write(id, "refresh_token", refreshToken)
            }
            if let expiresIn = refreshed.expiresIn {
                let expiry = Date.now.addingTimeInterval(expiresIn)
                write(id, "token_expiry", ISO8601DateFormatter().string(from: expiry))
            }
            if let scope = refreshed.scope {
                write(id, "scope", scope)
            }
            return refreshed.accessToken
        } catch CredentialRefreshError.terminal {
            clear(id: id)
            return nil
        } catch {
            // Transient (network, timeout, unknown) — keep the credential.
            return nil
        }
    }

    /// Deletes every standard-suffix entry under `id`. Only covers the
    /// standard set; namespace-specific extras are the owner's to clear.
    func clear(id: UUID) {
        for suffix in Self.standardSuffixes {
            remove(id, suffix)
        }
    }
}
