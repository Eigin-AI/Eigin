import FixtureBindings
import Foundation
import Synchronization
import XCTest

final class DiagnosticTests: ContractTestCase {
    func testCallbackPreservesContextAndPrivacyPolicy() throws {
        let receiver = RecordingReceiver()
        setDiagnosticReceiver(receiver: receiver, options: defaults)
        defer { clearDiagnosticReceiver() }

        emitDiagnosticFixture()
        updateDiagnosticOptions(options: .init(minimumLevel: .debug, includePrivate: true))
        emitDiagnosticFixture()
        updateDiagnosticOptions(options: defaults)
        emitDiagnosticFixture()

        let events = receiver.events
        XCTAssertEqual(events.count, 3)
        let first = try XCTUnwrap(events.first)
        XCTAssertEqual(first.level, .info)
        XCTAssertEqual(first.context?.operationId, "operation-1")
        XCTAssertEqual(first.context?.parentOperationId, "parent-1")
        let publicField = try XCTUnwrap(first.fields.first { $0.name == "status" })
        XCTAssertEqual(publicField.privacy, .public)
        XCTAssertEqual(publicField.value, "ok")
        let expected: [String?] = [nil, "private fixture", nil]
        for (event, value) in zip(events, expected) {
            let field = try XCTUnwrap(event.fields.first { $0.name == "detail" })
            XCTAssertEqual(field.privacy, .private)
            XCTAssertEqual(field.value, value)
        }
    }

    func testFilteringReplacementAndClearControlDelivery() {
        let original = RecordingReceiver()
        let replacement = RecordingReceiver()
        setDiagnosticReceiver(receiver: original, options: defaults)
        defer { clearDiagnosticReceiver() }
        emitDiagnosticFixture()
        updateDiagnosticOptions(options: .init(minimumLevel: .error, includePrivate: false))
        emitDiagnosticFixture()
        XCTAssertEqual(original.events.count, 1)

        setDiagnosticReceiver(receiver: replacement, options: defaults)
        emitDiagnosticFixture()
        XCTAssertEqual(original.events.count, 1)
        XCTAssertEqual(replacement.events.count, 1)
        clearDiagnosticReceiver()
        emitDiagnosticFixture()
        XCTAssertEqual(replacement.events.count, 1)
    }

    func testRegistrationRetainsReceiverUntilClear() throws {
        var receiver: RecordingReceiver? = RecordingReceiver()
        weak var retained = receiver
        try setDiagnosticReceiver(receiver: XCTUnwrap(receiver), options: defaults)
        defer { clearDiagnosticReceiver() }
        receiver = nil
        XCTAssertNotNil(retained)
        emitDiagnosticFixture()
        XCTAssertEqual(retained?.events.count, 1)
        clearDiagnosticReceiver()
        XCTAssertNil(retained)
    }

    func testWorkerCallbackRetainsReceiverUntilInFlightDeliveryFinishes() throws {
        let state = WorkerState()
        var receiver: BlockingReceiver? = BlockingReceiver(state: state)
        weak var retained = receiver
        try setDiagnosticReceiver(receiver: XCTUnwrap(receiver), options: defaults)
        receiver = nil
        defer {
            clearDiagnosticReceiver()
            state.resume.signal()
        }
        DispatchQueue.global().async {
            emitDiagnosticWorkerFixture()
            state.finished.signal()
        }
        guard state.entered.wait(timeout: .now() + 5) == .success else {
            XCTFail("Native worker callback did not arrive")
            return
        }
        clearDiagnosticReceiver()
        XCTAssertNotNil(retained)
        state.resume.signal()
        guard state.finished.wait(timeout: .now() + 5) == .success else {
            XCTFail("Native worker callback did not finish")
            return
        }
        XCTAssertNil(retained)
        XCTAssertEqual(state.events.withLock { $0.count }, 1)
        XCTAssertEqual(state.events.withLock { $0.first?.context?.operationId }, "operation-1")
        emitDiagnosticFixture()
        XCTAssertEqual(state.events.withLock { $0.count }, 1)
    }
}

private let defaults = DiagnosticOptions(minimumLevel: .debug, includePrivate: false)

private final class RecordingReceiver: DiagnosticReceiver, Sendable {
    private let storage = Mutex<[DiagnosticEvent]>([])

    var events: [DiagnosticEvent] {
        storage.withLock { $0 }
    }

    func receive(event: DiagnosticEvent) {
        storage.withLock { $0.append(event) }
    }
}

private final class WorkerState: Sendable {
    let entered = DispatchSemaphore(value: 0)
    let resume = DispatchSemaphore(value: 0)
    let finished = DispatchSemaphore(value: 0)
    let events = Mutex<[DiagnosticEvent]>([])
}

private final class BlockingReceiver: DiagnosticReceiver, Sendable {
    let state: WorkerState

    init(state: WorkerState) {
        self.state = state
    }

    func receive(event: DiagnosticEvent) {
        XCTAssertFalse(Thread.isMainThread)
        state.events.withLock { $0.append(event) }
        state.entered.signal()
        XCTAssertEqual(state.resume.wait(timeout: .now() + 5), .success)
    }
}
