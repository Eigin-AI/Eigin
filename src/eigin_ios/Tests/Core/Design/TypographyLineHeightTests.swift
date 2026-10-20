@testable import Eigin
import SwiftUI
import UIKit
import XCTest

/// Text styles lay out like Figma and CSS: each line box is the token's line height,
/// and the glyphs sit centred in it, with half the spare space above and half below.
@MainActor
final class TypographyLineHeightTests: XCTestCase {
    /// Loose body styles and tight display styles, whose line height is below the font size.
    private let styles = [
        Typography.chatMessage,
        Typography.body,
        Typography.titleM,
        Typography.button,
    ]
    private let margin: CGFloat = 20
    private let scale: CGFloat = 4

    func testSwiftUITextSitsCentredInTokenLineBoxes() throws {
        for style in styles {
            let image = try PixelRender.image(
                Text("H\nH").typography(style),
                margin: margin,
                scale: scale
            )
            try assertCentred(style, in: image)
        }
    }

    func testUIKitTextSitsCentredInTokenLineBoxes() throws {
        for style in styles {
            var attributes = style.textAttributes
            attributes[.foregroundColor] = UIColor.black
            let text = UITextView()
            text.textContainerInset = .zero
            text.textContainer.lineFragmentPadding = 0
            text.isScrollEnabled = false
            text.backgroundColor = .clear
            text.clipsToBounds = false
            text.attributedText = NSAttributedString(string: "H\nH", attributes: attributes)
            let size = text.sizeThatFits(CGSize(
                width: 200,
                height: CGFloat.greatestFiniteMagnitude
            ))
            text.frame = CGRect(
                x: margin,
                y: margin + style.textKitShift,
                width: size.width,
                height: size.height
            )
            let container = UIView(frame: CGRect(
                x: 0, y: 0, width: size.width + 2 * margin, height: size.height + 2 * margin
            ))
            container.backgroundColor = .white
            container.addSubview(text)
            container.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            let image = UIGraphicsImageRenderer(size: container.bounds.size, format: format).image {
                container.layer.render(in: $0.cgContext)
            }
            try assertCentred(style, in: XCTUnwrap(image.cgImage))
        }
    }

    // MARK: - Helpers

    /// Checks two lines of "H": the box is two line heights, the first cap top and the
    /// second baseline land where CSS puts them.
    private func assertCentred(
        _ style: TypographyStyle,
        in image: CGImage,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let lineHeight = try XCTUnwrap(style.lineHeight)
        let font = style.uiFont
        let baseline = (lineHeight - font.ascender + font.descender) / 2 + font.ascender
        let ink = PixelRender.inkRows(image, scale: scale)
        let name = font.fontName
        XCTAssertEqual(
            CGFloat(image.height) / scale - 2 * margin,
            2 * lineHeight,
            accuracy: 0.5,
            "\(name) box",
            file: file,
            line: line
        )
        XCTAssertEqual(
            ink.top - margin,
            baseline - font.capHeight,
            accuracy: 0.75,
            "\(name) cap top",
            file: file,
            line: line
        )
        XCTAssertEqual(
            ink.bottom - margin,
            baseline + lineHeight,
            accuracy: 0.75,
            "\(name) last baseline",
            file: file,
            line: line
        )
    }

    /// First and last rows with dark pixels, in points from the top.
    private func inkRows(_ image: CGImage) -> (top: CGFloat, bottom: CGFloat) {
        PixelRender.inkRows(image, scale: scale)
    }
}
