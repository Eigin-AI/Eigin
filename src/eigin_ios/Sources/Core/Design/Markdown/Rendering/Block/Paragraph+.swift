import Foundation
import Markdown
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Paragraph: BlockConvertible {
    func convert(
        attributeContainer: NSAttributeContainer,
        config: MarkdownRenderConfig
    ) -> MarkdownRenderable {
        // Fall back to the default paragraph style only for attributes not
        // already set by an ancestor (e.g. a block quote tinting its content).
        var container = attributeContainer
        container[.font] = container[.font] ?? config.paragraphStyle.textFonts.normal
        container[.typography] = container[.typography] ?? config.paragraphStyle.textFonts
        if container[.kern] == nil,
           let kern = config.paragraphStyle.textFonts.preferredLetterSpacing
        {
            container[.kern] = kern
        }
        container[.foregroundColor] = container[.foregroundColor] ??
            MDColor(config.paragraphStyle.textColor)
        let paragraphContent: NSMutableAttributedString = buildParagraphContent(
            container: container,
            config: config
        )
        return MarkdownRenderable.paragraph(id: id, content: paragraphContent)
    }
}

extension BlockMarkup {
    func buildParagraphContent(
        container: NSAttributeContainer,
        config: MarkdownRenderConfig
    ) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()

        for child in children {
            guard let convertible = child as? InlineConvertible else {
                continue
            }
            let stringPart = convertible.convert(attributeContainer: container, config: config)
            result.append(stringPart)
        }

        return result
    }
}
