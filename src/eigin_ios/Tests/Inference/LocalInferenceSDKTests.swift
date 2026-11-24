@testable import Eigin
import EiginSDK
import Foundation
import Testing

@Suite("Local inference SDK integration")
@MainActor
struct LocalInferenceSDKTests {
    private typealias SDK = EiginSDK.Experimental.Inference

    @Test func downloadedModelRemainsDiscoverableBeforeRuntimeLoading() async throws {
        let client = LocalClient(inference: .init { _, _ in
            Issue.record("Discovery must not load the runtime")
            throw CancellationError()
        }, modelDownloaded: { true })
        let available = try await client.fetchModels()
        let providerID = UUID()
        let router = DefaultModelRouter(
            reachability: FakeNetworkReachability(), localModelReadiness: { true }
        )
        let route = await router.resolve(RouteRequest(
            currentProviderID: providerID, currentModel: "mistral-small-latest", isAuto: true,
            requirements: RouteRequirements(), providers: [RoutingProvider(
                id: providerID, name: "Local", baseURL: "local://",
                availableModels: available, enabledModels: ["gemma-4-e2b"]
            )]
        ))
        #expect(route.providerID == providerID)
        #expect(route.model == "gemma-4-e2b")
        #expect(try await LocalClient(modelDownloaded: { false }).fetchModels().isEmpty)
    }

    @Test func localClientUsesSDKValuesAndInvokesInlineToolsOnce() async throws {
        var executions = 0
        let provider = SDK.Local { input, tools in
            #expect(input.model == "gemma-4-e2b")
            #expect(input.messages.first?.content == "question")
            #expect(input.messages.first?.images.isEmpty == true)
            let result = try await tools?.execute(call: .init(
                id: "call",
                kind: "function",
                name: "web_search",
                arguments: "{}"
            ))
            #expect(result?.content == "tool result")
            let output = LocalTestOutput()
            return .init(next: { await output.next() }, cancel: {})
        }
        let client = LocalClient(inference: provider)
        let runner = InlineToolRunner { call in
            executions += 1
            return ToolResult(toolCallID: call.id, content: "tool result", isError: false)
        }
        let stream = try await client.chatCompletionEventStream(
            messages: [ChatMessage(role: "user", content: "question")], model: "gemma-4-e2b",
            tools: nil, inlineToolRunner: runner
        )
        var content = ""
        var finished = false
        for try await event in stream {
            switch event {
            case .contentDelta(let text): content += text
            case .finished: finished = true
            default: break
            }
        }
        #expect(content == "reply")
        #expect(finished)
        #expect(executions == 1)
    }

    @Test func availabilityErrorsRetainHostPresentation() async throws {
        let client = LocalClient(inference: .init { _, _ in
            throw SDK.Failure.LocalUnavailable(code: "not_downloaded", reason: "Download")
        })
        do {
            _ = try await client.chatCompletionEventStream(
                messages: [],
                model: "gemma-4-e2b",
                tools: nil
            )
            Issue.record("Expected missing download")
        } catch LocalClientError.modelNotDownloaded {}
    }

    @Test func removedSavedModelDoesNotRunGemma() async throws {
        let client = LocalClient(inference: .init { _, _ in
            Issue.record("Unsupported saved selection must not execute")
            throw CancellationError()
        })
        do {
            _ = try await client.chatCompletionEventStream(
                messages: [],
                model: "apple-foundation-model",
                tools: nil
            )
            Issue.record("Expected unsupported model")
        } catch LocalClientError.unsupportedModel {}
    }

    @Test func historyConversionPreservesToolNamesAndAdjacentRoles() throws {
        let call = ToolCall(
            id: "call",
            type: "function",
            function: .init(name: "web_search", arguments: "{}")
        )
        let messages = [
            ChatMessage(role: "user", content: "one"),
            ChatMessage(role: "user", content: "two"),
            ChatMessage(role: "assistant", content: nil, toolCalls: [call]),
            ChatMessage(role: "tool", content: "result", toolCallID: "call"),
        ]
        let input = try LocalInferenceSDKConversion.input(
            messages: messages,
            model: "gemma-4-e2b",
            tools: nil
        )
        let runtime = LocalClient.convertMessages(input.messages)
        #expect(runtime.count == 3)
        #expect(runtime[0].content == "one\ntwo")
        #expect(runtime[1].content == LocalClient.renderGemmaToolCall(
            name: "web_search",
            jsonArgs: "{}"
        ))
        #expect(runtime[2].content == LocalClient.renderGemmaToolResponse(
            name: "web_search",
            content: "result"
        ))
    }
}

private actor LocalTestOutput {
    private var index = 0
    func next() -> EiginSDK.Experimental.Inference.Event? {
        defer { index += 1 }
        return switch index {
        case 0: .contentDelta(text: "reply")
        case 1: .finished(reason: .stop)
        default: nil
        }
    }
}
