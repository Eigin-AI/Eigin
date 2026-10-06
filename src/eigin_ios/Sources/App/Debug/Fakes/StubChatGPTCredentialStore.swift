#if DEBUG || EIGIN_DEV
import Foundation

/// In-memory `ProviderCredentialStoring` for tests: returns a canned access
/// token and records the credentials saved through it.
final class StubChatGPTCredentialStore: ProviderCredentialStoring, @unchecked Sendable {
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
#endif

/// In-memory `ProviderCredentialResolving` for tests: resolves every ChatGPT
/// provider to the given store, everything else to `nil`.
final class StubProviderCredentialResolver: ProviderCredentialResolving, @unchecked Sendable {
    private let chatGPT: any ProviderCredentialStoring

    init(chatGPT: any ProviderCredentialStoring) {
        self.chatGPT = chatGPT
    }

    func store(for baseURL: String, providerID _: UUID) -> (any ProviderCredentialStoring)? {
        ProviderPreset.isChatGPTSubscription(baseURL) ? chatGPT : nil
    }
}
