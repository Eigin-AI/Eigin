@testable import Eigin
import Foundation
import Testing

/// Location is an integration that can be removed: removing it stops Eigin
/// using location, and asking iOS for it, without touching what iOS allows.
@Suite("LocationResolver")
@MainActor
struct LocationResolverTests {
    @Test func removedLocationIsUnavailableWithoutAsking() async {
        let declines = DeclinedCapabilities(defaults: .isolated())
        declines.decline(.location)
        var recorded = false

        let result = await LocationResolver.resolve(
            canPromptUser: true,
            declines: declines,
            recordAllowed: { recorded = true }
        )

        guard case .failure(let error) = result else {
            Issue.record("Expected no location once Location is removed")
            return
        }
        #expect(error == .removed)
        #expect(!recorded)
    }
}
