@testable import Eigin
import SwiftUI
import UIKit
import XCTest

/// A table's last row must retain ink below its trimmed baseline.
@MainActor
final class DataTableClippingTests: XCTestCase {
    func testLastRowDescenderRemainsVisible() throws {
        let plain = try renderLastRow("H")
        let descender = try renderLastRow("Hg")
        let plainInk = PixelRender.inkRows(plain, scale: 3)
        let descenderInk = PixelRender.inkRows(descender, scale: 3)
        XCTAssertGreaterThan(descenderInk.bottom - plainInk.bottom, 1)
    }

    private func renderLastRow(_ text: String) throws -> CGImage {
        let value = DataValue.array([
            .object([.init(key: "category", value: .string(text))]),
        ])
        let view = DataRows(value: value, openDepth: 3)
            .previewEnvironment()
            .frame(width: 240)
            .padding(20)
            .frame(width: 280, height: 200, alignment: .topLeading)
            .background(.white)
            .environment(\.colorScheme, .light)
        let host = UIHostingController(rootView: view)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 280, height: 200)
        let previousKeyWindow = scene.keyWindow
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            previousKeyWindow?.makeKey()
        }
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        return try XCTUnwrap(image.cgImage)
    }
}
