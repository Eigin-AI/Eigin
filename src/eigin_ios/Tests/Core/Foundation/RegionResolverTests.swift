@testable import Eigin
import Foundation
import Testing

@Suite("RegionResolver")
struct RegionResolverTests {
    private func resolver(
        regionCode: String?,
        timeZone: String
    ) -> RegionResolver {
        RegionResolver(
            regionCode: { regionCode },
            timeZoneIdentifier: { timeZone }
        )
    }

    @Test("resolves Denmark from the region code, ignoring timezone")
    func regionCodeIsPrimary() {
        let r = resolver(regionCode: "DK", timeZone: "America/New_York")
        #expect(r.resolve() == .denmark)
    }

    @Test("region code is case-insensitive")
    func regionCodeCaseInsensitive() {
        #expect(resolver(regionCode: "dk", timeZone: "UTC").resolve() == .denmark)
    }

    @Test("falls back to timezone when no region code is exposed")
    func timezoneFallback() {
        let r = resolver(regionCode: nil, timeZone: "Europe/Copenhagen")
        #expect(r.resolve() == .denmark)
    }

    @Test("returns nil when neither signal resolves a known region")
    func inconclusive() {
        #expect(resolver(regionCode: "US", timeZone: "America/New_York").resolve() == nil)
        #expect(resolver(regionCode: nil, timeZone: "America/New_York").resolve() == nil)
    }
}
