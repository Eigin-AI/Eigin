@testable import Eigin
import EiginSDK
import Foundation
import Testing

@Suite("Gemma adapter integration", .serialized)
@MainActor
struct GemmaLocalInferenceTests {
    private typealias SDK = EiginSDK.Experimental.Inference

    private func client(_ host: NativeGemmaFixture) -> LocalClient {
        LocalClient(inference: .init { input, tools in
            try await GemmaLocalInference.prepare(input, tools: tools, host: host)
        })
    }

    @Test func resourceChecksPrecedeLoading() async throws {
        let host = NativeGemmaFixture()
        host.supported = false
        do {
            _ = try await client(host).chatCompletionEventStream(
                messages: [],
                model: "gemma-4-e2b",
                tools: nil
            )
            Issue.record("Expected resource refusal")
        } catch LocalClientError.deviceUnsupported {}
        #expect(host.loads == 0)
        host.supported = true
        host.inferenceDownloaded = false
        do {
            _ = try await client(host).chatCompletionEventStream(
                messages: [],
                model: "gemma-4-e2b",
                tools: nil
            )
            Issue.record("Expected missing download")
        } catch LocalClientError.modelNotDownloaded {}
        #expect(host.loads == 0)
    }

    @Test func cancellationStopsGenerationAndBalancesActivity() async throws {
        let host = NativeGemmaFixture()
        host.suspend = true
        let client = client(host)
        let task = Task {
            let stream = try await client.chatCompletionEventStream(
                messages: [],
                model: "gemma-4-e2b",
                tools: nil
            )
            for try await _ in stream {}
        }
        try await wait { host.generating }
        task.cancel()
        do { try await task.value } catch is CancellationError {}
        try await wait { host.stopped && host.active == 0 }
        #expect(host.loads == 1)
        #expect(host.begins == 1)
        #expect(host.ends == 1)
    }

    @Test func concurrentRequestsKeepToolRunnersAndRecordedExchangesIsolated() async throws {
        let host = NativeGemmaFixture()
        let client = client(host)
        let first = Task { try await runToolTurn("first", client: client) }
        let second = Task { try await runToolTurn("second", client: client) }
        let outputs = try await [first.value, second.value]
        #expect(outputs == ["first", "second"])
        try await wait { host.active == 0 }
        #expect(host.maximumNativeGenerations == 1)
        #expect(host.begins == 2)
        #expect(host.ends == 2)
        #expect(GemmaToolBridgeRunner.current == nil)
    }

    @Test func runtimeEOFStillFinishesAndThrownFailureReleasesActivity() async throws {
        let host = NativeGemmaFixture()
        host.empty = true
        let stream = try await client(host).chatCompletionEventStream(
            messages: [],
            model: "gemma-4-e2b",
            tools: nil
        )
        var finished = 0
        for try await event in stream {
            if case .finished = event { finished += 1 }
        }
        #expect(finished == 1)
        try await wait { host.active == 0 }
        host.fail = true
        do {
            let stream = try await client(host).chatCompletionEventStream(
                messages: [],
                model: "gemma-4-e2b",
                tools: nil
            )
            for try await _ in stream {}
            Issue.record("Expected runtime failure")
        } catch SDK.Failure.LocalRuntime {}
        try await wait { host.active == 0 }
        #expect(host.begins == host.ends)
    }

    private func runToolTurn(_ label: String, client: LocalClient) async throws -> String {
        let round = EiginSDK.Experimental.Agent.Round()
        let output = EiginSDK.Experimental.Agent.Output()
        let runner = InlineToolRunner { call in
            #expect(call.function.arguments.contains(label))
            let result = ToolResult(toolCallID: call.id, content: label, isError: false)
            do {
                let exchange = try round.recordInlineExchange(
                    call: InferenceSDKConversion.call(call),
                    result: .init(toolCallId: result.toolCallID, content: result.content)
                )
                _ = try output.recordInlineExchange(messages: exchange)
            } catch { Issue.record(error) }
            return result
        }
        let tool = ToolDefinition(
            name: "search_knowledge",
            description: "Search",
            parameters: .init(type: "object")
        )
        let stream = try await client.chatCompletionEventStream(
            messages: [ChatMessage(role: "user", content: label)], model: "gemma-4-e2b",
            tools: [tool], inlineToolRunner: runner
        )
        var text = ""
        for try await event in stream {
            try round.acceptEvent(event: InferenceSDKConversion.event(event))
            if case .contentDelta(let value) = event { text += value }
        }
        #expect(output.output().map(\.message).map(\.role) == ["assistant", "tool"])
        #expect(output.output().map(\.message)[1].content == label)
        #expect(output.output().map(\.message)[0].toolCalls?.first?.id == output.output()
            .map(\.message)[1].toolCallId)
        return text
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

/// Replaces model files and native decoding; SDK, adapter, session gate, and tool bridge stay real.
@MainActor
private final class NativeGemmaFixture: GemmaInferenceHost {
    var inferenceDownloaded = true
    var inferenceLoaded = false
    var supported = true
    var suspend = false
    var empty = false
    var fail = false
    var loads = 0
    var begins = 0
    var ends = 0
    var active = 0
    var generating = false
    var stopped = false
    var nativeGenerations = 0
    var maximumNativeGenerations = 0
    private let session = GemmaGenerationSession()

    func hasRequiredRAM() -> Bool {
        supported
    }

    func insufficientResourcesDetail() -> String {
        "Insufficient test memory"
    }

    func load() async throws {
        loads += 1; inferenceLoaded = true
    }

    func beginGeneration() {
        begins += 1; active += 1
    }

    func endGeneration() {
        ends += 1; active -= 1
    }

    func generate(
        _ messages: [GemmaRuntime.Message],
        tools: BridgedToolBox,
        runner: InlineToolRunner?
    ) async throws -> AsyncStream<String> {
        if fail { throw URLError(.cannotDecodeContentData) }
        return session.stream(runner: runner) { continuation in
            await self.decode(messages, tools: tools, continuation: continuation)
        }
    }

    private func decode(
        _ messages: [GemmaRuntime.Message],
        tools: BridgedToolBox,
        continuation: AsyncStream<String>.Continuation
    ) async {
        generating = true
        nativeGenerations += 1
        maximumNativeGenerations = max(maximumNativeGenerations, nativeGenerations)
        defer { stopped = true; nativeGenerations -= 1 }
        if suspend {
            try? await Task.sleep(for: .seconds(60))
        } else if !empty {
            #expect(tools.tools.count == 1)
            do {
                try await Task.sleep(for: .milliseconds(20))
                let result = try await runBridgedTool(
                    name: "search_knowledge",
                    arguments: ["query": messages.last?.content ?? ""]
                )
                continuation.yield(result as? String ?? "")
            } catch { Issue.record(error) }
        }
    }
}
