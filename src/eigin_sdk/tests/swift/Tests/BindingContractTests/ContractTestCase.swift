import XCTest

/// Bounds each contract so a broken foreign-future wakeup fails the test.
@MainActor
class ContractTestCase: XCTestCase {
    func check(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: @escaping @Sendable () async throws -> Void
    ) async {
        let finished = expectation(description: "Binding operation completed")
        let task = Task {
            do {
                try await body()
            } catch {
                XCTFail("Unexpected error: \(error)", file: file, line: line)
            }
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 10)
        task.cancel()
    }
}
