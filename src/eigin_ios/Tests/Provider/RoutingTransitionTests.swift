@testable import Eigin
import Foundation
import Testing

@Suite("Routing transitions")
struct RoutingTransitionTests {
    private actor SuspendedHealth: RemoteModelHealthSource {
        private var suspendNext = true
        private var pending: CheckedContinuation<Void, Never>?
        private var observer: CheckedContinuation<Void, Never>?

        func health(for _: RoutingProvider) async -> [String: RemoteModelHealth] {
            if suspendNext {
                suspendNext = false
                await withCheckedContinuation { pending in
                    self.pending = pending
                    observer?.resume()
                    observer = nil
                }
            }
            return [:]
        }

        func waitUntilSuspended() async {
            if pending != nil { return }
            await withCheckedContinuation { observer = $0 }
        }

        func release() {
            pending?.resume()
            pending = nil
        }
    }

    @Test("retry retains demand from before its remote-health await")
    func retryDemandSnapshot() async {
        let provider = RoutingProvider(
            id: UUID(), name: "Cloud", baseURL: "https://cloud.test/v1",
            availableModels: ["gpt-4.1", "gpt-4.1-mini", "corti-s1"]
        )
        let conversation = UUID()
        func request(_ message: String) -> RouteRequest {
            RouteRequest(
                currentProviderID: provider.id, currentModel: "gpt-4.1", isAuto: true,
                requirements: RouteRequirements(), providers: [provider],
                conversationID: conversation, lastUserMessage: message
            )
        }
        let source = SuspendedHealth()
        let router = DefaultModelRouter(
            reachability: FakeNetworkReachability(), localModelReadiness: { false },
            now: { Date(timeIntervalSince1970: 0) }, remoteHealthSource: source
        )
        let simple = request("hi")
        let retry = Task {
            await router.retry(after: URLError(.timedOut), request: simple)
        }
        await source.waitUntilSuspended()
        let escalated = await router.resolve(request("think through this step by step, please"))
        #expect(escalated.model == "corti-s1")
        await source.release()
        #expect(await retry.value?.model == "gpt-4.1-mini")
    }

    @Test("an absent provider still establishes the fixed-reasoning conversation lock")
    func missingProviderReasoningLock() async {
        let provider = RoutingProvider(
            id: UUID(), name: "Mistral", baseURL: "https://api.mistral.ai/v1",
            availableModels: ["mistral-large-4"]
        )
        let conversation = UUID()
        func request(providers: [RoutingProvider]) -> RouteRequest {
            RouteRequest(
                currentProviderID: provider.id, currentModel: "mistral-large-4", isAuto: true,
                requirements: RouteRequirements(), providers: providers,
                conversationID: conversation
            )
        }
        let router = DefaultModelRouter(
            reachability: FakeNetworkReachability(), localModelReadiness: { false }
        )
        _ = await router.resolve(request(providers: []))
        #expect(await router.reasoningEffort(
            for: "mistral-large-4", request: request(providers: [provider])
        ) == .medium)
    }
}
