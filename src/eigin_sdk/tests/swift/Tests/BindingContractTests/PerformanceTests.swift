import FixtureBindings
import XCTest

final class PerformanceTests: ContractTestCase {
    func testPerformanceEventsPreserveOptionalMeasurements() async {
        await check {
            let events = performanceEventsFixture()
            XCTAssertEqual(events.count, 3)
            guard case let .performance(measured) = events[0],
                  case let .performance(missing) = events[1],
                  case let .performance(zero) = events[2]
            else {
                XCTFail("Expected typed performance events")
                return
            }
            XCTAssertEqual(measured.timeToFirstTokenMs, 125.5)
            XCTAssertEqual(measured.tokensPerSecond, 8.25)
            XCTAssertNil(missing.timeToFirstTokenMs)
            XCTAssertNil(missing.tokensPerSecond)
            XCTAssertEqual(zero.timeToFirstTokenMs, 0)
            XCTAssertNil(zero.tokensPerSecond)
        }
    }
}
