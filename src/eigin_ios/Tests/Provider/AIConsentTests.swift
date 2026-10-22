@testable import Eigin
import Foundation
import Testing

@Suite("AI consent")
struct AIConsentTests {
    private let openAI = "https://api.openai.com/v1"

    private func makeStore() -> DefaultAIConsentStore {
        DefaultAIConsentStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    private func send(to baseURL: String, store: some AIConsentStore) async throws {
        let service = DefaultChatService(
            keychainService: FakeKeychainService(),
            providerCredentialResolver: StubProviderCredentialResolver(
                chatGPT: StubChatGPTCredentialStore()
            ),
            consentStore: store
        )
        _ = try await service.chatCompletionStream(
            baseURL: baseURL,
            providerID: UUID(),
            messages: [ChatMessage(role: "user", content: "Hi")],
            model: "gpt-test"
        )
    }

    @Test func refusesCloudProviderNotYetAllowed() async {
        await #expect(throws: AIConsentError.notAllowed) {
            try await send(to: openAI, store: makeStore())
        }
    }

    @Test func sendsOnceProviderIsAllowed() async {
        let store = makeStore()
        store.allow(baseURL: openAI)

        // Past the gate, the request stops at the missing key instead.
        await #expect(throws: ChatServiceError.self) {
            try await send(to: openAI, store: store)
        }
    }

    @Test func allowingOneProviderLeavesOthersAsking() {
        let store = makeStore()
        store.allow(baseURL: openAI)

        #expect(!store.needsConsent(baseURL: openAI))
        #expect(store.needsConsent(baseURL: ProviderPreset.relayBaseURL))
    }

    @Test func consentSurvivesRelaunch() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        DefaultAIConsentStore(defaults: defaults).allow(baseURL: openAI)

        #expect(DefaultAIConsentStore(defaults: defaults).isAllowed(baseURL: openAI))
    }

    @Test func onDeviceModelNeverAsks() {
        #expect(!makeStore().needsConsent(baseURL: "local://"))
    }
}
