import Foundation
import Markdown
import SwiftUI

extension Markdown.Document {
    func convert(with config: MarkdownRenderConfig) -> [MarkdownRenderable] {
        blockConvertibleChildren
            .map { $0.convert(attributeContainer: NSAttributeContainer(), config: config) }
    }
}
