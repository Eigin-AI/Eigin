import Foundation
import Markdown
import SwiftUI

extension BlockQuote: BlockConvertible {
    func convert(
        attributeContainer: NSAttributeContainer,
        config: MarkdownRenderConfig
    ) -> MarkdownRenderable {
        // Pre-populate the container with the quote's muted styling. Nested
        // blocks (Paragraph, etc.) only fall back to their own default style
        // for attributes not already set, so this tints quoted text without
        // overriding block kinds that carry their own font (e.g. a heading).
        var container = attributeContainer
        container[.font] = config.blockQuoteStyle.textFonts.normal
        container[.typography] = config.blockQuoteStyle.textFonts
        if let kern = config.blockQuoteStyle.textFonts.preferredLetterSpacing {
            container[.kern] = kern
        }
        container[.foregroundColor] = MDColor(config.blockQuoteStyle.textColor)

        let children = blockConvertibleChildren.map {
            $0.convert(attributeContainer: container, config: config)
        }
        return .blockQuote(id: id, children: children)
    }
}
