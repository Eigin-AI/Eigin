import FixtureBindings
import XCTest

final class TypedErrorTests: ContractTestCase {
    func testInitializationErrorPreservesReason() async {
        await check {
            do {
                try await failInitializationFixture()
                XCTFail("Expected initialization error")
            } catch let InitializationError.Unavailable(reason) {
                XCTAssertEqual(reason, "binding fixture")
            }
        }
    }
}
