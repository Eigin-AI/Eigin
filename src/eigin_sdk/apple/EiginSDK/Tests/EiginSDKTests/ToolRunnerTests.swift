@testable import EiginSDK
import Testing

private typealias Runner = EiginSDK.Experimental.Agent

@Suite("Experimental tool execution") @MainActor
struct ToolRunnerTests {
    @Test(arguments: [false, true])
    func promptResumesBeforeExecution(forChat: Bool) async {
        let (responses, reply) = AsyncStream<Runner.Grant>.makeStream()
        let (requests, request) = AsyncStream<Void>.makeStream()
        var events: [String] = []
        let operation = Task {
            await Runner.runTool(permission: .ask, canPrompt: true, interactive: true, prompt: {
                request.yield(())
                var iterator = responses.makeAsyncIterator()
                return await iterator.next() ?? .deny
            }, granted: { events.append($0 ? "chat" : "once") }, interactionChanged: { _ in
                Issue.record("Prompted interactive execution is timed")
            }, execute: {
                events.append("execute")
                return "host result"
            })
        }
        var iterator = requests.makeAsyncIterator()
        _ = await iterator.next()
        #expect(events.isEmpty)
        reply.yield(forChat ? .forChat : .once)
        guard case let .executed(value) = await operation.value else {
            Issue.record("Expected the executor result")
            return
        }
        #expect(value == "host result")
        #expect(events == [forChat ? "chat" : "once", "execute"])
    }

    @Test func authorizedInteractiveWorkInheritsCallerCancellation() async {
        var interaction: [Bool] = []
        let operation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await Runner.runTool(permission: .always, canPrompt: false, interactive: true, prompt: {
                Issue.record("Unexpected prompt"); return .deny
            }, granted: { _ in Issue.record("Unexpected grant") }, interactionChanged: { interaction.append($0) }, execute: {
                Task.isCancelled
            })
        }
        guard case .executed(true) = await operation.value else {
            Issue.record("Expected the original task")
            return
        }
        #expect(interaction == [true, false])
    }

    @Test func timeoutCancelsWithoutJoiningTheExecutor() async {
        let gate = Gate()
        let (cancellations, report) = AsyncStream<Bool>.makeStream()
        let outcome: Runner.CallOutcome<Void> = await Runner.$startDeadline.withValue({ milliseconds in
            #expect(milliseconds == 30000)
            return .init(timeoutMs: 10)
        }) {
            await Runner.runTool(
                permission: .ask, canPrompt: true, interactive: true, prompt: { .once },
                granted: { _ in }, interactionChanged: { _ in Issue.record("Unexpected interaction") },
                execute: {
                    await gate.wait()
                    report.yield(Task.isCancelled)
                }
            )
        }
        gate.open()
        guard case .timedOut(seconds: 30) = outcome else {
            Issue.record("Expected the Rust deadline to expire")
            return
        }
        var iterator = cancellations.makeAsyncIterator()
        #expect(await iterator.next() == true)
    }
}

/// Remains suspended across cancellation, like a native tool that cannot be interrupted.
@MainActor private final class Gate {
    var opened = false
    var waiter: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !opened else { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func open() {
        opened = true
        waiter?.resume()
        waiter = nil
    }
}
