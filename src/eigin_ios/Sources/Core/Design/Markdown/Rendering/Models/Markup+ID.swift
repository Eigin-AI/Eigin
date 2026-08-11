import Foundation
import Markdown

extension Markup {
    /// A unique ID of the markdown node, formed by using the path from root.
    var id: String {
        var parentNode = parent
        var path = [String]()
        while parentNode != nil {
            path.append(String(indexInParent))
            parentNode = parentNode?.parent
        }
        return path.joined(separator: "-")
    }
}
