@testable import Eigin
import Testing

@Suite("SoftEdgeCurve")
struct SoftEdgeCurveTests {
    @Test("The blur is full to its start and gone by its end")
    func blurSpan() {
        let stops = SoftEdgeCurve.blurStops(full: 0.4, end: 0.8)

        #expect(stops.filter { $0.location <= 0.4 }.allSatisfy { $0.coverage == 1 })
        #expect(stops.filter { $0.location >= 0.8 }.allSatisfy { $0.coverage == 0 })
    }

    @Test("The fade is strongest at the screen edge and gone at the end")
    func fadeEndpoints() {
        #expect(SoftEdgeCurve.fadeStops.first?.coverage == SoftEdgeCurve.fadeStrength)
        #expect(SoftEdgeCurve.fadeStops.last?.coverage == 0)
    }

    @Test("Both curves only fall toward the content")
    func falling() {
        for stops in [SoftEdgeCurve.fadeStops, SoftEdgeCurve.blurStops(full: 0.3, end: 0.7)] {
            let coverage = stops.map(\.coverage)
            #expect(coverage == coverage.sorted(by: >))
        }
    }
}
