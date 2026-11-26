import EiginSDKBindings
import Foundation

/// Schedules turn capabilities and cancels their Swift tasks by binding operation ID.
final class TurnHostAdapter: TurnHost, @unchecked Sendable {
    typealias ToolSchedule = @Sendable (@escaping @Sendable () -> Void) -> Void
    private let beforeToolExecution: @Sendable () async -> Void
    private let scheduleTool: ToolSchedule
    typealias Agent = EiginSDK.Experimental.Agent
    private let host: any Agent.TurnHost
    private let presentation: (any Agent.TurnPresentation)?
    private let observe: @Sendable (Agent.ChatEvent) async -> Void
    private let lifecycle: TurnLifecycle
    private let lock = NSLock()
    private var operations: [UInt64: RequestWork] = [:]

    init(host: any Agent.TurnHost, presentation: (any Agent.TurnPresentation)?,
         observe: @escaping @Sendable (Agent.ChatEvent) async -> Void, lifecycle: TurnLifecycle,
         scheduleTool: @escaping ToolSchedule, beforeToolExecution: @escaping @Sendable () async -> Void)
    {
        self.beforeToolExecution = beforeToolExecution
        self.scheduleTool = scheduleTool
        self.host = host
        self.presentation = presentation
        self.observe = observe
        self.lifecycle = lifecycle
    }

    private func run(
        _ id: UInt64, cancelled: @escaping @Sendable () -> Void = {},
        schedule: ToolSchedule = { $0() },
        body: @escaping @Sendable () async -> Void
    ) {
        let work = RequestWork()
        lock.withLock { operations[id] = work }
        schedule { [weak self] in
            work.launch(onCancelled: cancelled) { [weak self] in
                await body()
                _ = self?.lock.withLock { self?.operations.removeValue(forKey: id) }
            }
        }
    }

    func prepare(operationId: UInt64, context: TurnContext, inline: InlineTurnOperation, completion: TurnPrepareCallback) {
        run(operationId) { [host, lifecycle] in
            do {
                try lifecycle.checkPreparation()
                let prepared = try await host.prepare(context, inline: .init(inline))
                try Task.checkCancellation()
                _ = completion.succeed(providerId: prepared.providerID, local: prepared.local,
                                       routing: prepared.routing, host: RequestHostAdapter(services: prepared.services))
            } catch { completion.fail(error: requestHostError(error)) }
        }
    }

    func notify(operationId: UInt64, event: ChatTurnEvent, completion: TurnNotifyCallback) {
        run(operationId) { [observe, lifecycle] in
            lifecycle.willObserve(event)
            await observe(event)
            lifecycle.didObserve(event)
            _ = completion.succeed()
        }
    }

    func present(operationId: UInt64, work: TurnPresentation, completion: TurnNotifyCallback) {
        run(operationId) { [presentation, lifecycle] in
            switch work {
            case let .finishToolProse(hasProse): await presentation?.finishToolProse(hasProse: hasProse)
            case let .beforeTool(call): await presentation?.beforeTool(call)
            case .afterTool: await presentation?.afterTool()
            case .drain: await presentation?.drain()
            }
            lifecycle.didPresent(work)
            _ = completion.succeed()
        }
    }

    func execute(operationId: UInt64, call: InferenceToolCall, completion: TurnToolCallback) {
        run(operationId, cancelled: {
            _ = completion.succeed(result: .init(toolCallId: call.id, content: "{}", isError: true))
        }, schedule: scheduleTool) { [host, lifecycle, beforeToolExecution] in
            await beforeToolExecution()
            guard !Task.isCancelled else {
                _ = completion.succeed(result: .init(toolCallId: call.id, content: "{}", isError: true))
                return
            }
            let result = await host.executeTool(call)
            lifecycle.cancelIfCurrentTaskCancelled()
            _ = completion.succeed(result: result)
        }
    }

    func refreshTools(operationId: UInt64, completion: TurnToolsCallback) {
        run(operationId) { [host, lifecycle] in
            let tools = await host.refreshTools()
            lifecycle.latchCancellation()
            _ = completion.succeed(tools: tools)
        }
    }

    func signals(operationId: UInt64, boundary: TurnSignalBoundary, completion: TurnSignalsCallback) {
        run(operationId) { [host, lifecycle] in
            let signals = await lifecycle.signals(at: boundary) { await host.completionRequested() }
            _ = completion.succeed(signals: signals)
        }
    }

    func classifyFailure(error: RequestError) -> EiginSDKBindings.TurnFailure {
        host.classifyFailure(error)
    }

    func cancelOperation(operationId: UInt64) {
        lock.withLock { operations.removeValue(forKey: operationId) }?.cancel()
    }
}
