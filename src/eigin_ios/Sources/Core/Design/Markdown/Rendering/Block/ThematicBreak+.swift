import Foundation
import Markdown
import SwiftUI

extension ThematicBreak: BlockConvertible {
    func convert(
        attributeContainer: NSAttributeContainer,
        config: MarkdownRenderConfig
    ) -> MarkdownRenderable {
        MarkdownRenderable.thematicBreak(id: id)
    }
}
