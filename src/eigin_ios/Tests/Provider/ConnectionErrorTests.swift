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

    @Test func modelNotDownloadedMapsToActionableCard() {
        let error = ConnectionError(from: LocalClientError.modelNotDownloaded)

        #expect(error.title == Localized.Model.NotDownloaded.title)
        #expect(error.suggestion == Localized.Model.NotDownloaded.suggestion)
    }

    @Test func modelNotLoadedMapsToRetryCard() {
        let error = ConnectionError(from: LocalClientError.modelNotLoaded)

        #expect(error.title == Localized.Model.NotLoaded.title)
        #expect(error.suggestion == Localized.Model.NotLoaded.suggestion)
    }

    @Test func firstEventTimeoutMapsToNetworkTimeoutCard() {
        let error = ConnectionError(from: FirstEventTimeout())

        #expect(error.title == Localized.Ui.connectionTimedOut)
        #expect(error.suggestion == Localized.Errors.Provider.timeout)
        // Weird raw wire output (Cocoa's "Eigin.FirstEventTimeout error 1")
        // must never leak through as the detail.
        #expect(error.rawDescription == nil)
    }

    // MARK: - Responses API (ChatGPT subscription) errors

    @Test func planNotEligibleMapsToPlusRequiredCard() {
        let error = ConnectionError(from: ResponsesAPIError.planNotEligible)

        #expect(error.title == Localized.Errors.Chatgpt.plusRequiredTitle)
        #expect(error.suggestion == Localized.Errors.Chatgpt.plusRequiredSuggestion)
    }

    @Test func usageLimitExceededMapsToPlanLimitCard() {
        let error = ConnectionError(from: ResponsesAPIError.usageLimitExceeded)

        #expect(error.title == Localized.Errors.Chatgpt.usageLimitTitle)
        #expect(error.suggestion == Localized.Errors.Chatgpt.usageLimitSuggestion)
    }

    @Test func invalidUserMapsToSignInAgainCard() {
        let error = ConnectionError(from: ResponsesAPIError.invalidUser)

        #expect(error.title == Localized.Errors.Chatgpt.invalidUserTitle)
        #expect(error.suggestion == Localized.Errors.Chatgpt.invalidUserSuggestion)
    }

    @Test func unsupportedCapabilityNamesTheCapability() {
        let error = ConnectionError(
            from: ResponsesAPIError.unsupportedCapability(param: "temperature")
        )

        #expect(error.title == Localized.Errors.Chatgpt.unsupportedCapabilityTitle)
        #expect(error.suggestion == Localized.Errors.Chatgpt.unsupportedCapabilitySuggestion)
    }
}
