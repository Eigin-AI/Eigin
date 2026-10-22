@testable import Eigin
import SwiftUI
import XCTest

/// Glyph overflow must not move the baseline of other glyphs in the line.
@MainActor
final class TypographyGlyphPositionTests: XCTestCase {
    func testAccentsAndDescendersPreserveLeadingCapitalPosition() throws {
        for sample in ["Hgj ÅÉ", "Hgj ÅÉ\nHgj ÅÉ"] {
            let reference = sample.contains("\n") ? "H\nH" : "H"
            let expected = try leadingCapitalInk(reference)
            let actual = try leadingCapitalInk(sample)
            XCTAssertEqual(actual.top, expected.top, accuracy: 0.5, sample)
            XCTAssertEqual(actual.bottom, expected.bottom, accuracy: 0.5, sample)
        }
    }

    private func leadingCapitalInk(_ sample: String) throws -> (top: CGFloat, bottom: CGFloat) {
        let scale: CGFloat = 3
        let margin: CGFloat = 20
        let image = try PixelRender.image(
            Text(sample).typography(Typography.titleXS), margin: margin, scale: scale
        )
        let lineCount: CGFloat = sample.contains("\n") ? 2 : 1
        let lineHeight = try XCTUnwrap(Typography.titleXS.lineHeight)
        XCTAssertEqual(
            CGFloat(image.height) / scale - 2 * margin,
            lineHeight * lineCount,
            accuracy: 0.5
        )
        // Scan only the leading H; accented glyphs extend above the cap height.
        let capital = try XCTUnwrap(image.cropping(to: CGRect(
            x: margin * scale, y: 0, width: 12 * scale, height: CGFloat(image.height)
        )))
        return PixelRender.inkRows(capital, scale: scale)
    }
}
