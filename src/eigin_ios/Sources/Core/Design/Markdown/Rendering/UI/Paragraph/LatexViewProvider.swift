import Foundation
import iosMath
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - LatexAttachmentData Color Resolution

extension LatexAttachmentData {
    var resolvedTextColor: MDColor {
        let fallback = MDColor.label
#if canImport(UIKit)
        guard let lightColor = UIColor(hex: lightTextColor),
              let darkColor = UIColor(hex: darkTextColor)
        else {
            return fallback
        }
        return UIColor { trait in
            trait.userInterfaceStyle == .dark ? darkColor : lightColor
        }
#elseif canImport(AppKit)
        guard let lightColor = NSColor(hex: lightTextColor),
              let darkColor = NSColor(hex: darkTextColor)
        else {
            return fallback
        }
        return NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? darkColor : lightColor
        }
#endif
    }
}

// MARK: - Latex View Provider

/// The framework's override points are declared nonisolated, but TextKit only
/// invokes them on the main thread. Each override reads its state into locals and
/// does the UIKit work inside `MainActor.assumeIsolated`, which asserts the main
/// actor at runtime (and traps if that ever changes) without capturing `self`.
final class LatexViewProvider: NSTextAttachmentViewProvider {
    private let latex: String
    private let fontSize: CGFloat
    private let textColor: MDColor

    private struct DecodedAttachment {
        var latex: String = ""
        var fontSize: CGFloat = MDFont.systemFont(ofSize: 17).pointSize
        var textColor: MDColor = .label
    }

#if canImport(UIKit)
    override required init(
        textAttachment attachment: NSTextAttachment,
        parentView: UIView?,
        textLayoutManager: NSTextLayoutManager?,
        location: any NSTextLocation
    ) {
        let decoded = Self.decode(attachment: attachment)
        (latex, fontSize, textColor) = (decoded.latex, decoded.fontSize, decoded.textColor)
        super.init(
            textAttachment: attachment,
            parentView: parentView,
            textLayoutManager: textLayoutManager,
            location: location
        )
        tracksTextAttachmentViewBounds = true
    }

#elseif canImport(AppKit)
    override required init(
        textAttachment attachment: NSTextAttachment,
        parentView: NSView?,
        textLayoutManager: NSTextLayoutManager?,
        location: any NSTextLocation
    ) {
        let decoded = Self.decode(attachment: attachment)
        (latex, fontSize, textColor) = (decoded.latex, decoded.fontSize, decoded.textColor)
        super.init(
            textAttachment: attachment,
            parentView: parentView,
            textLayoutManager: textLayoutManager,
            location: location
        )
        tracksTextAttachmentViewBounds = true
    }
#endif

    private nonisolated static func decode(attachment: NSTextAttachment) -> DecodedAttachment {
        var result = DecodedAttachment()
        if let data = attachment.contents,
           let attachmentData = try? JSONDecoder().decode(LatexAttachmentData.self, from: data)
        {
            result.latex = attachmentData.latex
            result.fontSize = attachmentData.fontSize
            result.textColor = attachmentData.resolvedTextColor
        }
        return result
    }

    override func loadView() {
        let (latex, textColor, fontSize) = (latex, textColor, fontSize)
        view = MainActor.assumeIsolated {
            let label = MTMathUILabel()
            label.latex = latex
            label.textColor = textColor
            label.displayErrorInline = false
            label.fontSize = fontSize
            label.setContentHuggingPriority(.defaultHigh, for: .vertical)
            return label
        }
    }

    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        // Read state into locals so the main-actor closure captures only Sendable
        // values, not `self` or the non-Sendable attributes dictionary.
        let attributeFont = attributes[.font] as? MDFont
        let fontSize = fontSize
        let currentView = view
        return MainActor.assumeIsolated {
            guard let mathLabel = currentView as? MTMathUILabel else {
                return .zero
            }
#if canImport(UIKit)
            mathLabel.sizeToFit()
            let size = mathLabel.bounds.size
#elseif canImport(AppKit)
            let size = mathLabel.intrinsicContentSize
#endif
            let height = size.height.rounded(.up) + 1.0
            let font = attributeFont ?? MDFont.systemFont(ofSize: fontSize)
            let yOffset = (font.xHeight - height) / 2.0
            return CGRect(x: 0, y: yOffset, width: size.width.rounded(.up), height: height)
        }
    }
}
