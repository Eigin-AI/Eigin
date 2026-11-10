import FixtureBindings
import XCTest

final class PendingOperationTests: ContractTestCase {
    func testPendingSuccessPreservesValue() async {
        await check {
            let operation = PendingOperation()
            let result = Task { try await operation.run() }
            defer { result.cancel() }
            await operation.waitUntilPending()
            operation.succeed(value: "host completion")
            let value = try await result.value
            XCTAssertEqual(value, "host completion")
        }
    }

    func testPendingFailurePreservesVariantAndPayload() async {
        await check {
            let operation = PendingOperation()
            let result = Task { try await operation.run() }
            defer { result.cancel() }
            await operation.waitUntilPending()
            operation.fail(code: 42, reason: "host failure")
            do {
                _ = try await result.value
                XCTFail("Expected typed failure")
            } catch let BindingTestError.Rejected(code, reason) {
                XCTAssertEqual(code, 42)
                XCTAssertEqual(reason, "host failure")
            }
        }
    }

    func testOperationsCompleteIndependently() async {
        await check {
            let first = PendingOperation()
            let second = PendingOperation()
            let completion = Completion()
            let firstResult = Task {
                let value = try await first.run()
                await completion.markFinished()
                return value
            }
            let secondResult = Task { try await second.run() }
            defer {
                firstResult.cancel()
                secondResult.cancel()
            }
            await first.waitUntilPending()
            await second.waitUntilPending()
            second.succeed(value: "second")
            let secondValue = try await secondResult.value
            XCTAssertEqual(secondValue, "second")
            let firstCompleted = await completion.finished
            XCTAssertFalse(firstCompleted, "Completing second also completed first")
            first.succeed(value: "first")
            let firstValue = try await firstResult.value
            XCTAssertEqual(firstValue, "first")
        }
    }
}

private actor Completion {
    private(set) var finished = false

    func markFinished() {
        finished = true
    }
}
