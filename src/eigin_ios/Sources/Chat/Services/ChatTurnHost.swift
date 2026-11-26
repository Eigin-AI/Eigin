import EiginSDK
import Foundation

/// Supplies app capabilities and converts turn input/output at the SDK boundary.
@MainActor
final class ChatTurnHost: EiginSDK.Experimental.Agent.TurnHost {
    typealias SDK = EiginSDK.Experimental.Agent
    let request: ChatTurnRequest
    let environment: ChatTurnEnvironment
    let mapping = TurnMessageMapping()
    nonisolated let errors = RequestHostErrors()
    let factory: InferenceRequestFactory
    var presentation: ChatTurnPresentationScope?
    private var tools: [ToolDefinition]?
    private var executor: ToolExecutor
    private var toolError: (any Error)?

    init(request: ChatTurnRequest, environment: ChatTurnEnvironment) {
        self.request = request
        self.environment = environment
        tools = request.tools
        executor = environment.executor
        factory = InferenceRequestFactory(context: environment.routing, errors: errors)
    }

    func makeTurn(presentation view: AgenticChatLoop, token: UUID) -> SDK.ChatTurn {
        presentation = .init(view: view, token: token)
        let initial = request.messages.enumerated().map { index, message in
            var value = MessagePreparationSDKConversion.message(message)
            value.sourceIndex = UInt64(index)
            return value
        }
        return SDK.ChatTurn(input: .init(
            messages: initial, tools: definitions(), model: request.model,
            initialInstruction: request.initialInstruction,
            allowInterruptionRecovery: !ProviderPreset.isLocal(request.provider.baseURL),
            propagateStreamCancellation: request.propagatesStreamCancellation
        ), router: environment.routing.policy, host: self, presentation: self, observe: observe)
    }

    func messages(_ output: [SDK.OutputEntry]) -> [ChatMessage] {
        mapping.messages(output)
    }

    nonisolated func classifyFailure(_ error: EiginSDK.Experimental.Inference.RequestFailure) -> SDK
        .TurnFailure
    {
        ChatTurnErrorConversion.failure(errors.restore(error))
    }

    func executeTool(_ call: EiginSDK.Experimental.Inference.ToolCall) async -> EiginSDK
        .Experimental.Inference.LocalToolResult
    {
        guard let view = presentation?.active else {
            return .init(toolCallId: call.id, content: "{}", isError: true)
        }
        let result = await view.executeToolCall(
            InferenceSDKConversion.call(call),
            agent: request.agent,
            executor: executor
        )
        return .init(
            toolCallId: result.toolCallID,
            content: result.content,
            isError: result.isError
        )
    }

    func refreshTools() async -> [EiginSDK.Experimental.Inference.ToolDefinition]? {
        guard let view = presentation?.active else { return nil }
        if let refresh = view.onToolsChanged {
            let updated = await refresh()
            return update(tools: updated.tools, executor: updated.executor)
        }
        return definitions()
    }

    func completionRequested() -> Bool {
        presentation?.active?.shouldTerminate?() == true
    }

    func prepare(_ context: SDK.ChatContext, inline: SDK.InlineTools) throws -> SDK
        .PreparedRequest
    {
        do {
            guard let view = presentation?.active else { throw CancellationError() }
            view.preparingRequest()
            if let toolError { throw toolError }
            var request = context.initialMessages.map { value -> ChatMessage in
                guard let index = value.sourceIndex
                else { preconditionFailure("Missing initial message provenance") }
                return MessagePreparationSDKConversion.restore(
                    .init(origin: .history(sourceIndex: index), message: value),
                    history: self.request.messages
                )
            }
            request += mapping.messages(context.output)
            let instruction = context.initialInstruction ?? context.continuation
                .map(ChatTurnErrorConversion.instruction)
            if let instruction, let hint = SystemHintBuilder.build(sections: [instruction]) {
                request = MessagePreparationSDKConversion.appendHint(hint, to: request)
            }
            request = try environment.paging.prepare(
                request,
                tools: tools,
                model: context.model,
                origin: ReasoningOrigin.destination(
                    providerID: self.request.provider.id,
                    baseURL: self.request.provider.baseURL,
                    model: context.model
                )
            )
            let dispatchedAt = ContinuousClock.now
            let prep = self.request.sentAt.map { $0.duration(to: dispatchedAt) }
            let runner = InlineToolRunner { call in
                let result = await inline.execute(InferenceSDKConversion.call(call))
                return ToolResult(
                    toolCallID: result.toolCallId,
                    content: result.content,
                    isError: result.isError
                )
            }
            return factory.prepare(
                chatService: environment.chatService, host: self.request.provider.baseURL,
                hostID: self.request.provider.id,
                messages: request, tools: tools, cacheKey: self.request.cacheKey,
                inlineToolRunner: runner,
                reported: { report, result in
                    RequestTiming.log(
                        prep: prep,
                        modelTTFT: report?.firstTokenSeconds.map { .seconds($0) },
                        result: result
                    )
                },
                routing: { requirements in
                    self.request.routing?
                        .forPreparedTurn(model: context.model, requirements: requirements) ??
                        RouteRequest(
                            agent: self.request.agent,
                            provider: self.request.provider,
                            model: context.model,
                            requirements: requirements,
                            conversationID: self.request.conversationID,
                            lastUserMessage: request.last(where: { $0.role == "user" })?.content
                        )
                }, refreshCatalog: environment.refreshCatalog
            )
        } catch { throw errors.encode(error) }
    }

    private func update(
        tools: [ToolDefinition],
        executor: ToolExecutor
    ) -> [EiginSDK.Experimental.Inference.ToolDefinition]? {
        self.tools = tools
        self.executor = executor
        return definitions()
    }

    private func definitions() -> [EiginSDK.Experimental.Inference.ToolDefinition]? {
        do { return try tools?.map(InferenceSDKConversion.tool) }
        catch { toolError = error; return nil }
    }
}
