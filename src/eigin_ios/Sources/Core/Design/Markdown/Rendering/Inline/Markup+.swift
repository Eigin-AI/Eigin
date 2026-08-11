import Foundation
import Markdown

extension Markup {
    var inlineConvertibleChildren: [InlineConvertible] {
        children.compactMap { $0 as? InlineConvertible }
    }
}
