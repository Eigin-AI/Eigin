import EiginSDKBindings
import Foundation

public extension EiginSDK.Experimental.Agent {
    typealias ChatInput = ChatTurnInput
    typealias ChatContext = TurnContext
    typealias ChatEvent = ChatTurnEvent
    typealias ChatFailure = ChatTurnError

    /// Prepared platform capabilities for the next SDK-owned inference request.
    struct PreparedRequest: Sendable {
        public let providerID: String
        public let local: Bool
        public let routing: EiginSDK.Experimental.Routing.Request?
        public let services: EiginSDK.Experimental.Inference.RequestServices

        public init(providerID: String, local: Bool, routing: EiginSDK.Experimental.Routing.Request? = nil,
                    services: EiginSDK.Experimental.Inference.RequestServices)
        {
            self.providerID = providerID
            self.local = local
            self.routing = routing
            self.services = services
        }
    }

    /// Inline execution belongs to the original SDK turn and generation.
    final class InlineTools: Sendable {
        private let operation: InlineTurnOperation
        init(_ operation: InlineTurnOperation) {
            self.operation = operation
        }

        public func execute(_ call: EiginSDK.Experimental.Inference.ToolCall) async -> EiginSDK.Experimental.Inference.LocalToolResult {
            guard !Task.isCancelled else { return .init(toolCallId: call.id, content: "{}", isError: true) }
            return await operation.execute(call: call)
        }
    }

    /// One initial submission, automatic continuation, and independently accessible stop/checkpoint.
    final class ChatTurn: @unchecked Sendable {
        private let operation: ChatTurnOperation
        private let lifecycle: TurnLifecycle
        private let propagateStreamCancellation: Bool
        private let lock = NSLock()
        private var started = false

        public convenience init(
            input: ChatInput, router: EiginSDK.Experimental.Routing.Router,
            host: any TurnHost, presentation: (any TurnPresentation)? = nil,
            observe: @escaping @Sendable (ChatEvent) async -> Void = { _ in }
        ) {
            self.init(input: input, router: router, host: host, presentation: presentation,
                      observe: observe, scheduleTool: { $0() })
        }

        init(
            input: ChatInput, router: EiginSDK.Experimental.Routing.Router,
            host: any TurnHost, presentation: (any TurnPresentation)? = nil,
            observe: @escaping @Sendable (ChatEvent) async -> Void = { _ in },
            scheduleTool: @escaping TurnHostAdapter.ToolSchedule,
            beforeToolExecution: @escaping @Sendable () async -> Void = {}
        ) {
            let lifecycle = TurnLifecycle()
            self.lifecycle = lifecycle
            propagateStreamCancellation = input.propagateStreamCancellation
            operation = ChatTurnOperation(input: input, router: router,
                                          host: TurnHostAdapter(host: host, presentation: presentation, observe: observe, lifecycle: lifecycle, scheduleTool: scheduleTool, beforeToolExecution: beforeToolExecution))
            lifecycle.attach(operation)
        }

        deinit { operation.cancel() }

        public func run() async throws -> [OutputEntry] {
            let accepted = lock.withLock {
                guard !started else { return false }
                started = true
                return true
            }
            guard accepted else { throw ChatTurnError.AlreadyStarted }
            do {
                return try await withCancellation(cancel: { self.operation.cancel() }, mapError: turnConsumerError) {
                    try await self.operation.run()
                }
            } catch {
                if lifecycle.returnsStoppedOutput(for: error, propagateStreamCancellation: propagateStreamCancellation) { return [] }
                throw error
            }
        }

        public func stop() -> [OutputEntry] {
            lifecycle.stop()
            return operation.stop()
        }

        public func cancel() {
            operation.cancel()
        }

        public func checkpoint() -> [OutputEntry] {
            operation.checkpoint()
        }

        public func retainedOutput() -> [OutputEntry] {
            operation.retainedOutput()
        }

        public var roundsExecuted: UInt32 {
            operation.roundsExecuted()
        }

        public var partialContent: String {
            operation.partialContent()
        }

        public var activeModel: String {
            operation.activeModel()
        }
    }
}

private func turnConsumerError(_ error: any Error) -> any Error {
    guard let error = error as? ChatTurnError else { return error }
    switch error {
    case .Cancelled: return CancellationError()
    case let .Request(error): return requestConsumerError(error)
    default: return error
    }
}
