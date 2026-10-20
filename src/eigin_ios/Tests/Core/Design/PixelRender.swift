import CoreGraphics
import SwiftUI
import UIKit
import XCTest

/// Shared by the typography pixel tests: renders a view offscreen and scans the result
/// for ink.
@MainActor
enum PixelRender {
    /// Renders a view to a bitmap at `scale`, with `margin` of whitespace around it.
    static func image(_ view: some View, margin: CGFloat, scale: CGFloat) throws -> CGImage {
        let renderer = ImageRenderer(
            content: view
                .foregroundStyle(.black)
                .fixedSize()
                .padding(margin)
        )
        renderer.scale = scale
        return try XCTUnwrap(renderer.cgImage)
    }

    /// First and last rows with dark pixels, in points from the top.
    static func inkRows(_ image: CGImage, scale: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
        let width = image.width, height = image.height
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
        var top = -1, bottom = -1
        for row in 0 ..< height {
            let hasInk = (0 ..< width).contains { pixels[(row * width + $0) * 4] < 128 }
            if hasInk {
                if top < 0 { top = row }
                bottom = row + 1
            }
        }
        return (CGFloat(top) / scale, CGFloat(bottom) / scale)
    }
}
