import Foundation
import Markdown
import SwiftUI

extension CodeBlock: BlockConvertible {
    func convert(
        attributeContainer: NSAttributeContainer,
        config: MarkdownRenderConfig
    ) -> MarkdownRenderable {
        // Still hit for `\[...\]` display math: `LaTexPreProcessorImpl` rewrites it into a
        // fenced code block tagged with this language before parsing. `$$...$$` math
        // skips the markdown parser entirely via `ContentBlock`'s own `.math` block kind.
        if language == LaTexPreProcessorImpl.customCodeType {
            .latex(id: id, content: code)
        } else {
            .codeBlock(id: id, language: language, code: code)
        }
    }
}
