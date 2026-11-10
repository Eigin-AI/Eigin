import Foundation
import Synchronization

final class FixtureReceiver: DiagnosticReceiver, Sendable {
    private let storage = Mutex<[DiagnosticEvent]>([])
    var events: [DiagnosticEvent] {
        storage.withLock { $0 }
    }

    func receive(event: DiagnosticEvent) {
        storage.withLock { $0.append(event) }
    }
}

final class WorkerFixtureState: Sendable {
    let entered = DispatchSemaphore(value: 0)
    let resume = DispatchSemaphore(value: 0)
    let finished = DispatchSemaphore(value: 0)
    let events = Mutex<[DiagnosticEvent]>([])
}

final class BlockingFixtureReceiver: DiagnosticReceiver, Sendable {
    let state: WorkerFixtureState
    init(state: WorkerFixtureState) {
        self.state = state
    }

    func receive(event: DiagnosticEvent) {
        precondition(!Thread.isMainThread)
        state.events.withLock { $0.append(event) }
        state.entered.signal()
        precondition(state.resume.wait(timeout: .now() + 10) == .success)
    }
}

@main
struct BindingErrors {
    static func main() async throws {
        var receiver: FixtureReceiver? = FixtureReceiver()
        weak let retained = receiver
        let defaults = DiagnosticOptions(minimumLevel: .debug, includePrivate: false)
        setDiagnosticReceiver(receiver: receiver!, options: defaults)
        receiver = nil
        precondition(retained != nil)
        emitDiagnosticFixture()
        precondition(retained!.events[0].fields.last!.value == nil)
        precondition(retained!.events[0].context?.operationId == "operation-1")
        updateDiagnosticOptions(options: .init(minimumLevel: .debug, includePrivate: true))
        emitDiagnosticFixture()
        precondition(retained!.events[1].fields.last!.value == "private fixture")
        updateDiagnosticOptions(options: defaults)
        emitDiagnosticFixture()
        precondition(retained!.events[2].fields.last!.value == nil)
        clearDiagnosticReceiver()
        precondition(retained == nil)

        let state = WorkerFixtureState()
        var blocking: BlockingFixtureReceiver? = BlockingFixtureReceiver(state: state)
        weak let inFlight = blocking
        setDiagnosticReceiver(receiver: blocking!, options: defaults)
        blocking = nil
        DispatchQueue.global().async {
            emitDiagnosticWorkerFixture()
            state.finished.signal()
        }
        precondition(state.entered.wait(timeout: .now() + 10) == .success)
        clearDiagnosticReceiver()
        precondition(inFlight != nil)
        state.resume.signal()
        precondition(state.finished.wait(timeout: .now() + 10) == .success)
        precondition(inFlight == nil)
        precondition(state.events.withLock { $0.count == 1 && $0[0].context?.operationId == "operation-1" })
        emitDiagnosticFixture()
        precondition(state.events.withLock { $0.count == 1 })

        let iterations = 10000
        func measure(_ label: String, _ body: () -> Void) {
            let start = ContinuousClock.now
            for _ in 0 ..< iterations {
                body()
            }
            print("Swift bridge \(label): \(iterations) events, \(start.duration(to: .now))")
        }
        measure("no receiver", emitDiagnosticFixture)
        final class NoopReceiver: DiagnosticReceiver, Sendable {
            func receive(event _: DiagnosticEvent) {}
        }
        setDiagnosticReceiver(receiver: NoopReceiver(), options: .init(minimumLevel: .error, includePrivate: false))
        measure("filtered", emitDiagnosticFixture)
        updateDiagnosticOptions(options: defaults)
        measure("public", emitDiagnosticFixture)
        updateDiagnosticOptions(options: .init(minimumLevel: .debug, includePrivate: true))
        measure("private enabled", emitDiagnosticFixture)
        clearDiagnosticReceiver()

        try await initialize()
        do {
            try await failInitializationFixture()
            fatalError("Expected a typed Rust error")
        } catch let InitializationError.Unavailable(reason) {
            precondition(reason == "binding fixture")
        }
        print("Swift diagnostic callbacks and typed Rust errors passed")
    }
}
