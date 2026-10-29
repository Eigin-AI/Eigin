#if DEBUG || EIGIN_DEV
import Foundation

/// In-memory `ProviderCredentialStoring` for tests: returns a canned access
/// token and records the credentials saved through it.
final class StubChatGPTCredentialStore: ChatGPTCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    /// Token handed out by `validAccessToken`; `nil` simulates an unusable
    /// credential (cleared, failed refresh, or never signed in).
    var stubbedToken: String? = "stub-access-token"
    private var savedCredentials: [UUID: ChatGPTCredential] = [:]

    func validAccessToken(providerID _: UUID) async -> String? {
        lock.withLock { stubbedToken }
    }

    func save(_ credential: ChatGPTCredential, providerID: UUID) async {
        lock.withLock { savedCredentials[providerID] = credential }
    }

    func clear(providerID: UUID) async {
        lock.withLock { savedCredentials[providerID] = nil }
    }

    func clientID(providerID: UUID) async -> String? {
        lock.withLock { savedCredentials[providerID]?.clientID }
    }

    func idToken(providerID: UUID) async -> String? {
        lock.withLock { savedCredentials[providerID]?.idToken }
    }

    func hostID() async -> String? {
        "urn:uuid:stub"
    }
}

/// In-memory `ProviderCredentialResolving` for tests: resolves every ChatGPT
/// or Infercom sign-in provider to the given store, everything else to `nil`.
final class StubProviderCredentialResolver: ProviderCredentialResolving, @unchecked Sendable {
    private let chatGPT: any ProviderCredentialStoring
    private let infercom: any ProviderCredentialStoring

    init(
        chatGPT: any ProviderCredentialStoring,
        infercom: any ProviderCredentialStoring = StubInfercomCredentialStore()
    ) {
        self.chatGPT = chatGPT
        self.infercom = infercom
    }

    func store(for baseURL: String, providerID _: UUID) -> (any ProviderCredentialStoring)? {
        if ProviderPreset.isChatGPTSubscription(baseURL) { return chatGPT }
        if ProviderPreset.isInfercomSignIn(baseURL) { return infercom }
        return nil
    }
}

/// In-memory `InfercomCredentialStoring` for tests: returns a canned access
/// token and records the credentials saved through it.
final class StubInfercomCredentialStore: InfercomCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    var stubbedToken: String? = "stub-infercom-token"
    private var savedCredentials: [UUID: InfercomCredential] = [:]
    private var cleared: Set<UUID> = []
    private var revoked: Set<UUID> = []

    func validAccessToken(providerID _: UUID) async -> String? {
        lock.withLock { stubbedToken }
    }

    func save(_ credential: InfercomCredential, providerID: UUID) async {
        lock.withLock { savedCredentials[providerID] = credential }
    }

    func clear(providerID: UUID) async {
        lock.withLock {
            savedCredentials[providerID] = nil
            cleared.insert(providerID)
        }
    }

    func revokeAndClear(providerID: UUID) async {
        await clear(providerID: providerID)
        lock.withLock { revoked.insert(providerID) }
    }

    func savedCredential(providerID: UUID) -> InfercomCredential? {
        lock.withLock { savedCredentials[providerID] }
    }

    var revokedProviderIDs: Set<UUID> {
        lock.withLock { revoked }
    }
}
#endif
