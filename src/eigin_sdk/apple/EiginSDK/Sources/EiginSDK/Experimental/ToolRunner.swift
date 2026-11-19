import EiginSDKBindings

public extension EiginSDK.Experimental.Agent {
    typealias Permission = CallPermission
    typealias Grant = CallGrant
    typealias Denial = CallDenial

    /// The host keeps its executor result and translates failures for presentation.
    enum CallOutcome<Value: Sendable>: Sendable {
        case executed(Value)
        case denied(Denial)
        case timedOut(seconds: UInt32)
    }

    /// Runs one call on the main actor. Only pre-authorized interactive work inherits the caller's task.
    @MainActor static func runTool<Value: Sendable>(
        permission: Permission, canPrompt: Bool, interactive: Bool,
        prompt: @MainActor () async -> Grant, granted: @MainActor (_ forChat: Bool) -> Void,
        interactionChanged: @MainActor (_ awaiting: Bool) -> Void,
        execute: @escaping @MainActor () async -> Value
    ) async -> CallOutcome<Value> {
        var action = agentAuthorizeCall(permission: permission, canPrompt: canPrompt, interactive: interactive)
        while true {
            switch action {
            case .prompt:
                action = agentResolveCallPrompt(response: await prompt())
            case let .denied(reason): return .denied(reason)
            case .interactive:
                interactionChanged(true)
                defer { interactionChanged(false) }
                return .executed(await execute())
            case let .timed(timeoutMs, scope):
                if let scope { granted(scope == .forChat) }
                return await runTimed(timeoutMs: timeoutMs, execute: execute)
            }
        }
    }
}

extension EiginSDK.Experimental.Agent {
    @TaskLocal static var startDeadline: @Sendable (UInt32) -> ToolCallDeadline = { ToolCallDeadline(timeoutMs: $0) }

    /// Starts host work after the Rust clock starts, and cancels without joining on expiry.
    @MainActor private static func runTimed<Value: Sendable>(
        timeoutMs: UInt32, execute: @escaping @MainActor () async -> Value
    ) async -> CallOutcome<Value> {
        let deadline = startDeadline(timeoutMs)
        let work = Task { @MainActor in
            let result = await execute()
            deadline.complete()
            return result
        }
        guard await deadline.completedInTime() else {
            work.cancel()
            return .timedOut(seconds: timeoutMs / 1000)
        }
        return .executed(await work.value)
    }
}
