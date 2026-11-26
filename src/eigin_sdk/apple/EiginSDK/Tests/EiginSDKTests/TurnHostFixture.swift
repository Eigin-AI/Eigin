import EiginSDK

typealias FixtureAgent = EiginSDK.Experimental.Agent
typealias FixtureInference = EiginSDK.Experimental.Inference

enum TestTurnPresentation {
    case finishToolProse(hasProse: Bool)
    case beforeTool(call: FixtureInference.ToolCall)
    case afterTool
    case drain
}

/// Configurable platform and presentation boundaries for complete-turn tests.
struct TurnHostFixture: FixtureAgent.TurnHost, FixtureAgent.TurnPresentation {
    let prepareRequest: @Sendable (FixtureAgent.ChatContext, FixtureAgent.InlineTools) async throws -> FixtureAgent.PreparedRequest
    let notify: @Sendable (FixtureAgent.ChatEvent) async -> Void
    let present: @Sendable (TestTurnPresentation) async -> Void
    let execute: @Sendable (FixtureInference.ToolCall) async -> FixtureInference.LocalToolResult
    let refresh: @Sendable () async -> [FixtureInference.ToolDefinition]?
    let completion: @Sendable () async -> Bool
    let classify: @Sendable (FixtureInference.RequestFailure) -> FixtureAgent.TurnFailure

    init(
        prepare: @escaping @Sendable (FixtureAgent.ChatContext, FixtureAgent.InlineTools) async throws -> FixtureAgent.PreparedRequest,
        notify: @escaping @Sendable (FixtureAgent.ChatEvent) async -> Void = { _ in },
        present: @escaping @Sendable (TestTurnPresentation) async -> Void = { _ in },
        execute: @escaping @Sendable (FixtureInference.ToolCall) async -> FixtureInference.LocalToolResult,
        refreshTools: @escaping @Sendable () async -> [FixtureInference.ToolDefinition]?,
        completionRequested: @escaping @Sendable () async -> Bool = { false },
        classifyFailure: @escaping @Sendable (FixtureInference.RequestFailure) -> FixtureAgent.TurnFailure
    ) {
        prepareRequest = prepare
        self.notify = notify
        self.present = present
        self.execute = execute
        refresh = refreshTools
        completion = completionRequested
        classify = classifyFailure
    }

    func prepare(_ context: FixtureAgent.ChatContext, inline: FixtureAgent.InlineTools) async throws -> FixtureAgent.PreparedRequest {
        try await prepareRequest(context, inline)
    }

    func executeTool(_ call: FixtureInference.ToolCall) async -> FixtureInference.LocalToolResult {
        await execute(call)
    }

    func refreshTools() async -> [FixtureInference.ToolDefinition]? {
        await refresh()
    }

    func completionRequested() async -> Bool {
        await completion()
    }

    func classifyFailure(_ error: FixtureInference.RequestFailure) -> FixtureAgent.TurnFailure {
        classify(error)
    }

    func finishToolProse(hasProse: Bool) async {
        await present(.finishToolProse(hasProse: hasProse))
    }

    func beforeTool(_ call: FixtureInference.ToolCall) async {
        await present(.beforeTool(call: call))
    }

    func afterTool() async {
        await present(.afterTool)
    }

    func drain() async {
        await present(.drain)
    }
}

func makeTurn(
    input: EiginSDK.Experimental.Agent.ChatInput,
    router: EiginSDK.Experimental.Routing.Router,
    services: TurnHostFixture
) -> EiginSDK.Experimental.Agent.ChatTurn {
    .init(input: input, router: router, host: services, presentation: services, observe: services.notify)
}
