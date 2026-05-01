@testable import Eigin
import Testing

@Suite("AppLogger")
struct AppLoggerTests {
    // MARK: - LogMessage interpolation

    @Test func literalOnlyRendersSameInBothModes() {
        let msg: LogMessage = "plain text"
        #expect(msg.redactedDescription == "plain text")
        #expect(msg.fullDescription == "plain text")
    }

    @Test func publicInterpolationVisibleInBothModes() {
        let msg: LogMessage = "count: \(public: 42)"
        #expect(msg.redactedDescription == "count: 42")
        #expect(msg.fullDescription == "count: 42")
    }

    @Test func privateInterpolationRedactedInRedactedMode() {
        let msg: LogMessage = "user: \(private: "alice")"
        #expect(msg.redactedDescription == "user: <REDACTED>")
        #expect(msg.fullDescription == "user: alice")
    }

    @Test func mixedSegmentsRenderCorrectly() {
        let msg: LogMessage = "Round \(public: 3): response from \(private: "secret-key")"
        #expect(msg.redactedDescription == "Round 3: response from <REDACTED>")
        #expect(msg.fullDescription == "Round 3: response from secret-key")
    }

    @Test func emptyMessageRendersEmpty() {
        let msg: LogMessage = ""
        #expect(msg.redactedDescription == "")
        #expect(msg.fullDescription == "")
    }

    @Test func multiplePrivateSegments() {
        let msg: LogMessage = "\(private: "a") and \(private: "b")"
        #expect(msg.redactedDescription == "<REDACTED> and <REDACTED>")
        #expect(msg.fullDescription == "a and b")
    }
}
