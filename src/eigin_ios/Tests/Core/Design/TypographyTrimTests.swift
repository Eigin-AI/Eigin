@testable import Eigin
import SwiftUI
import UIKit
import XCTest

/// `.textStyle` trims the frame to the cap top and last baseline, like web's
/// `text-box: trim-both cap alphabetic`, so spacing next to the text is the Figma
/// token with no maths.
@MainActor
final class TypographyTrimTests: XCTestCase {
    /// Loose body styles and tight display styles, whose line height is below the font size.
    private let styles = [
        Typography.chatMessage,
        Typography.body,
        Typography.titleM,
        Typography.button,
    ]
    private let margin: CGFloat = 20
    private let scale: CGFloat = 4

    func testTrimmedTextFrameRunsFromCapTopToLastBaseline() throws {
        for style in styles {
            let lineHeight = try XCTUnwrap(style.lineHeight)
            let capHeight = style.uiFont.capHeight
            let image = try PixelRender.image(
                Text("H\nH").textStyle(style),
                margin: margin,
                scale: scale
            )
            let ink = PixelRender.inkRows(image, scale: scale)
            let name = style.uiFont.fontName

            // Two line boxes lose everything above the first cap and below the last
            // baseline: lineHeight + capHeight of frame remain.
            XCTAssertEqual(
                CGFloat(image.height) / scale - 2 * margin,
                lineHeight + capHeight,
                accuracy: 0.75,
                "\(name) trimmed box",
                file: #filePath,
                line: #line
            )
            XCTAssertEqual(
                ink.top,
                margin,
                accuracy: 0.75,
                "\(name) frame edge at cap top",
                file: #filePath,
                line: #line
            )
            XCTAssertEqual(
                ink.bottom,
                margin + lineHeight + capHeight,
                accuracy: 0.75,
                "\(name) frame edge at last baseline",
                file: #filePath,
                line: #line
            )
        }
    }

    /// The one line of "H" case: the whole trim is still exact.
    func testTrimmedSingleLineFrameRunsFromCapTopToBaseline() throws {
        for style in styles {
            let lineHeight = try XCTUnwrap(style.lineHeight)
            let image = try PixelRender.image(
                Text("H").textStyle(style),
                margin: margin,
                scale: scale
            )
            let ink = PixelRender.inkRows(image, scale: scale)
            XCTAssertEqual(
                CGFloat(image.height) / scale - 2 * margin,
                style.uiFont.capHeight,
                accuracy: 0.75,
                file: #filePath,
                line: #line
            )
            XCTAssertEqual(ink.top, margin, accuracy: 0.75, file: #filePath, line: #line)
            XCTAssertEqual(
                ink.bottom,
                margin + style.uiFont.capHeight,
                accuracy: 0.75,
                file: #filePath,
                line: #line
            )
        }
    }
}
