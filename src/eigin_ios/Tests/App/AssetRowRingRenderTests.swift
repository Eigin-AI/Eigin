@testable import Eigin
import SwiftUI
import Testing
import UIKit

/// Renders the real `AssetRow` off-screen and counts accent pixels, so the
/// progress ring provably fills with the fraction instead of guessing.
@MainActor @Suite(.serialized)
struct AssetRowRingRenderTests {
    @Observable
    final class StubAsset: OnDemandAsset, @unchecked Sendable {
        let id = "stub"
        let displayName = "Stub model"
        let downloadDescription = "desc"
        var sizeDescription: String? {
            "1 GB"
        }

        var state: AssetState
        var hasBeenDeclined = false

        init(state: AssetState) {
            self.state = state
        }

        func download() async {}
        func delete() {}
        func decline() {}
    }

    /// Render the row (delivering the fill fraction) and return the number of
    /// accent-colored pixels. While downloading, the only accent element is
    /// the ring's progress arc — the trailing control is neutral.
    private func accentPixelCount(fraction: Double) throws -> Int {
        let colors = DefaultTheme().colors(for: .light)
        let info = AssetTransferInfo(
            fractionCompleted: fraction,
            bytesCompleted: 0,
            totalBytes: 1_000_000_000,
            estimatedSecondsLeft: nil
        )
        let row = AssetRow(asset: StubAsset(state: .downloading(info)))
            .environment(\.colors, colors)
            .frame(width: 320)
            .padding(8)

        let renderer = ImageRenderer(content: row)
        renderer.scale = 2
        let image = try #require(renderer.uiImage)
        let cg = try #require(image.cgImage)

        let w = cg.width, h = cg.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = try #require(
            CGContext(
                data: &data, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        let accent = UIColor(colors.accent)
        var count = 0
        for i in stride(from: 0, to: data.count, by: 4) {
            let px = UIColor(
                red: CGFloat(data[i]) / 255, green: CGFloat(data[i + 1]) / 255,
                blue: CGFloat(data[i + 2]) / 255, alpha: 1
            )
            if isClose(px, accent) {
                count += 1
            }
        }
        return count

        func isClose(_ a: UIColor, _ b: UIColor) -> Bool {
            var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
            var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
            a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
            b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
            return abs(r1 - r2) < 0.05 && abs(g1 - g2) < 0.05 && abs(b1 - b2) < 0.05
        }
    }

    /// The ring's accent arc must clearly separate low progress from half.
    @Test func ringFillsWithProgress() throws {
        let half = try accentPixelCount(fraction: 0.5)
        let low = try accentPixelCount(fraction: 0.05)
        #expect(half > low * 2)
        #expect(half > 30)
    }
}
