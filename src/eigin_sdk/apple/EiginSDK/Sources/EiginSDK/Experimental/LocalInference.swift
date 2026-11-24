import EiginSDKBindings
import Foundation

public extension EiginSDK.Experimental.Inference {
    typealias LocalToolResult = EiginSDKBindings.LocalToolResult
    typealias LocalTools = EiginSDKBindings.LocalToolSession

    /// Host runtime stream. Cancellation must stop native generation as well as Swift work.
    struct LocalSession: Sendable {
        public let next: @Sendable () async throws -> Event?
        public let cancel: @Sendable () -> Void

        public init(next: @escaping @Sendable () async throws -> Event?, cancel: @escaping @Sendable () -> Void) {
            self.next = next
            self.cancel = cancel
        }
    }

    /// Host-owned model loading and execution, consumed through the shared inference stream.
    final class Local: Sendable {
        public typealias Prepare = @Sendable (Input, LocalTools?) async throws -> LocalSession
        public typealias ExecuteTool = @Sendable (ToolCall) async throws -> LocalToolResult
        private let provider: LocalInferenceProvider

        public init(prepare: @escaping Prepare) {
            provider = LocalInferenceProvider(executor: LocalExecutor(prepare: prepare))
        }

        /// Opens the runtime with a fresh request-scoped inline tool handler.
        public func stream(_ input: Input, executeTool: ExecuteTool? = nil) async throws -> Stream {
            let tools = executeTool.map { LocalTools(executor: LocalToolsExecutor(execute: $0)) }
            let operation = provider.stream(input: input, tools: tools)
            try await withCancellation(cancel: { operation.cancel() }, mapError: inferenceError) {
                try await operation.open()
            }
            return Stream(operation)
        }
    }
}

private typealias Inference = EiginSDK.Experimental.Inference

/// Serializes task installation with cancellation; host callbacks run outside the lock.
private final class LocalWork: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var task: Task<Void, Never>?
    private var session: Inference.LocalSession?

    func launch(_ body: @escaping @Sendable () async -> Void) {
        lock.withLock {
            guard !cancelled else { return }
            task = Task { await body() }
        }
    }

    func install(_ value: Inference.LocalSession) -> Bool {
        let accepted = lock.withLock {
            guard !cancelled else { return false }
            session = value
            return true
        }
        if !accepted { value.cancel() }
        return accepted
    }

    func next() async throws -> Inference.Event? {
        let value = lock.withLock { session }
        guard let value else { throw InferenceError.Cancelled }
        return try await value.next()
    }

    func cancel() {
        let resources = lock.withLock {
            cancelled = true
            let resources = (task, session)
            task = nil
            session = nil
            return resources
        }
        resources.0?.cancel()
        resources.1?.cancel()
    }
}

private final class LocalExecutor: LocalInferenceExecutor, @unchecked Sendable {
    private let prepare: Inference.Local.Prepare
    private let lock = NSLock()
    private var requests: [UInt64: LocalWork] = [:]

    init(prepare: @escaping Inference.Local.Prepare) {
        self.prepare = prepare
    }

    func startRequest(id: UInt64, input: Inference.Input, tools: LocalToolSession?, completion: LocalOpenCallback) {
        let work = LocalWork()
        lock.withLock { requests[id] = work }
        work.launch { [prepare] in
            do {
                let session = try await prepare(input, tools)
                if work.install(session) { completion.succeed() }
                else { completion.fail(error: .Cancelled) }
            } catch { completion.fail(error: localFailure(error)) }
        }
    }

    func read(id: UInt64, completion: LocalEventCallback) {
        guard let work = lock.withLock({ requests[id] }) else {
            completion.fail(error: .Cancelled)
            return
        }
        work.launch {
            do { try completion.succeed(event: await work.next()) }
            catch { completion.fail(error: localFailure(error)) }
        }
    }

    func close(id: UInt64) {
        lock.withLock { requests.removeValue(forKey: id) }?.cancel()
    }
}

private final class LocalToolsExecutor: LocalToolExecutor, Sendable {
    private let run: Inference.Local.ExecuteTool
    private let work = LocalWork()

    init(execute: @escaping Inference.Local.ExecuteTool) {
        run = execute
    }

    func execute(call: Inference.ToolCall, completion: LocalToolCallback) {
        work.launch { [run] in
            do { try completion.succeed(result: await run(call)) }
            catch { completion.fail(error: localFailure(error)) }
        }
    }

    func cancel() {
        work.cancel()
    }
}

private func localFailure(_ error: any Error) -> InferenceError {
    if error is CancellationError { return .Cancelled }
    return error as? InferenceError ?? .LocalRuntime(reason: error.localizedDescription)
}
