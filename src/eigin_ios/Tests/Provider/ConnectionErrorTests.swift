@testable import Eigin
import Foundation
import Testing

/// Verifies ``ConnectionError`` mapping of thrown errors into user-facing cards.
@Suite("ConnectionError")
struct ConnectionErrorTests {
    @Test func deviceUnsupportedMapsToDeviceCardWithJSONDetail() {
        let payload = """
        {"error":{"type":"insufficient_memory","device_memory_gb":"4.0"}}
        """
        let error = ConnectionError(
            from: LocalClientError.deviceUnsupported(detail: payload)
        )

        #expect(error.title == Localized.Model.deviceUnsupportedTitle)
        #expect(error.suggestion == Localized.Model.deviceUnsupportedSuggestion)
        // The JSON payload is passed straight through so the detail sheet can
        // render it as a structured field breakdown.
        #expect(error.rawDescription == payload)
    }
}
