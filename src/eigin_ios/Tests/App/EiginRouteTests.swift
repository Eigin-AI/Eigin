@testable import Eigin
import XCTest

final class EiginRouteTests: XCTestCase {
    func testRoundTripsAllRoutes() {
        for route in EiginRoute.allCases {
            XCTAssertEqual(EiginRoute(url: route.url), route, "URL round-trip failed for \(route)")
        }
    }

    func testRejectsForeignScheme() throws {
        XCTAssertNil(try EiginRoute(url: XCTUnwrap(URL(string: "https://new-chat"))))
        XCTAssertNil(try EiginRoute(url: XCTUnwrap(URL(string: "otherapp://new-chat"))))
        XCTAssertNil(try EiginRoute(url: XCTUnwrap(URL(string: "eiginx://new-chat"))))
    }

    func testRejectsUnknownRoute() throws {
        XCTAssertNil(try EiginRoute(url: XCTUnwrap(URL(string: "eigin://nonsense"))))
        XCTAssertNil(try EiginRoute(url: XCTUnwrap(URL(string: "eigin://"))))
    }
}
