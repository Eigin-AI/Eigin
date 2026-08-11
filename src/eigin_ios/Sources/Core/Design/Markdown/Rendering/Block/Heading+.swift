import Foundation
import Markdown
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Heading: BlockConvertible {
    func convert(
        attributeContainer: NSAttributeContainer,
        config: MarkdownRenderConfig
    ) -> MarkdownRenderable {
        var newContainer = attributeContainer
        let headingFont: TextFonts = switch level {
        case 1:
            config.headingStyle.h1Font
        case 2:
            config.headingStyle.h2Font
        case 3:
            config.headingStyle.h3Font
        case 4:
            config.headingStyle.h4Font
        case 5:
            config.headingStyle.h5Font
        case 6:
            config.headingStyle.h6Font
        default:
            config.headingStyle.h6Font
        }
        newContainer[.font] = headingFont.normal
        newContainer[.typography] = headingFont
        if let kern = headingFont.preferredLetterSpacing {
            newContainer[.kern] = kern
        }
        newContainer[.foregroundColor] = MDColor(config.headingStyle.textColor)
        let paragraphContent = buildParagraphContent(container: newContainer, config: config)
        return .heading(id: id, level: level, content: paragraphContent)
    }
}
